import Foundation

/// Today's line (D58) in numbers: which hours it shows, where each thing sits, and which hours get a label, in points
/// from its leading edge. Pure, so where the rail draws things is tested rather than looked at.
///
/// The rule the rail keeps: a thing's chip starts exactly at its time. Only when the line ends too soon after it for
/// even a short chip does the chip end at its time instead (`endsAtTime`), and the view marks that edge. A chip used to
/// be pushed left to fit whole, so a reminder at 15:00 sat over 12:45.
public enum DayLine {
    /// Something on the line: an event from `start` to `end`, or a reminder (`end == start`), whose words need
    /// `readable` points.
    public struct Item: Sendable, Equatable {
        public var start: Date
        public var end: Date
        public var readable: Double

        public init(start: Date, end: Date, readable: Double) {
            self.start = start
            self.end = end
            self.readable = readable
        }
    }

    public struct Placement: Sendable, Equatable {
        /// Its time on the line: the chip's leading edge, or its trailing one when `endsAtTime`.
        public var at: Double
        /// The chip's leading edge and width.
        public var x: Double
        public var width: Double
        /// How long it lasts, in points (0 for a reminder), drawn on the chip so an event's end is exact too.
        public var length: Double
        public var endsAtTime: Bool
        /// Which row of the line it's on: the first where it covers nothing.
        public var lane: Int
    }

    /// An hour mark, and where its label goes when it has one (labels are left out where they'd touch).
    public struct Tick: Sendable, Equatable {
        public var date: Date
        public var x: Double
        public var labelX: Double?
    }

    /// The shortest chip worth drawing: an icon and a few letters.
    public static let shortestChip: Double = 56
    /// The space kept between two labels, and between two chips on a lane.
    public static let gap: Double = 6

    /// The hours shown: from an hour before now (or the first thing, if earlier) to three hours ahead, or an hour past
    /// the last thing, so its chip has room after its time; whole hours, at least `least`, within the day.
    public static func range(now: Date, starts: [Date], ends: [Date], calendar: Calendar, least: TimeInterval = 6 * 3600) -> ClosedRange<Date> {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let lastStart = starts.max().map { $0.addingTimeInterval(3600) }
        var lower = min(now.addingTimeInterval(-3600), starts.min() ?? now)
        var upper = [now.addingTimeInterval(3 * 3600), ends.max(), lastStart].compactMap { $0 }.max() ?? now
        lower = max(dayStart, hourStart(lower, calendar))
        upper = min(dayEnd, hourStart(upper.addingTimeInterval(3599), calendar))
        if upper.timeIntervalSince(lower) < least {
            upper = min(dayEnd, lower.addingTimeInterval(least))
            lower = max(dayStart, upper.addingTimeInterval(-least))
        }
        return lower...upper
    }

    /// Where a time is on a line `width` points long.
    public static func x(_ date: Date, in span: ClosedRange<Date>, width: Double) -> Double {
        let total = span.upperBound.timeIntervalSince(span.lowerBound)
        return date.timeIntervalSince(span.lowerBound) / max(total, 1) * width
    }

    /// The time at a point of the line.
    public static func time(at x: Double, in span: ClosedRange<Date>, width: Double) -> Date {
        span.lowerBound.addingTimeInterval(x / max(width, 1) * span.upperBound.timeIntervalSince(span.lowerBound))
    }

    /// Each item's chip, in the order given (sort by start first): at its time, as wide as its words or its length,
    /// cut short rather than moved when the line ends, on the first lane where it covers nothing.
    public static func place(_ items: [Item], in span: ClosedRange<Date>, width: Double) -> [Placement] {
        var rights: [Double] = []
        return items.map { item in
            let at = min(max(0, x(item.start, in: span, width: width)), width)
            let length = max(0, min(width, x(item.end, in: span, width: width)) - at)
            let wanted = min(width, max(item.readable, length, shortestChip))
            let room = width - at
            let x: Double, w: Double, flipped: Bool
            if room >= min(wanted, shortestChip) {
                (x, w, flipped) = (at, min(wanted, room), false)
            } else {
                w = min(wanted, max(shortestChip, at))
                (x, flipped) = (max(0, at - w), true)
            }
            let lane: Int
            if let free = rights.firstIndex(where: { $0 + gap <= x }) {
                lane = free
                rights[free] = x + w
            } else {
                lane = rights.count
                rights.append(x + w)
            }
            return Placement(at: at, x: x, width: w, length: length, endsAtTime: flipped, lane: lane)
        }
    }

    /// A mark at every hour; labels every hour, or every 2, 3, 4, 6 or 12 when they'd crowd, on round hours, centred on
    /// their mark, kept inside the line, and left out where one would touch the one before.
    public static func ticks(in span: ClosedRange<Date>, width: Double, labelWidth: Double, calendar: Calendar) -> [Tick] {
        let hours = Int((span.upperBound.timeIntervalSince(span.lowerBound) / 3600).rounded(.down))
        guard hours >= 0, width > 0 else { return [] }
        let perHour = width / Double(max(hours, 1))
        let every = [1, 2, 3, 4, 6, 12].first { Double($0) * perHour >= labelWidth + gap } ?? 24
        var ticks: [Tick] = []
        var lastRight = -Double.infinity
        for k in 0...hours {
            let date = span.lowerBound.addingTimeInterval(Double(k) * 3600)
            let at = x(date, in: span, width: width)
            var label: Double?
            if calendar.component(.hour, from: date) % every == 0, labelWidth <= width {
                let placed = min(max(0, at - labelWidth / 2), width - labelWidth)
                if placed >= lastRight + gap {
                    label = placed
                    lastRight = placed + labelWidth
                }
            }
            ticks.append(Tick(date: date, x: at, labelX: label))
        }
        return ticks
    }

    private static func hourStart(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }
}
