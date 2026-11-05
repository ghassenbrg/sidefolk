import Foundation
import Testing
@testable import SidefolkCore

@Suite struct AttentionPolicyTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    func decide(_ level: AttentionLevel, env: AttentionEnvironment = AttentionEnvironment(), source: String = "reminder",
                createdAt: Date? = nil, recent: [(source: String, at: Date)] = []) -> AttentionDecision {
        AttentionPolicy.decide(level: level, source: source, createdAt: createdAt ?? now, now: now, env: env, recent: recent)
    }

    @Test func aQuestionIsntSpacedOutLikeANotice() {
        func ask(recent: [(source: String, at: Date)]) -> AttentionDecision {
            AttentionPolicy.decide(level: .attention, source: "ext", createdAt: now, now: now, env: AttentionEnvironment(), recent: recent, question: true)
        }
        let aMomentAgo = [(source: "other", at: now.addingTimeInterval(-5))]
        if case .hold = decide(.attention, source: "ext", recent: aMomentAgo) {} else { Issue.record("a notice waits its turn") }
        #expect(ask(recent: aMomentAgo) == .present(.attention(expandFor: AttentionPolicy.expandSeconds)), "someone's waiting on a question")
        // Past a notice's budget, and a timeout of a few minutes would run out before it came up.
        let aFew = (1...AttentionPolicy.perSourceLimit).map { (source: "ext", at: now.addingTimeInterval(-Double($0) * 10)) }
        #expect(ask(recent: aFew) == .present(.attention(expandFor: AttentionPolicy.expandSeconds)))
    }

    @Test func aLoopOfQuestionsHasALimit() {
        let many = (1...AttentionPolicy.questionsPerSourceLimit).map { (source: "ext", at: now.addingTimeInterval(-Double($0))) }
        let held = AttentionPolicy.decide(level: .attention, source: "ext", createdAt: now, now: now, env: AttentionEnvironment(), recent: many, question: true)
        if case .hold = held {} else { Issue.record("it holds: \(held)") }
        let other = AttentionPolicy.decide(level: .attention, source: "other", createdAt: now, now: now, env: AttentionEnvironment(), recent: many, question: true)
        #expect(other == .present(.attention(expandFor: AttentionPolicy.expandSeconds)), "one source's loop doesn't hold another's")
    }

    @Test func aQuestionStillWaitsForTheWayOut() {
        func ask(_ env: AttentionEnvironment) -> AttentionDecision {
            AttentionPolicy.decide(level: .attention, source: "ext", createdAt: now, now: now, env: env, recent: [], question: true)
        }
        var away = AttentionEnvironment()
        away.away = true
        #expect(ask(away) == .hold(until: nil), "nobody's there to see it")
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

    @Test func questionsInARowAreAllShownNotHeld() async throws {
        let (center, _, store) = try center()
        // More than a notice's budget, each with its caller waiting.
        let asking = (1...(AttentionPolicy.perSourceLimit + 1)).map { n in
            Task { await center.ask(AttentionRequest(level: .attention, source: "external:test", title: "Question \(n)?", refKind: "ask"), timeout: 5) }
        }
        var open: [AttentionItem] = []
        for _ in 0..<400 {
            open = (try? await store.open()) ?? []
            if open.count == asking.count, open.allSatisfy({ $0.state == .shown }) { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(open.count == asking.count)
        #expect(open.allSatisfy { $0.state == .shown }, "\(open.map { $0.state })")
        #expect(await center.heldCount == 0)
        for item in open { await center.respond(id: item.id, actionId: nil) }
        for task in asking { _ = await task.value }
    }

    @Test func aNoticeIsStillSpacedOut() async throws {
        let (center, _, store) = try center()
        await center.post(AttentionRequest(level: .attention, source: "external:test", title: "One"))
        await center.post(AttentionRequest(level: .attention, source: "external:test", title: "Two"))
        #expect(await center.heldCount == 1)
        #expect(try await store.open().filter { $0.state == .shown }.count == 1)
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

extension AttentionCenterTests {
    /// Quiet ends (D84): what waited comes as one card, as after Focus or being away, instead of a parade of whispers.
    @Test func quietEndsWithOneCard() async throws {
        let (center, events, _) = try center()
        await center.update { $0.quiet = true }
        let saved = await center.post(AttentionRequest(level: .gentle, source: "external:claude-code", title: "Saved a note"))
        await center.post(AttentionRequest(level: .gentle, source: "external:codex", title: "Finished in pockito"))
        #expect(await center.isHeld(saved.id))
        let stream = events.stream()
        await center.update { $0.quiet = false }
        for await e in stream {
            if case .attention(.present(let item, _)) = e {
                #expect(item.source == "summary" && item.refKind == "quiet")
                #expect(item.title.contains("2"))
                #expect(item.body?.contains("Saved a note") == true && item.body?.contains("Finished in pockito") == true)
                break
            }
        }
        #expect(!(await center.isHeld(saved.id)))
    }
}

final class Box<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ v: T) { stored = v }
    var value: T { lock.withLock { stored } }
    func set(_ v: T) { lock.withLock { stored = v } }
}
