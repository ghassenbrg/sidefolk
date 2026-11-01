import Foundation
import GRDB
import Synchronization
import Testing
@testable import SidefolkCore

/// A watch's history (D87): the check log, its runs, the kept versions, the migration, pruning and "Your data".
@Suite struct WatchHistoryTests {
    let env: WatchEnv
    init() throws { env = try WatchEnv() }

    var now: Date { env.clock.now }
    var log: WatchHistoryStore { WatchHistoryStore(env.base.db) }

    func fake(_ script: @escaping @Sendable (Watcher, Date) async throws -> ProbeResult) -> ScriptedProbe {
        ScriptedProbe(minimumInterval: 60, repeatCooldown: 60, script: script)
    }

    // MARK: The log

    @Test func quietChecksAreOneRunAndChangesTheirOwnRows() async throws {
        let answer = Mutex<ProbeResult>(ProbeResult(state: ["n": 0]))
        let engine = env.engine(probes: [fake { _, _ in answer.withLock { $0 } }])
        let w = try await engine.add(.make("fake", interval: 60, mode: .repeat, now: now))
        for _ in 0..<3 {
            await engine.tick()
            env.clock.advance(60)
        }
        answer.withLock { $0 = ProbeResult(state: ["n": 1], triggered: true, summary: "The page changed") }
        await engine.tick()
        env.clock.advance(60)
        answer.withLock { $0 = ProbeResult(state: ["n": 1]) }
        await engine.tick()

        let checks = await engine.checks(for: w.id)
        #expect(checks.map(\.result) == [.unchanged, .changed, .unchanged])
        #expect(checks.map(\.count) == [1, 1, 3])
        #expect(checks[1].reason == "The page changed")
        #expect(checks[2].firstAt == w.createdAt)
        #expect(checks[2].lastAt == w.createdAt.addingTimeInterval(120))
        #expect(checks.allSatisfy { $0.durationMs != nil })
        #expect(await engine.recentTicks(for: [w.id], count: 24)[w.id] == [.unchanged, .unchanged, .unchanged, .changed, .unchanged])
        #expect(await engine.recentTicks(for: [w.id], count: 2)[w.id] == [.changed, .unchanged])
    }

