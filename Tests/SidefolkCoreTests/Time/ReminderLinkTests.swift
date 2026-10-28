import Foundation
import GRDB
import Testing
@testable import SidefolkCore

/// Reminders that belong to a note or task follow it (D49). Reference time: Wednesday 22 October 2025, 10:00 UTC.
@Suite struct ReminderLinkTests {
    let t: SchedulerEnv
    let notebook: NotebookStore

    init() async throws {
        t = try await SchedulerEnv()
        notebook = NotebookStore(t.env.db)
    }

    func item(_ title: String, kind: NotebookItem.Kind = .task) async throws -> NotebookItem {
        let inbox = try await notebook.inbox(now: t.clock.now)
        let item = NotebookItem(collectionId: inbox.id, kind: kind, title: title, source: "user", now: t.clock.now)
        try await notebook.add(item)
        return item
    }

    func remind(_ item: NotebookItem, in seconds: TimeInterval, title: String? = nil, every rule: Recurrence? = nil) async throws -> Reminder {
        try await t.scheduler.create(title: title ?? item.title, at: t.clock.now.addingTimeInterval(seconds), recurrence: rule, itemId: item.id)
    }

    func mark(_ item: NotebookItem, _ status: NotebookItem.Status) async throws {
        _ = try await notebook.setStatus(itemId: item.id, status, now: t.clock.now)
        await t.scheduler.settleLinks()
    }

