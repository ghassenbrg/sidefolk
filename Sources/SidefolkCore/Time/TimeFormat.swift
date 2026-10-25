import Foundation

/// Plain, locale-independent wording for times ("Tomorrow 09:00", "every weekday"). Used by hints,
/// result cards and notifications, so it never depends on the Mac's region settings.
public enum TimeFormat {
    static let weekdayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let monthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// ISO weekday: 1 = Monday ... 7 = Sunday.
    public static func isoWeekday(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    /// "09:05" (24-hour).
    public static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return pad(c.hour ?? 0) + ":" + pad(c.minute ?? 0)
    }

    /// "Today", "Tomorrow", "Tue" (the coming week), "12 Nov", or "12 Nov 2026" in another year.
    public static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch diff {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return weekdayShort[isoWeekday(of: date, calendar: calendar) - 1]
        default:
            let c = calendar.dateComponents([.day, .month, .year], from: date)
            let base = "\(c.day ?? 1) \(monthShort[(c.month ?? 1) - 1])"
            return c.year == calendar.component(.year, from: now) ? base : "\(base) \(c.year ?? 0)"
        }
    }

    /// "Tomorrow 09:00", "Tue 09:00", "12 Nov 09:00".
    public static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        "\(day(date, now: now, calendar: calendar)) \(clock(date, calendar: calendar))"
    }

    /// "Thu 23 Oct 2025 09:00": unambiguous, for text a model reads.
    public static func full(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        return "\(weekdayShort[isoWeekday(of: date, calendar: calendar) - 1]) \(c.day ?? 1) \(monthShort[(c.month ?? 1) - 1]) \(c.year ?? 0) \(clock(date, calendar: calendar))"
    }

    /// "every day", "every 2 weeks on Tue, Thu", "every weekday".
    public static func recurrence(_ r: Recurrence) -> String {
        let n = r.interval
        func every(_ unit: String) -> String { n == 1 ? "every \(unit)" : "every \(n) \(unit)s" }
        switch r.frequency {
        case .hourly: return every("hour")
        case .daily: return every("day")
        case .weekdays: return "every weekday"
        case .weekly:
            let days = r.weekdays.filter { (1...7).contains($0) }.sorted().map { weekdayShort[$0 - 1] }
            guard !days.isEmpty else { return every("week") }
            return n == 1 ? "every \(days.joined(separator: ", "))" : "\(every("week")) on \(days.joined(separator: ", "))"
        case .monthly: return every("month")
        case .yearly: return every("year")
        }
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}
