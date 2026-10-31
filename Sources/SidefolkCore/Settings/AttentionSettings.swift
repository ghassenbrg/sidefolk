import Foundation

/// Open, Focus or Quiet (D84): how much may reach the person right now. Focus holds whispers and lets cards that need
/// an answer through; Quiet lets only what can't wait through, silently. Quiet wins when both apply.
public enum AttentionMode: String, Codable, Sendable, CaseIterable {
    case open, focus, quiet
}

/// What a full-screen app (a presentation, a game, a video call) does to interruptions (D84). Quiet, as before.
public enum FullScreenRule: String, Codable, Sendable, CaseIterable {
    case quiet, focus, nothing
}

/// Quiet every day between two times, across midnight when the end is earlier than the start (D84). Off until the
/// person turns it on; minutes since midnight, in the Mac's time zone.
public struct QuietHours: Codable, Sendable, Equatable {
    public var on = false
    public var start = 22 * 60
    public var end = 8 * 60

    public init(on: Bool = false, start: Int = 22 * 60, end: Int = 8 * 60) {
        self.on = on
        self.start = start
        self.end = end
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = (try? c.decode(Bool.self, forKey: .on)) ?? false
        start = Self.clamp((try? c.decode(Int.self, forKey: .start)) ?? 22 * 60)
        end = Self.clamp((try? c.decode(Int.self, forKey: .end)) ?? 8 * 60)
    }

    private static func clamp(_ minutes: Int) -> Int { min(max(minutes, 0), 24 * 60 - 1) }

    /// Whether `date` falls in the quiet hours (always false while they're off, or when start and end are the same).
    public func contains(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard on, start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    /// The next start or end after `date`, so the app can look again then.
    public func nextBoundary(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard on, start != end else { return nil }
        return [start, end].compactMap { minutes in
            calendar.nextDate(after: date, matching: DateComponents(hour: minutes / 60, minute: minutes % 60),
                              matchingPolicy: .nextTime)
        }.min()
    }
}

extension AppSettings {
    /// Quiet now: turned on until a time (or for good), or inside the quiet hours unless the person chose Open or
    /// Focus for the rest of them.
    public func isQuiet(at now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        (quietUntil ?? .distantPast) > now || inQuietHours(at: now, calendar: calendar)
    }

    private func inQuietHours(at now: Date, calendar: Calendar) -> Bool {
        quietHours.contains(now, calendar: calendar) && (quietHoursSetAside ?? .distantPast) <= now
    }

    /// Focus now, and not Quiet (Quiet lets less through, so it wins).
    public func isFocused(at now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        !isQuiet(at: now, calendar: calendar) && (focusUntil ?? .distantPast) > now
    }

    public func attentionMode(at now: Date, calendar: Calendar = .autoupdatingCurrent) -> AttentionMode {
        isQuiet(at: now, calendar: calendar) ? .quiet : isFocused(at: now, calendar: calendar) ? .focus : .open
    }

    /// When the current Focus or Quiet ends by itself: nil while Open, or when it lasts until turned off. Quiet
    /// hours end at their end; a Quiet turned on inside them ends at the later of the two.
    public func attentionEnds(at now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        switch attentionMode(at: now, calendar: calendar) {
        case .open: return nil
        case .focus: return focusUntil.flatMap { $0 == .distantFuture ? nil : $0 }
        case .quiet:
            let chosen = quietUntil.flatMap { $0 > now ? $0 : nil }
            if chosen == .distantFuture { return nil }
            let hoursEnd = inQuietHours(at: now, calendar: calendar) ? quietHours.nextBoundary(after: now, calendar: calendar) : nil
            return [chosen, hoursEnd].compactMap { $0 }.max()
        }
    }

    /// The next time Open, Focus or Quiet changes by itself (an end, or quiet hours starting or ending), so the
    /// app can tell Attention then.
    public func nextAttentionChange(after now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        [quietUntil, focusUntil, quietHours.nextBoundary(after: now, calendar: calendar)]
            .compactMap { $0 }
            .filter { $0 > now && $0 != .distantFuture }
            .min()
    }

    /// Switches to `mode` until `until` (nil: until turned off). Open ends both; Focus and Quiet replace each other.
    /// Choosing Open or Focus inside the quiet hours sets the rest of them aside; the schedule itself stays.
    public mutating func setAttention(_ mode: AttentionMode, until: Date?, now: Date, calendar: Calendar = .autoupdatingCurrent) {
        switch mode {
        case .open: (quietUntil, focusUntil) = (nil, nil)
        case .focus: (quietUntil, focusUntil) = (nil, until ?? .distantFuture)
        case .quiet: (quietUntil, focusUntil) = (until ?? .distantFuture, nil)
        }
        quietHoursSetAside = mode != .quiet && quietHours.contains(now, calendar: calendar)
            ? quietHours.nextBoundary(after: now, calendar: calendar) : nil
    }
}
