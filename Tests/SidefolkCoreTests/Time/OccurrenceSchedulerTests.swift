import Foundation
@testable import SidefolkCore
import Testing

/// Extensions' planned moments (D107): told once, on time, and never again; silent when late; taken back when over.
struct OccurrenceSchedulerTests {
    static let id = "dev.example.times"

    /// A scheduler over a real attention center, with a clock the test moves.
    final class World {
        let env: TestEnv
        let attention: AttentionCenter
        var scheduler: OccurrenceScheduler
        let allowed = AllowedList()

        final class AllowedList: @unchecked Sendable {
            var on = true
        }

        init() throws {
            env = try TestEnv()
            attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
            scheduler = OccurrenceScheduler(store: ExtensionOccurrenceStore(KVStore(env.db)), attention: attention, events: env.events, clock: env.clock)
        }

        func start() async {
            let allowed = allowed
            await scheduler.configure(mayTell: { _ in allowed.on }, onOpen: { _, _, _ in })
            await scheduler.start(extensions: [(OccurrenceSchedulerTests.id, "Times")])
        }

        /// A restart: everything in memory gone, what was stored kept.
        func restart() async {
            await scheduler.stop()
            scheduler = OccurrenceScheduler(store: ExtensionOccurrenceStore(KVStore(env.db)), attention: attention, events: env.events, clock: env.clock)
            await start()
        }

        func moment(_ id: String, in seconds: TimeInterval, lasting: TimeInterval = 1800, group: String? = nil, system: Bool = false) -> ScheduledOccurrence {
            ScheduledOccurrence(id: id, at: env.clock.now.addingTimeInterval(seconds), expiresAt: env.clock.now.addingTimeInterval(seconds + lasting), title: "Maghrib",
                                body: "Tokyo", group: group, systemFallback: system, openPage: "noor", openState: ["tab": "prayer"])
        }

        func told() async -> [AttentionItem] {
            ((try? await AttentionStore(env.db).open()) ?? []).filter { $0.source == "extension:\(OccurrenceSchedulerTests.id)" }
        }

        func plan(_ list: [ScheduledOccurrence], revision: Int = 1) async -> Int? {
            await scheduler.replace(OccurrenceSchedulerTests.id, name: "Times", revision: revision, occurrences: list)
        }
    }

    @Test func aMomentIsToldWhenItComesUnderItsExtensionsName() async throws {
        let w = try World()
        await w.start()
        #expect(await w.plan([w.moment("a", in: 60)]) == 1)
        await w.scheduler.tick()
        #expect(await w.told().isEmpty, "not yet")
        w.env.clock.advance(61)
        await w.scheduler.tick()
        let told = await w.told()
        #expect(told.count == 1)
        #expect(told.first?.title == "Maghrib")
        #expect(told.first?.body == "Times · Tokyo", "the title is the extension's to choose, so its name is always there")
        #expect(told.first?.refId == "\(Self.id)/a")
        #expect(await w.scheduler.status(Self.id).pending == 0)
    }

