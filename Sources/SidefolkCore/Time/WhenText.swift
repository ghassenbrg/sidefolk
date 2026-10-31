import Foundation

/// How a time picked on a calendar is written into a "when" field, so typing and picking meet in one value (the app's
/// WhenField): an ISO 8601 date and time on the person's clock, "2026-11-03 15:00". `WhenParser` reads it back to the
/// same minute in every language, calendar and numbering; the field shows its reading in the person's own words.
public enum WhenText {
    public static func phrase(for date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        // ISO 8601 is Gregorian whatever calendar the person uses, and its digits are ASCII.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let c = gregorian.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0)
    }
}
