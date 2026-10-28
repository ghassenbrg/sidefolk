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
        /// Ends a series (offered on reminders that repeat within the hour).
        public static let stop = "stop"
        /// A reminder that belongs to a task: marks the task done, which ends its reminders (D49).
        public static let taskDone = "taskDone"
        /// A reminder that belongs to a note or task: the app opens it in the Notebook.
        public static let open = "open"
    }

    /// Later than this after its time, a reminder is reported as missed.
    static let missedAfter: TimeInterval = 90
    /// Longest single sleep; a guard in case the clock changed without the app telling us.
    static let longestSleep: TimeInterval = 6 * 3600

    let store: ReminderStore
    private let kv: KVStore
    let attention: AttentionCenter
    let events: EventBus
    private let settings: SettingsStore
    let clock: any Clock
    let calendar: Calendar
    private let runPrompt: PromptRunner?
    private let brief: MorningBrief?

    private var started = false
    private var timer: Task<Void, Never>?
    private var generation = 0
    private var ticking = false
    private var tickRequested = false
    /// Settles reminders that belong to notebook items whenever the notebook changes (ReminderLinks).
    private var links: Task<Void, Never>?

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
        let stream = events.stream()
        links = Task { [weak self] in
            for await event in stream {
                if case .dataChanged(.notebook) = event { await self?.settleLinks() }
            }
        }
        await settleLinks()
        await tick()
    }

    public func stop() {
        started = false
        timer?.cancel()
        timer = nil
        links?.cancel()
        links = nil
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
    /// Only the user's own reminders ("user", or "user:agent" from a clean agent turn) may be critical:
    /// anyone else's is stored as an ordinary alert, whatever the caller asked (SECURITY T24).
    /// `itemId` is the note or task it belongs to (D49); the caller checks the item is there and still open.
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
        let level = Self.isUsersOwn(source) ? level : min(level, .attention)
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
            guard r.state != .cancelled || r.endedWithItem != nil else { return false }
            r.state = .cancelled
            r.snoozedUntil = nil
            // The person's own word: it no longer comes back with its item.
            r.endedWithItem = nil
            return true
        }
        // The series anchor stays, as the row does: Undo (`restore`) must bring a monthly reminder back
        // on its own day. After a short month `fireAt` alone would turn "the 31st" into "the 30th".
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
            r.endedWithItem = nil
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

    /// Changes a reminder's title and/or time (and repeat). Returns how it was before, for Undo.
    @discardableResult
    public func edit(id: String, title: String?, fireAt: Date?, recurrence: Recurrence??) async throws -> Reminder? {
        if let fireAt, fireAt <= clock.now { throw UserFacingError("That time has already passed.", recovery: "Pick a time in the future.") }
        let changed = try await update(id) { r in
            guard r.state != .cancelled, r.state != .done else { return false }
            if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { r.title = title.clipped(200) }
            if let fireAt {
                r.fireAt = fireAt
                r.state = .scheduled
                r.snoozedUntil = nil
            }
            if let recurrence { r.recurrence = recurrence }
            return true
        }
        if let fireAt, recurrence != nil { try? await kv.set(Self.anchorKey(id), fireAt.timeIntervalSince1970) }
        await finishChange()
        return changed?.before
    }

    /// Puts a reminder back exactly as it was (the Undo of cancel, done and snooze), series anchor
    /// included: `cancel` keeps it. Only a series that lost it (cancelled by an older version) restarts
    /// from its next time.
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
            let body = r.notes ?? String(localized: "Reminder")
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
            // Its task was done or its item trashed a moment ago, and the notebook's word hasn't been settled yet.
            if let itemId = r.itemId, let reason = Self.endReason(try NotebookItem.fetchOne(db, key: itemId)) {
                Self.end(&r, with: reason)
                r.updatedAt = now
                try r.update(db)
                return nil
            }
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
        let own = Self.isUsersOwn(r.source)
        let item = await linkedItem(r)
        var lines: [String] = []
        if firing.missed { lines.append(missedText(firing.dueAt)) }
        if let item, let line = Self.itemLine(item, reminder: r) { lines.append(line) }
        if let notes = r.notes, !notes.isEmpty { lines.append(notes) }
        // "You asked yesterday 18:20." — context for one-off reminders set a while ago.
        if r.recurrence == nil, !firing.missed, firing.dueAt.timeIntervalSince(r.createdAt) > 120 {
            lines.append(askedText(r.createdAt, own: own))
        }
        if let rule = r.recurrence {
            // The last time's notice is old news now: one "Stretch" waits for an answer, not twelve.
            await attention.withdraw(refKind: "reminder", refId: r.id)
            // Every few minutes or hours: say why it keeps coming, and offer to stop it right here.
            if rule.frequency.isElapsed { lines.append(TimeFormat.recurrence(rule, now: clock.now, calendar: calendar).capitalizedFirst) }
        }
        await attention.post(AttentionRequest(
            level: r.level, source: Self.attentionSource(r.source), title: r.title, body: lines.isEmpty ? nil : lines.joined(separator: "\n"),
            actions: Self.actions(for: r, item: item), refKind: "reminder", refId: r.id
        ))
        return nil
    }

    /// Done, 10 min, Tomorrow; a reminder that comes back within the hour offers Stop instead of Tomorrow, and drops
    /// "10 min" when it repeats that often anyway. One that belongs to a note or task (D49) offers Open as its third
    /// button (a bubble shows three), and for an open task its first button marks the task done.
    static func actions(for r: Reminder, item: NotebookItem? = nil) -> [AttentionAction] {
        var actions = [AttentionAction(id: ActionID.done, title: String(localized: "Done"), isPrimary: true)]
        if let rule = r.recurrence, rule.frequency.isElapsed {
            if rule.frequency == .hourly || rule.interval > 10 {
                actions.append(AttentionAction(id: ActionID.snooze10, title: String(localized: "10 min")))
            }
            actions.append(AttentionAction(id: ActionID.stop, title: String(localized: "Stop repeating")))
        } else {
            actions.append(AttentionAction(id: ActionID.snooze10, title: String(localized: "10 min")))
            actions.append(AttentionAction(id: ActionID.tomorrow, title: String(localized: "Tomorrow")))
        }
        guard let item else { return actions }
        if item.kind == .task, item.status == .open {
            actions[0] = AttentionAction(id: ActionID.taskDone, title: String(localized: "Mark done"), isPrimary: true)
        }
        let second = actions.first { $0.id == ActionID.stop } ?? actions[1]
        return [actions[0], second, AttentionAction(id: ActionID.open, title: String(localized: "Open"))]
    }

    private func missedText(_ due: Date) -> String {
        let now = clock.now
        let time = TimeFormat.clock(due, calendar: calendar)
        switch daysAgo(due, now: now) {
        case ...0: return String(localized: "Missed at \(time)")
        case 1: return String(localized: "Missed yesterday \(time)")
        default: return String(localized: "Missed \(TimeFormat.day(due, now: now, calendar: calendar)) \(time)", comment: "A day like “Nov 12”, then a time")
        }
    }

    /// "You asked yesterday 18:20.": context for a one-off reminder set a while ago, or who else set it.
    private func askedText(_ created: Date, own: Bool) -> String {
        let now = clock.now
        let time = TimeFormat.clock(created, calendar: calendar)
        switch daysAgo(created, now: now) {
        case ...0:
            return own ? String(localized: "You asked today \(time).") : String(localized: "Another app or agent set this today \(time).")
        case 1:
            return own ? String(localized: "You asked yesterday \(time).") : String(localized: "Another app or agent set this yesterday \(time).")
        default:
            let day = TimeFormat.day(created, now: now, calendar: calendar)
            return own ? String(localized: "You asked \(day) \(time).", comment: "A day like “Nov 12”, then a time")
                : String(localized: "Another app or agent set this \(day) \(time).", comment: "A day like “Nov 12”, then a time")
        }
    }

    private func daysAgo(_ date: Date, now: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    }

    // MARK: Answers from the bubble or a notification

    private func answer(item: AttentionItem, actionId: String) async {
        guard let id = item.refId else { return }
        do {
            switch actionId {
            case ActionID.done: try await complete(id: id)
            case ActionID.snooze10: try await snooze(id: id, until: clock.now.addingTimeInterval(600))
            case ActionID.tomorrow: try await snooze(id: id, until: tomorrowMorning())
            case ActionID.stop: try await cancel(id: id)
            case ActionID.taskDone: try await finishTask(reminderId: id)
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

    // MARK: Provenance

    /// The user's own reminders: set by them, or by Sidefolk's agent in a clean turn ("user:agent").
    static func isUsersOwn(_ source: String) -> Bool { ContextBuilder.isUserSourced(source) }

    /// The attention source a reminder fires under. Only the user's own use "reminder", which arrives on
    /// time past the spacing rule and may be critical (AttentionPolicy); another agent's, an extension's
    /// or a tainted turn's ("reminder:external", "reminder:agent"…) takes its turn like any other notice.
    /// The bubble's look and buttons key on `refKind`, which stays "reminder".
    static func attentionSource(_ source: String) -> String {
        isUsersOwn(source) ? "reminder" : "reminder:" + (source.split(separator: ":").first.map(String.init) ?? "other")
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
    func seriesAnchor(for r: Reminder) async -> Date {
        let stored = await storedAnchor(for: r)
        guard r.recurrence?.frequency.isElapsed != true, let zone = TimeZone(identifier: r.timezone) else { return stored }
        return RecurrenceMath.floating(stored, from: zone, to: calendar)
    }

    /// After a time zone change, repeating reminders keep their local time: move their next fire accordingly.
    private func realignTimeZones() async {
        let zone = calendar.timeZone.identifier
        let now = clock.now
        guard let pending = try? await store.pending() else { return }
        for r in pending where r.timezone != zone {
            guard let rule = r.recurrence, !rule.frequency.isElapsed else { continue }
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
    func update(_ id: String, _ change: @escaping @Sendable (inout Reminder) -> Bool) async throws -> (before: Reminder, after: Reminder)? {
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

    func finishChange() async {
        events.changed(.reminders)
        await reschedule()
    }
}
