import Foundation
import SidefolkExtensionKit

/// Days between dates and dates from now, counted on the calendar here, so "how many days until 25 December"
/// or "what's 90 days from today" never rests on a guess.
enum Dates {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }

    /// "today", "tomorrow", "yesterday", "2026-12-25", "25 December 2026", "December 25" (the next one).
    static func parse(_ raw: String?, today: Date = Date()) throws -> Date {
        let start = calendar.startOfDay(for: today)
        let text = (raw ?? "today").trimmingCharacters(in: .whitespaces).lowercased()
        switch text {
        case "", "today", "now": return start
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: start)!
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: start)!
        default: break
        }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .current
        format.isLenient = false
        for pattern in ["yyyy-MM-dd", "d MMMM yyyy", "MMMM d, yyyy", "MMMM d yyyy", "d MMM yyyy", "MMM d, yyyy", "MMM d yyyy"] {
            format.dateFormat = pattern
            if let date = format.date(from: text) { return calendar.startOfDay(for: date) }
        }
        // A day and month without a year: the next time it comes round.
        for pattern in ["d MMMM", "MMMM d", "d MMM", "MMM d"] {
            format.dateFormat = pattern
            guard let date = format.date(from: text) else { continue }
            let parts = calendar.dateComponents([.month, .day], from: date)
            guard let next = calendar.nextDate(after: calendar.date(byAdding: .day, value: -1, to: start)!, matching: parts,
                                               matchingPolicy: .nextTime) else { break }
            return next
        }
        throw Problem("I couldn't read “\(raw ?? "")” as a date. Use YYYY-MM-DD, 25 December 2026, or today.")
    }

    static func show(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .current
        format.dateFormat = "EEEE d MMMM yyyy"
        return format.string(from: date)
    }

    /// "3 weeks", "-10 days", "2 months", "1 year", "5 weekdays".
    static func add(_ amount: String, to date: Date) throws -> Date {
        guard let m = amount.lowercased().trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: /([+-]?\s*\d+)\s*(day|days|d|week|weeks|wk|month|months|year|years|yr|weekday|weekdays|business days?|working days?)/) else {
            throw Problem("I couldn't read “\(amount)” as an amount of time. Use something like 3 weeks, -10 days or 2 months.")
        }
        let n = Int(m.1.replacingOccurrences(of: " ", with: ""))!
        switch m.2 {
        case "day", "days", "d": return calendar.date(byAdding: .day, value: n, to: date)!
        case "week", "weeks", "wk": return calendar.date(byAdding: .day, value: 7 * n, to: date)!
        case "month", "months": return calendar.date(byAdding: .month, value: n, to: date)!
        case "year", "years", "yr": return calendar.date(byAdding: .year, value: n, to: date)!
        default:
            // Weekdays: Monday to Friday, stepping over weekends.
            var day = date, left = abs(n)
            while left > 0 {
                day = calendar.date(byAdding: .day, value: n < 0 ? -1 : 1, to: day)!
                if !calendar.isDateInWeekend(day) { left -= 1 }
            }
            return day
        }
    }

    static func between(_ from: Date, _ to: Date) -> String {
        let days = calendar.dateComponents([.day], from: from, to: to).day!
        let (weeks, rest) = (abs(days) / 7, abs(days) % 7)
        var weekdays = 0
        var day = min(from, to)
        while day < max(from, to) {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
            if !calendar.isDateInWeekend(day) { weekdays += 1 }
        }
        let span = abs(days) == 1 ? "1 day" : "\(abs(days)) days"
        let breakdown = weeks > 0 ? " (\(weeks) week\(weeks == 1 ? "" : "s")\(rest > 0 ? " and \(rest) day\(rest == 1 ? "" : "s")" : ""))" : ""
        let direction = days < 0 ? ", going back" : ""
        return "From \(show(from)) to \(show(to)): \(span)\(breakdown)\(direction), \(weekdays) of them weekdays."
    }

    static func describe(_ date: Date, today: Date = Date()) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: date).day!
        let week = calendar.component(.weekOfYear, from: date), dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let when = days == 0 ? "today" : days > 0 ? "in \(days) day\(days == 1 ? "" : "s")" : "\(-days) day\(days == -1 ? "" : "s") ago"
        return "\(show(date)): \(when), week \(week), day \(dayOfYear) of the year."
    }
}
