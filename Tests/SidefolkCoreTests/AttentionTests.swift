import Foundation
import Testing
@testable import SidefolkCore

@Suite struct AttentionPolicyTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    func decide(_ level: AttentionLevel, env: AttentionEnvironment = AttentionEnvironment(), source: String = "reminder",
                createdAt: Date? = nil, recent: [(source: String, at: Date)] = []) -> AttentionDecision {
        AttentionPolicy.decide(level: level, source: source, createdAt: createdAt ?? now, now: now, env: env, recent: recent)
    }

    @Test func defaults() {
        #expect(decide(.ambient) == .present(.ambient))
        #expect(decide(.gentle) == .present(.gentle(autoDismiss: AttentionPolicy.gentleSeconds)))
        #expect(decide(.attention) == .present(.attention(expandFor: AttentionPolicy.expandSeconds)))
        #expect(decide(.critical) == .present(.system(sound: true, alsoOnDesktop: true)))
    }

    @Test func typingGuardDefersUpToMax() {
        var env = AttentionEnvironment()
        env.lastKeyAt = now.addingTimeInterval(-0.5)
        guard case .hold(let until) = decide(.attention, env: env) else { Issue.record("should hold"); return }
        #expect(until == env.lastKeyAt!.addingTimeInterval(AttentionPolicy.typingQuiet))
        // Waited long enough already: present even while typing.
        #expect(decide(.attention, env: env, createdAt: now.addingTimeInterval(-25)) == .present(.attention(expandFor: AttentionPolicy.expandSeconds)))
    }

    @Test func quietAndFullscreenUseSilentSystemNotifications() {
        var env = AttentionEnvironment()
        env.quiet = true
        #expect(decide(.attention, env: env) == .present(.system(sound: false, alsoOnDesktop: false)))
        #expect(decide(.gentle, env: env) == .hold(until: nil))
        env.quiet = false
        env.fullscreen = true
        #expect(decide(.attention, env: env) == .present(.system(sound: false, alsoOnDesktop: false)))
        #expect(decide(.critical, env: env) == .present(.system(sound: true, alsoOnDesktop: false)))
    }

    @Test func awayHoldsEverythingButCritical() {
        var env = AttentionEnvironment()
        env.away = true
        #expect(decide(.attention, env: env) == .hold(until: nil))
        #expect(decide(.critical, env: env) == .present(.system(sound: true, alsoOnDesktop: true)))
    }

    @Test func rateLimits() {
        let recent = [(source: "watcher", at: now.addingTimeInterval(-30))]
        guard case .hold(let until) = decide(.attention, source: "job", recent: recent) else { Issue.record("spacing"); return }
        #expect(until == now.addingTimeInterval(60))
        let burst = (1...3).map { (source: "watcher", at: now.addingTimeInterval(-Double(100 * $0 + 100))) }
        guard case .hold = decide(.attention, source: "watcher", recent: burst) else { Issue.record("per source"); return }
        #expect(decide(.attention, source: "job", recent: burst) == .present(.attention(expandFor: AttentionPolicy.expandSeconds)))
        // Reminders are never spaced out: they arrive when the user asked.
        #expect(decide(.attention, source: "reminder", recent: recent) == .present(.attention(expandFor: AttentionPolicy.expandSeconds)))
    }

    @Test func menuBarOnlyMode() {
        var env = AttentionEnvironment()
        env.presence = .menuBarOnly
        #expect(decide(.gentle, env: env) == .present(.ambient))
        #expect(decide(.attention, env: env) == .present(.system(sound: true, alsoOnDesktop: false)))
    }
}

@Suite struct AttentionCenterTests {
    func center() throws -> (AttentionCenter, EventBus, AttentionStore) {
        let db = try AppDatabase.inMemory()
        let events = EventBus()
        let store = AttentionStore(db)
        return (AttentionCenter(store: store, events: events), events, store)
    }

    @Test func postPresentsAndPersists() async throws {
        let (center, events, store) = try center()
        let stream = events.stream()
        let item = await center.post(AttentionRequest(level: .attention, source: "reminder", title: "Stretch"))
        for await e in stream {
            if case .attention(.present(let shown, _)) = e {
                #expect(shown.id == item.id)
                break
            }
        }
        #expect(try await store.item(id: item.id)?.state == .shown)
    }

    @Test func respondRoutesToHandlerAndWithdraws() async throws {
        let (center, events, store) = try center()
        let got = Box<String?>(nil)
        await center.onAction(kind: "reminder") { _, action in got.set(action) }
        let item = await center.post(AttentionRequest(level: .attention, source: "reminder", title: "x", refKind: "reminder", refId: "r1"))
        let stream = events.stream()
        await center.respond(id: item.id, actionId: "done")
        #expect(got.value == "done")
        #expect(try await store.item(id: item.id)?.state == .acknowledged)
        for await e in stream { if case .attention(.withdraw(let id)) = e { #expect(id == item.id); break } }
    }

    @Test func askReturnsChosenOptionOrNilOnTimeout() async throws {
        let (center, events, _) = try center()
        let stream = events.stream()
        let answering = Task {
            for await e in stream {
                if case .attention(.present(let item, _)) = e {
                    await center.respond(id: item.id, actionId: "yes")
                    return
                }
            }
        }
        let answer = await center.ask(AttentionRequest(level: .attention, source: "external:test", title: "Deploy?",
                                                       actions: [AttentionAction(id: "yes", title: "Yes"), AttentionAction(id: "no", title: "No")]),
                                      timeout: 5)
        _ = await answering.value
        #expect(answer == "yes")
        let none = await center.ask(AttentionRequest(level: .gentle, source: "external:test", title: "Ignored?"), timeout: 0.05)
        #expect(none == nil)
    }

    @Test func waitingNoticesComeBackAfterARestart() async throws {
        let db = try AppDatabase.inMemory()
        let store = AttentionStore(db)
        let before = AttentionCenter(store: store, events: EventBus())
        await before.update { $0.away = true }
        let held = await before.post(AttentionRequest(level: .attention, source: "reminder", title: "Stretch"))
        let question = await before.post(AttentionRequest(level: .attention, source: "external:codex", title: "Deploy?", refKind: "ask"))
        #expect(try await store.item(id: held.id)?.state == .pending)

        // The app quits and starts again.
        let events = EventBus()
        let after = AttentionCenter(store: store, events: events)
        let stream = events.stream()
        await after.restoreWaiting()
        for await e in stream {
            if case .attention(.present(let item, _)) = e {
                #expect(item.id == held.id)
                break
            }
        }
        #expect(try await store.item(id: question.id)?.state == .expired, "nobody waits for the old question's answer")
    }

    @Test func returningFromAwaySummarisesHeldItems() async throws {
        let (center, events, _) = try center()
        await center.update { $0.away = true }
        for t in ["A", "B", "C"] { await center.post(AttentionRequest(level: .attention, source: "reminder", title: t)) }
        let stream = events.stream()
        await center.update { $0.away = false }
        for await e in stream {
            if case .attention(.present(let item, _)) = e {
                #expect(item.source == "summary")
                #expect(item.title.contains("3"))
                break
            }
        }
    }
}

final class Box<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ v: T) { stored = v }
    var value: T { lock.withLock { stored } }
    func set(_ v: T) { lock.withLock { stored = v } }
}
