import Foundation
import Testing
@testable import SidefolkCore

/// One phrase and the date it must resolve to, with "now" = Wednesday 22 October 2025, 10:00 UTC
/// (morning 09, afternoon 14, evening 18, night 21).
struct WhenCase: Sendable, CustomTestStringConvertible {
    let input: String
    let expected: String
    var testDescription: String { "\(input) -> \(expected)" }
    init(_ input: String, _ expected: String) {
        self.input = input
        self.expected = expected
    }
}

@Suite struct WhenParserTests {
    let parser = TimeTest.parser()
    let now = TimeTest.wednesday10

    func resolve(_ text: String, at now: Date? = nil) -> WhenResult? { parser.parse(text, now: now ?? self.now) }
    func shown(_ text: String, at now: Date? = nil) -> String { TimeTest.show(resolve(text, at: now)?.date) }

    // MARK: Offsets

    static let offsets: [WhenCase] = [
        WhenCase("in 20 min", "Wed 2025-10-22 10:20"),
        WhenCase("in 20 mins", "Wed 2025-10-22 10:20"),
        WhenCase("in 20 minutes", "Wed 2025-10-22 10:20"),
        WhenCase("in 20m", "Wed 2025-10-22 10:20"),
        WhenCase("IN 20 MIN", "Wed 2025-10-22 10:20"),
        WhenCase("in 5 mnutes", "Wed 2025-10-22 10:05"),
        WhenCase("in 2 hours", "Wed 2025-10-22 12:00"),
        WhenCase("in 2 hrs", "Wed 2025-10-22 12:00"),
        WhenCase("in 2h", "Wed 2025-10-22 12:00"),
        WhenCase("in two hours", "Wed 2025-10-22 12:00"),
        WhenCase("in an hour", "Wed 2025-10-22 11:00"),
        WhenCase("in a hour", "Wed 2025-10-22 11:00"),
        WhenCase("in half an hour", "Wed 2025-10-22 10:30"),
        WhenCase("in half hour", "Wed 2025-10-22 10:30"),
        WhenCase("in an hour and a half", "Wed 2025-10-22 11:30"),
        WhenCase("in 1 hour 30 minutes", "Wed 2025-10-22 11:30"),
        WhenCase("in 2 hours and 15 min", "Wed 2025-10-22 12:15"),
        WhenCase("in 1.5 hours", "Wed 2025-10-22 11:30"),
        WhenCase("in a couple of hours", "Wed 2025-10-22 12:00"),
        WhenCase("in 90 seconds", "Wed 2025-10-22 10:01:30"),
        WhenCase("20 minutes from now", "Wed 2025-10-22 10:20"),
        WhenCase("after 10 min", "Wed 2025-10-22 10:10"),
        // Days and larger are dates: the morning hour applies.
        WhenCase("in 3 days", "Sat 2025-10-25 09:00"),
        WhenCase("in a week", "Wed 2025-10-29 09:00"),
        WhenCase("in 2 weeks at 3pm", "Wed 2025-11-05 15:00"),
        WhenCase("in a month", "Sat 2025-11-22 09:00"),
        WhenCase("in 1 day 2 hours", "Thu 2025-10-23 12:00"),
    ]

    @Test(arguments: offsets) func offsetPhrases(_ c: WhenCase) {
        #expect(shown(c.input) == c.expected)
    }

    // MARK: Clock times

