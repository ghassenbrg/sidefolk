import Foundation
import Testing
@testable import SidefolkCore

/// Tasks with a time and reminders that name a task, carried out through the real tools (D49).
@Suite struct LocalIntentReminderLinkTests {
    let runtime: SidefolkRuntime
    let runner: LocalIntentRunner

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-links-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(),
                                        clock: ManualClock(TestEnv.referenceDate))
        runner = LocalIntentRunner(runtime: runtime)
    }

    @discardableResult
    func run(_ text: String) async throws -> LocalOutcome {
        let parsed = try #require(await runner.parse(text), "“\(text)” should be understood locally")
        let outcome = await runner.run(parsed.intent)
        if case .failed(let problem) = outcome { Issue.record("“\(text)” failed: \(problem.message)") }
        return outcome
    }

    func task(_ title: String) async throws -> NotebookItem {
        let inbox = try await runtime.notebook.inbox()
        let item = NotebookItem(collectionId: inbox.id, kind: .task, title: title, source: "user")
        try await runtime.notebook.add(item)
        return item
    }

    @Test func aTaskWithATimeIsSavedWithItsReminder() async throws {
        try await run("add a task to call mom at 5pm")
        let saved = try #require(try await runtime.notebook.items(kinds: [.task]).first)
        #expect(saved.title == "Call mom")
        let reminder = try #require(await runtime.scheduler.upcoming().first)
        #expect(reminder.itemId == saved.id)
        #expect(reminder.title == "Call mom")
    }

    @Test func aReminderThatNamesATaskBelongsToIt() async throws {
        let report = try await task("Prepare the report")
        _ = try await task("Call the bank")
        try await run("remind me about the report task tomorrow at 9")
        let reminder = try #require(await runtime.scheduler.upcoming().first)
        #expect(reminder.itemId == report.id)
        #expect(reminder.title == "Prepare the report")
    }

    @Test func twoTasksThatFitLeaveAPlainReminder() async throws {
        _ = try await task("Prepare the report")
        _ = try await task("Report for Anna")
        try await run("remind me about the report task tomorrow at 9")
        let reminder = try #require(await runtime.scheduler.upcoming().first)
        #expect(reminder.itemId == nil)
        #expect(reminder.title == "The report task")
    }

    @Test func aFactAboutThePersonIsNeverTheItem() async throws {
        let profile = try #require(try await NotebookCollections.profile(runtime.notebook, create: true))
        try await runtime.notebook.add(NotebookItem(collectionId: profile.id, kind: .note, title: "Dentist", source: "user"))
        try await run("remind me about my dentist note tomorrow at 9")
        let reminder = try #require(await runtime.scheduler.upcoming().first)
        #expect(reminder.itemId == nil, "About you is not something to be reminded about")
    }
}
