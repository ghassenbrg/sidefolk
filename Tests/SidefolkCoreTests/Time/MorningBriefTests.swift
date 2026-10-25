import Foundation
import Testing
@testable import SidefolkCore

@Suite struct MorningBriefTests {
    func addTask(_ t: SchedulerEnv, _ title: String) async throws {
        let notebook = NotebookStore(t.env.db)
        let inbox = try await notebook.inbox(now: t.clock.now)
        try await notebook.add(NotebookItem(collectionId: inbox.id, kind: .task, title: title, source: "test", now: t.clock.now))
    }

    func addWatcher(_ t: SchedulerEnv, _ title: String) async throws {
        try await WatcherStore(t.env.db).save(Watcher(kind: "url_change", title: title, config: .object([:]), intervalS: 300, source: "test", now: t.clock.now))
    }

    @Test func sumsUpTodayRemindersTasksAndWatchers() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 9))
        try await t.scheduler.create(title: "Dentist", at: t.date(2025, 10, 22, 15, 30))
        try await t.scheduler.create(title: "Standup", at: t.date(2025, 10, 22, 9, 30))
        try await t.scheduler.create(title: "Not today", at: t.date(2025, 10, 23, 9, 30))
        try await addTask(t, "Renew passport")
        try await addTask(t, "Buy oat milk")
        try await addWatcher(t, "Pricing page")

        let content = try #require(await t.brief.compose(now: t.clock.now))
        #expect(content.title == "Good morning · 2 reminders today")
        #expect(content.body == "09:30 Standup\n15:30 Dentist\n2 open tasks · 1 watcher on duty")
        #expect(content.reminders == 2)
        #expect(content.openTasks == 2)
        #expect(content.watchers == 1)
    }

    @Test func singularsAndNoReminders() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 9))
        try await addTask(t, "Only one")
        let onlyTask = try #require(await t.brief.compose(now: t.clock.now))
        #expect(onlyTask.title == "Good morning")
        #expect(onlyTask.body == "1 open task")

        try await t.scheduler.create(title: "Single", at: t.date(2025, 10, 22, 12))
        let one = try #require(await t.brief.compose(now: t.clock.now))
        #expect(one.title == "Good morning · 1 reminder today")
    }

    @Test func longListsAreCut() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 9))
        for i in 1...8 { try await t.scheduler.create(title: "Item \(i)", at: t.date(2025, 10, 22, 9 + i)) }
        let content = try #require(await t.brief.compose(now: t.clock.now))
        #expect(content.body.split(separator: "\n").count == 6)
        #expect(content.body.hasSuffix("+3 more"))
    }

    @Test func watchersAloneAreNotWorthAnInterruption() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 9))
        try await addWatcher(t, "Pricing page")
        #expect(await t.brief.compose(now: t.clock.now) == nil)
        #expect(await t.brief.runIfDue() == false)
        #expect(await t.posted().isEmpty)
    }

    @Test func doneTasksAndFinishedRemindersAreNotCounted() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 9))
        let notebook = NotebookStore(t.env.db)
        let inbox = try await notebook.inbox(now: t.clock.now)
        let item = NotebookItem(collectionId: inbox.id, kind: .task, title: "Finished", source: "test", now: t.clock.now)
        try await notebook.add(item)
        _ = try await notebook.setStatus(itemId: item.id, .done)
        let r = try await t.scheduler.create(title: "Cancelled", at: t.date(2025, 10, 22, 12))
        try await t.scheduler.cancel(id: r.id)
        #expect(await t.brief.compose(now: t.clock.now) == nil)
    }

    @Test func showsOnceADayAtTheMorningHour() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 8, 30))
        try await t.scheduler.create(title: "Dentist", at: t.date(2025, 10, 22, 15))

        #expect(await t.brief.runIfDue() == false)  // not morning yet
        #expect(await t.posted().isEmpty)

        t.clock.set(t.date(2025, 10, 22, 9, 0))
        #expect(await t.brief.runIfDue() == true)
        let item = try #require(await t.posted().first)
        #expect(item.source == "brief")
        #expect(item.level == .gentle)
        #expect(item.title == "Good morning · 1 reminder today")
        #expect(item.body == "15:00 Dentist")

        t.clock.set(t.date(2025, 10, 22, 9, 30))
        #expect(await t.brief.runIfDue() == false)
        #expect(await t.posted().count == 1)
    }

    @Test func restartingTheAppDoesNotRepeatTheBrief() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 9))
        try await addTask(t, "Anything")
        #expect(await t.brief.runIfDue() == true)

        // A fresh MorningBrief and scheduler over the same data, as after a relaunch.
        let again = MorningBrief(db: t.env.db, attention: t.attention, settings: t.settings, clock: t.clock, calendar: t.calendar)
        t.clock.set(t.date(2025, 10, 22, 9, 40))
        #expect(await again.runIfDue() == false)
        let restarted = t.restarted()
        await restarted.start()
        #expect(await t.posted().count == 1)
    }

    @Test func comesBackTheNextDay() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 9))
        try await addTask(t, "Anything")
        #expect(await t.brief.runIfDue() == true)
        t.clock.set(t.date(2025, 10, 23, 9, 5))
        #expect(await t.brief.runIfDue() == true)
        #expect(await t.posted().count == 2)
    }

    @Test func aLateStartStillGetsTheBriefButNotInTheAfternoon() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 11, 30))
        try await addTask(t, "Anything")
        #expect(await t.brief.runIfDue() == true)

        let later = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 14, 0))
        try await addTask(later, "Anything")
        #expect(await later.brief.runIfDue() == false)
    }

    @Test func followsTheMorningHourSetting() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 7, 30))
        await t.settings.update { $0.morningHour = 7 }
        try await addTask(t, "Anything")
        #expect(await t.brief.runIfDue() == true)
    }

    @Test func canBeSwitchedOff() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 9))
        await t.settings.update { $0.morningBrief = false }
        try await addTask(t, "Anything")
        #expect(await t.brief.runIfDue() == false)
        #expect(await t.brief.nextRun(after: t.clock.now) == nil)
        #expect(await t.posted().isEmpty)
    }

    @Test func nextRunIsAlwaysInTheFuture() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 7))
        #expect(await t.brief.nextRun(after: t.clock.now) == t.date(2025, 10, 22, 9))
        try await addTask(t, "Anything")
        t.clock.set(t.date(2025, 10, 22, 9))
        await t.brief.runIfDue()
        #expect(await t.brief.nextRun(after: t.clock.now) == t.date(2025, 10, 23, 9))
        // Due but not yet shown (grace period): still never "now", so a timer armed on it cannot spin.
        let late = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 10))
        let next = try #require(await late.brief.nextRun(after: late.clock.now))
        #expect(next > late.clock.now)
    }

    @Test func theSchedulerShowsTheBriefOnItsOwnTimer() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 7))
        try await addTask(t, "Anything")
        await t.scheduler.start()
        #expect(await t.posted().isEmpty)
        t.clock.set(t.date(2025, 10, 22, 9, 0))
        await t.scheduler.tick()
        let item = try #require(await t.posted().first)
        #expect(item.source == "brief")
        t.clock.set(t.date(2025, 10, 22, 9, 5))
        await t.scheduler.tick()
        #expect(await t.posted().count == 1)
    }
}