    @Test func aMomentMissedBySleepIsSilent() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("late", in: 60), w.moment("very-late", in: 60 + 3600)])
        w.env.clock.advance(60 + OccurrenceScheduler.grace + 3600 + 30)
        await w.scheduler.reschedule()
        let told = await w.told()
                #expect(!told.contains { $0.refId == "\(Self.id)/late" }, "an hour late, it's no use to anyone")
    }

    @Test func aWakeWithinGraceStillTellsIt() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("soon", in: 60)])
        w.env.clock.advance(60 + OccurrenceScheduler.grace - 5)
        await w.scheduler.reschedule()
        #expect(await w.told().count == 1)
    }

    @Test func aRestartNeverTellsItAgain() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("a", in: 1), w.moment("b", in: 7200)])
        w.env.clock.advance(2)
        await w.scheduler.tick()
        #expect(await w.told().count == 1)
        await w.restart()
        #expect(await w.told().count == 1)
        #expect(await w.scheduler.status(Self.id).pending == 1, "what is still to come survives")
        // A plan that names it again, as one made from the same day would.
        await w.plan([w.moment("a", in: 1), w.moment("b", in: 7200)], revision: 2)
        w.env.clock.advance(5)
        await w.scheduler.tick()
        #expect(await w.told().count == 1, "told once is told once")
    }

    @Test func anOlderPlanCantUndoANewerOne() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("new", in: 60)], revision: 5)
        #expect(await w.plan([], revision: 4) == nil)
        let kept = await w.scheduler.status(Self.id)
        #expect(kept.pending == 1 && kept.revision == 5)
        #expect(await w.plan([], revision: 6) == 0, "a newer, empty one cancels")
    }

    @Test func aPlanIsBounded() async throws {
        let w = try World()
        await w.start()
        let far = w.moment("far", in: ScheduledOccurrence.horizon + 60)
        let gone = w.moment("gone", in: -3600)
        let many = (0..<400).map { w.moment("m\($0)", in: Double(60 + $0)) }
        #expect(await w.plan([far, gone] + many + [many[0]]) == ScheduledOccurrence.maxPending)
    }

    @Test func aPlanThatChangesNothingOnlyMovesItsNumber() async throws {
        let w = try World()
        await w.start()
        let list = [w.moment("a", in: 60)]
        await w.plan(list, revision: 1)
        #expect(await w.scheduler.isSame(Self.id, revision: 2, occurrences: list))
        #expect(await w.scheduler.status(Self.id).revision == 2)
        #expect(await !w.scheduler.isSame(Self.id, revision: 3, occurrences: [w.moment("b", in: 60)]))
    }

    @Test func aNoticeIsTakenBackWhenItsTimeIsOver() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("a", in: 1, lasting: 600)])
        w.env.clock.advance(2)
        await w.scheduler.tick()
        #expect(await w.told().count == 1)
        w.env.clock.advance(601)
        await w.scheduler.tick()
        #expect(await w.told().isEmpty)
    }

    @Test func aRestartAfterItsTimeDoesntBringItBack() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("a", in: 1, lasting: 600)])
        w.env.clock.advance(2)
        await w.scheduler.tick()
        w.env.clock.advance(3600)
        await w.restart()
        await w.attention.restoreWaiting()
        #expect(await w.told().isEmpty)
    }

    @Test func aNewOneOfAGroupTakesTheLastOnesPlace() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("before", in: 1, group: "maghrib"), w.moment("at", in: 601, group: "maghrib")])
        w.env.clock.advance(2)
        await w.scheduler.tick()
        w.env.clock.advance(600)
        await w.scheduler.tick()
        #expect(await w.told().map(\.refId) == ["\(Self.id)/at"])
    }

    @Test func cancellingTakesAwayWhatIsToComeAndWhatIsUp() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("a", in: 1), w.moment("b", in: 600)], revision: 3)
        w.env.clock.advance(2)
        await w.scheduler.tick()
        await w.scheduler.cancel(Self.id)
        #expect(await w.told().isEmpty)
        let left = await w.scheduler.status(Self.id)
        #expect(left.pending == 0 && left.revision == 3, "its number stays, so a plan on its way can't bring them back")
        w.env.clock.advance(601)
        await w.scheduler.tick()
        #expect(await w.told().isEmpty)
    }

    @Test func nothingIsToldOnceItIsNoLongerAllowed() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("a", in: 1)])
        w.allowed.on = false
        w.env.clock.advance(2)
        await w.scheduler.tick()
        #expect(await w.told().isEmpty)
        #expect(await w.scheduler.status(Self.id).pending == 0)
    }

    @Test func aDayHasALimit() async throws {
        let w = try World()
        await w.start()
        await w.plan((0..<(OccurrenceScheduler.dailyLimit + 10)).map { w.moment("m\($0)", in: 1) })
        w.env.clock.advance(2)
        await w.scheduler.tick()
        #expect(await w.told().count == OccurrenceScheduler.dailyLimit)
    }

    @Test func forgettingLeavesNothing() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("a", in: 1), w.moment("b", in: 600)], revision: 9)
        w.env.clock.advance(2)
        await w.scheduler.tick()
        await w.scheduler.forget(Self.id)
        #expect(await w.told().isEmpty)
        let left = await w.scheduler.status(Self.id)
        #expect(left.pending == 0 && left.revision == 0, "its numbering starts again")
    }

    @Test func macOSGetsOnlyWhatWasMarkedAndItIsNotToldAgain() async throws {
        let w = try World()
        await w.start()
        await w.plan([w.moment("plain", in: 3600), w.moment("marked", in: 3600, system: true)])
        let fallback = await w.scheduler.fallbackNotifications()
        #expect(fallback.count == 1)
        #expect(fallback.first?.title == "Maghrib" && fallback.first?.body == "Times · Tokyo")
        w.env.clock.advance(3700)
        await w.restart()
        #expect(await !w.told().contains { $0.refId == "\(Self.id)/marked" }, "macOS said it")
    }

    @Test func thePersonsOffKeepsItFromMacOSToo() async throws {
        let w = try World()
        await w.start()
        await w.attention.update { $0.interruptions.set(.off, for: .extension(OccurrenceSchedulerTests.id)) }
        await w.plan([w.moment("marked", in: 3600, system: true)])
        #expect(await w.scheduler.fallbackNotifications().isEmpty)
    }

    @Test func aBadOccurrenceIsLeftOutWhole() throws {
        func parse(_ text: String) throws -> ScheduledOccurrence? {
            try ScheduledOccurrence.parse(JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), pages: ["noor"])
        }
        let good = try parse(#"{"id": "prayer.fajr.2026-11-03", "at": "2026-11-03T04:37:00+09:00", "expires_at": "2026-11-03T05:00:00+09:00", "title": "Fajr", "open": {"page": "noor", "state": {"tab": "prayer"}}}"#)
        #expect(good?.openPage == "noor" && good?.openState?["tab"] == .string("prayer"))
        #expect(try parse(#"{"id": "BAD ID", "at": "2026-11-03T04:37:00Z", "title": "Fajr"}"#) == nil)
        #expect(try parse(#"{"id": "a", "at": "tomorrow", "title": "Fajr"}"#) == nil)
        #expect(try parse(#"{"id": "a", "at": "2026-11-03T04:37:00Z"}"#) == nil)
        #expect(try parse(#"{"id": "a", "at": "2026-11-03T04:37:00Z", "expires_at": "2026-11-03T04:00:00Z", "title": "Fajr"}"#) == nil)
        let other = try parse(#"{"id": "a", "at": "2026-11-03T04:37:00Z", "title": "Fajr", "open": {"page": "not-mine"}}"#)
        #expect(other?.openPage == nil, "only a page of its own")
    }
}

