import Foundation
import Observation
import SidefolkCore

/// Home › Calendar (D66): everything with a time, a month, a week or a few days at once. Your reminders (a repeating
/// one at every time it will fire), the notes and tasks they belong to (D49), what was done or told you on past days,
/// and the Mac calendar's events once you show it (D57, read-only). Changes go through the same paths as Today's:
/// moving is `moveReminder`, adding is `reminders.create` through ToolExecutor, the rest is NowModel's.
@MainActor @Observable
final class CalendarModel {
    enum Mode: String, CaseIterable, Identifiable {
        case month, week, day
        var id: Self { self }
    }

    /// One thing on the calendar.
    enum Entry: Identifiable {
        /// A time a pending reminder comes due.
        case reminder(ReminderOccurrence)
        /// A reminder that was done, or told you, at `at`.
        case finished(Reminder, at: Date)
        case event(CalendarEvent)

        var id: String {
            switch self {
            case .reminder(let o): "r" + o.id
            case .finished(let r, _): "f" + r.id
            case .event(let e): "e" + e.id
            }
        }
        var start: Date {
            switch self {
            case .reminder(let o): o.at
            case .finished(_, let at): at
            case .event(let e): e.start
            }
        }
        /// A reminder is a moment; it ends where it starts.
        var end: Date {
            if case .event(let e) = self { return e.end }
            return start
        }
        var title: String {
            switch self {
            case .reminder(let o): o.reminder.title
            case .finished(let r, _): r.title
            case .event(let e): e.title
            }
        }
        var allDay: Bool { if case .event(let e) = self { e.allDay } else { false } }
        var reminder: Reminder? {
            switch self {
            case .reminder(let o): o.reminder
            case .finished(let r, _): r
            case .event: nil
            }
        }
        /// Its next time: the only one that can be dragged elsewhere (a series' later times are where it will fall).
        var movable: Bool { if case .reminder(let o) = self { o.isNext } else { false } }
    }

    var mode: Mode = .month {
        didSet { if mode != oldValue { Task { await reload() } } }
    }
    /// The day in view: the month or week it's in, or the first day of the list.
    private(set) var anchor = Date()
    private(set) var entries: [Entry] = []
    /// The notes and tasks the shown reminders belong to (D49), by id.
    private(set) var items: [String: NotebookItem] = [:]
    /// What the last move or add couldn't do.
    var problem: UserFacingError?

    let services: AppServices
    /// Today's model: editing, ticking, snoozing and opening a reminder's note work as they do there.
    let now: NowModel
    private var runtime: SidefolkRuntime { services.runtime }
    var calendar: Calendar { .autoupdatingCurrent }
    var calendarOn: Bool { runtime.calendarReader.isOn }

    /// How many days the list shows from its first.
    static let listDays = 14

    init(services: AppServices, now: NowModel) {
        self.services = services
        self.now = now
    }

    // MARK: What's in view