    @Test func aGrowingRunReachesTheDatabaseWithTheRoutineSaves() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: ["n": 0]) }])
        let w = try await engine.add(.make("fake", interval: 60, mode: .repeat, now: now))
        await engine.tick()
        env.clock.advance(60)
        await engine.tick()
        // The engine has the run as it stands; the database still has its first check.
        #expect(await engine.checks(for: w.id).first?.count == 2)
        #expect(try await log.checks(watcherId: w.id).first?.count == 1)
        env.clock.advance(WatcherEngine.routineSaveInterval)
        await engine.tick()
        #expect(try await log.checks(watcherId: w.id).first?.count == 3)
        env.clock.advance(60)
        await engine.tick()
        await engine.flushHistory()
        #expect(try await log.checks(watcherId: w.id).first?.count == 4, "quitting saves the run")
    }

    @Test func failuresCarryTheirReasonAndWaitingIsNoCheck() async throws {
        let failing = Mutex<(any Error)?>(ProbeError.failed("The site didn't answer in time."))
        let engine = env.engine(probes: [fake { _, _ in
            if let error = failing.withLock({ $0 }) { throw error }
            return ProbeResult(state: .object([:]))
        }])
        let w = try await engine.add(.make("fake", interval: 60, mode: .repeat, now: now))
        await engine.tick()
        env.clock.advance(3600)
        await engine.tick()
        failing.withLock { $0 = ProbeError.offline }
        env.clock.advance(3600)
        await engine.tick()
        failing.withLock { $0 = ProbeError.deferred(until: Date.distantPast) }
        env.clock.advance(3600)
        await engine.tick()

        let checks = await engine.checks(for: w.id)
        #expect(checks.count == 1)
        #expect(checks[0].result == .failed)
        #expect(checks[0].count == 2)
        #expect(checks[0].reason == "The site didn't answer in time.")
    }

    @Test func pausingIsOnTheTimelineAndReportsKeepNoLog() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:]), reading: ReadingText(shown: "4", forModel: "4")) }])
        let w = try await engine.add(.make("fake", interval: 60, mode: .repeat, now: now))
        let report = try await engine.add(.make("fake", interval: 60, mode: .report, now: now))
        await engine.tick()
        env.clock.advance(10)
        try await engine.pause(w.id)
        try await engine.pause(report.id)
        #expect(await engine.checks(for: w.id).map(\.result) == [.paused, .unchanged])
        #expect(await engine.checks(for: report.id).isEmpty)
    }

    @Test func historyGoesWithItsWatch() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:]), compared: ComparedText("one")) }])
        let w = try await engine.add(.make("fake", interval: 60, mode: .repeat, now: now))
        await engine.tick()
        #expect(try await log.checks(watcherId: w.id).count == 1)
        #expect(try await log.versions(watcherId: w.id).count == 1)
        await engine.remove(w.id)
        #expect(try await log.checks(watcherId: w.id).isEmpty)
        #expect(try await log.versions(watcherId: w.id).isEmpty)
    }

    // MARK: Versions

    @Test func aFileWatchKeepsItsLastTwoTexts() async throws {
        let box = try Sandbox()
        let path = try box.write("notes.md", "Milk\nEggs\n")
        let engine = env.engine()
        let w = try await engine.add(.make(WatchKind.fileChanges, config: ["path": .string(path)], interval: 15, mode: .repeat, now: now))
        await engine.tick()
        #expect(await engine.versions(for: w.id).map(\.text) == ["Milk\nEggs"])

        for (i, text) in ["Milk\nBread\nEggs\n", "Milk\nBread\n"].enumerated() {
            try box.write("notes.md", text, age: Double(100 - i * 10))
            await engine.checkNow(w.id)
        }
        let versions = await engine.versions(for: w.id)
        #expect(versions.map(\.text) == ["Milk\nBread\nEggs", "Milk\nBread"])
        #expect(LineDiff.inline(old: versions[0].text, new: versions[1].text) == [.same("Milk"), .same("Bread"), .removed("Eggs")])
        #expect(await engine.checks(for: w.id).map(\.result) == [.changed, .changed, .unchanged])
    }

    @Test func aFileThatIsNotTextKeepsNoVersion() async throws {
        let box = try Sandbox()
        let path = try box.write("photo.png", "\u{0}PNG")
        let engine = env.engine()
        let w = try await engine.add(.make(WatchKind.fileChanges, config: ["path": .string(path)], interval: 15, mode: .repeat, now: now))
        await engine.tick()
        #expect(await engine.versions(for: w.id).isEmpty)
        #expect(FileText.lines("a\u{202E}b\t c  \r\nd") == "ab     c\nd")
    }

    @Test func aPageWatchKeepsTheTextItComparedNotItsHTML() async throws {
        let engine = env.engine()
        env.fetcher.say("<html><body><p>Price: 10 €</p><p>In stock</p><script>x()</script></body></html>")
        let w = try await engine.add(.make(WatchKind.urlChange, config: ["url": "https://example.com/p"], interval: 300, mode: .repeat, now: now))
        await engine.tick()
        env.fetcher.reset()
        env.fetcher.say("<html><body><p>Price: 10 €</p><p>Small tweak</p><p>Sold out</p></body></html>")
        await engine.checkNow(w.id)
        let versions = await engine.versions(for: w.id)
        #expect(versions.map(\.text) == ["Price: 10 €\nIn stock", "Price: 10 €\nSmall tweak\nSold out"])
        #expect(!versions.contains { $0.text.contains("<") })
    }

    @Test func versionsAreDedupedCappedAndKeptTwo() async throws {
        let box = try Sandbox()
        let engine = env.engine()
        let w = try await engine.add(.make(WatchKind.fileChanges, config: ["path": .string(try box.write("a.txt"))], interval: 15, now: now))
        #expect(try await log.addVersion(watcherId: w.id, text: "one", at: now))
        let again = try await log.addVersion(watcherId: w.id, text: "one", at: now)
        #expect(!again, "the same text isn't kept twice")
        try await log.addVersion(watcherId: w.id, text: "two", at: now)
        try await log.addVersion(watcherId: w.id, text: "three", at: now)
        #expect(try await log.versions(watcherId: w.id).map(\.text) == ["two", "three"])
        let long = (0..<5000).map { "line \($0) of a long page" }.joined(separator: "\n")
        let kept = WatchVersion(watcherId: w.id, at: now, text: long).text
        #expect(kept.count <= WatchHistoryLimits.versionCharacters + 2)
        #expect(kept.hasSuffix("\n…"))
    }

    // MARK: Keeping it small

    @Test func oldChecksArePrunedAndEachWatchIsCapped() async throws {
        let box = try Sandbox()
        let engine = env.engine()
        let w = try await engine.add(.make(WatchKind.fileChanges, config: ["path": .string(try box.write("a.txt"))], interval: 15, now: now))
        let old = now.addingTimeInterval(-31 * 86400)
        try await log.save(WatchCheck(watcherId: w.id, result: .changed, at: old))
        for i in 0..<(WatchHistoryLimits.rowsPerWatch + 5) {
            try await log.save(WatchCheck(watcherId: w.id, result: .changed, at: now.addingTimeInterval(Double(i))))
        }
        #expect(try await log.checks(watcherId: w.id).count == WatchHistoryLimits.rowsPerWatch)
        try await log.save(WatchCheck(watcherId: w.id, result: .paused, at: old))
        #expect(try await log.purge(olderThan: now.addingTimeInterval(-30 * 86400)) == 1)
    }

    @Test func ticksExpandRunsNewestLast() {
        let runs = [WatchCheck(watcherId: "w", result: .failed, at: now, count: 2),
                    WatchCheck(watcherId: "w", result: .changed, at: now),
                    WatchCheck(watcherId: "w", result: .unchanged, at: now, count: 40)]
        #expect(WatchCheck.ticks(runs, count: 5) == [.unchanged, .unchanged, .changed, .failed, .failed])
        #expect(WatchCheck.ticks([], count: 24).isEmpty)
    }

    // MARK: The migration

    @Test func anOlderDatabaseGainsTheHistoryTables() async throws {
        let queue = try DatabaseQueue(configuration: { var c = Configuration(); c.foreignKeysEnabled = true; return c }())
        try AppDatabase.migrator.migrate(queue, upTo: "v5-item-run")
        try await queue.write { db in
            try db.execute(sql: """
                INSERT INTO watchers (id, kind, title, config, condition, interval_s, state, mode, level, source, created_at, updated_at)
                VALUES ('w1', 'url_change', 'Old', '{}', '{}', 300, 'active', 'repeat', 'attention', 'user', 0, 0)
                """)
        }
        let upgraded = try AppDatabase(queue)
        let store = WatchHistoryStore(upgraded)
        #expect(try await store.checks(watcherId: "w1").isEmpty, "nothing kept it before")
        try await store.save(WatchCheck(watcherId: "w1", result: .unchanged, at: now))
        try await store.addVersion(watcherId: "w1", text: "hello", at: now)
        #expect(try await WatcherStore(upgraded).watcher(id: "w1")?.title == "Old")
        try await WatcherStore(upgraded).delete(id: "w1")
        #expect(try await store.checks(watcherId: "w1").isEmpty)
        #expect(try await store.versions(watcherId: "w1").isEmpty)
    }

    // MARK: Agents and your data

    @Test func watchListSaysWhenEachWatchLastChanged() async throws {
        let engine = env.engine(probes: [fake { _, _ in ProbeResult(state: .object([:]), triggered: true, summary: "example.com/p changed") }])
        env.base.registry.register(WatchTools.make(engine: engine, parser: { WhenParser(calendar: .current) }))
        var page = Watcher.make("fake", interval: 60, mode: .repeat, now: now)
        page.kind = WatchKind.urlChange
        let w = try await engine.add(.make("fake", title: "Pricing", interval: 60, mode: .repeat, now: now))
        await engine.tick()
        env.clock.advance(7200)
        let outcome = await env.base.executor.execute(name: "watch.list", input: .object([:]), caller: .user, mentions: UserMentions(text: ""))
        guard case .ok(let result) = outcome.status else { Issue.record("watch.list failed: \(outcome.status)"); return }
        let text = result.text
        #expect(text.contains("id \(w.id)"))
        #expect(text.contains("last changed 2 h ago"))
        // A probe's own words aren't repeated for kinds whose summary may carry outside text.
        #expect(!text.contains("example.com/p changed"))
        #expect(WatchListTool.lastChange(WatchCheck(watcherId: "x", result: .changed, at: now, reason: "example.com/p changed"),
                                         of: page, now: now).contains("(example.com/p changed)"))
    }

    @Test func historyIsExportedAndDeletedWithYourData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sf-history-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SidefolkPaths(home: root)
        try paths.prepare()
        let runtime = await SidefolkRuntime(paths: paths, db: try AppDatabase.inMemory(), platform: RecordingPlatform())
        let w = Watcher.make(WatchKind.urlChange, config: ["url": "https://example.com"], interval: 300)
        try await runtime.watcherStore.save(w)
        let store = WatchHistoryStore(runtime.db)
        try await store.save(WatchCheck(watcherId: w.id, result: .changed, at: now, reason: "example.com changed"))
        try await store.addVersion(watcherId: w.id, text: "Hello", at: now)

        let file = root.appendingPathComponent("export.json")
        try await DataPorter(runtime: runtime).export(to: file)
        let exported = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        #expect(exported["watchChecks"]?.arrayValue?.count == 1)
        #expect(exported["watchVersions"]?.arrayValue?.first?.string("text") == "Hello")

        try await DataPorter(runtime: runtime).deleteEverything()
        #expect(try await runtime.db.writer.read { db in try WatchCheck.fetchCount(db) + WatchVersion.fetchCount(db) } == 0)
    }
}

