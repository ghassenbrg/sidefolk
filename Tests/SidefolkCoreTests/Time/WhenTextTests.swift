import Foundation
import Testing
@testable import SidefolkCore

/// A time picked on a calendar is written into a "when" field and read back by the same parser as typed words: the
/// same minute, whatever the time zone, calendar or language.
@Suite struct WhenTextTests {
    static let zones = ["UTC", "America/New_York", "Europe/Paris", "Asia/Tokyo", "Asia/Kolkata", "Pacific/Chatham", "America/St_Johns"]
    static let calendars: [(Calendar.Identifier, String)] = [
        (.gregorian, "en_US"), (.gregorian, "fr_FR"), (.gregorian, "ar_SA"), (.buddhist, "th_TH"), (.japanese, "ja_JP"),
        (.islamicUmmAlQura, "ar_SA"), (.hebrew, "he_IL"), (.gregorian, "zh_Hans_CN"),
    ]

    @Test func aPickedTimeReadsBackToTheSameMinute() {
        for zone in Self.zones {
            for (identifier, locale) in Self.calendars {
                var cal = Calendar(identifier: identifier)
                cal.timeZone = TimeZone(identifier: zone)!
                cal.locale = Locale(identifier: locale)
                let parser = WhenParser(calendar: cal)
                let now = TimeTest.date(2026, 10, 31, 9, 41)
                // Later today, tomorrow morning, next year, a minute before midnight, the end of a month.
                let picked = [now.addingTimeInterval(3 * 3600 + 7 * 60), now.addingTimeInterval(86400 - 41 * 60),
                              now.addingTimeInterval(400 * 86400), TimeTest.date(2026, 12, 31, 23, 59), TimeTest.date(2027, 2, 28, 12)]
                for date in picked {
                    let phrase = WhenText.phrase(for: date, timeZone: cal.timeZone)
                    let read = parser.parse(phrase, now: now)
                    #expect(read?.date == date, "\(zone) \(identifier) \(locale): \(phrase)")
                    #expect(read?.remaining.trimmingCharacters(in: .whitespaces).isEmpty == true, "\(phrase) left words over")
                }
            }
        }
    }

    @Test func thePhraseIsISOWithASCIIDigits() {
        var cal = Calendar(identifier: .buddhist)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let date = TimeTest.date(2026, 11, 3, 8, 5) // 15:05 in Bangkok
        #expect(WhenText.phrase(for: date, timeZone: cal.timeZone) == "2026-11-03 15:05")
    }
}