    static let clocks: [WhenCase] = [
        WhenCase("at 5", "Wed 2025-10-22 17:00"),
        WhenCase("at 5pm", "Wed 2025-10-22 17:00"),
        WhenCase("5pm", "Wed 2025-10-22 17:00"),
        WhenCase("5 pm", "Wed 2025-10-22 17:00"),
        WhenCase("at 5 p.m.", "Wed 2025-10-22 17:00"),
        WhenCase("at 5 o'clock", "Wed 2025-10-22 17:00"),
        WhenCase("at five", "Wed 2025-10-22 17:00"),
        WhenCase("at 17:30", "Wed 2025-10-22 17:30"),
        WhenCase("17:30", "Wed 2025-10-22 17:30"),
        WhenCase("at 5:30pm", "Wed 2025-10-22 17:30"),
        WhenCase("at 5:30", "Wed 2025-10-22 17:30"),
        WhenCase("at 11", "Wed 2025-10-22 11:00"),
        WhenCase("at 11:45", "Wed 2025-10-22 11:45"),
        // 09:00 is over, so a bare 9 means the evening rather than tomorrow morning.
        WhenCase("at 9", "Wed 2025-10-22 21:00"),
        WhenCase("at 8", "Wed 2025-10-22 20:00"),
        WhenCase("at 9am", "Thu 2025-10-23 09:00"),
        WhenCase("at 10:30", "Wed 2025-10-22 10:30"),
        WhenCase("at 12", "Wed 2025-10-22 12:00"),
        WhenCase("at 12pm", "Wed 2025-10-22 12:00"),
        WhenCase("at 12am", "Thu 2025-10-23 00:00"),
        WhenCase("at 0:30", "Thu 2025-10-23 00:30"),
        WhenCase("at 17", "Wed 2025-10-22 17:00"),
        WhenCase("noon", "Wed 2025-10-22 12:00"),
        WhenCase("at noon", "Wed 2025-10-22 12:00"),
        WhenCase("midnight", "Thu 2025-10-23 00:00"),
        WhenCase("at midnight", "Thu 2025-10-23 00:00"),
        WhenCase("at 5 sharp", "Wed 2025-10-22 17:00"),
    ]

    @Test(arguments: clocks) func clockPhrases(_ c: WhenCase) {
        #expect(shown(c.input) == c.expected)
    }

    @Test func aBareHourThatPassedTodayMeansTomorrow() {
        let evening = TimeTest.date(2025, 10, 22, 18)
        #expect(shown("at 5", at: evening) == "Thu 2025-10-23 17:00")
        let lateNight = TimeTest.date(2025, 10, 22, 22)
        #expect(shown("at 9", at: lateNight) == "Thu 2025-10-23 09:00")
        #expect(shown("at 17:30", at: TimeTest.date(2025, 10, 22, 18)) == "Thu 2025-10-23 17:30")
    }

    // MARK: Days

    static let days: [WhenCase] = [
        WhenCase("tomorrow", "Thu 2025-10-23 09:00"),
        WhenCase("tommorow", "Thu 2025-10-23 09:00"),
        WhenCase("tomorow", "Thu 2025-10-23 09:00"),
        WhenCase("tmrw", "Thu 2025-10-23 09:00"),
        WhenCase("TOMORROW", "Thu 2025-10-23 09:00"),
        WhenCase("the day after tomorrow", "Fri 2025-10-24 09:00"),
        WhenCase("tomorrow morning", "Thu 2025-10-23 09:00"),
        WhenCase("tomorrow afternoon", "Thu 2025-10-23 14:00"),
        WhenCase("tomorrow evening", "Thu 2025-10-23 18:00"),
        WhenCase("tomorrow night", "Thu 2025-10-23 21:00"),
        WhenCase("tomorrow at 10", "Thu 2025-10-23 10:00"),
        WhenCase("tomorrow at 10 dentist", "Thu 2025-10-23 10:00"),
        WhenCase("tomorrow at 5", "Thu 2025-10-23 17:00"),
        WhenCase("tomorrow at 5am", "Thu 2025-10-23 05:00"),
        WhenCase("tomorrow 3pm", "Thu 2025-10-23 15:00"),
        WhenCase("tomorrow evening at 7", "Thu 2025-10-23 19:00"),
        WhenCase("tomorrow at 9 in the morning", "Thu 2025-10-23 09:00"),
        WhenCase("tonight", "Wed 2025-10-22 21:00"),
        WhenCase("tonight at 8", "Wed 2025-10-22 20:00"),
        WhenCase("this afternoon", "Wed 2025-10-22 14:00"),
        WhenCase("this evening", "Wed 2025-10-22 18:00"),
        WhenCase("today at 3pm", "Wed 2025-10-22 15:00"),
        WhenCase("in the morning", "Thu 2025-10-23 09:00"),
        WhenCase("in the evening", "Wed 2025-10-22 18:00"),
        WhenCase("at night", "Wed 2025-10-22 21:00"),
        WhenCase("on friday", "Fri 2025-10-24 09:00"),
        WhenCase("friday", "Fri 2025-10-24 09:00"),
        WhenCase("Friday", "Fri 2025-10-24 09:00"),
        WhenCase("friday at 3pm", "Fri 2025-10-24 15:00"),
        WhenCase("friday 3pm", "Fri 2025-10-24 15:00"),
        WhenCase("fri at 3", "Fri 2025-10-24 15:00"),
        WhenCase("on fri", "Fri 2025-10-24 09:00"),
        WhenCase("this friday", "Fri 2025-10-24 09:00"),
        WhenCase("freday", "Fri 2025-10-24 09:00"),
        WhenCase("wensday at 3pm", "Wed 2025-10-22 15:00"),
        WhenCase("saturday morning", "Sat 2025-10-25 09:00"),
        WhenCase("sunday evening", "Sun 2025-10-26 18:00"),
        // Today is Wednesday and 09:00 has passed: the next Wednesday.
        WhenCase("wednesday", "Wed 2025-10-29 09:00"),
        WhenCase("monday", "Mon 2025-10-27 09:00"),
        WhenCase("next monday", "Mon 2025-10-27 09:00"),
        WhenCase("next wednesday", "Wed 2025-10-29 09:00"),
        WhenCase("next friday at noon", "Fri 2025-10-24 12:00"),
        WhenCase("next week", "Mon 2025-10-27 09:00"),
        WhenCase("next week at 2pm", "Mon 2025-10-27 14:00"),
        WhenCase("next month", "Sat 2025-11-01 09:00"),
        WhenCase("next year", "Thu 2026-01-01 09:00"),
        WhenCase("this weekend", "Sat 2025-10-25 09:00"),
        WhenCase("on the weekend", "Sat 2025-10-25 09:00"),
    ]

