import Foundation
import Testing
@testable import SidefolkCore

/// Today's "done today" (D88): only what a person would call done.
struct DoneTodayTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 15))! }
    var yesterday: Date { now.addingTimeInterval(-86_400) }

    func call(_ tool: String, _ caller: String = "user", _ decision: ActivityEntry.Decision = .allowed, at: Date? = nil,
              args: JSONValue? = nil) -> ActivityEntry {
        ActivityEntry(at: at ?? now.addingTimeInterval(-600), caller: caller, tool: tool, risk: "low", decision: decision,
                      summary: tool, args: args)
    }

    func count(reminders: [Reminder] = [], items: [NotebookItem] = [], calls: [ActivityEntry] = []) -> Int {
        let changing: Set<String> = ["notes.save", "notes.update", "reminders.create", "reminders.complete", "watch.create", "notes.trash"]
        return DayBrief.doneCount(reminders: reminders, items: items, calls: calls, changes: { changing.contains($0) },
                                  now: now, calendar: calendar)
    }

    @Test func readsAndStatusChecksAreNotDone() {
        let reads = [call("status", "external:claude-code"), call("notes.search", "external:codex"), call("notes.list", "external:codex"),
                     call("reminders.list", "agent"), call("agenda.today", "external:claude-code")]
        #expect(count(calls: reads) == 0)
    }

    @Test func whatChangedSomethingToday() {
        let calls = [call("reminders.create", "external:claude-code"), call("watch.create", "agent"), call("notes.trash"),
                     call("reminders.create", "external:codex", .denied), call("watch.create", "agent", .failed),
                     call("reminders.create", at: yesterday), call("some.removed.tool")]
        #expect(count(calls: calls) == 3, "refused, failed, yesterday's and a tool no longer there don't count")
    }

    @Test func remindersTasksAndNotesCountOnce() {
        var reminder = Reminder(title: "Stretch", fireAt: now.addingTimeInterval(-3600), source: "user", now: yesterday)
        reminder.state = .done
        var old = Reminder(title: "Old", fireAt: yesterday, source: "user", now: yesterday)
        old.state = .done
        let note = NotebookItem(collectionId: "inbox", kind: .note, title: "Tea ideas", source: "external:claude-code", now: now.addingTimeInterval(-900))
        var task = NotebookItem(collectionId: "inbox", kind: .task, title: "Ship it", source: "user", now: yesterday)
        task.status = .done
        task.updatedAt = now.addingTimeInterval(-300)
        var trashed = NotebookItem(collectionId: "inbox", kind: .note, title: "Gone", source: "user", now: now)
        trashed.deletedAt = now
        // The calls that made them are counted from the notebook and the reminders, not again.
        let calls = [call("notes.save", "external:claude-code"), call("reminders.complete"),
                     call("notes.update", args: ["id": "x", "status": "done"]), call("notes.update", args: ["id": "y", "title": "New"])]
        #expect(count(reminders: [reminder, old], items: [note, task, trashed], calls: calls) == 4,
                "the reminder, the note, the task, and the renamed note")
    }
}