    /// The days on screen: whole weeks of the month, the week, or the list's days.
    var days: [Date] {
        switch mode {
        case .month: CalendarGrid.monthDays(of: anchor, calendar: calendar)
        case .week: CalendarGrid.weekDays(of: anchor, calendar: calendar)
        case .day:
            (0..<Self.listDays).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: anchor)) }
        }
    }

    /// "November 2026", "26 Oct – 1 Nov 2026"; the list's two weeks the same way.
    var title: String {
        switch mode {
        case .month: return anchor.formatted(.dateTime.month(.wide).year())
        case .week, .day:
            let days = self.days
            guard let first = days.first, let last = days.last else { return "" }
            return (first..<last).formatted(.interval.day().month(.abbreviated).year())
        }
    }

    /// One step back or ahead: a month, a week or a day.
    func go(_ step: Int) {
        let unit: Calendar.Component = switch mode {
        case .month: .month
        case .week: .weekOfYear
        case .day: .day
        }
        anchor = calendar.date(byAdding: unit, value: step, to: anchor) ?? anchor
        Task { await reload() }
    }

    func today() { jump(to: Date()) }

    /// The month, week or list that has this day.
    func jump(to day: Date) {
        anchor = day
        Task { await reload() }
    }

    /// A day's own view: the list from that day.
    func show(day: Date) {
        anchor = day
        if mode == .day { Task { await reload() } } else { mode = .day }
    }

    /// What's on a day, all-day events first, then by time.
    func entries(on day: Date) -> [Entry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let those = entries.filter { $0.allDay ? ($0.start < end && $0.end > start) : ($0.start >= start && $0.start < end) }
        return those.filter(\.allDay) + those.filter { !$0.allDay }
    }

    func item(of reminder: Reminder) -> NotebookItem? { reminder.itemId.flatMap { items[$0] } }

    func reload() async {
        let days = self.days
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        let rt = runtime
        let due = await rt.scheduler.occurrences(from: first, to: end).map(Entry.reminder)
        let finished = ((try? await rt.reminderStore.finished(from: first, to: end)) ?? [])
            .map { Entry.finished($0, at: $0.lastFiredAt ?? $0.fireAt) }
        let events = (await rt.calendarReader.events(from: first, to: end) ?? []).map(Entry.event)
        entries = (due + finished + events).sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        let ids = Set(entries.compactMap { $0.reminder?.itemId })
        let found = ids.isEmpty ? [] : ((try? await rt.notebook.items(ids: Array(ids))) ?? [])
        items = Dictionary(found.filter { $0.deletedAt == nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Changes

    /// Shows the calendar's events too; macOS asks the first time (D57).
    func showCalendar() async {
        await services.showCalendar(true)
        await now.reload()
        await reload()
    }

    /// Moves a reminder's next time, as dragging it on Today's line does, and lets ⌘Z put it back while that time is
    /// still to come. Never into the past.
    func move(_ reminder: Reminder, from due: Date, to target: Date, undo: UndoManager?) async {
        guard target > Date() else {
            problem = UserFacingError("That time has already passed.", recovery: "Pick a time in the future.")
            return
        }
        guard abs(target.timeIntervalSince(due)) >= 60 else { return }
        problem = await services.moveReminder(reminder.id, to: target)
        await reload()
        guard problem == nil, let undo else { return }
        undo.registerUndo(withTarget: self) { model in
            guard due > Date() else { return }
            Task { @MainActor in
                _ = await model.services.moveReminder(reminder.id, to: due)
                await model.reload()
            }
        }
        undo.setActionName(String(localized: "Move Reminder"))
    }

    /// A reminder dropped on a day (keeping its time of day) or at a time.
    func drop(_ reminderId: String, on day: Date, at time: Date? = nil, undo: UndoManager?) async {
        guard let entry = entries.first(where: { $0.movable && $0.reminder?.id == reminderId }), let reminder = entry.reminder else { return }
        let target: Date
        if let time {
            target = time
        } else {
            let clock = calendar.dateComponents([.hour, .minute], from: entry.start)
            target = calendar.date(bySettingHour: clock.hour ?? 9, minute: clock.minute ?? 0, second: 0, of: day) ?? day
        }
        await move(reminder, from: entry.start, to: target, undo: undo)
    }

    /// A new reminder at a time, the way the one bar or Today's row adds one: `reminders.create` through Guard.
    func add(_ title: String, at date: Date) async -> UserFacingError? {
        let words = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        // An exact time the parser reads as is (ISO 8601, in UTC), whatever the language.
        let error = await services.createReminder(title: words, when: date.ISO8601Format())
        if error == nil { await reload() }
        return error
    }

    /// Where a double-click on a day (not at a time) puts a new reminder: the morning, or the next hour today.
    func newTime(on day: Date) -> Date {
        let morning = calendar.date(bySettingHour: runtime.settings.current.morningHour, minute: 0, second: 0, of: day) ?? day
        guard calendar.isDateInToday(day), morning < Date() else { return morning }
        let next = calendar.dateInterval(of: .hour, for: Date())?.end ?? Date()
        return calendar.isDate(next, inSameDayAs: day) ? next : Date().addingTimeInterval(900)
    }
}
