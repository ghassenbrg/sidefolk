import Foundation

/// The days a read asks about, in plain words or ISO 8601: a day with no time means all of that day, so "until friday"
/// includes friday.
struct DateWindow: Sendable {
    var start: Date?
    var end: Date?

    /// Nil when neither end was given, read before anything else so a bad one is said at once.
    static func read(from: String?, to: String?, parser: WhenParser, now: Date) throws -> DateWindow? {
        guard from != nil || to != nil else { return nil }
        let window = DateWindow(start: try from.map { try moment($0, end: false, parser: parser, now: now) },
                                end: try to.map { try moment($0, end: true, parser: parser, now: now) })
        if let start = window.start, let end = window.end, end <= start {
            throw UserFacingError("Those dates are the wrong way round.")
        }
        return window
    }

    /// All of one day.
    static func day(_ date: Date, calendar: Calendar) -> DateWindow {
        let start = calendar.startOfDay(for: date)
        return DateWindow(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400))
    }

    func contains(_ date: Date) -> Bool {
        (start.map { date >= $0 } ?? true) && (end.map { date < $0 } ?? true)
    }

    private static func moment(_ text: String, end: Bool, parser: WhenParser, now: Date) throws -> Date {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A time to act on rolls forward, so the parser has no bare "today"; a read means this very day.
        if words.lowercased() == "today" {
            let day = parser.calendar.startOfDay(for: now)
            return end ? (parser.calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)) : day
        }
        guard words.count <= 200, let found = parser.parse(words, now: now) ?? parser.parse("in " + words, now: now),
              found.confidence != .low, found.recurrence == nil else {
            throw UserFacingError("I couldn't read “\(words.clipped(60))” as a date.", recovery: "Try something like “friday”, “dec 5” or an ISO date such as 2025-11-12.")
        }
        if found.hasTime { return found.date }
        let day = parser.calendar.startOfDay(for: found.date)
        return end ? (parser.calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)) : day
    }
}
