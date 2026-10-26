import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

@Suite struct WatcherEngineTests {
    let env: WatchEnv
    init() throws { env = try WatchEnv() }

    var now: Date { env.clock.now }

    func fake(minimum: TimeInterval = 60, script: @escaping @Sendable (Watcher, Date) async throws -> ProbeResult) -> ScriptedProbe {
        ScriptedProbe(minimumInterval: minimum, script: script)
    }

    func fired(_ summary: String = "It happened", detail: String? = nil, open: String? = nil) -> ProbeResult {
        ProbeResult(state: ["done": true], triggered: true, summary: summary, detail: detail, openTarget: open)
    }

    func stored(_ id: String) async throws -> Watcher { try #require(try await env.store.watcher(id: id)) }

    /// The engine's own copy: check times are only written to the database every few minutes.
    func live(_ engine: WatcherEngine, _ id: String) async throws -> Watcher { try #require(await engine.watcher(id: id)) }

    func notice(titled title: String) async -> AttentionItem? { await env.notices().first { $0.title == title } }

    // MARK: Scheduling

    @Test func checksWhatIsDueAndPersistsAfterEveryCheck() async throws {
        let calls = Counter()
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: ["n": .number(Double(calls.next()))]) }])
        let w = try await engine.add(.make("fake", interval: 600, now: now))
        #expect(w.nextCheckAt == now)

        await engine.tick()
        #expect(calls.count == 1)
        let first = try await stored(w.id)
        #expect(first.lastState == ["n": 1])
        #expect(first.lastCheckedAt == now)
        #expect(first.nextCheckAt == now.addingTimeInterval(600))
        #expect(first.errorCount == 0)

        env.clock.advance(599)
        await engine.tick()
        #expect(calls.count == 1, "not due yet")
        env.clock.advance(1)
        await engine.tick()
        #expect(calls.count == 2)
        #expect(try await stored(w.id).lastState == ["n": 2])
    }

    @Test func publishesDataChangedWhenSomethingChanges() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:])) }])
        let stream = env.base.events.stream()
        _ = try await engine.add(.make("fake", interval: 600, now: now))
        await engine.tick()
        var seen = 0
        for await event in stream {
            if case .dataChanged(.watchers) = event { seen += 1 }
            if seen >= 2 { break }
        }
        #expect(seen >= 2)
    }

    @Test func routineChecksReachTheDatabaseOnlyEveryFewMinutes() async throws {
        let n = Mutex(0)
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: ["n": .number(Double(n.withLock { $0 }))]) }])
        let w = try await engine.add(.make("fake", interval: 60, mode: .repeat, now: now))
        let t0 = now
        await engine.tick()
        #expect(try await stored(w.id).lastCheckedAt == t0)

        // Same answer a minute later: the engine knows, the database is not touched.
        env.clock.advance(60)
        await engine.tick()
        #expect(try await live(engine, w.id).lastCheckedAt == t0.addingTimeInterval(60))
        #expect(try await stored(w.id).lastCheckedAt == t0)

        // A different answer is saved at once, and so is the timing after a few quiet minutes.
        n.withLock { $0 = 1 }
        env.clock.advance(60)
        await engine.tick()
        #expect(try await stored(w.id).lastState == ["n": 1])
        env.clock.advance(WatcherEngine.routineSaveInterval)
        await engine.tick()
        #expect(try await stored(w.id).lastCheckedAt == now)
    }

    @Test func intervalsAreRaisedToTheFloorAndDefaultsFilledIn() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:])) }])
        #expect(try await engine.add(.make("fake", interval: 10, now: now)).intervalS == 60)
        #expect(try await engine.add(.make("fake", interval: 0, now: now)).intervalS == 600)
        #expect(try await engine.add(.make("fake", interval: 99 * 86400, now: now)).intervalS == WatchLimits.maxInterval)
        #expect(try await engine.add(.make("fake", interval: 900, now: now)).intervalS == 900)
    }

    @Test func realKindsKeepTheirOwnFloors() async throws {
        let engine = env.engine()
        let page = try await engine.add(.make(WatchKind.urlChange, config: ["url": "https://example.com"], interval: 30, now: now))
        #expect(page.intervalS == 300)
        let defaulted = try await engine.add(.make(WatchKind.urlChange, config: ["url": "https://example.com/b"], now: now))
        #expect(defaulted.intervalS == 1800)
        let site = try await engine.add(.make(WatchKind.siteStatus, config: ["url": "https://example.com"], interval: 5, now: now))
        #expect(site.intervalS == 60)
        let box = try Sandbox()
        defer { box.cleanUp() }
        let file = try await engine.add(.make(WatchKind.fileAppears, config: ["path": .string(box.path("a"))], interval: 1, now: now))
        #expect(file.intervalS == 15)
        let process = try await engine.add(.make(WatchKind.processExits, config: ["name": "Xcode"], interval: 1, now: now))
        #expect(process.intervalS == 3)
        let command = try await engine.add(.make(WatchKind.command, config: ["command": "true"], condition: ["changed": true], interval: 5, now: now))
        #expect(command.intervalS == 60)
    }

    @Test func oneTimerWakesAtTheSoonestCheckOrExpiry() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:])) }])
        #expect(await engine.soonest() == nil)
        _ = try await engine.add(.make("fake", interval: 600, now: now))
        await engine.tick() // checked, and now waits 600 s
        _ = try await engine.add(.make("fake", interval: 6000, now: now))
        await engine.tick()
        #expect(await engine.soonest() == now.addingTimeInterval(600))
        // An expiry earlier than the next check pulls the wake-up forward.
        var soon = Watcher.make("fake", interval: 6000, now: now)
        soon.expiresAt = now.addingTimeInterval(100)
        _ = try await engine.add(soon)
        await engine.tick()
        #expect(await engine.soonest() == now.addingTimeInterval(100))
    }

    @Test func dueChecksRunAFewAtATime() async throws {
        let live = Mutex(0)
        let peak = Mutex(0)
        let engine = env.engine(probes: [fake { _, _ in
            let now = live.withLock { n -> Int in n += 1; return n }
            peak.withLock { $0 = max($0, now) }
            try await Task.sleep(for: .milliseconds(150))
            live.withLock { $0 -= 1 }
            return ProbeResult(state: .object([:]))
        }])
        for _ in 0..<10 { _ = try await engine.add(.make("fake", interval: 600, now: now)) }
        await engine.tick()
        let seen = peak.withLock { $0 }
        #expect(seen > 1 && seen <= WatcherEngine.maxConcurrentChecks, "peak concurrency \(seen)")
        for w in await engine.list() { #expect(w.lastCheckedAt != nil) }
    }

    @Test func checkNowIgnoresTheSchedule() async throws {
        let calls = Counter()
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: ["n": .number(Double(calls.next()))]) }])
        let w = try await engine.add(.make("fake", interval: 6000, now: now))
        await engine.tick()
        let after = await engine.checkNow(w.id)
        #expect(calls.count == 2)
        #expect(after?.lastState == ["n": 2])
        #expect(await engine.checkNow("nope") == nil)
    }

    // MARK: Triggers

    @Test func aOnceWatcherTellsYouAndStops() async throws {
        let calls = Counter()
        let engine = env.engine(probes: [fake { _, _ in
            calls.next()
            return ProbeResult(state: ["done": true], triggered: true, summary: "example.com/pricing changed",
                               detail: "“$19” → “$29”", openTarget: "https://example.com/pricing")
        }])
        let w = try await engine.add(.make("fake", interval: 600, now: now))
        await engine.tick()

        let done = try await stored(w.id)
        #expect(done.state == .triggered)
        #expect(done.fireCount == 1)
        #expect(done.nextCheckAt == nil)

        let item = try #require(await notice(titled: "example.com/pricing changed"))
        #expect(item.body == "“$19” → “$29”")
        #expect(item.level == .attention)
        #expect(item.source == "watcher")
        #expect(item.refKind == "watcher")
        #expect(item.refId == w.id)
        #expect(item.actions.map(\.id) == ["open", "keep", "stop"])
        #expect(item.actions.first?.isPrimary == true)

        env.clock.advance(100_000)
        await engine.tick()
        #expect(calls.count == 1, "a finished watcher stays finished")
    }

    @Test func aRepeatWatcherRestsBeforeLookingAgain() async throws {
        let calls = Counter()
        let engine = env.engine(probes: [fake { _, _ in calls.next(); return ProbeResult(state: .object([:]), triggered: true, summary: "Fired \(calls.count)") }])
        var w = Watcher.make("fake", interval: 600, mode: .repeat, now: now)
        w.level = .gentle
        let added = try await engine.add(w)
        await engine.tick()

        let first = try await stored(added.id)
        #expect(first.state == .active)
        #expect(first.fireCount == 1)
        #expect(first.nextCheckAt == now.addingTimeInterval(WatchLimits.defaultCooldown), "30 minutes of quiet, longer than the interval")
        let item = try #require(await notice(titled: "Fired 1"))
        #expect(item.level == .gentle)
        #expect(item.actions.map(\.id) == ["stop"], "repeat watchers have nothing to keep")

        env.clock.advance(WatchLimits.defaultCooldown - 1)
        await engine.tick()
        #expect(calls.count == 1)
        env.clock.advance(1)
        await engine.tick()
        #expect(calls.count == 2)
        #expect(try await stored(added.id).fireCount == 2)
    }

    @Test func cooldownCanBeShorterOrLongerPerWatcher() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:]), triggered: true, summary: "x") }])
        let w = try await engine.add(.make("fake", config: ["cooldown_minutes": 5], interval: 60, mode: .repeat, now: now))
        await engine.tick()
        #expect(try await stored(w.id).nextCheckAt == now.addingTimeInterval(300))

        let probe = ScriptedProbe(repeatCooldown: 60, script: { _, _ in ProbeResult(state: .object([:]), triggered: true, summary: "y") })
        let other = env.engine(probes: [probe])
        let v = try await other.add(.make("fake", interval: 600, mode: .repeat, now: now))
        await other.tick()
        #expect(try await stored(v.id).nextCheckAt == now.addingTimeInterval(600), "never sooner than its own interval")
    }

    @Test func twoWatchersOnOneHostTakeTurnsAndCheckNowDoesNotWait() async throws {
        env.fetcher.say("<p>hello</p>")
        let engine = env.engine()
        let a = try await engine.add(.make(WatchKind.urlChange, config: ["url": "https://example.com/a"], now: now))
        let b = try await engine.add(.make(WatchKind.urlChange, config: ["url": "https://example.com/b"], now: now))
        await engine.tick()

        let results = [try await live(engine, a.id), try await live(engine, b.id)]
        let checked = results.filter { $0.lastState != nil }
        let waiting = results.filter { $0.lastState == nil }
        #expect(checked.count == 1 && waiting.count == 1, "one request a minute per host")
        let late = try #require(waiting.first)
        #expect(late.errorCount == 0 && late.lastError == nil, "waiting your turn is not a failure")
        #expect(late.nextCheckAt == now.addingTimeInterval(60))
        #expect(env.fetcher.requests.count == 1)

        let forced = await engine.checkNow(late.id)
        #expect(forced?.lastState != nil, "the user pressing check now is not made to wait")
        #expect(env.fetcher.requests.count == 2)
    }

    @Test func recheckAsksForAnotherLookSooner() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:]), recheckIn: 3) }])
        let w = try await engine.add(.make("fake", interval: 600, now: now))
        await engine.tick()
        #expect(try await stored(w.id).nextCheckAt == now.addingTimeInterval(3))
    }

    @Test func gentleLevelOverrideFromTheProbeIsUsed() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:]), triggered: true, summary: "Just so you know", level: .gentle) }])
        _ = try await engine.add(.make("fake", interval: 600, now: now))
        await engine.tick()
        #expect(await notice(titled: "Just so you know")?.level == .gentle)
    }

    @Test func noticesAreShortAndFreeOfHiddenCharacters() async throws {
        let long = "Price \u{202E}changed " + String(repeating: "x", count: 500)
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:]), triggered: true, summary: long, detail: "a\u{200B}b\n\nc " + String(repeating: "y", count: 500)) }])
        _ = try await engine.add(.make("fake", interval: 600, now: now))
        await engine.tick()
        let item = try #require(await env.notices().first)
        #expect(item.title.count <= 160)
        #expect(!item.title.unicodeScalars.contains { $0.value == 0x202E })
        #expect(item.body?.hasPrefix("ab\nc yyy") == true)
        #expect((item.body?.count ?? 0) <= 200 + 1)
    }

    @Test func onlyTheUserCanMakeACriticalWatcher() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:])) }])
        var mine = Watcher.make("fake", interval: 600, now: now)
        mine.level = .critical
        #expect(try await engine.add(mine).level == .critical)
        for source in ["agent", "external:codex", "extension:dev.x"] {
            var other = Watcher.make("fake", interval: 600, source: source, now: now)
            other.level = .critical
            #expect(try await engine.add(other).level == .attention, "\(source)")
        }
    }

    // MARK: Failures

    @Test func failuresBackOffExponentiallyAndSpeakUpOnTheThird() async throws {
        let fail = Mutex(true)
        let engine = env.engine(probes: [fake { _, _ in
            if fail.withLock({ $0 }) { throw ProbeError.failed("The site didn't answer in time.") }
            return ProbeResult(state: ["ok": true])
        }])
        let w = try await engine.add(.make("fake", title: "example.com/pricing", interval: 3600, now: now))

        var waits: [TimeInterval] = []
        for round in 1...5 {
            await engine.tick()
            let s = try await stored(w.id)
            #expect(s.errorCount == round)
            #expect(s.lastError == "The site didn't answer in time.")
            #expect(s.state == .active)
            waits.append(s.nextCheckAt!.timeIntervalSince(now))
            if round == 2 { #expect(await env.notices().isEmpty, "two failures are still just a hiccup") }
            env.clock.set(s.nextCheckAt!)
        }
        // interval × 2^errors, never more than six hours.
        #expect(waits == [7200, 14400, 21600, 21600, 21600])

        let items = await env.notices()
        #expect(items.count == 1, "told once, on the third failure, not on every later one")
        let item = try #require(items.first)
        #expect(item.title == "I can't check example.com/pricing: the site didn't answer in time")
        #expect(item.level == .attention, "something they asked to hear about stopped working")
        #expect(item.actions.map(\.id) == ["stop"])

        fail.withLock { $0 = false }
        await engine.tick()
        let recovered = try await stored(w.id)
        #expect(recovered.errorCount == 0)
        #expect(recovered.lastError == nil)
        #expect(recovered.nextCheckAt == now.addingTimeInterval(3600))
    }

    @Test func waitingForAHostAndBeingOfflineAreNotFailures() async throws {
        let mode = Mutex(0)
        let engine = env.engine(probes: [fake { _, at in
            switch mode.withLock({ $0 }) {
            case 0: throw ProbeError.deferred(until: at.addingTimeInterval(45))
            case 1: throw ProbeError.offline
            default: return ProbeResult(state: .object([:]))
            }
        }])
        let t0 = now
        let w = try await engine.add(.make("fake", interval: 3600, now: now))
        await engine.tick()
        var s = try await live(engine, w.id)
        #expect(s.errorCount == 0 && s.lastError == nil)
        #expect(s.nextCheckAt == t0.addingTimeInterval(45))

        mode.withLock { $0 = 1 }
        env.clock.advance(45)
        await engine.tick()
        s = try await live(engine, w.id)
        #expect(s.errorCount == 0)
        #expect(s.nextCheckAt == t0.addingTimeInterval(45 + 60), "try again in a minute")
        #expect(await env.notices().isEmpty)
    }

    @Test func otherErrorsGetPlainWords() async throws {
        let engine = env.engine(probes: [fake { _, _ in throw NSError(domain: "x", code: 1) }])
        let w = try await engine.add(.make("fake", interval: 600, now: now))
        await engine.tick()
        #expect(try await stored(w.id).lastError == "Something went wrong while checking.")
    }

    // MARK: Lifetime

    @Test func watchersExpireWithAGentleNotice() async throws {
        let calls = Counter()
        let engine = env.engine(probes: [fake { _, _ in calls.next(); return ProbeResult(state: .object([:])) }])
        let once = try await engine.add(.make("fake", title: "Pricing", interval: 600, now: now))
        let repeating = try await engine.add(.make("fake", title: "Status", interval: 600, mode: .repeat, now: now))
        #expect(once.expiresAt == now.addingTimeInterval(7 * 86400))
        #expect(repeating.expiresAt == now.addingTimeInterval(30 * 86400))

        env.clock.advance(7 * 86400 + 1)
        await engine.tick()
        let gone = try await stored(once.id)
        #expect(gone.state == .expired)
        #expect(try await stored(repeating.id).state == .active)
        let item = try #require(await notice(titled: "I stopped watching Pricing"))
        #expect(item.level == .gentle)
        #expect(item.body == "It's been 7 days. I can start again if you still want it.")
        #expect(item.actions.map(\.id) == ["keep", "stop"])
        #expect(await notice(titled: "I stopped watching Status") == nil)
    }

    @Test func anExpiryBetweenChecksIsHonouredWithoutACheck() async throws {
        let calls = Counter()
        let engine = env.engine(probes: [fake { _, _ in calls.next(); return ProbeResult(state: .object([:])) }])
        var w = Watcher.make("fake", interval: 6000, now: now)
        w.expiresAt = now.addingTimeInterval(1000)
        let added = try await engine.add(w)
        await engine.tick()
        #expect(calls.count == 1)
        env.clock.advance(1001)
        await engine.tick()
        #expect(calls.count == 1, "expired, not checked")
        #expect(try await stored(added.id).state == .expired)
    }

    @Test func pauseResumeAndRemove() async throws {
        let calls = Counter()
        let engine = env.engine(probes: [fake { _, _ in calls.next(); return ProbeResult(state: .object([:])) }])
        let w = try await engine.add(.make("fake", interval: 600, now: now))
        await engine.tick()

        let paused = try await engine.pause(w.id)
        #expect(paused.state == .paused)
        #expect(paused.nextCheckAt == nil)
        env.clock.advance(10_000)
        await engine.tick()
        #expect(calls.count == 1)

        let resumed = try await engine.resume(w.id)
        #expect(resumed.state == .active)
        #expect(resumed.nextCheckAt == now)
        #expect(resumed.expiresAt! >= now.addingTimeInterval(7 * 86400))
        await engine.tick()
        #expect(calls.count == 2)

        let removed = await engine.remove(w.id)
        #expect(removed?.id == w.id)
        #expect(try await env.store.watcher(id: w.id) == nil)
        #expect(await engine.list().isEmpty)
        await #expect(throws: WatchError.self) { try await engine.pause("missing") }
    }

    @Test func aResultArrivingAfterPauseOrRemoveIsDropped() async throws {
        let engine = env.engine(probes: [fake { _, _ in
            try await Task.sleep(for: .milliseconds(300))
            return ProbeResult(state: ["late": true], triggered: true, summary: "Too late")
        }])
        let a = try await engine.add(.make("fake", interval: 600, now: now))
        let b = try await engine.add(.make("fake", interval: 600, now: now))
        let round = Task { await engine.tick() }
        try await Task.sleep(for: .milliseconds(100))
        _ = try await engine.pause(a.id)
        _ = await engine.remove(b.id)
        await round.value
        let pausedA = try await stored(a.id)
        #expect(pausedA.state == .paused)
        #expect(pausedA.lastState == nil)
        #expect(pausedA.fireCount == 0)
        #expect(try await env.store.watcher(id: b.id) == nil)
        #expect(await env.notices().isEmpty)
    }

    // MARK: Kinds

    @Test func unknownKindsAreRefusedAndParkedUntilTheirProbeArrives() async throws {
        let engine = env.engine(probes: [])
        // A row left by an extension that is switched off right now.
        try await env.store.save(.make("battery_low", interval: 60, now: now))
        await #expect(throws: WatchError.unknownKind("battery_low")) { try await engine.add(.make("battery_low", now: now)) }
        let calls = Counter()
        await engine.tick()
        let parked = try #require(await engine.list().first)
        #expect(parked.state == .error)
        #expect(parked.lastError?.contains("battery_low") == true)

        await engine.register(ScriptedProbe(kind: "battery_low", script: { _, _ in calls.next(); return ProbeResult(state: .object([:])) }))
        await engine.tick()
        #expect(calls.count == 1)
        #expect(await engine.watcher(id: parked.id)?.state == .active)
    }

    // MARK: Quotas

    @Test func atMostFiftyAreActive() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:])) }])
        for _ in 0..<WatchLimits.maxActive { _ = try await engine.add(.make("fake", interval: 600, now: now)) }
        await #expect(throws: WatchError.self) { try await engine.add(.make("fake", interval: 600, now: now)) }
        // A paused one makes room, and cannot be resumed into a full house.
        let first = try #require(await engine.list().last)
        _ = try await engine.pause(first.id)
        let extra = try await engine.add(.make("fake", interval: 600, now: now))
        await #expect(throws: WatchError.self) { try await engine.resume(first.id) }
        _ = await engine.remove(extra.id)
        _ = try await engine.resume(first.id)
    }

    @Test func externalAppsShareTen() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:])) }])
        for _ in 0..<WatchLimits.maxActivePerExternalClient {
            _ = try await engine.add(.make("fake", interval: 600, source: "external:codex", now: now))
        }
        await #expect(throws: WatchError.self) { try await engine.add(.make("fake", interval: 600, source: "external:codex", now: now)) }
        // A new name doesn't buy new room: the cap is for all of them together.
        await #expect(throws: WatchError.self) { try await engine.add(.make("fake", interval: 600, source: "external:claude-code", now: now)) }
        _ = try await engine.add(.make("fake", interval: 600, source: "user", now: now))
    }

    /// The slot is taken in the same actor step as the count, so parallel adds can't all see room.
    @Test func parallelExternalAddsNeverPassTheCap() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:])) }])
        let now = self.now
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<(WatchLimits.maxActiveExternal + 8) {
                group.addTask { _ = try? await engine.add(.make("fake", interval: 600, source: "external:agent-\(i)", now: now)) }
            }
        }
        #expect(await engine.list().filter { $0.state == .active }.count == WatchLimits.maxActiveExternal)
        #expect(try await env.store.active().count == WatchLimits.maxActiveExternal)
    }

    @Test func externalWatchersStopAfterADay() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:])) }])
        let theirs = try await engine.add(.make("fake", interval: 600, mode: .repeat, source: "external:codex", now: now))
        #expect(theirs.expiresAt == now.addingTimeInterval(WatchLimits.externalExpiry))
        // An earlier expiry they asked for stands; a later one is cut to a day.
        var short = Watcher.make("fake", interval: 600, source: "external:codex", now: now)
        short.expiresAt = now.addingTimeInterval(3600)
        #expect(try await engine.add(short).expiresAt == now.addingTimeInterval(3600))
        var long = Watcher.make("fake", interval: 600, source: "external:codex", now: now)
        long.expiresAt = now.addingTimeInterval(10 * 86400)
        #expect(try await engine.add(long).expiresAt == now.addingTimeInterval(WatchLimits.externalExpiry))
        // Everyone else keeps the usual lifetimes.
        let mine = try await engine.add(.make("fake", interval: 600, mode: .repeat, source: "user:agent", now: now))
        #expect(mine.expiresAt == now.addingTimeInterval(WatchLimits.repeatExpiry))
    }

    @Test func atMostFiveCommandWatchers() async throws {
        let engine = env.engine()
        for n in 0..<WatchLimits.maxActiveCommands {
            _ = try await engine.add(.make(WatchKind.command, config: ["command": .string("echo \(n)")], condition: ["changed": true], now: now))
        }
        await #expect(throws: WatchError.self) {
            try await engine.add(.make(WatchKind.command, config: ["command": "echo 6"], condition: ["changed": true], now: now))
        }
    }

    @Test func commandsCannotBeAddedByExternalAppsAtAll() async throws {
        let engine = env.engine()
        for source in ["external:codex", "extension:dev.x", "routine:r1", "agent"] {
            await #expect(throws: WatchError.self, "\(source)") {
                try await engine.add(.make(WatchKind.command, config: ["command": "echo hi"], condition: ["changed": true], source: source, now: now))
            }
        }
    }

    // MARK: Restart

    @Test func aNewEngineContinuesWhereTheOldOneStopped() async throws {
        let seen = Mutex<[JSONValue?]>([])
        let probe = fake { w, _ in
            seen.withLock { $0.append(w.lastState) }
            return ProbeResult(state: ["round": .number(Double(seen.withLock { $0.count }))])
        }
        let first = env.engine(probes: [probe])
        let w = try await first.add(.make("fake", interval: 600, now: now))
        await first.tick()
        await first.stop()

        env.clock.advance(600)
        let second = env.engine(probes: [probe])
        #expect(await second.list().map(\.id) == [w.id])
        await second.tick()
        #expect(seen.withLock { $0 } == [nil, ["round": 1]], "the second engine saw what the first one left behind")
        #expect(try await stored(w.id).lastState == ["round": 2])
    }

    @Test func whatCameDueWhileTheAppWasClosedIsCheckedAtLaunch() async throws {
        let calls = Counter()
        let probe = fake { _, _ in calls.next(); return ProbeResult(state: .object([:])) }
        let first = env.engine(probes: [probe])
        _ = try await first.add(.make("fake", interval: 600, now: now))
        await first.tick()
        await first.stop()

        env.clock.advance(3 * 86400) // the Mac was off for three days
        let second = env.engine(probes: [probe])
        await second.start()
        for _ in 0..<50 where calls.count < 2 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(calls.count == 2)
        await second.stop()
    }

    @Test func nothingRunsAfterStop() async throws {
        let calls = Counter()
        let engine = env.engine(probes: [fake { _, _ in calls.next(); return ProbeResult(state: .object([:])) }])
        await engine.start()
        await engine.stop()
        _ = try await engine.add(.make("fake", interval: 600, now: now))
        try await Task.sleep(for: .milliseconds(200))
        #expect(calls.count == 0, "stopped engines do not arm a timer")
    }

    // MARK: Buttons on the notice

    @Test func stopRemovesKeepRearmsAndOpenOpens() async throws {
        let engine = env.engine(probes: [fake { w, _ in
            ProbeResult(state: .object([:]), triggered: true, summary: "Fired \(w.title)", openTarget: "https://example.com/pricing")
        }])
        await engine.connectAttention()
        let keep = try await engine.add(.make("fake", title: "keep", interval: 600, now: now))
        let stop = try await engine.add(.make("fake", title: "stop", interval: 600, now: now))
        let open = try await engine.add(.make("fake", title: "open", interval: 600, now: now))
        await engine.tick()
        #expect(try await stored(keep.id).state == .triggered)

        await env.attention.respond(id: try #require(await notice(titled: "Fired keep")).id, actionId: "keep")
        let rearmed = try await stored(keep.id)
        #expect(rearmed.state == .active)
        #expect(rearmed.nextCheckAt == now)

        await env.attention.respond(id: try #require(await notice(titled: "Fired stop")).id, actionId: "stop")
        #expect(try await env.store.watcher(id: stop.id) == nil)

        await env.attention.respond(id: try #require(await notice(titled: "Fired open")).id, actionId: "open")
        #expect(env.openedURLs == [URL(string: "https://example.com/pricing")!])
        #expect(try await stored(open.id).state == .triggered, "opening does not stop anything")
    }

    @Test func openNeverRunsADownloadedProgram() async throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        let engine = env.engine(probes: [fake { _, _ in
            ProbeResult(state: .object([:]), triggered: true, summary: "Installer arrived", openTarget: box.path("Setup.pkg"))
        }])
        await engine.connectAttention()
        _ = try await engine.add(.make("fake", interval: 600, now: now))
        await engine.tick()
        await env.attention.respond(id: try #require(await notice(titled: "Installer arrived")).id, actionId: "open")
        #expect(env.openedURLs == [URL(fileURLWithPath: box.root)])
    }

    @Test func aNoticeAfterRestartStillWorks() async throws {
        let probe = fake { _, _ in ProbeResult(state: .object([:]), triggered: true, summary: "Fired") }
        let first = env.engine(probes: [probe])
        let w = try await first.add(.make("fake", interval: 600, now: now))
        await first.tick()
        await first.stop()

        let second = env.engine(probes: [probe])
        await second.connectAttention()
        await env.attention.respond(id: try #require(await notice(titled: "Fired")).id, actionId: "stop")
        #expect(try await env.store.watcher(id: w.id) == nil)
    }
}

/// Real timers and real kernel events, with the real clock. Kept few and generous.
@Suite struct WatcherEngineLiveTests {
    let env: WatchEnv
    init() throws { env = try WatchEnv() }

    func waitUntil(_ seconds: TimeInterval = 6, _ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    @Test func theTimerChecksWhenDueAndNotMoreOften() async throws {
        let calls = Counter()
        let probe = ScriptedProbe(minimumInterval: 0.05, script: { _, _ in calls.next(); return ProbeResult(state: .object([:])) })
        let engine = env.engine(probes: [probe], clock: SystemClock())
        _ = try await engine.add(.make("fake", interval: 0.2, now: Date()))
        await engine.start()
        try await Task.sleep(for: .milliseconds(1100))
        await engine.stop()
        let count = calls.count
        #expect((3...8).contains(count), "expected about 6 checks in 1.1 s at 0.2 s apart, got \(count)")
        try await Task.sleep(for: .milliseconds(400))
        #expect(calls.count == count, "no checks after stop")
    }

    @Test func aNewFileInAWatchedFolderIsNoticedAtOnceNotAtTheNextInterval() async throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        let engine = env.engine(probes: [FileAppearsProbe(settle: 0)], clock: SystemClock())
        let w = try await engine.add(.make(WatchKind.fileAppears, config: ["path": .string(box.path("report.pdf"))], interval: 3600, now: Date()))
        await engine.start()
        let store = env.store
        let baseline = await waitUntil { (try? await store.watcher(id: w.id))?.lastCheckedAt != nil }
        #expect(baseline)

        try box.write("report.pdf", "data", age: 60)
        let noticed = await waitUntil { (try? await store.watcher(id: w.id))?.state == .triggered }
        #expect(noticed, "the folder event should have woken the watcher long before its hour was up")
        await engine.stop()
        #expect(await env.notices().contains { $0.title == "report.pdf appeared" })
    }

    @Test func aProcessExitingIsNoticedAtOnce() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        try SpawnLock.withLock { try child.run() }
        defer { if child.isRunning { child.terminate() } }

        let engine = env.engine(probes: [ProcessExitsProbe()], clock: SystemClock())
        let w = try await engine.add(.make(WatchKind.processExits, config: ["pid": .number(Double(child.processIdentifier))], interval: 3600, now: Date()))
        await engine.start()
        let store = env.store
        let seen = await waitUntil { (try? await store.watcher(id: w.id))?.lastState?["seen"]?.boolValue == true }
        #expect(seen)

        child.terminate()
        let noticed = await waitUntil { (try? await store.watcher(id: w.id))?.state == .triggered }
        #expect(noticed, "a kernel exit event should wake the watcher without waiting for the interval")
        await engine.stop()
    }
}
