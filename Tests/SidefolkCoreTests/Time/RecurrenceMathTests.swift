import Foundation
import Testing
@testable import SidefolkCore

@Suite struct RecurrenceMathTests {
    let utc = TimeTest.utc
    let ny = TimeTest.newYork

    func next(_ after: Date, _ r: Recurrence, anchor: Date, cal: Calendar? = nil) -> String {
        TimeTest.show(nextOccurrence(after: after, recurrence: r, anchor: anchor, calendar: cal ?? utc), in: cal ?? utc)
    }

    @Test func dailyKeepsTimeAndSkipsToTomorrow() {
        let anchor = TimeTest.date(2025, 10, 20, 9)
        let r = Recurrence(frequency: .daily)
        #expect(next(TimeTest.date(2025, 10, 22, 8), r, anchor: anchor) == "Wed 2025-10-22 09:00")
        #expect(next(TimeTest.date(2025, 10, 22, 9), r, anchor: anchor) == "Thu 2025-10-23 09:00")
        #expect(next(TimeTest.date(2025, 10, 22, 23, 59), r, anchor: anchor) == "Thu 2025-10-23 09:00")
    }

    @Test func nothingBeforeTheAnchor() {
        let anchor = TimeTest.date(2025, 10, 22, 9)
        #expect(next(TimeTest.date(2025, 1, 1), Recurrence(frequency: .daily), anchor: anchor) == "Wed 2025-10-22 09:00")
        #expect(next(TimeTest.date(2025, 1, 1), Recurrence(frequency: .monthly), anchor: anchor) == "Wed 2025-10-22 09:00")
    }

    @Test func dailyWithInterval() {
        let anchor = TimeTest.date(2025, 10, 20, 9)
        let r = Recurrence(frequency: .daily, interval: 3)
        #expect(next(TimeTest.date(2025, 10, 20, 9), r, anchor: anchor) == "Thu 2025-10-23 09:00")
        #expect(next(TimeTest.date(2025, 10, 23, 9), r, anchor: anchor) == "Sun 2025-10-26 09:00")
        // Long gaps (the app was off for months) land back on the series.
        let far = nextOccurrence(after: TimeTest.date(2026, 3, 1, 12), recurrence: r, anchor: anchor, calendar: utc)!
        #expect(utc.dateComponents([.day], from: anchor, to: far).day! % 3 == 0)
        #expect(far > TimeTest.date(2026, 3, 1, 12))
    }

    @Test func hourlyIsElapsedTime() {
        let anchor = TimeTest.date(2025, 10, 22, 9, 15)
        let r = Recurrence(frequency: .hourly, interval: 2)
        #expect(next(TimeTest.date(2025, 10, 22, 9, 15), r, anchor: anchor) == "Wed 2025-10-22 11:15")
        #expect(next(TimeTest.date(2025, 10, 22, 12), r, anchor: anchor) == "Wed 2025-10-22 13:15")
        #expect(next(TimeTest.date(2025, 10, 22, 8), r, anchor: anchor) == "Wed 2025-10-22 09:15")
    }

    @Test func weekdaysSkipTheWeekend() {
        let anchor = TimeTest.date(2025, 10, 20, 8, 30)  // Monday
        let r = Recurrence(frequency: .weekdays)
        #expect(next(TimeTest.date(2025, 10, 24, 9), r, anchor: anchor) == "Mon 2025-10-27 08:30")  // Friday after the time
        #expect(next(TimeTest.date(2025, 10, 25, 12), r, anchor: anchor) == "Mon 2025-10-27 08:30")  // Saturday
        #expect(next(TimeTest.date(2025, 10, 22, 7), r, anchor: anchor) == "Wed 2025-10-22 08:30")
    }

    @Test func weeklyOnSeveralDays() {
        let anchor = TimeTest.date(2025, 10, 21, 8)  // Tuesday
        let r = Recurrence(frequency: .weekly, weekdays: [2, 4])
        #expect(next(TimeTest.date(2025, 10, 21, 8), r, anchor: anchor) == "Thu 2025-10-23 08:00")
        #expect(next(TimeTest.date(2025, 10, 23, 8), r, anchor: anchor) == "Tue 2025-10-28 08:00")
    }

    @Test func weeklyWithoutDaysUsesTheAnchorsWeekday() {
        let anchor = TimeTest.date(2025, 10, 22, 8)  // Wednesday
        let r = Recurrence(frequency: .weekly)
        #expect(next(TimeTest.date(2025, 10, 22, 8), r, anchor: anchor) == "Wed 2025-10-29 08:00")
    }

    @Test func everyOtherWeekKeepsItsPhase() {
        let anchor = TimeTest.date(2025, 10, 20, 8)  // Monday
        let r = Recurrence(frequency: .weekly, interval: 2, weekdays: [1, 4])
        #expect(next(TimeTest.date(2025, 10, 20, 8), r, anchor: anchor) == "Thu 2025-10-23 08:00")
        #expect(next(TimeTest.date(2025, 10, 23, 8), r, anchor: anchor) == "Mon 2025-11-03 08:00")
        #expect(next(TimeTest.date(2025, 11, 3, 8), r, anchor: anchor) == "Thu 2025-11-06 08:00")
    }

    @Test func monthlyClampsTheThirtyFirst() {
        let anchor = TimeTest.date(2025, 1, 31, 9)
        let r = Recurrence(frequency: .monthly)
        #expect(next(TimeTest.date(2025, 1, 31, 9), r, anchor: anchor) == "Fri 2025-02-28 09:00")
        #expect(next(TimeTest.date(2025, 2, 28, 9), r, anchor: anchor) == "Mon 2025-03-31 09:00")
        #expect(next(TimeTest.date(2025, 3, 31, 9), r, anchor: anchor) == "Wed 2025-04-30 09:00")
        // Leap year.
        #expect(next(TimeTest.date(2028, 1, 31, 9), r, anchor: anchor) == "Tue 2028-02-29 09:00")
    }