    func reminder(_ r: Reminder) async throws -> Reminder { try #require(await t.reminder(r.id)) }

    // MARK: Done and open again

    @Test func aDoneTaskEndsItsRemindersAndOpeningItBringsThemBack() async throws {
        let task = try await item("Send the report")
        let once = try await remind(task, in: 3600)
        let daily = try await remind(task, in: 7200, every: Recurrence(frequency: .daily))

        try await mark(task, .done)
        #expect(try await reminder(once).state == .done)
        #expect(try await reminder(once).endedWithItem == .done)
        #expect(try await reminder(daily).state == .cancelled, "a series stops with its task")
        #expect(try await reminder(daily).endedWithItem == .done)
        #expect(await t.scheduler.upcoming().isEmpty)

        try await mark(task, .open)
        #expect(try await reminder(once).state == .scheduled)
        #expect(try await reminder(once).fireAt == once.fireAt)
        #expect(try await reminder(once).endedWithItem == nil)
        #expect(try await reminder(daily).state == .scheduled)
        #expect(await t.scheduler.upcoming().count == 2)
    }

    @Test func onlyTimesStillAheadComeBack() async throws {
        let task = try await item("Send the report")
        let once = try await remind(task, in: 3600)
        let daily = try await remind(task, in: 7200, every: Recurrence(frequency: .daily))
        try await mark(task, .done)
        t.clock.advance(8000)
        try await mark(task, .open)
        let gone = try await reminder(once)
        #expect(gone.state == .done, "its time passed while the task was done")
        #expect(gone.endedWithItem == nil, "and it no longer waits for the task")
        let series = try await reminder(daily)
        #expect(series.state == .scheduled)
        #expect(series.fireAt == daily.fireAt.addingTimeInterval(86_400), "the series picks up at its next time")
    }

    @Test func aSnoozedReminderComesBackSnoozed() async throws {
        let task = try await item("Call mom")
        let r = try await remind(task, in: 600)
        let until = t.clock.now.addingTimeInterval(1800)
        try await t.scheduler.snooze(id: r.id, until: until)
        try await mark(task, .done)
        #expect(try await reminder(r).state == .done)
        try await mark(task, .open)
        #expect(try await reminder(r).state == .snoozed)
        #expect(try await reminder(r).nextDue == until)
    }

    // MARK: The Trash

    @Test func theTrashEndsThemAndRestoringBringsThemBack() async throws {
        let note = try await item("Passport renewal", kind: .note)
        let r = try await remind(note, in: 3600)
        _ = try await notebook.trash(itemId: note.id, now: t.clock.now)
        await t.scheduler.settleLinks()
        #expect(try await reminder(r).state == .cancelled)
        #expect(try await reminder(r).endedWithItem == .trashed)

        try await notebook.restore(itemId: note.id, now: t.clock.now)
        await t.scheduler.settleLinks()
        #expect(try await reminder(r).state == .scheduled)
    }

    @Test func aReminderCancelledByThePersonStaysCancelled() async throws {
        let note = try await item("Passport renewal", kind: .note)
        let r = try await remind(note, in: 3600)
        _ = try await notebook.trash(itemId: note.id, now: t.clock.now)
        await t.scheduler.settleLinks()
        try await t.scheduler.cancel(id: r.id)
        try await notebook.restore(itemId: note.id, now: t.clock.now)
        await t.scheduler.settleLinks()
        #expect(try await reminder(r).state == .cancelled)
        #expect(try await reminder(r).endedWithItem == nil)
    }

    @Test func deletingAReminderLeavesItsItem() async throws {
        let task = try await item("Call mom")
        let r = try await remind(task, in: 600)
        try await t.store.delete(id: r.id)
        #expect(try await notebook.item(id: task.id)?.deletedAt == nil)
    }

    @Test func anItemDeletedForGoodCancelsItsReminders() async throws {
        let task = try await item("Call mom")
        let r = try await remind(task, in: 600)
        try await notebook.purge(itemId: task.id)
        let left = try await reminder(r)
        #expect(left.state == .cancelled)
        #expect(left.itemId == nil)
    }

    // MARK: Renamed and moved

    @Test func aRenameCarriesTheItemsOwnTitleAlong() async throws {
        var task = try await item("Call mom")
        let plain = try await remind(task, in: 600)
        let ownWords = try await remind(task, in: 900, title: "Ask about the trip")
        task.title = "Call mum"
        try await notebook.update(task)
        #expect(try await reminder(plain).title == "Call mum")
        #expect(try await reminder(ownWords).title == "Ask about the trip")

        let work = try await notebook.createCollection(name: "Work", kind: .project, now: t.clock.now)
        task.collectionId = work.id
        try await notebook.update(task)
        await t.scheduler.settleLinks()
        #expect(try await reminder(plain).state == .scheduled)
        #expect(try await reminder(plain).itemId == task.id)
    }

    // MARK: Firing

    @Test func nothingFiresForATaskDoneAMomentAgo() async throws {
        await t.scheduler.start()
        let task = try await item("Call mom")
        let r = try await remind(task, in: 60)
        // Done straight in the store, before anyone settled the links.
        _ = try await notebook.setStatus(itemId: task.id, .done, now: t.clock.now)
        t.clock.advance(60)
        await t.scheduler.tick()
        #expect(await t.posted().isEmpty)
        #expect(try await reminder(r).state == .done)
        #expect(try await reminder(r).endedWithItem == .done)
    }

    @Test func theBubbleNamesItsTaskAndOffersMarkDoneAndOpen() async throws {
        await t.scheduler.start()
        let task = try await item("Prepare the report")
        _ = try await remind(task, in: 60, title: "Send it to Anna")
        t.clock.advance(60)
        await t.scheduler.tick()
        let bubble = try #require(await t.posted().first)
        #expect(bubble.actions.map(\.id) == ["taskDone", "snooze10", "open"])
        #expect(bubble.actions.map(\.title) == ["Mark done", "10 min", "Open"])
        #expect(bubble.actions.first?.isPrimary == true)
        #expect(bubble.body?.contains("Task: Prepare the report") == true)
    }

    @Test func aNoteKeepsDoneAndANameItAlreadyHasIsNotRepeated() async throws {
        await t.scheduler.start()
        let note = try await item("Passport renewal", kind: .note)
        _ = try await remind(note, in: 60)
        t.clock.advance(60)
        await t.scheduler.tick()
        let bubble = try #require(await t.posted().first)
        #expect(bubble.actions.map(\.id) == ["done", "snooze10", "open"])
        #expect(bubble.body?.contains("Note:") != true)
    }

    @Test func aFrequentSeriesKeepsStop() {
        let task = NotebookItem(collectionId: "c", kind: .task, title: "Stretch", source: "user")
        var r = Reminder(title: "Stretch", fireAt: Date(), recurrence: Recurrence(frequency: .minutely, interval: 30), source: "user")
        r.itemId = task.id
        #expect(ReminderScheduler.actions(for: r, item: task).map(\.id) == ["taskDone", "stop", "open"])
        #expect(ReminderScheduler.actions(for: r).map(\.id) == ["done", "snooze10", "stop"], "without an item nothing changes")
    }

    @Test func markDoneOnTheBubbleFinishesTheTaskAndItsSeries() async throws {
        await t.scheduler.start()
        let task = try await item("Water the plants")
        let series = try await remind(task, in: 60, every: Recurrence(frequency: .daily))
        t.clock.advance(60)
        await t.scheduler.tick()
        let bubble = try #require(await t.posted().first)
        await t.attention.respond(id: bubble.id, actionId: "taskDone")
        #expect(try await notebook.item(id: task.id)?.status == .done)
        let after = try await reminder(series)
        #expect(after.state == .cancelled)
        #expect(after.endedWithItem == .done)
    }

    @Test func aBubbleForATaskDoneElsewhereGoesAway() async throws {
        await t.scheduler.start()
        let task = try await item("Call mom")
        _ = try await remind(task, in: 60)
        t.clock.advance(60)
        await t.scheduler.tick()
        #expect(await t.attention.open().contains { $0.refKind == "reminder" })
        try await mark(task, .done)
        #expect(await !t.attention.open().contains { $0.refKind == "reminder" })
    }

    @Test func theSchedulerSettlesWhenTheNotebookChanges() async throws {
        await t.scheduler.start()
        let task = try await item("Call mom")
        let r = try await remind(task, in: 600)
        _ = try await notebook.setStatus(itemId: task.id, .done, now: t.clock.now)
        t.env.events.changed(.notebook)
        for _ in 0..<100 where try await reminder(r).state == .scheduled {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try await reminder(r).state == .done)
        await t.scheduler.stop()
    }

    // MARK: Lines for the model

    @Test func theAgendaAndTheLiveLinesNameTheItem() async throws {
        let task = try await item("Prepare the report")
        let r = try await remind(task, in: 3600, title: "Send it to Anna")
        let live = LiveStateSummary.make(reminders: [r], watchers: [], jobs: [], sessions: [], now: t.clock.now, timeZone: TimeZone(identifier: "UTC")!,
                                         items: [task.id: task])
        #expect(live.contains("“Send it to Anna” at 11:00 (for the task “Prepare the report”)"))

        var foreign = task
        foreign.source = "external:other-agent"
        let hidden = LiveStateSummary.make(reminders: [r], watchers: [], jobs: [], sessions: [], now: t.clock.now, timeZone: TimeZone(identifier: "UTC")!,
                                           items: [task.id: foreign])
        #expect(hidden.contains("(for a task)"), "someone else's words are not quoted (T3)")
        #expect(!hidden.contains("Prepare the report"))
    }
}