    @Test(arguments: days) func dayPhrases(_ c: WhenCase) {
        #expect(shown(c.input) == c.expected)
    }

    // MARK: Dates

    static let dates: [WhenCase] = [
        WhenCase("on 12 nov", "Wed 2025-11-12 09:00"),
        WhenCase("12 nov", "Wed 2025-11-12 09:00"),
        WhenCase("nov 12", "Wed 2025-11-12 09:00"),
        WhenCase("Nov 12th", "Wed 2025-11-12 09:00"),
        WhenCase("november 12", "Wed 2025-11-12 09:00"),
        WhenCase("12th of november", "Wed 2025-11-12 09:00"),
        WhenCase("the 12th of november", "Wed 2025-11-12 09:00"),
        WhenCase("novembr 12", "Wed 2025-11-12 09:00"),
        WhenCase("Oct 30 at 9", "Thu 2025-10-30 09:00"),
        WhenCase("oct 30 at 9am", "Thu 2025-10-30 09:00"),
        WhenCase("oct 30 at 5", "Thu 2025-10-30 17:00"),
        WhenCase("on 3 dec at 14:30", "Wed 2025-12-03 14:30"),
        WhenCase("dec 25, 2026", "Fri 2026-12-25 09:00"),
        WhenCase("25 december 2026 at noon", "Fri 2026-12-25 12:00"),
        // Already past this year: next year.
        WhenCase("jan 5", "Mon 2026-01-05 09:00"),
        WhenCase("oct 1", "Thu 2026-10-01 09:00"),
        WhenCase("on the 15th", "Sat 2025-11-15 09:00"),
        WhenCase("on the 25th", "Sat 2025-10-25 09:00"),
        WhenCase("on the 31st", "Fri 2025-10-31 09:00"),
        WhenCase("feb 29", "Tue 2028-02-29 09:00"),
    ]

    @Test(arguments: dates) func datePhrases(_ c: WhenCase) {
        #expect(shown(c.input) == c.expected)
    }

    @Test func ambiguousNumericDatesAreNotGuessed() {
        #expect(resolve("12/11") == nil)
        #expect(resolve("on 12/11") == nil)
        #expect(resolve("11/12/2025") == nil)
        #expect(resolve("feb 30") == nil)
    }

    // MARK: ISO 8601

    @Test func isoDatesAndTimes() {
        #expect(shown("2025-11-12") == "Wed 2025-11-12 09:00")
        #expect(shown("2025-11-12 at 5pm") == "Wed 2025-11-12 17:00")
        #expect(shown("2025-11-12T09:30:00Z") == "Wed 2025-11-12 09:30")
        #expect(shown("2025-11-12T09:30:00") == "Wed 2025-11-12 09:30")
        #expect(shown("2025-11-12 09:30") == "Wed 2025-11-12 09:30")
        #expect(shown("2025-11-12T09:30:00.250Z") == "Wed 2025-11-12 09:30")
        #expect(shown("2025-11-12T09:30:00+01:00") == "Wed 2025-11-12 08:30")
        #expect(shown("2025-11-12T09:30:00-05:00") == "Wed 2025-11-12 14:30")
        #expect(shown("2025-11-12T09:30:00+0100") == "Wed 2025-11-12 08:30")
        #expect(resolve("2025-11-12T09:30:00Z")?.isExplicitInstant == true)
        #expect(resolve("tomorrow")?.isExplicitInstant == false)
    }

