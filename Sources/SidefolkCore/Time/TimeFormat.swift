import Foundation

/// Wording for times, always on a 24-hour clock. Two audiences (DECISIONS D28):
/// - people (`day`, `when`, `recurrence`): words from the string catalog, weekday and month names in
///   `calendar.locale`. The app passes the user's calendar; tests pin an English one, so they never
///   depend on the Mac's region.
/// - models (`full`, `recurrenceForModel`): always English and unambiguous.
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

    /// "Today", "Tomorrow", "Yesterday", "Tue" (the coming week), "Nov 12", or "Nov 12, 2026" in another
    /// year; the date's order and names follow `calendar.locale` ("12 Nov" in Britain, "11月12日" in Japan).
    public static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch diff {
        case -1: return String(localized: "Yesterday")
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        case 2...6: return weekday(isoWeekday(of: date, calendar: calendar), calendar: calendar)
        default:
            let style = Date.FormatStyle(locale: locale(of: calendar), calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return date.formatted(sameYear ? style : style.year())
        }
    }

    /// "Tomorrow 09:00", "Tue 09:00", "Nov 12 09:00".
    public static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        "\(day(date, now: now, calendar: calendar)) \(clock(date, calendar: calendar))"
    }

    /// "Thu 23 Oct 2025 09:00": unambiguous, for text a model reads.
    public static func full(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        return "\(weekdayShort[isoWeekday(of: date, calendar: calendar) - 1]) \(c.day ?? 1) \(monthShort[(c.month ?? 1) - 1]) \(c.year ?? 0) \(clock(date, calendar: calendar))"
    }

    /// "every day", "every 2 weeks on Tue, Thu", "every weekday", for people.
    public static func recurrence(_ r: Recurrence, calendar: Calendar) -> String {
        let n = r.interval
        switch r.frequency {
        case .hourly: return n == 1 ? String(localized: "every hour") : String(localized: "every \(n) hours")
        case .daily: return n == 1 ? String(localized: "every day") : String(localized: "every \(n) days")
        case .weekdays: return String(localized: "every weekday")
        case .weekly:
            let days = r.weekdays.filter { (1...7).contains($0) }.sorted().map { weekday($0, calendar: calendar) }
            guard !days.isEmpty else { return n == 1 ? String(localized: "every week") : String(localized: "every \(n) weeks") }
            let list = Wording.list(days)
            return n == 1 ? String(localized: "every \(list)") : String(localized: "every \(n) weeks on \(list)")
        case .monthly: return n == 1 ? String(localized: "every month") : String(localized: "every \(n) months")
        case .yearly: return n == 1 ? String(localized: "every year") : String(localized: "every \(n) years")
        }
    }

    /// The same in English, for text a model reads.
    public static func recurrenceForModel(_ r: Recurrence) -> String {
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

    /// "Tue" for ISO weekday 2, in `calendar.locale`.
    static func weekday(_ iso: Int, calendar: Calendar) -> String {
        var named = calendar
        named.locale = locale(of: calendar)
        return named.shortStandaloneWeekdaySymbols[iso % 7]   // the symbols start on Sunday
    }

    /// A calendar made without a locale names things in the root locale ("M11"); English instead.
    private static func locale(of calendar: Calendar) -> Locale {
        guard let locale = calendar.locale, !locale.identifier.isEmpty else { return Locale(identifier: "en_US_POSIX") }
        return locale
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}
