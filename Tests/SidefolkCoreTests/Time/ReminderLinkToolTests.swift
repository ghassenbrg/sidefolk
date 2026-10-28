import Foundation
import Testing
@testable import SidefolkCore

/// The tools that tie a reminder to a note or task (D49), run through the real executor. Reference time: Wednesday
/// 22 October 2025, 10:00 UTC; morning 09.
@Suite struct ReminderLinkToolTests {
    let t: SchedulerEnv
    let notebook: NotebookStore
    let run: ToolExecutor

    init() async throws {
        t = try await SchedulerEnv()
        notebook = NotebookStore(t.env.db)
        let calendar = t.calendar
        let parser: @Sendable () -> WhenParser = { TimeTest.parser(calendar) }
        t.env.registry.register(ReminderTools.make(scheduler: t.scheduler, parser: parser))
        t.env.registry.register(BuiltinTools.make(notebook: notebook, platform: NullPlatform(), events: t.env.events,
                                                  reminders: ReminderTools.Shared(scheduler: t.scheduler, parser: parser)))
        run = t.env.executor
    }

    func item(_ title: String, kind: NotebookItem.Kind = .task, in collection: NotebookCollection? = nil) async throws -> NotebookItem {
        var place = collection
        if place == nil { place = try await notebook.inbox(now: t.clock.now) }
        let item = NotebookItem(collectionId: place!.id, kind: kind, title: title, source: "user", now: t.clock.now)
        try await notebook.add(item)
        return item
    }

    func ok(_ outcome: ToolOutcome) throws -> ToolResult {
        guard case .ok(let r) = outcome.status else { throw Failure(String(describing: outcome.status)) }
        return r
    }

    func failure(_ outcome: ToolOutcome) -> String? {
        if case .ok = outcome.status { return nil }
        return outcome.problem?.message ?? String(describing: outcome.status)
    }

    struct Failure: Error { let message: String; init(_ m: String) { message = m } }

    // MARK: reminders.create

    @Test func aReminderForATaskTakesItsTitle() async throws {
        let task = try await item("Prepare the report")
        let result = try ok(await run.execute(name: "reminders.create", input: ["item": .string(task.id), "when": "tomorrow at 9"],
                                              caller: .agent(runId: "r1")))
        let saved = try #require(await t.scheduler.upcoming().first)
        #expect(saved.itemId == task.id)
        #expect(saved.title == "Prepare the report")
        #expect(saved.fireAt == t.date(2025, 10, 23, 9))
        #expect(result.text.contains("It belongs to the task “Prepare the report” (item \(task.id))"))
        #expect(result.card?.detail == nil, "the card doesn't repeat the title it shows")

        let own = try ok(await run.execute(name: "reminders.create", input: ["title": "Send it to Anna", "item": .string(task.id), "when": "friday"],
                                           caller: .user))
        #expect(own.card?.detail == "Task: Prepare the report")
    }

    @Test func anotherAgentLearnsWhichItemNotItsWords() async throws {
        let task = try await item("Prepare the report")
        let untitled = await run.execute(name: "reminders.create", input: ["item": .string(task.id), "when": "tomorrow at 9"],
                                         caller: .external(client: "codex"))
        #expect(failure(untitled)?.contains("title") == true, "the item's words are not another agent's title")
        let result = try ok(await run.execute(name: "reminders.create", input: ["title": "Check the build", "item": .string(task.id),
                                                                                "when": "tomorrow at 9"],
                                              caller: .external(client: "codex")))
        #expect(result.text.contains("It belongs to the task (item \(task.id))"))
        #expect(!result.text.contains("Prepare the report"))
    }