/// When a moment gets to the person (D107): on time past the spacing, within the budgets, and through macOS only if they asked.
struct OccurrenceAttentionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func itDoesntWaitForTheSpacing() {
        let recent = [(source: "watcher", at: now.addingTimeInterval(-5))]
        let plain = AttentionPolicy.decide(level: .attention, source: "extension:a", createdAt: now, now: now, env: AttentionEnvironment(), recent: recent)
        let punctual = AttentionPolicy.decide(level: .attention, source: "extension:a", createdAt: now, now: now, env: AttentionEnvironment(), recent: recent, punctual: true)
        if case .hold = plain {} else { Issue.record("anything else waits for the spacing") }
        if case .present = punctual {} else { Issue.record("a moment doesn't") }
    }

    @Test func itKeepsTheBudgets() {
        let recent = (0..<20).map { (source: "extension:a", at: now.addingTimeInterval(Double(-$0 - 100))) }
        let decision = AttentionPolicy.decide(level: .attention, source: "extension:a", createdAt: now, now: now, env: AttentionEnvironment(), recent: recent, punctual: true)
        if case .hold = decision {} else { Issue.record("a flood is still a flood") }
    }

    @Test func awayOnlyMacOSReachesThemAndOnlyIfAsked() {
        var away = AttentionEnvironment()
        away.away = true
        away.systemNotificationsAllowed = true
        if case .hold = AttentionPolicy.decide(level: .attention, source: "extension:a", createdAt: now, now: now, env: away, recent: [], punctual: true) {} else { Issue.record("waits") }
        if case .present(.system) = AttentionPolicy.decide(level: .attention, source: "extension:a", createdAt: now, now: now, env: away, recent: [], punctual: true, reachWhenAway: true) {} else { Issue.record("through macOS") }
        away.systemNotificationsAllowed = false
        if case .hold = AttentionPolicy.decide(level: .attention, source: "extension:a", createdAt: now, now: now, env: away, recent: [], punctual: true, reachWhenAway: true) {} else { Issue.record("macOS said no") }
    }

    @Test func quietStaysQuietWhileAway() {
        var away = AttentionEnvironment()
        away.away = true
        away.systemNotificationsAllowed = true
        away.quiet = true
        if case .hold = AttentionPolicy.decide(level: .attention, source: "extension:a", createdAt: now, now: now, env: away, recent: [], punctual: true, reachWhenAway: true) {} else { Issue.record("Quiet holds") }
    }
}
