import Foundation

/// A short, deterministic good-morning note: today's calendar (when shown, D57), reminders, open tasks, watchers on duty.
/// No AI. Shown once a day at the morning hour, only when there is something worth saying, and
/// never twice (the day it was shown is stored, so restarting the app does not repeat it).
///
/// `ReminderScheduler` runs it from its single timer; give the scheduler this object.
public actor MorningBrief {
    public struct Content: Sendable, Equatable {
        public var title: String
        public var body: String
        public var reminders: Int
        public var events: Int = 0
        public var openTasks: Int
        public var watchers: Int
    }

    /// The brief still makes sense this long after the morning hour (the app may start a little late).
    static let grace: TimeInterval = 4 * 3600
    static let lastDayKey = "morningbrief.lastDay"
    private static let listed = 5

    private let reminders: ReminderStore
    private let notebook: NotebookStore
    private let watchers: WatcherStore
    private let kv: KVStore
    private let attention: AttentionCenter
    private let settings: SettingsStore
    private let clock: any Clock
    private let calendar: Calendar
    /// The day's calendar events, empty while the calendar is off.
    private let events: @Sendable (Date) async -> [CalendarEvent]

    public init(db: AppDatabase, attention: AttentionCenter, settings: SettingsStore,
                clock: any Clock = SystemClock(), calendar: Calendar = .autoupdatingCurrent,
                events: @escaping @Sendable (Date) async -> [CalendarEvent] = { _ in [] }) {
        reminders = ReminderStore(db)
        notebook = NotebookStore(db)
        watchers = WatcherStore(db)
        kv = KVStore(db)
        self.attention = attention
        self.settings = settings
        self.clock = clock
        self.calendar = calendar
        self.events = events
    }

    /// What the brief would say right now, or nil when there is nothing worth saying
    /// (watchers alone are not worth an interruption).
    public func compose(now: Date) async -> Content? {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let today = ((try? await reminders.pending()) ?? []).filter { r in
            guard let due = r.nextDue else { return false }
            return due >= start && due < end
        }
        let tasks = ((try? await notebook.items(kinds: [.task], status: .open, limit: 1000)) ?? []).count
        let watching = ((try? await watchers.active()) ?? []).count
        let meetings = await events(now)
        guard !today.isEmpty || tasks > 0 || !meetings.isEmpty else { return nil }

        // The day in time order: events and reminders together, the way Today shows them.
        let timed = meetings.map { e in (e.allDay ? start : e.start, e.allDay ? "· \(e.title)" : "\(TimeFormat.clock(e.start, calendar: calendar)) \(e.title)") }
            + today.map { r in (r.nextDue ?? r.fireAt, "\(TimeFormat.clock(r.nextDue ?? r.fireAt, calendar: calendar)) \(r.title)") }
        let ordered = timed.sorted { $0.0 < $1.0 }.map(\.1)
        var lines = Array(ordered.prefix(Self.listed))
        if ordered.count > Self.listed { lines.append(String(localized: "+\(ordered.count - Self.listed) more")) }
        var facts: [String] = []
        if tasks > 0 { facts.append(String(localized: "\(tasks) open tasks")) }
        if watching > 0 { facts.append(String(localized: "\(watching) watchers on duty")) }
        if !facts.isEmpty { lines.append(facts.joined(separator: " · ")) }

        let headline = today.isEmpty ? String(localized: "Good morning") : String(localized: "Good morning · \(today.count) reminders today")
        return Content(title: headline, body: lines.joined(separator: "\n"), reminders: today.count, events: meetings.count, openTasks: tasks,
                       watchers: watching)
    }

    /// The next moment the brief could become due: the coming morning hour, or the following day's if it
    /// was already shown. Always in the future, so a timer armed on it never spins. Nil when the brief is off.
    public func nextRun(after now: Date) async -> Date? {
        guard settings.current.morningBrief else { return nil }
        let todayStart = calendar.startOfDay(for: now)
        let target = morning(on: todayStart)
        if now < target, await lastDay() != dayKey(now) { return target }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86400)
        return morning(on: tomorrow)
    }

    /// Shows the brief if it is due today and has not been shown yet. Returns whether it was shown.
    @discardableResult
    public func runIfDue(now: Date? = nil) async -> Bool {
        guard settings.current.morningBrief else { return false }
        let now = now ?? clock.now
        let key = dayKey(now)
        guard await lastDay() != key else { return false }
        let target = morning(on: calendar.startOfDay(for: now))
        guard now >= target, now < target.addingTimeInterval(Self.grace) else { return false }
        // Mark the day first: a crash between here and the post must not repeat the brief.
        try? await kv.set(Self.lastDayKey, key)
        guard let content = await compose(now: now) else { return false }
        await attention.post(AttentionRequest(
            level: .gentle, source: "brief", title: content.title, body: content.body,
            actions: [AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true)], refKind: "brief"
        ))
        return true
    }

    // MARK: Helpers

    private func morning(on day: Date) -> Date {
        calendar.wallClock(on: day, hour: settings.current.morningHour, minute: 0)
    }

    private func lastDay() async -> String? { try? await kv.get(Self.lastDayKey, as: String.self) }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
