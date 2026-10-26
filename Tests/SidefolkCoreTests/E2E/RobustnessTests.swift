import Foundation
import Testing
@testable import SidefolkCore

/// What happens when things go wrong around a run: the AI service drops mid-request, Sidefolk quits while a card
/// waits, the database file is damaged, and Sidefolk runs for weeks.
@Suite struct RobustnessTests {
    @Test func theAIServiceDropsAfterAStepWasDone() async throws {
        let world = try await World([
            .turn(.calling([ToolCall(id: "c1", name: "notes_save", input: ["text": "Buy oat milk"])])),
            .perform { _ in throw URLError(.networkConnectionLost) },
        ])
        let events = await world.ask("save buy oat milk and tell me what else I need this week")
        let failure = try #require(events.compactMap(\.failure).first)
        #expect(failure.message.contains("Some of it was already done; Activity shows what."), "\(failure.message)")
        #expect(!failure.changedNothing)
        #expect(try await world.notebook.items().map(\.title) == ["Buy oat milk"])
        #expect(try await AgentRunStore(world.env.db).recent().first?.outcome == "failed")
    }

    /// Quitting (or Stop) while a card waits: the card is withdrawn, the step never runs, the run is recorded.
    @Test func quittingWhileACardWaitsRunsNothingLater() async throws {
        let world = try await World([
            .turn(.calling([ToolCall(id: "c1", name: "clipboard_read", input: [:])])),
            .turn(.reply("never")),
        ])
        world.platform.clipboard = "private"
        let shown = world.env.events.stream()
        let run = Task { await world.ask("what's on my clipboard?") }
        var card: ApprovalRequest?
        for await e in shown { if case .approvalRequested(let r) = e { card = r; break } }
        #expect(card?.tool == "clipboard.read")

        await world.runtime.cancelAll()
        let events = await run.value
        #expect(events.compactMap(\.failure).first?.message == "Stopped. Nothing was changed.")
        #expect(await world.env.broker.pending().isEmpty, "the card is gone")
        // An Allow arriving now (a click on a stale card) does nothing.
        await world.env.broker.resolve(id: try #require(card).id, decision: .allowOnce)
        let logged = try await world.activity()
        #expect(logged.map(\.tool) == ["clipboard.read"] && logged.first?.decision == .denied, "Activity still shows the step that never ran")
        #expect(try await AgentRunStore(world.env.db).recent().first?.outcome == "cancelled")
    }

    /// A damaged database is never "repaired" by starting over: opening fails and the file stays as it was, so the
    /// launch alert's "Nothing was deleted or changed" is true.
    @Test func aDamagedDatabaseIsLeftAlone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sf-corrupt-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("sidefolk.sqlite")
        let garbage = Data((0..<8192).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        try garbage.write(to: file)
        #expect(throws: (any Error).self) { try AppDatabase.open(at: file) }
        #expect(try Data(contentsOf: file) == garbage)
    }

    /// Weeks of running: history, activity, runs and finished jobs past their time go; a running job stays.
    @Test func housekeepingKeepsTablesFromGrowingForever() async throws {
        let clock = ManualClock(TestEnv.referenceDate)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sf-keep-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: clock)
        let old = clock.now.addingTimeInterval(-200 * 86_400)
        var finished = Job(kind: .command, title: "npm test", command: "npm test", cwd: nil, pid: nil, source: "external:x", now: old)
        finished.state = .failed
        finished.outputTail = "token=abc"
        try await runtime.jobs.save(finished)
        try await runtime.jobs.save(Job(kind: .command, title: "server", command: "npm start", cwd: nil, pid: nil, source: "external:x", now: old))
        try await runtime.runs.save(AgentRun(threadId: "t", provider: "p", model: "m", now: old))
        try await runtime.runs.save(AgentRun(threadId: "t", provider: "p", model: "m", now: clock.now))

        await runtime.housekeeping()
        #expect(try await runtime.jobs.recent().map(\.title) == ["server"])
        #expect(try await runtime.runs.recent().count == 1)
    }

    /// Next checks are moments: with the clock set back an hour, a report every 10 s went silent for that hour.
    @Test func aClockSetBackDoesntSilenceReports() async throws {
        let world = try await World([])
        let made = await world.executor.execute(name: "watch.report", input: ["source": "metric", "metric": "cpu", "every_seconds": 10],
                                                caller: .user)
        #expect(made.isOK)
        let id = try #require(await world.engine.list().first?.id)
        world.clock.advance(-3600)
        await world.engine.rearm()
        let next = try #require(await world.engine.watcher(id: id)?.nextCheckAt)
        #expect(next <= world.clock.now.addingTimeInterval(10))
        await world.engine.stop()
    }

    /// Drafts are capped, and a write cut short by a quit doesn't leave its staging folder forever.
    @Test func extensionDraftsDontPileUp() throws {
        let dir = try ExtFixtures.tempDir("drafts")
        defer { ExtensionFiles.removeTree(dir.path) }
        let drafts = ExtensionDrafts(directory: dir) { url in ExtensionFiles.removeTree(url.path) }
        let stale = dir.appendingPathComponent(".staging-old")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: stale.path)
        let manifest: JSONValue = ["name": "D", "version": "0.1.0", "sidefolk": ">=0.1", "run": ["command": "python3", "args": ["main.py"]]]
        for i in 0..<ExtensionDrafts.maxDrafts { try drafts.write(name: "d\(i)", manifest: manifest, files: ["main.py": "print()"]) }
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(throws: UserFacingError.self) { try drafts.write(name: "one-more", manifest: manifest, files: ["main.py": "print()"]) }
        try drafts.write(name: "d0", manifest: manifest, files: ["main.py": "print(1)"])
        #expect(drafts.list().count == ExtensionDrafts.maxDrafts)
    }

    /// Notes that can't start (-600, -10810) is said plainly and changes nothing.
    @Test(arguments: [-600, -609, -10810]) func notesThatCantStartIsSaidPlainly(code: Int) {
        let error = AppleEventsError.from(code: code, message: "", app: .notes)
        #expect(error == .unavailable(.notes))
        #expect(error.userFacing.message == "I couldn't start Notes. Nothing was changed.")
        #expect(error.userFacing.changedNothing)
    }

    @Test func aDailyChoreKeepsComingBack() async throws {
        let chore = DailyChore(every: 0.02)
        let count = Shared(0)
        await chore.start { count.change { $0 += 1 } }
        // Waits for the second run rather than a fixed time: a busy CI machine wakes sleepers late.
        let deadline = Date().addingTimeInterval(5)
        while count.value < 2, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        await chore.stop()
        let seen = count.value
        #expect(seen >= 2)
        try await Task.sleep(for: .milliseconds(60))
        #expect(count.value == seen, "stopped means stopped")
    }
}