    @Test func onlyAnItemThatIsThereAndOpen() async throws {
        let unknown = await run.execute(name: "reminders.create", input: ["item": "nope", "when": "tomorrow"], caller: .user)
        #expect(failure(unknown) != nil)

        let trashed = try await item("Old idea", kind: .idea)
        _ = try await notebook.trash(itemId: trashed.id, now: t.clock.now)
        #expect(failure(await run.execute(name: "reminders.create", input: ["item": .string(trashed.id), "when": "tomorrow"], caller: .user)) != nil)

        let done = try await item("Pay rent")
        _ = try await notebook.setStatus(itemId: done.id, .done)
        let refused = failure(await run.execute(name: "reminders.create", input: ["item": .string(done.id), "when": "tomorrow"], caller: .user))
        #expect(refused?.contains("already done") == true)

        let profile = try #require(try await NotebookCollections.profile(notebook, create: true))
        let fact = try await item("I prefer short answers", kind: .note, in: profile)
        #expect(failure(await run.execute(name: "reminders.create", input: ["item": .string(fact.id), "when": "tomorrow"], caller: .user)) != nil)

        #expect(failure(await run.execute(name: "reminders.create", input: ["when": "tomorrow"], caller: .user))?.contains("title") == true)
        #expect(await t.scheduler.upcoming().isEmpty)
    }

    @Test func theListSaysWhichItemEachBelongsTo() async throws {
        let task = try await item("Prepare the report")
        _ = try ok(await run.execute(name: "reminders.create", input: ["item": .string(task.id), "when": "tomorrow at 9"], caller: .user))
        let listed = try ok(await run.execute(name: "reminders.list", input: [:], caller: .agent(runId: "r1")))
        #expect(listed.text.contains("for the task “Prepare the report” (item \(task.id))"))
    }

    // MARK: notes.save and notes.update

    @Test func savingATaskWithATimeRemindsAboutIt() async throws {
        let outcome = await run.execute(name: "notes.save", input: ["text": "Call mom", "kind": "task", "remind": "tomorrow at 9"],
                                        caller: .agent(runId: "r1"))
        let result = try ok(outcome)
        let task = try #require(try await notebook.items(kinds: [.task]).first)
        let reminder = try #require(await t.scheduler.upcoming().first)
        #expect(reminder.itemId == task.id)
        #expect(reminder.title == "Call mom")
        #expect(reminder.fireAt == t.date(2025, 10, 23, 9))
        #expect(result.card?.detail == "Reminder: Tomorrow 09:00")
        #expect(result.text.contains("Reminder set for Thu 23 Oct 2025 09:00"))

        // Undo takes back both.
        _ = try await run.undo.undo(outcome.activity.id)
        #expect(try await notebook.item(id: task.id)?.deletedAt != nil)
        #expect(await t.scheduler.upcoming().isEmpty)
    }

    @Test func aTimeThatCantBeUsedSavesNothing() async throws {
        let outcome = await run.execute(name: "notes.save", input: ["text": "Call mom", "kind": "task", "remind": "yesterday"], caller: .user)
        #expect(failure(outcome) != nil)
        #expect(try await notebook.items().isEmpty)
        #expect(await t.scheduler.upcoming().isEmpty)
    }

    @Test func anItemCanGetAReminderLater() async throws {
        let note = try await item("Passport renewal", kind: .note)
        let outcome = await run.execute(name: "notes.update", input: ["id": .string(note.id), "remind": "in 2 hours"], caller: .agent(runId: "r1"))
        let result = try ok(outcome)
        #expect(result.card?.title == "Reminder set")
        let reminder = try #require(await t.scheduler.upcoming().first)
        #expect(reminder.itemId == note.id)
        #expect(reminder.fireAt == t.clock.now.addingTimeInterval(7200))
        _ = try await run.undo.undo(outcome.activity.id)
        #expect(await t.scheduler.upcoming().isEmpty)
        #expect(try await notebook.item(id: note.id)?.title == "Passport renewal")

        let done = try await item("Pay rent")
        _ = try await notebook.setStatus(itemId: done.id, .done)
        #expect(failure(await run.execute(name: "notes.update", input: ["id": .string(done.id), "remind": "tomorrow"], caller: .user)) != nil)
    }

    @Test func notebookLinesShowTheNextReminder() async throws {
        let task = try await item("Prepare the report")
        _ = try ok(await run.execute(name: "reminders.create", input: ["item": .string(task.id), "when": "tomorrow at 9"], caller: .user))
        let reminder = try #require(await t.scheduler.upcoming().first)
        let listed = try ok(await run.execute(name: "notes.list", input: [:], caller: .agent(runId: "r1")))
        #expect(listed.text.contains("(reminder \(reminder.id))"))
        let found = try ok(await run.execute(name: "notes.search", input: ["query": "report"], caller: .agent(runId: "r1")))
        #expect(found.text.contains("(reminder \(reminder.id))"))
    }
}
