import Foundation
import Testing
@testable import SidefolkCore

@Suite struct ReminderSchedulerTests {
    // Reference time: Wednesday 22 October 2025, 10:00 UTC.

    @Test func firesAtTheRightTimeAndOnlyOnce() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Call mom", at: t.clock.now.addingTimeInterval(600))

        await t.scheduler.tick()
        #expect(await t.posted().isEmpty)
        #expect(await t.reminder(r.id)?.state == .scheduled)

        t.clock.advance(599)
        await t.scheduler.tick()
        #expect(await t.posted().isEmpty)

        t.clock.advance(1)
        await t.scheduler.tick()
        let posted = await t.posted()
        #expect(posted.count == 1)
        let item = try #require(posted.first)
        #expect(item.title == "Call mom")
        #expect(item.source == "reminder")
        #expect(item.refKind == "reminder")
        #expect(item.refId == r.id)
        #expect(item.level == .attention)
        #expect(item.body?.hasPrefix("You asked") == true)
        #expect(item.actions.map(\.id) == ["done", "snooze10", "tomorrow"])
        #expect(item.actions.map(\.title) == ["Done", "10 min", "Tomorrow"])
        #expect(item.actions.first?.isPrimary == true)

        let fired = try #require(await t.reminder(r.id))
        #expect(fired.state == .fired)
        #expect(fired.firedCount == 1)
        #expect(fired.lastFiredAt == t.clock.now)

