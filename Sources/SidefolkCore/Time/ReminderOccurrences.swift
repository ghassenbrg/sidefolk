import Foundation
import GRDB

/// One time a reminder comes due, as the Calendar shows it (D66).
public struct ReminderOccurrence: Sendable, Hashable, Identifiable {
    public var reminder: Reminder
    public var at: Date
    /// Its next time: the one moving, snoozing or ticking acts on. A repeating reminder's later times only say where
    /// the series will fall.
    public var isNext: Bool

    public var id: String { "\(reminder.id)@\(Int(at.timeIntervalSince1970))" }

    public init(reminder: Reminder, at: Date, isNext: Bool) {
        self.reminder = reminder
        self.at = at
        self.isNext = isNext
    }
}

extension ReminderScheduler {
    /// Every time a pending reminder comes due from `from` up to `to`: its next time (even if already late, when that's
    /// in the range), and a repeating one's later times, at most `limit` each, so "every minute" can't flood a month.
    /// The series math is the scheduler's own (anchor and all), so the Calendar shows what will really fire.
    public func occurrences(from: Date, to: Date, limit: Int = 200) async -> [ReminderOccurrence] {
        var out: [ReminderOccurrence] = []
        for r in await upcoming() {
            guard let due = r.nextDue else { continue }
            var count = 0
            if due >= from, due < to {
                out.append(ReminderOccurrence(reminder: r, at: due, isNext: true))
                count += 1
            }
            guard let rule = r.recurrence else { continue }
            let anchor = await seriesAnchor(for: r)
            // The series goes on after the time it's on now (a snoozed one's own time included).
            var when = max(max(r.fireAt, due), from.addingTimeInterval(-1))
            while count < limit,
                  let next = RecurrenceMath.nextOccurrence(after: when, recurrence: rule, anchor: anchor, calendar: calendar),
                  next < to {
                if next >= from, next != due { out.append(ReminderOccurrence(reminder: r, at: next, isNext: false)) }
                count += 1
                when = next
            }
        }
        return out.sorted { ($0.at, $0.reminder.title) < ($1.at, $1.reminder.title) }
    }
}

extension ReminderStore {
    /// Reminders that told you or were done from `from` up to `to`, by when that was (the Calendar's past days).
    public func finished(from: Date, to: Date) async throws -> [Reminder] {
        try await db.writer.read { db in
            try Reminder.filter(["fired", "done"].contains(Column("state")))
                .filter(sql: "COALESCE(last_fired_at, fire_at) >= ? AND COALESCE(last_fired_at, fire_at) < ?",
                        arguments: [from.timeIntervalSince1970, to.timeIntervalSince1970])
                .fetchAll(db)
        }
    }
}
