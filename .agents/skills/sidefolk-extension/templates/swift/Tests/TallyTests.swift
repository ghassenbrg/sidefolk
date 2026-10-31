import Foundation
import Testing
@testable import ext_water_tally

/// The extension's own logic with fixed dates: no process, no sandbox. The sandbox is tested by installing the built
/// folder (`sidefolk ext validate`, and in Sidefolk's ShippedExtensionSandboxTests for the gallery's).
struct TallyTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func aNewDayStartsFromNoneAndKeepsTheGoal() {
        var t = Tally(day: "2026-10-30", goal: 10, largeGlasses: true)
        t.times = [at(30, 9), at(30, 12)]
        let next = t.on(at(31, 8), calendar: calendar)
        #expect(next.day == "2026-10-31" && next.glasses == 0 && next.goal == 10 && next.largeGlasses)
        #expect(t.on(at(30, 20), calendar: calendar) == t)
    }

    @Test func behindOnceADayAfterTheHour() {
        var t = Tally(day: "2026-10-31", goal: 8)
        t.times = [at(31, 9), at(31, 10), at(31, 11)]
        #expect(!t.behind(now: at(31, 14), afterHour: 15, toldOn: nil, calendar: calendar))
        #expect(t.behind(now: at(31, 16), afterHour: 15, toldOn: nil, calendar: calendar))
        #expect(!t.behind(now: at(31, 17), afterHour: 15, toldOn: "2026-10-31", calendar: calendar))
        t.times.append(at(31, 16))
        #expect(!t.behind(now: at(31, 17), afterHour: 15, toldOn: nil, calendar: calendar))
    }

    @Test func theSentenceSaysWhatIsLeft() {
        var t = Tally(day: "2026-10-31", goal: 2)
        t.times = [at(31, 9)]
        #expect(t.sentence == "1 glass of water today (250 ml), 1 to go for your goal of 2.")
        t.times.append(at(31, 10))
        #expect(t.sentence == "2 glasses of water today (500 ml): your goal of 2 is reached.")
    }

    @MainActor @Test func thePageSaysWhatIsTrue() {
        var t = Tally(day: "2026-10-31", goal: 8)
        t.times = [at(31, 9)]
        let page = WaterPage.make(t, now: at(31, 10))
        #expect(page.summary?.title == "1 of 8 glasses")
        #expect(page.sections.map(\.title).contains("Over the day"))
    }
}