        await t.scheduler.tick()
        #expect(await t.posted().count == 1)
    }

    @Test func notesAndLevelCarryOver() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        try await t.scheduler.create(title: "Pay rent", at: t.clock.now.addingTimeInterval(60), notes: "Account ending 42", level: .critical)
        t.clock.advance(60)
        await t.scheduler.tick()
        let item = try #require(await t.posted().first)
        #expect(item.level == .critical)
        #expect(item.body == "Account ending 42")
    }

    @Test func eventsAnnounceChanges() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        let stream = t.env.events.stream()
        let seen = Task { () -> Bool in
            for await event in stream {
                if case .dataChanged(.reminders) = event { return true }
            }
            return false
        }
        try await t.scheduler.create(title: "x", at: t.clock.now.addingTimeInterval(60))
        #expect(await seen.value)
    }

    @Test func rejectsEmptyTitlesAndThePast() async throws {
        let t = try await SchedulerEnv()
        await #expect(throws: UserFacingError.self) { try await t.scheduler.create(title: "   ", at: t.clock.now.addingTimeInterval(60)) }
        await #expect(throws: UserFacingError.self) { try await t.scheduler.create(title: "Late", at: t.clock.now.addingTimeInterval(-3600)) }
        #expect(await t.scheduler.upcoming().isEmpty)
    }

    // MARK: Restart

    @Test func survivesARestartAndFiresMissedOnesOnceEach() async throws {
        let t = try await SchedulerEnv()
        let first = t.scheduler
        await first.start()
        let early = try await first.create(title: "Standup", at: t.date(2025, 10, 22, 11, 0))
        let later = try await first.create(title: "Dentist", at: t.date(2025, 10, 22, 11, 30))
        let future = try await first.create(title: "Tomorrow thing", at: t.date(2025, 10, 23, 9, 0))
        await first.stop()

        // The app was closed from 10:30 until 12:00.
        t.clock.set(t.date(2025, 10, 22, 12, 0))
        let second = t.restarted()
        await second.start()

        let posted = await t.posted()
        #expect(Set(posted.map(\.title)) == ["Standup", "Dentist"])
        #expect(posted.first { $0.title == "Standup" }?.body == "Missed at 11:00")
        #expect(posted.first { $0.title == "Dentist" }?.body == "Missed at 11:30")
        #expect(await t.reminder(early.id)?.state == .fired)
        #expect(await t.reminder(later.id)?.state == .fired)
        #expect(await t.reminder(future.id)?.state == .scheduled)

        await second.tick()
        #expect(await t.posted().count == 2)
    }

    @Test func missedFromYesterdayNamesTheDay() async throws {
        let t = try await SchedulerEnv()
        try await t.scheduler.create(title: "Old", at: t.date(2025, 10, 22, 11, 0))
        t.clock.set(t.date(2025, 10, 23, 8, 0))
        await t.scheduler.start()
        #expect(await t.posted().first?.body == "Missed yesterday 11:00")
    }

    @Test func aReminderFiringOnTimeIsNotCalledMissed() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        try await t.scheduler.create(title: "On time", at: t.clock.now.addingTimeInterval(60))
        t.clock.advance(60 + 30)  // the timer woke us 30 s late
        await t.scheduler.tick()
        #expect(await t.posted().first?.body == nil)

        try await t.scheduler.create(title: "Slept through", at: t.clock.now.addingTimeInterval(60))
        t.clock.advance(60 + 3600)  // the Mac slept for an hour
        await t.scheduler.tick()
        #expect((await t.posted().last?.body ?? "").hasPrefix("Missed at"))
    }

    @Test func overlappingTicksFireOnce() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Once", at: t.clock.now.addingTimeInterval(60))
        t.clock.advance(120)
        async let a: Void = t.scheduler.tick()
        async let b: Void = t.scheduler.tick()
        async let c: Void = t.scheduler.reschedule()
        _ = await (a, b, c)
        #expect(await t.posted().count == 1)
        #expect(await t.reminder(r.id)?.firedCount == 1)
    }

    // MARK: Answers

    @Test func doneEndsTheReminder() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Pay bill", at: t.clock.now.addingTimeInterval(60))
        t.clock.advance(60)
        await t.scheduler.tick()
        let item = try #require(await t.posted().first)
        await t.attention.respond(id: item.id, actionId: "done")
        #expect(await t.reminder(r.id)?.state == .done)
        t.clock.advance(3600)
        await t.scheduler.tick()
        #expect(await t.posted().count == 1)
    }

    @Test func snoozeTenMinutesFiresAgain() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Stretch", at: t.clock.now.addingTimeInterval(60))
        t.clock.advance(60)
        await t.scheduler.tick()
        let first = try #require(await t.posted().first)
        await t.attention.respond(id: first.id, actionId: "snooze10")

        let snoozed = try #require(await t.reminder(r.id))
        #expect(snoozed.state == .snoozed)
        #expect(snoozed.snoozedUntil == t.clock.now.addingTimeInterval(600))

        t.clock.advance(599)
        await t.scheduler.tick()
        #expect(await t.posted().count == 1)

        t.clock.advance(1)
        await t.scheduler.tick()
        #expect(await t.posted().count == 2)
        let again = try #require(await t.reminder(r.id))
        #expect(again.state == .fired)
        #expect(again.firedCount == 2)
        #expect(again.snoozedUntil == nil)
    }

    @Test func snoozeToTomorrowUsesTheMorningHour() async throws {
        let t = try await SchedulerEnv()
        await t.settings.update { $0.morningHour = 8 }
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Later", at: t.clock.now.addingTimeInterval(60))
        t.clock.advance(60)
        await t.scheduler.tick()
        let item = try #require(await t.posted().first)
        await t.attention.respond(id: item.id, actionId: "tomorrow")
        #expect(await t.reminder(r.id)?.snoozedUntil == t.date(2025, 10, 23, 8, 0))

        t.clock.set(t.date(2025, 10, 23, 8, 0))
        await t.scheduler.tick()
        #expect(await t.posted().count == 2)
    }

    @Test func aSnoozeSurvivesARestart() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Stretch", at: t.clock.now.addingTimeInterval(60))
        try await t.scheduler.snooze(id: r.id, until: t.date(2025, 10, 22, 15, 0))
        await t.scheduler.stop()

        t.clock.set(t.date(2025, 10, 22, 14, 0))
        let again = t.restarted()
        await again.start()
        #expect(await t.posted().isEmpty)

        t.clock.set(t.date(2025, 10, 22, 15, 0))
        await again.tick()
        #expect(await t.posted().count == 1)
    }

    @Test func snoozeMustBeInTheFuture() async throws {
        let t = try await SchedulerEnv()
        let r = try await t.scheduler.create(title: "x", at: t.clock.now.addingTimeInterval(60))
        await #expect(throws: UserFacingError.self) { try await t.scheduler.snooze(id: r.id, until: t.clock.now.addingTimeInterval(-1)) }
    }

    // MARK: Cancel and undo

    @Test func cancelledRemindersStaySilentAndCanBeRestored() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Maybe", at: t.clock.now.addingTimeInterval(60))
        let before = try #require(try await t.scheduler.cancel(id: r.id))
        #expect(before.state == .scheduled)
        #expect(await t.reminder(r.id)?.state == .cancelled)
        t.clock.advance(120)
        await t.scheduler.tick()
        #expect(await t.posted().isEmpty)

        try await t.scheduler.restore(before)
        await t.scheduler.tick()
        #expect(await t.posted().count == 1)
    }

    @Test func idsCanBeGivenAsAPrefix() async throws {
        let t = try await SchedulerEnv()
        let r = try await t.scheduler.create(title: "Find me", at: t.clock.now.addingTimeInterval(60))
        #expect(await t.scheduler.reminder(matching: r.id)?.id == r.id)
        #expect(await t.scheduler.reminder(matching: String(r.id.prefix(12)))?.id == r.id)
        #expect(await t.scheduler.reminder(matching: String(r.id.prefix(3))) == nil)
        #expect(await t.scheduler.reminder(matching: "nope-nope-nope") == nil)
    }

    // MARK: Repeating

    @Test func aDailyReminderAdvancesToTheNextDay() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 8))
        await t.scheduler.start()
        let first = t.date(2025, 10, 22, 9)
        let r = try await t.scheduler.create(title: "Standup", at: first, recurrence: Recurrence(frequency: .daily))

        t.clock.set(first)
        await t.scheduler.tick()
        var now = try #require(await t.reminder(r.id))
        #expect(now.state == .scheduled)
        #expect(now.fireAt == t.date(2025, 10, 23, 9))
        #expect(now.firedCount == 1)
        #expect(await t.posted().count == 1)

        t.clock.set(t.date(2025, 10, 23, 9))
        await t.scheduler.tick()
        now = try #require(await t.reminder(r.id))
        #expect(now.fireAt == t.date(2025, 10, 24, 9))
        #expect(now.firedCount == 2)
        #expect(await t.posted().count == 2)
    }

    @Test func aMissedRepeatFiresOnceAndSkipsAhead() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 8))
        let r = try await t.scheduler.create(title: "Standup", at: t.date(2025, 10, 22, 9), recurrence: Recurrence(frequency: .daily))
        // Closed for three days.
        t.clock.set(t.date(2025, 10, 25, 12))
        await t.scheduler.start()
        #expect(await t.posted().count == 1)
        let after = try #require(await t.reminder(r.id))
        #expect(after.fireAt == t.date(2025, 10, 26, 9))
        #expect(after.firedCount == 1)
        #expect(after.state == .scheduled)
    }

    @Test func doneOnARepeatDoesNotEndTheSeries() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 8))
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Standup", at: t.date(2025, 10, 22, 9), recurrence: Recurrence(frequency: .weekdays))
        t.clock.set(t.date(2025, 10, 22, 9))
        await t.scheduler.tick()
        let item = try #require(await t.posted().first)
        await t.attention.respond(id: item.id, actionId: "done")
        let after = try #require(await t.reminder(r.id))
        #expect(after.state == .scheduled)
        #expect(after.fireAt == t.date(2025, 10, 23, 9))
    }

    @Test func snoozingARepeatKeepsTheNextOccurrence() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 8))
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Standup", at: t.date(2025, 10, 22, 9), recurrence: Recurrence(frequency: .daily))
        t.clock.set(t.date(2025, 10, 22, 9))
        await t.scheduler.tick()
        let item = try #require(await t.posted().first)
        await t.attention.respond(id: item.id, actionId: "snooze10")
        #expect(await t.reminder(r.id)?.state == .snoozed)
        #expect(await t.reminder(r.id)?.fireAt == t.date(2025, 10, 23, 9))

        t.clock.set(t.date(2025, 10, 22, 9, 10))
        await t.scheduler.tick()
        #expect(await t.posted().count == 2)
        let after = try #require(await t.reminder(r.id))
        #expect(after.state == .scheduled)
        #expect(after.fireAt == t.date(2025, 10, 23, 9))
    }

    @Test func aSeriesEndsAtItsUntilDate() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 8))
        await t.scheduler.start()
        let rule = Recurrence(frequency: .daily, until: t.date(2025, 10, 23, 12))
        let r = try await t.scheduler.create(title: "Short run", at: t.date(2025, 10, 22, 9), recurrence: rule)
        t.clock.set(t.date(2025, 10, 22, 9))
        await t.scheduler.tick()
        #expect(await t.reminder(r.id)?.state == .scheduled)
        t.clock.set(t.date(2025, 10, 23, 9))
        await t.scheduler.tick()
        #expect(await t.reminder(r.id)?.state == .fired)
        t.clock.set(t.date(2025, 10, 24, 9))
        await t.scheduler.tick()
        #expect(await t.posted().count == 2)
    }

    @Test func theThirtyFirstComesBackAfterAShortMonth() async throws {
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 30, 8))
        await t.scheduler.start()
        let rule = Recurrence(frequency: .monthly)
        let anchor = t.date(2025, 10, 31, 9)
        let r = try await t.scheduler.create(title: "Pay invoices", at: anchor, recurrence: rule, anchor: anchor)
        for (fire, expectedNext) in [(t.date(2025, 10, 31, 9), t.date(2025, 11, 30, 9)),
                                     (t.date(2025, 11, 30, 9), t.date(2025, 12, 31, 9)),
                                     (t.date(2025, 12, 31, 9), t.date(2026, 1, 31, 9))] {
            t.clock.set(fire)
            await t.scheduler.tick()
            #expect(await t.reminder(r.id)?.fireAt == expectedNext)
        }
    }

    @Test func dailyKeepsWallClockAcrossDaylightSaving() async throws {
        let ny = TimeTest.newYork
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 3, 8, 8, in: ny), calendar: ny)
        await t.scheduler.start()
        let first = t.date(2025, 3, 8, 9)
        let r = try await t.scheduler.create(title: "Standup", at: first, recurrence: Recurrence(frequency: .daily))
        t.clock.set(first)
        await t.scheduler.tick()
        #expect(await t.reminder(r.id)?.fireAt == t.date(2025, 3, 9, 9))
        t.clock.set(t.date(2025, 3, 9, 9))
        await t.scheduler.tick()
        #expect(await t.reminder(r.id)?.fireAt == t.date(2025, 3, 10, 9))
    }

    @Test func aRepeatKeepsItsLocalTimeWhenTheTimeZoneChanges() async throws {
        let ny = TimeTest.newYork
        let paris = TimeTest.calendar("Europe/Paris")
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 8, in: ny), calendar: ny)
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Standup", at: t.date(2025, 10, 22, 9), recurrence: Recurrence(frequency: .daily))
        #expect(await t.reminder(r.id)?.timezone == "America/New_York")
        await t.scheduler.stop()

        // The Mac lands in Paris at 20:00 New York time (02:00 Thursday there) and the app relaunches.
        t.clock.set(TimeTest.date(2025, 10, 23, 2, in: paris))
        let inParis = ReminderScheduler(store: t.store, attention: t.attention, events: t.env.events, settings: t.settings, clock: t.clock, calendar: paris)
        await inParis.start()
        let moved = try #require(await t.reminder(r.id))
        #expect(moved.timezone == "Europe/Paris")
        #expect(moved.fireAt == TimeTest.date(2025, 10, 23, 9, in: paris))

        t.clock.set(TimeTest.date(2025, 10, 23, 9, in: paris))
        await inParis.tick()
        #expect(await t.reminder(r.id)?.fireAt == TimeTest.date(2025, 10, 24, 9, in: paris))
        #expect(await t.posted().count == 1)
    }

    @Test func aOneOffKeepsItsMomentWhenTheTimeZoneChanges() async throws {
        let ny = TimeTest.newYork
        let paris = TimeTest.calendar("Europe/Paris")
        let t = try await SchedulerEnv(now: TimeTest.date(2025, 10, 22, 8, in: ny), calendar: ny)
        let r = try await t.scheduler.create(title: "Call", at: t.date(2025, 10, 22, 15))
        let inParis = ReminderScheduler(store: t.store, attention: t.attention, events: t.env.events, settings: t.settings, clock: t.clock, calendar: paris)
        await inParis.start()
        #expect(await t.reminder(r.id)?.fireAt == t.date(2025, 10, 22, 15))
    }

    // MARK: Routines

    @Test func promptRemindersRunThePromptInsteadOfNotifying() async throws {
        let t = try await SchedulerEnv(withPrompts: true)
        await t.scheduler.start()
        let r = try await t.scheduler.create(title: "Daily summary", at: t.clock.now.addingTimeInterval(60),
                                             action: ReminderAction(kind: .prompt, prompt: "Summarise my open tasks"))
        try await t.scheduler.create(title: "Plain", at: t.clock.now.addingTimeInterval(60))
        t.clock.advance(60)
        await t.scheduler.tick()
        let ran = await t.prompts.reminders
        #expect(ran.map(\.id) == [r.id])
        #expect(ran.first?.action?.prompt == "Summarise my open tasks")
        #expect(await t.posted().map(\.title) == ["Plain"])
    }

    @Test func promptRemindersStillNotifyWithoutARunner() async throws {
        let t = try await SchedulerEnv()
        await t.scheduler.start()
        try await t.scheduler.create(title: "Routine", at: t.clock.now.addingTimeInterval(60), action: ReminderAction(kind: .prompt, prompt: "x"))
        t.clock.advance(60)
        await t.scheduler.tick()
        #expect(await t.posted().map(\.title) == ["Routine"])
    }

    // MARK: Fallback notifications

    @Test func fallbackNotificationsCoverTheComingWeek() async throws {
        let t = try await SchedulerEnv()
        try await t.scheduler.create(title: "Soon", at: t.date(2025, 10, 22, 11), notes: "details")
        try await t.scheduler.create(title: "Far away", at: t.date(2026, 1, 1, 9))
        let weekly = try await t.scheduler.create(title: "Gym", at: t.date(2025, 10, 23, 7), recurrence: Recurrence(frequency: .daily))
        let cancelled = try await t.scheduler.create(title: "Never", at: t.date(2025, 10, 22, 12))
        try await t.scheduler.cancel(id: cancelled.id)

        let list = await t.scheduler.fallbackNotifications(horizon: 3 * 86400)
        #expect(list.first?.title == "Soon")
        #expect(list.first?.body == "details")
        #expect(list.first?.date == t.date(2025, 10, 22, 11))
        #expect(!list.contains { $0.title == "Far away" || $0.title == "Never" })
        let gym = list.filter { $0.title == "Gym" }
        #expect(gym.map(\.date) == [t.date(2025, 10, 23, 7), t.date(2025, 10, 24, 7), t.date(2025, 10, 25, 7)])
        #expect(gym.first?.id == weekly.id)
        #expect(Set(list.map(\.id)).count == list.count)
        #expect(list.map(\.date) == list.map(\.date).sorted())
    }

    @Test func fallbackNotificationsRespectTheLimit() async throws {
        let t = try await SchedulerEnv()
        try await t.scheduler.create(title: "Hourly", at: t.date(2025, 10, 22, 11), recurrence: Recurrence(frequency: .hourly))
        let list = await t.scheduler.fallbackNotifications(horizon: 7 * 86400, limit: 5)
        #expect(list.count == 5)
    }

    // MARK: The real timer

    @Test func theTimerFiresWithoutAnyoneCallingTick() async throws {
        let db = try AppDatabase.inMemory()
        let events = EventBus()
        let attention = AttentionCenter(store: AttentionStore(db), events: events)
        let settings = await SettingsStore(db: db, events: events)
        let scheduler = ReminderScheduler(store: ReminderStore(db), attention: attention, events: events, settings: settings)
        await scheduler.start()
        let r = try await scheduler.create(title: "Soon", at: Date().addingTimeInterval(0.4))

        var state = Reminder.State.scheduled
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(100))
            state = try await ReminderStore(db).reminder(id: r.id)?.state ?? .scheduled
            if state == .fired { break }
        }
        await scheduler.stop()
        #expect(state == .fired)
        #expect(try await AttentionStore(db).recent().map(\.title) == ["Soon"])
    }

    @Test func creatingAnEarlierReminderRearmsTheTimer() async throws {
        let db = try AppDatabase.inMemory()
        let events = EventBus()
        let attention = AttentionCenter(store: AttentionStore(db), events: events)
        let settings = await SettingsStore(db: db, events: events)
        let scheduler = ReminderScheduler(store: ReminderStore(db), attention: attention, events: events, settings: settings)
        await scheduler.start()
        try await scheduler.create(title: "Tomorrow", at: Date().addingTimeInterval(86400))
        let soon = try await scheduler.create(title: "Soon", at: Date().addingTimeInterval(0.4))

        var state = Reminder.State.scheduled
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(100))
            state = try await ReminderStore(db).reminder(id: soon.id)?.state ?? .scheduled
            if state == .fired { break }
        }
        await scheduler.stop()
        #expect(state == .fired)
    }
}