@Suite struct LineDiffTests {
    @Test func inlineShowsChangesInReadingOrderWithContext() {
        let old = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "line 5", with: "line five") + "\nline 11"
        #expect(LineDiff.inline(old: old, new: new) == [
            .skipped(2), .same("line 3"), .same("line 4"), .removed("line 5"), .added("line five"), .same("line 6"), .same("line 7"),
            .skipped(1), .same("line 9"), .same("line 10"), .added("line 11"),
        ])
        #expect(LineDiff.inline(old: "a\nb", new: "a\nb").isEmpty)
    }

    @Test func sideBySidePairsWhatWentWithWhatCame() {
        let rows = LineDiff.sideBySide(old: "a\nb\nc", new: "a\nB\nc\nd")
        #expect(rows == [
            DiffRow(before: .same("a"), after: .same("a")),
            DiffRow(before: .removed("b"), after: .added("B")),
            DiffRow(before: .same("c"), after: .same("c")),
            DiffRow(before: nil, after: .added("d")),
        ])
    }

    @Test func aHugeChangeIsCut() {
        let new = (0..<1000).map { "n\($0)" }.joined(separator: "\n")
        let lines = LineDiff.inline(old: "", new: new, limit: 10)
        #expect(lines.count == 11)
        #expect(lines.last == .skipped(990))
    }
}