    @Test func isoInThePastIsReturnedForTheCallerToReject() {
        let r = resolve("2024-01-01T10:00:00Z")
        #expect(TimeTest.show(r?.date) == "Mon 2024-01-01 10:00")
        #expect(r?.isExplicitInstant == true)
        #expect(resolve("2025-02-30") == nil)
    }

    @Test func isoUsesTheCallersTimeZoneWhenNoneIsGiven() {
        let ny = TimeTest.newYork
        let p = TimeTest.parser(ny)
        let r = p.parse("2025-11-12T09:30:00", now: TimeTest.date(2025, 10, 22, 10, in: ny))
        #expect(TimeTest.show(r?.date, in: ny) == "Wed 2025-11-12 09:30")
    }

    // MARK: Parts of today that are over

    @Test func askingForAMomentThatPassedIsLowConfidence() {
        let morning = resolve("this morning")
        #expect(morning?.confidence == .low)
        // The suggestion is the next chance.
        #expect(TimeTest.show(morning?.date) == "Thu 2025-10-23 09:00")
        #expect(resolve("today")?.confidence == .low)
        #expect(resolve("today at 9am")?.confidence == .low)
        #expect(resolve("on oct 22")?.confidence == .low)
        #expect(resolve("tonight", at: TimeTest.date(2025, 10, 22, 22))?.confidence == .low)
        #expect(resolve("this afternoon")?.confidence == .high)
    }

    @Test func confidenceReflectsAssumptions() {
        #expect(resolve("tomorrow at 5pm")?.confidence == .high)
        #expect(resolve("at 5")?.confidence == .high)
        #expect(resolve("at 9")?.confidence == .medium)
        #expect(resolve("wednesday")?.confidence == .medium)
        #expect(resolve("jan 5")?.confidence == .medium)
    }

    @Test func hasTimeTellsExplicitFromDefaulted() {
        #expect(resolve("tomorrow")?.hasTime == false)
        #expect(resolve("tomorrow morning")?.hasTime == true)
        #expect(resolve("in 20 min")?.hasTime == true)
        #expect(resolve("at 5")?.hasTime == true)
    }

    @Test func configuredHoursAreUsed() {
        let p = WhenParser(calendar: TimeTest.utc, morningHour: 8, afternoonHour: 13, eveningHour: 19)
        func show(_ s: String) -> String { TimeTest.show(p.parse(s, now: now)?.date) }
        #expect(show("tomorrow") == "Thu 2025-10-23 08:00")
        #expect(show("tomorrow morning") == "Thu 2025-10-23 08:00")
        #expect(show("tomorrow afternoon") == "Thu 2025-10-23 13:00")
        #expect(show("tomorrow evening") == "Thu 2025-10-23 19:00")
        #expect(show("tomorrow night") == "Thu 2025-10-23 21:00")
    }

    // MARK: Repeating

    @Test func everyDayAtNine() {
        let r = resolve("every day at 9")
        #expect(r?.recurrence == Recurrence(frequency: .daily))
        #expect(TimeTest.show(r?.date) == "Thu 2025-10-23 09:00")
        #expect(shown("every day at 9", at: TimeTest.date(2025, 10, 22, 8)) == "Wed 2025-10-22 09:00")
    }

    @Test func everyWeekday() {
        let r = resolve("every weekday at 9")
        #expect(r?.recurrence == Recurrence(frequency: .weekdays))
        #expect(TimeTest.show(r?.date) == "Thu 2025-10-23 09:00")
        // Friday afternoon: the next weekday is Monday.
        #expect(shown("every weekday at 9", at: TimeTest.date(2025, 10, 24, 15)) == "Mon 2025-10-27 09:00")
        #expect(resolve("weekdays at 8")?.recurrence == Recurrence(frequency: .weekdays))
        #expect(resolve("on weekdays at 8")?.recurrence == Recurrence(frequency: .weekdays))
        #expect(resolve("every working day at 8")?.recurrence == Recurrence(frequency: .weekdays))
    }

