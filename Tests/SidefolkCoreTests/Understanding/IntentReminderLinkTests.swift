import Foundation
import Testing
@testable import SidefolkCore

/// Tasks that come with a time, and reminders that name a task (D49). "Now" is Wednesday 22 October 2025, 10:00 UTC;
/// morning 09, evening 18.
@Suite struct IntentReminderLinkTests {
    let now = TimeTest.wednesday10
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    func parse(_ text: String, known: [String] = ["Work", "Sidefolk"]) -> ParsedIntent? {
        parser.parse(text, now: now, knownCollections: known)
    }

    func at(_ d: Int, _ h: Int, _ min: Int = 0) -> Date { TimeTest.date(2025, 10, d, h, min) }

    // MARK: A task with its time

    @Test func aTaskThatEndsWithATimeGetsItsReminder() {
        let p = parse("add a task to call mom at 5pm")
        #expect(p?.intent == .taskWithReminder(text: "Call mom", collection: nil, collectionKind: nil, remindAt: at(22, 17)))
        #expect(p?.hint == "Task → Inbox · Reminder · Today 17:00 · no AI")

        #expect(parse("todo: send the report tomorrow at 9")?.intent
            == .taskWithReminder(text: "Send the report", collection: nil, collectionKind: nil, remindAt: at(23, 9)))
        #expect(parse("task for Work: book the flights friday at 10am")?.intent
            == .taskWithReminder(text: "Book the flights", collection: "Work", collectionKind: nil, remindAt: at(24, 10)))
        #expect(parse("create a todo to water the plants tonight")?.intent
            == .taskWithReminder(text: "Water the plants", collection: nil, collectionKind: nil, remindAt: at(22, 21)))
        // A clock time already past today is tomorrow's, as for any reminder.
        #expect(parse("todo: call mom at 9am")?.intent
            == .taskWithReminder(text: "Call mom", collection: nil, collectionKind: nil, remindAt: at(23, 9)))
    }

    @Test func aTaskWithoutATimeStaysATask() {
        #expect(parse("add a task to call mom")?.intent == .note(kind: .task, text: "call mom", collection: nil))
        // A number the task needs is not a time.
        #expect(parse("todo: read chapter 5")?.intent == .note(kind: .task, text: "read chapter 5", collection: nil))
        // A time in the middle is part of the words.
        #expect(parse("todo: call mom at 5pm about the trip")?.intent == .note(kind: .task, text: "call mom at 5pm about the trip", collection: nil))
        // A repeat would end with the first time the task is done: the words stay as they are.
        #expect(parse("todo: water the plants every monday")?.intent == .note(kind: .task, text: "water the plants every monday", collection: nil))
        // Notes keep their times as words.
        #expect(parse("note: meeting at 5pm")?.intent == .note(kind: .note, text: "meeting at 5pm", collection: nil))
    }

    @Test func aTaskForACollectionIsNotATaskCalledLikeIt() {
        let got = parse("add a task to Work")?.intent
        #expect(got != .note(kind: .task, text: "Work", collection: nil))
        if case .taskWithReminder? = got { Issue.record("“add a task to Work” is not a task with a time") }
        #expect(parse("add a task to my todo list")?.intent == nil)
    }

    // MARK: A reminder that names a task

    @Test func referencesToANoteOrTask() {
        #expect(IntentParser.itemReference(in: "The report task")! == ("report", .task))
        #expect(IntentParser.itemReference(in: "about my dentist note")! == ("dentist", .note))
        #expect(IntentParser.itemReference(in: "the task “Send the report”")! == ("Send the report", .task))
        #expect(IntentParser.itemReference(in: "my todo called groceries")! == ("groceries", .task))
        #expect(IntentParser.itemReference(in: "Call mom") == nil)
        #expect(IntentParser.itemReference(in: "the task") == nil)
    }

    @Test func onlyTheOneItemThatFits() {
        func task(_ title: String, done: Bool = false, trashed: Bool = false) -> NotebookItem {
            var item = NotebookItem(collectionId: "c", kind: .task, title: title, source: "user", now: now)
            if done { item.status = .done }
            if trashed { item.deletedAt = now }
            return item
        }
        let report = task("Prepare the report")
        let items = [report, task("Report"), task("Reporting tool", done: true), task("Old report", trashed: true)]
        // The exact title wins over titles that merely hold the words.
        #expect(IntentParser.referencedItem("report", among: items)?.title == "Report")
        #expect(IntentParser.referencedItem("the report", among: items)?.id == report.id)
        // Two that hold the words: nothing is certain.
        #expect(IntentParser.referencedItem("report", among: [report, task("Report for Anna")]) == nil)
        // Done tasks and trashed items are not candidates; whole words only.
        #expect(IntentParser.referencedItem("reporting", among: items) == nil)
        #expect(IntentParser.referencedItem("old report", among: items) == nil)
        #expect(IntentParser.referencedItem("port", among: items) == nil)
    }
}
