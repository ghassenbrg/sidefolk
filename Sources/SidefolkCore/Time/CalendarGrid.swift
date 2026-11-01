import Foundation

/// The Calendar page's arithmetic (D66): which days a month or a week shows, and how things that overlap in a day
/// share its width. Pure, so it follows the person's first weekday and is tested without drawing.
public enum CalendarGrid {
    /// A month as whole weeks: from the week its 1st is in to the week its last day is in, each starting on the
    /// calendar's first weekday (Monday in France, Sunday in the US).
    public static func monthDays(of date: Date, calendar: Calendar) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let first = weekStart(of: month.start, calendar: calendar)
        let last = calendar.date(byAdding: .second, value: -1, to: month.end) ?? month.end
        let end = calendar.date(byAdding: .day, value: 7, to: weekStart(of: last, calendar: calendar)) ?? last
        var days: [Date] = []
        var day = first
        while day < end, days.count < 42 {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
        }
        return days
    }

    /// The seven days of the week a date is in, from the calendar's first weekday.
    public static func weekDays(of date: Date, calendar: Calendar) -> [Date] {
        let start = weekStart(of: date, calendar: calendar)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The first day of each month of the year a date is in.
    public static func yearMonths(of date: Date, calendar: Calendar) -> [Date] {
        guard let year = calendar.dateInterval(of: .year, for: date) else { return [] }
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: year.start) }
    }

    /// `count` whole weeks from the week `date` is in: the continuous month's rows (D97).
    public static func weeks(from date: Date, count: Int, calendar: Calendar) -> [Date] {
        let start = weekStart(of: date, calendar: calendar)
        return (0..<max(0, count) * 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The month most of these days are in: what a continuous month's title names while it scrolls.
    public static func mainMonth(of days: [Date], calendar: Calendar) -> Date? {
        var counts: [Date: Int] = [:]
        for day in days {
            if let month = calendar.dateInterval(of: .month, for: day)?.start { counts[month, default: 0] += 1 }
        }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key  // a tie: the earlier
    }

    /// Rows for a week's all-day band (D97): each span covers days `first...last` of the week (clipped by the caller);
    /// longer ones first, each in the first row free across all its days, as Calendar stacks them.
    public static func lanes(_ spans: [(first: Int, last: Int)]) -> [Int] {
        let order = spans.indices.sorted {
            let a = spans[$0], b = spans[$1]
            return (a.first, b.last - b.first, $0) < (b.first, a.last - a.first, $1)
        }
        var rows: [[ClosedRange<Int>]] = []
        var result = Array(repeating: 0, count: spans.count)
        for i in order {
            let range = spans[i].first...max(spans[i].first, spans[i].last)
            if let free = rows.firstIndex(where: { $0.allSatisfy { !$0.overlaps(range) } }) {
                rows[free].append(range)
                result[i] = free
            } else {
                result[i] = rows.count
                rows.append([range])
            }
        }
        return result
    }

    public static func weekStart(of date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let back = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    /// Where each of a day's timed things goes across its column, in the order given: things that overlap (directly or
    /// through others) split the width, each in the first free column; a thing alone gets all of it.
    public static func columns(_ spans: [(start: Date, end: Date)]) -> [(column: Int, of: Int)] {
        let order = spans.indices.sorted { (spans[$0].start, spans[$0].end) < (spans[$1].start, spans[$1].end) }
        var result = Array(repeating: (column: 0, of: 1), count: spans.count)
        var group: [Int] = []
        var ends: [Date] = []
        var groupEnd = Date.distantPast
        func close() {
            for i in group { result[i].of = ends.count }
            group = []
            ends = []
        }
        for i in order {
            let span = spans[i]
            if span.start >= groupEnd { close() }
            if let free = ends.firstIndex(where: { $0 <= span.start }) {
                ends[free] = span.end
                result[i].column = free
            } else {
                result[i].column = ends.count
                ends.append(span.end)
            }
            group.append(i)
            groupEnd = group.count == 1 ? span.end : max(groupEnd, span.end)
        }
        close()
        return result
    }

    /// Things that didn't fit across a day's column, counted at a place of their own: the "+N" that opens the day.
    public struct More: Sendable, Equatable {
        /// The earliest of them: where the count goes down the column.
        public var start: Date
        public var count: Int
        public var column: Int
        public var of: Int
    }

    /// `columns`, for a day's column that has room for `maxColumns` across: where an overlap needs more, its first
    /// `maxColumns - 1` columns show, each a `maxColumns`th of the width, and what is beyond them is counted in a "+N"
    /// in the last one. Each thing's place, or nil when it is counted instead.
    public static func fit(_ spans: [(start: Date, end: Date)], maxColumns: Int) -> (placed: [(column: Int, of: Int)?], more: [More]) {
        let all = columns(spans)
        let k = max(1, maxColumns)
        var placed: [(column: Int, of: Int)?] = all.map { $0 }
        var more: [More] = []
        // The things that overlap, as `columns` grouped them: in time order, a group ends where the next starts after it.
        let order = spans.indices.sorted { (spans[$0].start, spans[$0].end) < (spans[$1].start, spans[$1].end) }
        var group: [Int] = [], groupEnd = Date.distantPast
        func close() {
            defer { group = [] }
            guard let first = group.first, all[first].of > k else { return }
            let hidden = group.filter { all[$0].column >= k - 1 }
            for i in group { placed[i] = all[i].column < k - 1 ? (all[i].column, k) : nil }
            more.append(More(start: hidden.map { spans[$0].start }.min() ?? spans[first].start, count: hidden.count, column: k - 1, of: k))
        }
        for i in order {
            if spans[i].start >= groupEnd { close() }
            groupEnd = group.isEmpty ? spans[i].end : max(groupEnd, spans[i].end)
            group.append(i)
        }
        close()
        return (placed, more)
    }
}