    @Test func everyMondayAt10am() {
        let r = resolve("every monday 10am")
        #expect(r?.recurrence == Recurrence(frequency: .weekly, weekdays: [1]))
        #expect(TimeTest.show(r?.date) == "Mon 2025-10-27 10:00")
        #expect(resolve("every Monday at 10am")?.recurrence == r?.recurrence)
        #expect(resolve("mondays at 10am")?.recurrence == r?.recurrence)
        #expect(resolve("on mondays at 10am")?.recurrence == r?.recurrence)
    }

    @Test func everyNHours() {
        let r = resolve("every 2 hours")
        #expect(r?.recurrence == Recurrence(frequency: .hourly, interval: 2))
        #expect(TimeTest.show(r?.date) == "Wed 2025-10-22 12:00")
        #expect(resolve("every hour")?.recurrence == Recurrence(frequency: .hourly))
        #expect(resolve("hourly")?.recurrence == Recurrence(frequency: .hourly))
    }

    @Test func weeklyOnSeveralDays() {
        let r = resolve("weekly on tue and thu at 8")
        #expect(r?.recurrence == Recurrence(frequency: .weekly, weekdays: [2, 4]))
        #expect(TimeTest.show(r?.date) == "Thu 2025-10-23 08:00")
        #expect(resolve("every mon, wed and fri at 7am")?.recurrence == Recurrence(frequency: .weekly, weekdays: [1, 3, 5]))
        #expect(resolve("every tuesday and thursday")?.recurrence?.weekdays == [2, 4])
    }

    @Test func everyMonthOnTheFirst() {
        let r = resolve("every month on the 1st")
        #expect(r?.recurrence == Recurrence(frequency: .monthly))
        #expect(TimeTest.show(r?.date) == "Sat 2025-11-01 09:00")
        #expect(resolve("monthly on the 15th")?.recurrence == Recurrence(frequency: .monthly))
        #expect(shown("monthly on the 15th") == "Sat 2025-11-15 09:00")
        #expect(shown("every month on the 25th") == "Sat 2025-10-25 09:00")
        #expect(shown("every month on the last day") == "Fri 2025-10-31 09:00")
    }

    @Test func monthlyOnThe31stRemembersTheDayInShortMonths() {
        // Created on 5 November: the first fire is 30 November, but the series is still "the 31st".
        let november = TimeTest.date(2025, 11, 5, 10)
        let r = parser.parse("every month on the 31st", now: november)
        #expect(TimeTest.show(r?.date) == "Sun 2025-11-30 09:00")
        #expect(r.map { utcDay($0.anchor) } == 31)
        let after = RecurrenceMath.nextOccurrence(after: r!.date, recurrence: r!.recurrence!, anchor: r!.anchor, calendar: TimeTest.utc)
        #expect(TimeTest.show(after) == "Wed 2025-12-31 09:00")
    }

    func utcDay(_ d: Date) -> Int { TimeTest.utc.component(.day, from: d) }

    @Test func otherRepeatForms() {
        #expect(resolve("daily")?.recurrence == Recurrence(frequency: .daily))
        #expect(shown("daily") == "Thu 2025-10-23 09:00")
        #expect(resolve("every other day")?.recurrence == Recurrence(frequency: .daily, interval: 2))
        #expect(resolve("every 3 days at 6pm")?.recurrence == Recurrence(frequency: .daily, interval: 3))
        #expect(resolve("every 2 weeks on friday")?.recurrence == Recurrence(frequency: .weekly, interval: 2, weekdays: [5]))
        #expect(shown("every 2 weeks on friday") == "Fri 2025-10-24 09:00")
        #expect(resolve("every morning")?.recurrence == Recurrence(frequency: .daily))
        #expect(shown("every evening") == "Wed 2025-10-22 18:00")
        #expect(resolve("every weekend")?.recurrence == Recurrence(frequency: .weekly, weekdays: [6, 7]))
        #expect(resolve("weekly")?.recurrence == Recurrence(frequency: .weekly))
        #expect(resolve("every week")?.recurrence == Recurrence(frequency: .weekly))
        #expect(resolve("yearly")?.recurrence == Recurrence(frequency: .yearly))
        #expect(resolve("every year on nov 12")?.recurrence == Recurrence(frequency: .yearly))
        #expect(shown("every year on nov 12") == "Wed 2025-11-12 09:00")
        #expect(resolve("every nov 12")?.recurrence == Recurrence(frequency: .yearly))
        #expect(resolve("fortnightly")?.recurrence == Recurrence(frequency: .weekly, interval: 2))
    }

