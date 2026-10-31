import Foundation
import Testing
@testable import SidefolkCore

/// The Calendar page (D66): its month and week follow the person's first weekday, things that overlap share a day's
/// width, and a repeating reminder shows every time it will fire in what's on screen.
@Suite struct CalendarGridTests {
    func calendar(firstWeekday: Int) -> Calendar {
        var c = TimeTest.utc
        c.firstWeekday = firstWeekday
        return c
    }

    @Test func aMonthIsWholeWeeksFromTheFirstWeekday() {
        // November 2026 starts on a Sunday and ends on a Monday.
        let monday = CalendarGrid.monthDays(of: TimeTest.date(2026, 11, 14), calendar: calendar(firstWeekday: 2))
        #expect(monday.count == 42)
        #expect(monday.first == TimeTest.date(2026, 10, 26))
        #expect(monday.last == TimeTest.date(2026, 12, 6))
        let sunday = CalendarGrid.monthDays(of: TimeTest.date(2026, 11, 14), calendar: calendar(firstWeekday: 1))
        #expect(sunday.count == 35)
        #expect(sunday.first == TimeTest.date(2026, 11, 1))
        #expect(sunday.last == TimeTest.date(2026, 12, 5))
    }

    @Test func aWeekStartsOnTheFirstWeekday() {
        let days = CalendarGrid.weekDays(of: TimeTest.date(2026, 10, 31, 15), calendar: calendar(firstWeekday: 2))
        #expect(days.first == TimeTest.date(2026, 10, 26))
        #expect(days.count == 7)
        #expect(CalendarGrid.weekDays(of: TimeTest.date(2026, 10, 31), calendar: calendar(firstWeekday: 1)).first == TimeTest.date(2026, 10, 25))
    }

    @Test func overlappingThingsShareTheWidth() {
        let at = { (h: Double) in TimeTest.date(2026, 10, 31).addingTimeInterval(h * 3600) }
        let columns = CalendarGrid.columns([(at(9), at(10)), (at(9.5), at(11)), (at(10), at(10.5)), (at(12), at(13))])
        #expect(columns.map(\.column) == [0, 1, 0, 0])
        #expect(columns.map(\.of) == [2, 2, 2, 1])
    }

    @Test func aRepeatingReminderShowsEveryTimeInRange() async throws {
        let t = try await SchedulerEnv()
        // Wednesday 22 October 2025, 10:00.
        let daily = try await t.scheduler.create(title: "Stretch", at: t.date(2025, 10, 22, 17), recurrence: Recurrence(frequency: .daily))
        let once = try await t.scheduler.create(title: "Call mom", at: t.date(2025, 10, 24, 18))
        try await t.scheduler.create(title: "Next month", at: t.date(2025, 11, 30, 9))
        let found = await t.scheduler.occurrences(from: t.date(2025, 10, 20), to: t.date(2025, 10, 27))
        let stretch = found.filter { $0.reminder.id == daily.id }
        #expect(stretch.map(\.at) == (22...26).map { t.date(2025, 10, $0, 17) })
        #expect(stretch.map(\.isNext) == [true, false, false, false, false])
        #expect(found.filter { $0.reminder.id == once.id }.map(\.at) == [t.date(2025, 10, 24, 18)])
        #expect(!found.contains { $0.reminder.title == "Next month" })
        // A range that starts after its next time still shows the series there, and not the next time itself.
        let later = await t.scheduler.occurrences(from: t.date(2025, 10, 25), to: t.date(2025, 10, 27))
        #expect(later.filter { $0.reminder.id == daily.id }.map(\.isNext) == [false, false])
    }

    @Test func everyMinuteCannotFloodAMonth() async throws {
        let t = try await SchedulerEnv()
        try await t.scheduler.create(title: "Blink", at: t.clock.now.addingTimeInterval(60), recurrence: Recurrence(frequency: .minutely))
        let found = await t.scheduler.occurrences(from: t.date(2025, 10, 1), to: t.date(2025, 11, 1), limit: 50)
        #expect(found.count == 50)
    }

    @Test func finishedRemindersAreFoundByWhenTheyHappened() async throws {
        let t = try await SchedulerEnv()
        let r = try await t.scheduler.create(title: "Tea", at: t.clock.now.addingTimeInterval(600))
        _ = try await t.scheduler.complete(id: r.id)
        let today = try await t.store.finished(from: t.date(2025, 10, 22), to: t.date(2025, 10, 23))
        #expect(today.map(\.id) == [r.id])
        #expect(try await t.store.finished(from: t.date(2025, 10, 23), to: t.date(2025, 10, 24)).isEmpty)
    }
}
