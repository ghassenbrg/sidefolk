import Foundation
@testable import SidefolkCore

/// Fixed calendars and dates for the time tests, so nothing depends on the machine's time zone.
enum TimeTest {
    static func calendar(_ zone: String = "UTC") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    static let utc = calendar("UTC")
    static let newYork = calendar("America/New_York")

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0, in cal: Calendar = utc) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min; c.second = s
        return cal.date(from: c)!
    }

    /// Wednesday 22 October 2025, 10:00 UTC.
    static let wednesday10 = date(2025, 10, 22, 10)

    static func parser(_ cal: Calendar = utc) -> WhenParser {
        WhenParser(calendar: cal, morningHour: 9, afternoonHour: 14, eveningHour: 18)
    }

    /// "Wed 2025-10-22 10:00" style text for readable failures.
    static func show(_ d: Date?, in cal: Calendar = utc) -> String {
        guard let d else { return "nil" }
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let wd = TimeFormat.weekdayShort[TimeFormat.isoWeekday(of: d, calendar: cal) - 1]
        func p(_ n: Int?) -> String { String(format: "%02d", n ?? 0) }
        return "\(wd) \(c.year ?? 0)-\(p(c.month))-\(p(c.day)) \(p(c.hour)):\(p(c.minute))" + ((c.second ?? 0) > 0 ? ":\(p(c.second))" : "")
    }
}
