import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

// QA review 2 bugs in attention, the executor, reminders and notebook storage, copied from the QA
// branch's failing tests (QAEngineTests, QANotebookAndStorageTests) and kept as regression tests.

private final class Tally: Sendable {
    private let n = Mutex(0)
    func bump() { n.withLock { $0 += 1 } }
    var count: Int { n.withLock { $0 } }
}

@Suite struct QAFixedAttention {
    func center() throws -> (AttentionCenter, AttentionStore) {
        let db = try AppDatabase.inMemory()
        return (AttentionCenter(store: AttentionStore(db), events: EventBus()), AttentionStore(db))
    }

    // Once the idle signal says the user is active again, new attention items are presented.
    @Test func awayFlagClearsWhenInputResumes() async throws {
        let (center, store) = try center()
        let idle = Box<TimeInterval>(600)
        await center.setSignalProvider { (secondsSinceKey: 600, secondsSinceInput: idle.value) }
        let whileAway = await center.post(AttentionRequest(level: .attention, source: "reminder", title: "While away"))
        #expect(try await store.item(id: whileAway.id)?.state == .pending, "held while the user is idle (by design)")

        idle.set(1)
        let later = await center.post(AttentionRequest(level: .attention, source: "reminder", title: "After return"))
        #expect(try await store.item(id: later.id)?.state == .shown)
        #expect(await center.environment.away == false)
    }

    // Answering one notice twice (double click, or bubble + notification) runs the handler once.
    @Test func answeringTwiceRunsTheHandlerOnce() async throws {
        let (center, _) = try center()
        let calls = Tally()
        await center.onAction(kind: "reminder") { _, _ in calls.bump() }
        let item = await center.post(AttentionRequest(level: .attention, source: "reminder", title: "x", refKind: "reminder", refId: "r1"))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 { group.addTask { await center.respond(id: item.id, actionId: "snooze10") } }
        }
        #expect(calls.count == 1, "handler ran \(calls.count) times")
    }

    // An answer that arrives the moment the question is shown still reaches the asker.
    @Test func instantAnswerToAQuestionIsNotLost() async throws {
        let db = try AppDatabase.inMemory()
        let events = EventBus()
        let center = AttentionCenter(store: AttentionStore(db), events: events)
        let stream = events.stream()
        let answerer = Task {
            for await e in stream {
                if case .attention(.present(let item, _)) = e { await center.respond(id: item.id, actionId: "option-0"); return }
            }
        }
        let answer = await center.ask(AttentionRequest(level: .attention, source: "agent", title: "Now?",
                                                       actions: [AttentionAction(id: "option-0", title: "Yes")]), timeout: 10)
        answerer.cancel()
        #expect(answer == "option-0")
    }

    // Only reminders, watchers and the user's own actions may interrupt with critical.
    @Test func criticalIsKeptOnlyForTrustedSources() async throws {
        let (center, store) = try center()
        let fromAgent = await center.post(AttentionRequest(level: .critical, source: "external:x", title: "Look"))
        let fromReminder = await center.post(AttentionRequest(level: .critical, source: "reminder", title: "Meds"))
        #expect(try await store.item(id: fromAgent.id)?.level == .attention)
        #expect(try await store.item(id: fromReminder.id)?.level == .critical)
    }
}

@Suite struct QAFixedExecutor {
    // A tool that ignores cancellation still times out on time.
    @Test func timeoutDoesNotWaitForABlockingTool() async throws {
        let started = Date()
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(0.2) { usleep(1_500_000); return 1 }
        }
        #expect(Date().timeIntervalSince(started) < 1.0)
    }

    @Test func executorTimeoutDoesNotWaitForABlockingTool() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "test.block", risk: .low, mutates: false, result: { _ in
            usleep(1_500_000)
            return ToolResult(text: "late")
        }))
        let started = Date()
        let outcome = await env.executor.execute(name: "test.block", input: [:], caller: .user, timeout: 0.2)
        #expect(!outcome.isOK)
        #expect(Date().timeIntervalSince(started) < 1.0)
    }

    @Test func fastWorkStillReturnsItsValue() async throws {
        #expect(try await withTimeout(5) { 42 } == 42)
        await #expect(throws: ToolError.self) { try await withTimeout(5) { () throws -> Int in throw ToolError.notFound("x") } }
    }

    // An Undo older than 15 minutes is neither offered nor performed.
    @Test func staleUndoIsNotOffered() async {
        let undo = UndoCenter()
        let ran = Tally()
        await undo.register(UndoAction(label: "old") { ran.bump() }, id: "a", now: Date().addingTimeInterval(-3600))
        #expect(await undo.has("a") == false)
        _ = try? await undo.undo("a")
        #expect(ran.count == 0)
    }

    // JSON nested deeper than the bound is rejected with a normal error instead of overflowing the stack.
    @Test func deeplyNestedJSONIsRejectedNotFatal() async throws {
        let text = String(repeating: "[", count: 200) + "1" + String(repeating: "]", count: 200)
        let parsed = await Task { try? JSONValue.parse(text) }.value
        #expect(parsed == nil)
        let deepObject = String(repeating: "{\"a\":", count: 5_000) + "1" + String(repeating: "}", count: 5_000)
        #expect((try? JSONValue.parse(deepObject)) == nil)
        // Brackets inside strings don't count, and ordinary nesting is fine.
        #expect(try JSONValue.parse("{\"s\": \"" + String(repeating: "[", count: 500) + "\", \"a\": [[[1]]]}")["a"] != nil)
    }
}

