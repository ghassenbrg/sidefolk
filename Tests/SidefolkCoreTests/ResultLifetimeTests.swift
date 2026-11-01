import Foundation
import Testing
@testable import SidefolkCore

/// Ask tidies itself by each result's weight (D90).
@Suite struct ResultLifetimeTests {
    let now = TimeTest.wednesday10
    let calendar = TimeTest.calendar()

    func gone(_ w: ResultLifetime.Weight, made: TimeInterval, seen: TimeInterval? = nil, pinned: Bool = false, at: Date? = nil) -> Bool {
        ResultLifetime.expired(w, createdAt: now.addingTimeInterval(made), seenAt: seen.map { now.addingTimeInterval($0) }, pinned: pinned,
                               now: at ?? now, calendar: calendar)
    }

    @Test func aQuickAnswerGoesTwoMinutesAfterItWasSeen() {
        #expect(!gone(.quick, made: -90, seen: -90))
        #expect(gone(.quick, made: -130, seen: -125))
        // Not seen yet (it came while Ask was closed): it waits for its look.
        #expect(!gone(.quick, made: -3600))
        // Ask opened again ten minutes later: the battery level asked then is gone.
        #expect(gone(.quick, made: -600, seen: -600))
    }

    @Test func aNormalAnswerStaysHalfAnHourOrTheDay() {
        #expect(!gone(.normal, made: -1700, seen: -1700))
        #expect(gone(.normal, made: -1900))
        // Made last night at 23:50, looked at the next morning: gone even if not half an hour old.
        let lateNight = calendar.date(bySettingHour: 23, minute: 50, second: 0, of: now)!
        let morning = lateNight.addingTimeInterval(20 * 60)
        #expect(ResultLifetime.expired(.normal, createdAt: lateNight, seenAt: lateNight, pinned: false, now: morning, calendar: calendar))
    }

    @Test func whatNeedsThePersonAndWhatTheyPinnedStays() {
        #expect(!gone(.needsYou, made: -86_400 * 3, seen: -86_400 * 3))
        #expect(!gone(.quick, made: -3600, seen: -3600, pinned: true))
        #expect(!gone(.normal, made: -86_400, pinned: true))
    }

    @Test func valuesAndLookupsAreQuickWhatWasMadeIsNot() {
        #expect(ResultLifetime.weight(of: .reading) == .quick)
        #expect(ResultLifetime.weight(of: .extensionResult) == .quick)
        #expect(ResultLifetime.weight(of: .reminder) == .normal)
        #expect(ResultLifetime.weight(of: .note) == .normal)
    }
}
