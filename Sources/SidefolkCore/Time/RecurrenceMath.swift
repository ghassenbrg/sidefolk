import Foundation

/// Where a repeating reminder fires next. Occurrences are always computed from the series
/// `anchor` (its first fire) rather than from the previous fire, so a series created on the 31st
/// keeps returning to the 31st after a short month, and wall-clock time survives daylight saving.
public enum RecurrenceMath {
    /// The first occurrence strictly after `after`, or nil when the series has ended (`until`).
    /// Occurrences never come before `anchor`.
    public static func nextOccurrence(after: Date, recurrence r: Recurrence, anchor: Date, calendar: Calendar) -> Date? {
        let step = max(1, r.interval)
        let found: Date?
        switch r.frequency {
        case .hourly: found = hourly(after: after, anchor: anchor, step: step)
        case .daily: found = daily(after: after, anchor: anchor, step: step, calendar: calendar)
        case .weekdays: found = weekdays(after: after, anchor: anchor, calendar: calendar)
        case .weekly: found = weekly(after: after, anchor: anchor, step: step, days: r.weekdays, calendar: calendar)
        case .monthly: found = monthly(after: after, anchor: anchor, step: step, calendar: calendar)
        case .yearly: found = yearly(after: after, anchor: anchor, step: step, calendar: calendar)
        }
        guard let found else { return nil }
        if let until = r.until, found > until { return nil }
        return found
    }

    // MARK: Frequencies

    /// Hours are elapsed time, not wall-clock: "every 2 hours" stays two real hours apart across DST.
    private static func hourly(after: Date, anchor: Date, step: Int) -> Date? {
        let length = Double(step) * 3600
        guard after >= anchor else { return anchor }
        let k = (after.timeIntervalSince(anchor) / length).rounded(.down) + 1
        return anchor.addingTimeInterval(k * length)
    }

    private static func daily(after: Date, anchor: Date, step: Int, calendar: Calendar) -> Date? {
        let wall = WallClock(anchor, calendar)
        let first = calendar.startOfDay(for: anchor)
        let gap = max(0, days(from: first, to: calendar.startOfDay(for: after), calendar))
        var k = max(0, gap / step - 1)
        for _ in 0..<8 {
            let day = calendar.date(byAdding: .day, value: k * step, to: first) ?? first
            let candidate = wall.on(day)
            if candidate > after, candidate >= anchor { return candidate }
            k += 1
        }
        return nil
    }

