import Foundation
import GRDB

/// A system notification the app can hand to macOS when it quits, so reminders still reach the user.
public struct FallbackNotification: Sendable, Equatable {
    public var id: String
    public var title: String
    public var body: String
    public var date: Date
}

/// Keeps reminders and fires them on time, even after a restart: one timer for the soonest due
/// reminder (no polling), re-armed after every change, wake and clock change.
///
/// The app calls `start()` on launch (reminders that came due while Sidefolk was not running fire once,
/// with "Missed at HH:MM"), `reschedule()` after waking or when the clock or time zone changes,
/// `stop()` and `fallbackNotifications(horizon:)` when quitting.
public actor ReminderScheduler {
    public typealias PromptRunner = @Sendable (Reminder) async -> Void

    /// Attention action ids, as the app and tests answer them.
    public enum ActionID {
        public static let done = "done"
        public static let snooze10 = "snooze10"
        public static let tomorrow = "tomorrow"
    }

    /// Later than this after its time, a reminder is reported as missed.
    static let missedAfter: TimeInterval = 90
    /// Longest single sleep; a guard in case the clock changed without the app telling us.
    static let longestSleep: TimeInterval = 6 * 3600

    private let store: ReminderStore
    private let kv: KVStore
    private let attention: AttentionCenter
    private let events: EventBus
    private let settings: SettingsStore
    private let clock: any Clock
    private let calendar: Calendar
    private let runPrompt: PromptRunner?
    private let brief: MorningBrief?

    private var started = false
    private var timer: Task<Void, Never>?
    private var generation = 0
    private var ticking = false
    private var tickRequested = false

    public init(
        store: ReminderStore, attention: AttentionCenter, events: EventBus, settings: SettingsStore,
        clock: any Clock = SystemClock(), calendar: Calendar = .autoupdatingCurrent,
        brief: MorningBrief? = nil, runPrompt: PromptRunner? = nil
    ) {
        self.store = store
        kv = KVStore(store.db)
        self.attention = attention
        self.events = events
        self.settings = settings
        self.clock = clock
        self.calendar = calendar
        self.brief = brief
        self.runPrompt = runPrompt
    }

    // MARK: Lifecycle

    /// Registers the Done / 10 min / Tomorrow handler, fires what came due while the app was off, and arms the timer.
    public func start() async {
        guard !started else { return }
        started = true
        await attention.onAction(kind: "reminder") { [weak self] item, actionId in
            await self?.answer(item: item, actionId: actionId)
        }
        await tick()
    }

    public func stop() {
        started = false
        timer?.cancel()
        timer = nil
        generation += 1
    }

    /// Fires everything that is due now, then re-arms the timer. Call after any change to reminders,
    /// on wake and on clock or time zone changes.
    public func reschedule() async {
        if started { await tick() }
    }

    /// Fires every reminder due at `clock.now`, runs the morning brief if it is time, and re-arms the timer.
    /// Tests call this directly instead of waiting for the timer.
    public func tick() async {
        if ticking {
            tickRequested = true
            return
        }
        ticking = true
        var prompts: [Reminder] = []
        repeat {
            tickRequested = false
            await realignTimeZones()
            do {
                let now = clock.now
                for due in try await store.pending() where (due.nextDue ?? .distantFuture) <= now {
                    if let firing = try await fire(due.id, now: now), let prompt = await present(firing) { prompts.append(prompt) }
                }
            } catch {
                Log.shared.warning("reminders", "Checking due reminders failed", ["error": String(describing: error)])
            }
            _ = await brief?.runIfDue(now: clock.now)
        } while tickRequested
        ticking = false
        await armTimer()
        if let runPrompt {
            for reminder in prompts { await runPrompt(reminder) }
        }
    }

    // MARK: Changes

    /// Saves a new reminder. `anchor` is the start of a repeating series when it differs from `date`
    /// (WhenResult.anchor), which keeps "the 31st" on the 31st in short months.
    @discardableResult
    public func create(
        title: String, at date: Date, recurrence: Recurrence? = nil, anchor: Date? = nil, notes: String? = nil,
        level: AttentionLevel = .attention, action: ReminderAction? = nil, source: String = "user", itemId: String? = nil
    ) async throws -> Reminder {
        let clean = title.clipped(200)
        guard !clean.isEmpty else { throw UserFacingError("A reminder needs something to remind you about.") }
        let now = clock.now
        guard date > now.addingTimeInterval(-5) else {
            throw UserFacingError("That time has already passed.", recovery: "Pick a time in the future.")
        }
        var reminder = Reminder(title: clean, notes: notes?.clipped(1000), fireAt: date, timezone: calendar.timeZone.identifier,
                                recurrence: recurrence, level: level, action: action, source: source, now: now)
        if reminder.notes?.isEmpty == true { reminder.notes = nil }
        reminder.itemId = itemId
        try await store.save(reminder)
        if recurrence != nil { try? await kv.set(Self.anchorKey(reminder.id), (anchor ?? date).timeIntervalSince1970) }
        events.changed(.reminders)
        await reschedule()
        return reminder
    }

    /// Cancels a reminder (and, for a repeating one, the whole series). Returns how it was before, for Undo.
    @discardableResult
    public func cancel(id: String) async throws -> Reminder? {
        let changed = try await update(id) { r in
            guard r.state != .cancelled else { return false }
            r.state = .cancelled
            r.snoozedUntil = nil
            return true
        }
        try? await kv.remove(Self.anchorKey(id))
        await finishChange()
        return changed?.before
    }

    /// Marks a reminder done. A repeating reminder is not ended: Done answers this time only and
    /// clears a snooze; use `cancel` to stop the series.
    @discardableResult
    public func complete(id: String) async throws -> Reminder? {
        let changed = try await update(id) { r in
            if r.recurrence != nil {
                guard r.state == .snoozed else { return false }
                r.state = .scheduled
            } else {
                guard r.state != .done, r.state != .cancelled else { return false }
                r.state = .done
            }
            r.snoozedUntil = nil
            return true
        }
        await finishChange()
        return changed?.before
    }

    /// Postpones a reminder to `until`. Returns how it was before, for Undo.
    @discardableResult
    public func snooze(id: String, until: Date) async throws -> Reminder? {
        guard until > clock.now else { throw UserFacingError("Snooze needs a time in the future.") }
        let changed = try await update(id) { r in
            guard r.state == .scheduled || r.state == .snoozed || r.state == .fired else { return false }
            r.state = .snoozed
            r.snoozedUntil = until
            return true
        }
        await finishChange()
        return changed?.before
    }

    /// Puts a reminder back exactly as it was (the Undo of cancel, done and snooze).
    public func restore(_ reminder: Reminder) async throws {
        try await store.save(reminder)
        if reminder.recurrence != nil, reminder.state != .cancelled, reminder.state != .done {
            let existing = try? await kv.get(Self.anchorKey(reminder.id), as: Double.self)
            if existing == nil { try? await kv.set(Self.anchorKey(reminder.id), reminder.fireAt.timeIntervalSince1970) }
        }
        await finishChange()
    }

    // MARK: Reading

    /// Reminders still waiting, soonest first.
    public func upcoming() async -> [Reminder] { (try? await store.pending()) ?? [] }

    /// Recently fired, done or cancelled reminders.
    public func recent(limit: Int = 20) async -> [Reminder] { (try? await store.recentlyFinished(limit: limit)) ?? [] }

    /// By full id or an unambiguous prefix of at least 6 characters (what a model copies from a list).
    public func reminder(matching id: String) async -> Reminder? {
        let wanted = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        if let exact = try? await store.reminder(id: wanted) { return exact }
        guard wanted.count >= 6, let all = try? await store.all(limit: 1000) else { return nil }
        let matches = all.filter { $0.id.hasPrefix(wanted) }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Notifications for macOS to deliver while Sidefolk is not running: the next occurrence of every
    /// pending reminder inside `horizon`, plus a few more for repeating ones.
    public func fallbackNotifications(horizon: TimeInterval = 7 * 86400, limit: Int = 60) async -> [FallbackNotification] {
        let now = clock.now
        let end = now.addingTimeInterval(horizon)
        var out: [FallbackNotification] = []
        for r in await upcoming() {
            guard let due = r.nextDue, due <= end else { continue }
            let body = r.notes ?? "Reminder"
            var when = max(due, now.addingTimeInterval(2))
            out.append(FallbackNotification(id: r.id, title: r.title, body: body, date: when))
            guard let rule = r.recurrence else { continue }
            let anchor = await seriesAnchor(for: r)
            for k in 1...12 {
                guard let next = RecurrenceMath.nextOccurrence(after: when, recurrence: rule, anchor: anchor, calendar: calendar), next <= end else { break }
                when = next
                out.append(FallbackNotification(id: "\(r.id)#\(k)", title: r.title, body: body, date: next))
            }
        }
        return Array(out.sorted { $0.date < $1.date }.prefix(limit))
    }

    // MARK: Firing

    private struct Firing {
        var reminder: Reminder
        var dueAt: Date
        var missed: Bool
    }

    /// Atomically marks one due reminder as fired (or moves a repeating one to its next time).
    /// Two overlapping ticks cannot fire the same reminder twice: the check and the change are one transaction.
    private func fire(_ id: String, now: Date) async throws -> Firing? {
        guard let current = try await store.reminder(id: id) else { return nil }
        let anchor = await seriesAnchor(for: current)
        let cal = calendar
        let missedAfter = Self.missedAfter
        let outcome = try await store.db.writer.write { db -> Firing? in
            guard var r = try Reminder.fetchOne(db, key: id), r.state == .scheduled || r.state == .snoozed,
                  let due = r.nextDue, due <= now else { return nil }
            if let rule = r.recurrence {
                // A snoozed occurrence keeps the series' next time; otherwise move to the first time after now
                // (a series that was missed several times fires once).
                let keepsNext = r.state == .snoozed && r.fireAt > now
                let next = keepsNext ? r.fireAt : RecurrenceMath.nextOccurrence(after: now, recurrence: rule, anchor: anchor, calendar: cal)
                if let next {
                    r.fireAt = next
                    r.state = .scheduled
                } else {
                    r.state = .fired
                }
            } else {
                r.state = .fired
            }
            r.snoozedUntil = nil
            r.lastFiredAt = now
            r.firedCount += 1
            r.updatedAt = now
            try r.update(db)
            return Firing(reminder: r, dueAt: due, missed: now.timeIntervalSince(due) > missedAfter)
        }
        if let outcome, outcome.reminder.state == .fired { try? await kv.remove(Self.anchorKey(id)) }
        events.changed(.reminders)
        return outcome
    }

    /// Tells the user. Returns the reminder when it is a routine for the app's agent to run instead.
    private func present(_ firing: Firing) async -> Reminder? {
        let r = firing.reminder
        if r.action?.kind == .prompt, runPrompt != nil { return r }
        var lines: [String] = []
        if firing.missed { lines.append(missedText(firing.dueAt)) }
        if let notes = r.notes, !notes.isEmpty { lines.append(notes) }
        await attention.post(AttentionRequest(
            level: r.level, source: "reminder", title: r.title, body: lines.isEmpty ? nil : lines.joined(separator: "\n"),
            actions: [
                AttentionAction(id: ActionID.done, title: "Done", isPrimary: true),
                AttentionAction(id: ActionID.snooze10, title: "10 min"),
                AttentionAction(id: ActionID.tomorrow, title: "Tomorrow"),
            ],
            refKind: "reminder", refId: r.id
        ))
        return nil
    }

    private func missedText(_ due: Date) -> String {
        let now = clock.now
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: due), to: calendar.startOfDay(for: now)).day ?? 0
        let time = TimeFormat.clock(due, calendar: calendar)
        switch days {
        case ...0: return "Missed at \(time)"
        case 1: return "Missed yesterday \(time)"
        default: return "Missed \(TimeFormat.day(due, now: due, calendar: calendar)) \(time)"
        }
    }

    // MARK: Answers from the bubble or a notification

    private func answer(item: AttentionItem, actionId: String) async {
        guard let id = item.refId else { return }
        do {
            switch actionId {
            case ActionID.done: try await complete(id: id)
            case ActionID.snooze10: try await snooze(id: id, until: clock.now.addingTimeInterval(600))
            case ActionID.tomorrow: try await snooze(id: id, until: tomorrowMorning())
            default: break
            }
        } catch {
            Log.shared.warning("reminders", "Could not apply \(actionId)", ["error": String(describing: error)])
        }
    }

    /// Tomorrow at the configured morning hour.
    func tomorrowMorning() -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: clock.now)) ?? clock.now.addingTimeInterval(86400)
        return calendar.wallClock(on: tomorrow, hour: settings.current.morningHour, minute: 0)
    }

    // MARK: Timer

    private func armTimer() async {
        timer?.cancel()
        timer = nil
        generation += 1
        guard started else { return }
        let now = clock.now
        var next = (try? await store.pending())?.compactMap(\.nextDue).min()
        if let briefAt = await brief?.nextRun(after: now) { next = min(next ?? briefAt, briefAt) }
        guard let next else { return }
        let delay = min(max(0, next.timeIntervalSince(now)), Self.longestSleep)
        let mine = generation
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.timerFired(generation: mine)
        }
    }

    private func timerFired(generation fired: Int) async {
        guard fired == generation, started else { return }
        await tick()
    }

    // MARK: Storage helpers

    static func anchorKey(_ id: String) -> String { "reminder.anchor.\(id)" }

    /// Start of a repeating series (see `create`); falls back to the current time for reminders without one.
    private func storedAnchor(for r: Reminder) async -> Date {
        if r.recurrence != nil, let t = try? await kv.get(Self.anchorKey(r.id), as: Double.self) {
            return Date(timeIntervalSince1970: t)
        }
        return r.fireAt
    }

    /// The series anchor as wall-clock time in the current time zone (see `RecurrenceMath.floating`).
    private func seriesAnchor(for r: Reminder) async -> Date {
        let stored = await storedAnchor(for: r)
        guard r.recurrence?.frequency != .hourly, let zone = TimeZone(identifier: r.timezone) else { return stored }
        return RecurrenceMath.floating(stored, from: zone, to: calendar)
    }

    /// After a time zone change, repeating reminders keep their local time: move their next fire accordingly.
    private func realignTimeZones() async {
        let zone = calendar.timeZone.identifier
        let now = clock.now
        guard let pending = try? await store.pending() else { return }
        for r in pending where r.timezone != zone {
            guard let rule = r.recurrence, rule.frequency != .hourly else { continue }
            let anchor = await seriesAnchor(for: r)
            let next = RecurrenceMath.nextOccurrence(after: now, recurrence: rule, anchor: anchor, calendar: calendar) ?? r.fireAt
            _ = try? await update(r.id) { r in
                r.fireAt = next
                r.timezone = zone
                return true
            }
            try? await kv.set(Self.anchorKey(r.id), anchor.timeIntervalSince1970)
        }
    }

    /// Reads, changes and writes a reminder in one transaction. `before` is nil when nothing existed.
    private func update(_ id: String, _ change: @escaping @Sendable (inout Reminder) -> Bool) async throws -> (before: Reminder, after: Reminder)? {
        let now = clock.now
        return try await store.db.writer.write { db -> (before: Reminder, after: Reminder)? in
            guard var r = try Reminder.fetchOne(db, key: id) else { return nil }
            let before = r
            if change(&r) {
                r.updatedAt = now
                try r.update(db)
            }
            return (before, r)
        }
    }

    private func finishChange() async {
        events.changed(.reminders)
        await reschedule()
    }
}