@Suite struct QAFixedReminders {
    // "Mark done" on a cancelled reminder says so; it doesn't claim "Marked … done".
    @Test func completeOnACancelledReminderDoesNotClaimSuccess() async throws {
        let t = try await SchedulerEnv()
        t.env.registry.register(ReminderTools.make(scheduler: t.scheduler, parser: { TimeTest.parser(t.calendar) }))
        let r = try await t.scheduler.create(title: "Call mom", at: t.clock.now.addingTimeInterval(3600))
        try await t.scheduler.cancel(id: r.id)
        let outcome = await t.env.executor.execute(name: "reminders.complete", input: ["id": .string(r.id)], caller: .user)
        #expect(try await t.store.reminder(id: r.id)?.state == .cancelled)
        #expect(!outcome.isOK)
        #expect(!outcome.text.contains("Marked"), "tool said: \(outcome.text)")
    }
}

@Suite struct QAFixedNotebook {
    // Parallel "save to a new project" calls end up in one new project.
    @Test func parallelSavesToANewProjectCreateItOnce() async throws {
        let env = try BuiltinEnv()
        defer { env.cleanup() }
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<6 {
                group.addTask { await env.run("notes.save", ["text": .string("idea \(i)"), "collection": "Racy Project"], as: .user) }
            }
        }
        let names = try await env.notebook.collections().map(\.name).filter { $0.lowercased() == "racy project" }
        #expect(names.count == 1, "\(names.count) collections called “Racy Project”")
        #expect(try await env.notebook.items().count == 6)
    }

    // Filing under “Work” when only “Workout” exists creates “Work”.
    @Test func prefixOfAnotherCollectionIsNotTheSameCollection() async throws {
        let env = try BuiltinEnv()
        defer { env.cleanup() }
        await env.run("collections.create", ["name": "Workout"], as: .user)
        let outcome = await env.run("notes.save", ["text": "call dentist", "collection": "Work"], as: .user)
        let note = try #require(try await env.notebook.items().first)
        #expect(try await env.notebook.collection(id: note.collectionId)?.name == "Work", "tool said: \(outcome.text)")
    }

    // “Smart home” is not filed into “Art” just because it contains the letters.
    @Test func containedWordIsNotTheSameCollection() async throws {
        let env = try BuiltinEnv()
        defer { env.cleanup() }
        await env.run("collections.create", ["name": "Art"], as: .user)
        await env.run("notes.save", ["text": "new bulbs", "collection": "Smart home"], as: .user)
        let note = try #require(try await env.notebook.items().first)
        #expect(try await env.notebook.collection(id: note.collectionId)?.name == "Smart home")
    }

    // A whole-word prefix that names exactly one collection still finds it; two candidates find none.
    @Test func wholeWordPrefixFindsOneCollection() throws {
        let reading = NotebookCollection(name: "Reading list", kind: .list)
        let work = NotebookCollection(name: "Work stuff", kind: .project)
        let workTrips = NotebookCollection(name: "Work trips", kind: .project)
        #expect(NotebookStore.match("reading", in: [reading, work])?.id == reading.id)
        #expect(NotebookStore.match("Work", in: [reading, work, workTrips]) == nil)
        #expect(NotebookStore.match("read", in: [reading]) == nil)
    }

    // "\r\n" is a line break: title "Title", body "Body line".
    @Test func crlfIsALineBreak() {
        let (title, body) = NoteText.split("Title\r\nBody line")
        #expect(title == "Title" && body == "Body line", "title “\(title)” body “\(body)”")
    }

    // The reserved name “inbox” never produces a second, look-alike collection.
    @Test func creatingACollectionCalledInboxDoesNotDuplicateTheInbox() async throws {
        let env = try BuiltinEnv()
        defer { env.cleanup() }
        await env.run("collections.create", ["name": "inbox"], as: .user)
        await env.run("notes.save", ["text": "x"], as: .user)
        let names = try await env.notebook.collections().map(\.name).filter { $0.lowercased() == "inbox" }
        #expect(names.count == 1, "collections: \(names)")
    }
}

@Suite struct QAFixedStorageSearch {
    // LIKE wildcards typed by the user are literal.
    @Test(arguments: ["%", "_", "%%", "a_c", "\\"])
    func wildcardsAreLiteral(query: String) async throws {
        let db = try AppDatabase.inMemory()
        let store = NotebookStore(db)
        let inbox = try await store.inbox()
        for text in ["alpha note", "beta note", "abc"] {
            try await store.add(NotebookItem(collectionId: inbox.id, kind: .note, title: text, body: "", source: "user"))
        }
        let found = try await store.search(query)
        #expect(found.isEmpty, "search(“\(query)”) matched \(found.map(\.title))")
    }

    @Test func literalPercentIsFoundAndHugeQueriesAreSafe() async throws {
        let db = try AppDatabase.inMemory()
        let store = NotebookStore(db)
        let inbox = try await store.inbox()
        try await store.add(NotebookItem(collectionId: inbox.id, kind: .note, title: "50% off", body: "", source: "user"))
        #expect(try await store.search("%").map(\.title) == ["50% off"])
        _ = try await store.search(String(repeating: "x y ", count: 25_000))
    }
}
