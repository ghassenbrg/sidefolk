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
}