    @Test func repeatsEveryThirtyMinutesCannotBeExpressed() {
        // Recurrence's smallest step is an hour; better to say nothing than to get it wrong.
        #expect(resolve("every 30 minutes") == nil)
    }

    // MARK: Phrases inside sentences

    @Test func remainingTextIsWhatIsLeft() {
        let r = resolve("call Karim at 5")
        #expect(r?.remaining == "call Karim")
        #expect(r?.matched == "at 5")
        #expect(resolve("tomorrow at 10 dentist")?.remaining == "dentist")
        #expect(resolve("send the document tomorrow morning")?.remaining == "send the document")
        #expect(resolve("tomorrow morning to send the document")?.remaining == "to send the document")
        #expect(resolve("water the plants every monday at 8, please")?.remaining == "water the plants, please")
        #expect(resolve("call mom in 20 min.")?.remaining == "call mom.")
        #expect(resolve("pay rent on the 1st")?.remaining == "pay rent")
        #expect(resolve("pay rent on the 1st")?.matched == "on the 1st")
        #expect(resolve("tomorrow")?.remaining == "")
    }

    @Test func aDateAtTheStartJoinsATimeAtTheEnd() {
        let r = resolve("tomorrow call Karim at 5")
        #expect(TimeTest.show(r?.date) == "Thu 2025-10-23 17:00")
        #expect(r?.remaining == "call Karim")
        #expect(r?.ranges.count == 2)
        let r2 = resolve("tomorrow to send the report at 3pm")
        #expect(TimeTest.show(r2?.date) == "Thu 2025-10-23 15:00")
        #expect(r2?.remaining == "to send the report")
    }

    @Test func aPhraseAtTheEdgeBeatsOneInTheMiddle() {
        // "friday" is part of the title; the real time is at the end.
        let r = resolve("review the friday release notes tomorrow")
        #expect(TimeTest.show(r?.date) == "Thu 2025-10-23 09:00")
        #expect(r?.remaining == "review the friday release notes")
        let r2 = resolve("tomorrow review the friday release notes")
        #expect(TimeTest.show(r2?.date) == "Thu 2025-10-23 09:00")
        #expect(r2?.remaining == "review the friday release notes")
    }

    @Test func possessivesAreNotDays() {
        #expect(resolve("tomorrow's meeting") == nil)
        #expect(resolve("friday's release") == nil)
    }

    @Test func ordinaryTextIsNotATime() {
        for text in ["call mom", "buy 3 apples", "look at 5 pages", "the weekly report", "the daily summary",
                     "I sat down", "a second opinion", "at the office", "send it", "", "   ", "in the fridge",
                     "march forward", "remind me", "5 minutes"] {
            #expect(resolve(text) == nil, "\(text)")
        }
    }

    @Test func shortWeekdayNamesNeedContext() {
        #expect(resolve("the sun is out") == nil)
        #expect(resolve("sat quietly") == nil)
        #expect(shown("on sat") == "Sat 2025-10-25 09:00")
        #expect(shown("sat at 4") == "Sat 2025-10-25 16:00")
    }

    @Test func barePluralWeekdayNeedsAScheduleShape() {
        #expect(resolve("mondays") != nil)
        #expect(resolve("I hate mondays so much") == nil)
    }

    @Test func resultsAreNeverInThePastExceptISO() {
        let inputs = ["at 5", "at 9", "at 9am", "friday", "wednesday", "wednesday at 9", "tomorrow", "next week", "in the morning",
                      "every day", "every monday", "on the 3rd", "jan 1", "dec 25", "monday morning", "midnight", "noon", "this weekend"]
        for hour in [0, 3, 9, 12, 17, 23] {
            for day in [20, 22, 25, 26] {
                let at = TimeTest.date(2025, 10, day, hour, 30)
                for input in inputs {
                    if let r = resolve(input, at: at), r.confidence >= .medium {
                        #expect(r.date > at, "\(input) at \(TimeTest.show(at)) gave \(TimeTest.show(r.date))")
                    }
                }
            }
        }
    }
}