    @Test func monthlyEveryThreeMonthsAndAcrossYears() {
        let anchor = TimeTest.date(2025, 11, 15, 10)
        let r = Recurrence(frequency: .monthly, interval: 3)
        #expect(next(TimeTest.date(2025, 11, 15, 10), r, anchor: anchor) == "Sun 2026-02-15 10:00")
        #expect(next(TimeTest.date(2026, 2, 15, 10), r, anchor: anchor) == "Fri 2026-05-15 10:00")
    }

    @Test func yearlyFebruary29FallsBackToTheTwentyEighth() {
        let anchor = TimeTest.date(2024, 2, 29, 9)
        let r = Recurrence(frequency: .yearly)
        #expect(next(TimeTest.date(2024, 2, 29, 9), r, anchor: anchor) == "Fri 2025-02-28 09:00")
        #expect(next(TimeTest.date(2027, 3, 1), r, anchor: anchor) == "Tue 2028-02-29 09:00")
    }

    @Test func untilEndsTheSeries() {
        let anchor = TimeTest.date(2025, 10, 20, 9)
        let r = Recurrence(frequency: .daily, until: TimeTest.date(2025, 10, 23, 12))
        #expect(next(TimeTest.date(2025, 10, 22, 9), r, anchor: anchor) == "Thu 2025-10-23 09:00")
        #expect(nextOccurrence(after: TimeTest.date(2025, 10, 23, 9), recurrence: r, anchor: anchor, calendar: utc) == nil)
    }

    // MARK: Daylight saving (America/New_York: clocks jump 2025-03-09 02:00 -> 03:00 and repeat 01:00-02:00 on 2025-11-02)

    @Test func dailyKeepsWallClockAcrossSpringForward() {
        let anchor = TimeTest.date(2025, 3, 7, 9, in: ny)
        let r = Recurrence(frequency: .daily)
        let before = nextOccurrence(after: TimeTest.date(2025, 3, 8, 9, in: ny), recurrence: r, anchor: anchor, calendar: ny)!
        let after = nextOccurrence(after: before, recurrence: r, anchor: anchor, calendar: ny)!
        #expect(TimeTest.show(before, in: ny) == "Sun 2025-03-09 09:00")
        #expect(TimeTest.show(after, in: ny) == "Mon 2025-03-10 09:00")
        // 23 real hours between the two 09:00s of the short day.
        #expect(before.timeIntervalSince(TimeTest.date(2025, 3, 8, 9, in: ny)) == 23 * 3600)
    }

    @Test func aTimeSkippedBySpringForwardMovesIntoTheNewHour() {
        let anchor = TimeTest.date(2025, 3, 8, 2, 30, in: ny)
        let r = Recurrence(frequency: .daily)
        let skipped = nextOccurrence(after: TimeTest.date(2025, 3, 8, 12, in: ny), recurrence: r, anchor: anchor, calendar: ny)!
        let shown = TimeTest.show(skipped, in: ny)
        #expect(shown == "Sun 2025-03-09 03:30")
        let following = nextOccurrence(after: skipped, recurrence: r, anchor: anchor, calendar: ny)!
        #expect(TimeTest.show(following, in: ny) == "Mon 2025-03-10 02:30")
    }

    @Test func aRepeatedHourFiresOnce() {
        let anchor = TimeTest.date(2025, 10, 31, 1, 30, in: ny)
        let r = Recurrence(frequency: .daily)
        let day = nextOccurrence(after: TimeTest.date(2025, 11, 1, 12, in: ny), recurrence: r, anchor: anchor, calendar: ny)!
        #expect(TimeTest.show(day, in: ny) == "Sun 2025-11-02 01:30")
        // The first 01:30 (EDT), not the second (EST).
        #expect(day.timeIntervalSince(TimeTest.date(2025, 11, 1, 12, in: ny)) == 13.5 * 3600)
        let following = nextOccurrence(after: day, recurrence: r, anchor: anchor, calendar: ny)!
        #expect(TimeTest.show(following, in: ny) == "Mon 2025-11-03 01:30")
    }

    @Test func weekdaysAndWeeklyKeepWallClockAcrossDST() {
        let anchor = TimeTest.date(2025, 3, 3, 8, in: ny)  // Monday before the change
        let weekly = nextOccurrence(after: TimeTest.date(2025, 3, 3, 9, in: ny), recurrence: Recurrence(frequency: .weekly), anchor: anchor, calendar: ny)!
        #expect(TimeTest.show(weekly, in: ny) == "Mon 2025-03-10 08:00")
        let weekdays = nextOccurrence(after: TimeTest.date(2025, 3, 7, 9, in: ny), recurrence: Recurrence(frequency: .weekdays), anchor: anchor, calendar: ny)!
        #expect(TimeTest.show(weekdays, in: ny) == "Mon 2025-03-10 08:00")
    }

    @Test func hourlyAcrossDSTStaysTwoRealHoursApart() {
        let anchor = TimeTest.date(2025, 3, 9, 0, in: ny)
        let r = Recurrence(frequency: .hourly, interval: 2)
        let a = nextOccurrence(after: anchor, recurrence: r, anchor: anchor, calendar: ny)!
        let b = nextOccurrence(after: a, recurrence: r, anchor: anchor, calendar: ny)!
        #expect(b.timeIntervalSince(a) == 7200)
    }
}