    private static func weekdays(after: Date, anchor: Date, calendar: Calendar) -> Date? {
        let wall = WallClock(anchor, calendar)
        var day = calendar.startOfDay(for: max(after, anchor))
        for _ in 0..<9 {
            if (1...5).contains(TimeFormat.isoWeekday(of: day, calendar: calendar)) {
                let candidate = wall.on(day)
                if candidate > after, candidate >= anchor { return candidate }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        }
        return nil
    }

    private static func weekly(after: Date, anchor: Date, step: Int, days wanted: [Int], calendar: Calendar) -> Date? {
        let wall = WallClock(anchor, calendar)
        let valid = Set(wanted.filter { (1...7).contains($0) })
        let set = valid.isEmpty ? [TimeFormat.isoWeekday(of: anchor, calendar: calendar)] : valid
        let anchorMonday = monday(of: anchor, calendar)
        var day = calendar.startOfDay(for: max(after, anchor))
        for _ in 0..<(7 * step + 8) {
            let week = days(from: anchorMonday, to: monday(of: day, calendar), calendar) / 7
            if week % step == 0, set.contains(TimeFormat.isoWeekday(of: day, calendar: calendar)) {
                let candidate = wall.on(day)
                if candidate > after, candidate >= anchor { return candidate }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        }
        return nil
    }

    /// Same day of the month as the anchor; months too short for it use their last day.
    private static func monthly(after: Date, anchor: Date, step: Int, calendar: Calendar) -> Date? {
        let wall = WallClock(anchor, calendar)
        let a = calendar.dateComponents([.year, .month, .day], from: anchor)
        let b = calendar.dateComponents([.year, .month], from: after)
        let gap = ((b.year ?? 0) - (a.year ?? 0)) * 12 + (b.month ?? 0) - (a.month ?? 0)
        var k = max(0, gap / step - 1)
        for _ in 0..<8 {
            if let candidate = date(year: a.year ?? 1970, month: (a.month ?? 1) + k * step, day: a.day ?? 1, wall: wall, calendar),
               candidate > after, candidate >= anchor { return candidate }
            k += 1
        }
        return nil
    }

    /// Same date every year; 29 February falls back to 28 February in other years.
    private static func yearly(after: Date, anchor: Date, step: Int, calendar: Calendar) -> Date? {
        let wall = WallClock(anchor, calendar)
        let a = calendar.dateComponents([.year, .month, .day], from: anchor)
        let gap = calendar.component(.year, from: after) - (a.year ?? 1970)
        var k = max(0, gap / step - 1)
        for _ in 0..<8 {
            if let candidate = date(year: (a.year ?? 1970) + k * step, month: a.month ?? 1, day: a.day ?? 1, wall: wall, calendar),
               candidate > after, candidate >= anchor { return candidate }
            k += 1
        }
        return nil
    }

    // MARK: Helpers

    /// The anchor's time of day, applied to other days.
    struct WallClock {
        let hour: Int, minute: Int, second: Int
        let calendar: Calendar

        init(_ date: Date, _ calendar: Calendar) {
            let c = calendar.dateComponents([.hour, .minute, .second], from: date)
            hour = c.hour ?? 0
            minute = c.minute ?? 0
            second = c.second ?? 0
            self.calendar = calendar
        }

        /// Keeps the wall-clock time; a time skipped by daylight saving moves forward with its minutes
        /// (02:30 becomes 03:30), a repeated one fires the first time.
        func on(_ day: Date) -> Date { calendar.wallClock(on: day, hour: hour, minute: minute, second: second) }
    }

    /// The date for a year/month/day, rolling extra months into years and clamping the day to the month's length.
    private static func date(year: Int, month: Int, day: Int, wall: WallClock, _ calendar: Calendar) -> Date? {
        var first = DateComponents()
        first.year = year
        first.month = month
        first.day = 1
        guard let monthStart = calendar.date(from: first),
              let length = calendar.range(of: .day, in: .month, for: monthStart)?.count else { return nil }
        var target = calendar.dateComponents([.year, .month], from: monthStart)
        target.day = min(day, length)
        guard let d = calendar.date(from: target) else { return nil }
        return wall.on(calendar.startOfDay(for: d))
    }

    static func days(from a: Date, to b: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Start of the ISO week (Monday) containing `date`, independent of the user's first-weekday setting.
    static func monday(of date: Date, _ calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let back = TimeFormat.isoWeekday(of: start, calendar: calendar) - 1
        return calendar.date(byAdding: .day, value: -back, to: start) ?? start
    }
}

/// `RecurrenceMath.nextOccurrence`, for callers that want a plain function.
public func nextOccurrence(after: Date, recurrence: Recurrence, anchor: Date, calendar: Calendar) -> Date? {
    RecurrenceMath.nextOccurrence(after: after, recurrence: recurrence, anchor: anchor, calendar: calendar)
}

extension Calendar {
    /// `day` at a wall-clock time. A time that daylight saving skips (02:30) moves forward with its
    /// minutes (03:30); a time that happens twice (01:30) is the first one.
    func wallClock(on day: Date, hour: Int, minute: Int, second: Int = 0) -> Date {
        var c = dateComponents([.year, .month, .day], from: day)
        c.hour = hour
        c.minute = minute
        c.second = second
        return date(from: c) ?? day
    }
}
