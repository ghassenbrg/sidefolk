import Foundation
import Observation
import SidefolkCore

/// Home › Calendar (D66, D97): everything with a time as a day, a week, a month that scrolls on, a year, or the Agenda.
/// Your reminders (a repeating one at every time it will fire), the notes and tasks they belong to (D49), what was done
/// or told you on past days, and the Mac calendar's events in their calendars' colours once you show it (D57). Changes
/// go through the same paths as Today's: moving a reminder is `moveReminder`, adding is `reminders.create` or
/// `notes.save` through ToolExecutor; the Mac's events change only through `calendar.create`, `.update` and `.delete`
/// (D97), and only once the person allowed it.
@MainActor @Observable
final class CalendarModel {
    /// Agenda first (D84), then the four a calendar has (D97).
    enum Mode: String, CaseIterable, Identifiable {
        case agenda, day, week, month, year
        var id: Self { self }

        /// The dev channel's and older words for a mode.
        init?(word: String) {
            self.init(rawValue: word == "list" ? "agenda" : word)
        }

        /// Where a step back or ahead goes, and what a two-finger swipe turns.
        var step: (unit: Calendar.Component, count: Int) {
            switch self {
            case .agenda: (.day, CalendarModel.listDays)
            case .day: (.day, 1)
            case .week: (.weekOfYear, 1)
            case .month: (.month, 1)
            case .year: (.year, 1)
            }
        }
    }

    typealias Entry = CalendarEntry

    var mode: Mode = .agenda {
        didSet {
            guard mode != oldValue else { return }
            if mode == .month { monthTop = CalendarGrid.weekStart(of: monthStart(anchor), calendar: calendar) }
            selection = nil
            inspecting = nil
            let view = mode.rawValue
            remember { $0.view = view }
            Task { await reload() }
        }
    }
    /// The day in view: the day, the week or year it's in, the Agenda's first day, the month's first.
    private(set) var anchor = Date()
    /// The continuous month's first row: the week it starts from, and how far it has scrolled into it (D97).
    private(set) var monthTop = CalendarGrid.weekStart(of: Date(), calendar: .autoupdatingCurrent)
    var monthScroll: CGFloat = 0
    /// Which way the last step went, so the new period slides in from that side.
    private(set) var lastStep = 0
    /// A two-finger swipe in progress: how far the page follows the fingers.
    var swipe: CGFloat = 0

    private(set) var entries: [Entry] = []
    /// `entries` by the day they start (and every day an all-day event covers), so a busy month is one pass.
    private(set) var byDay: [Date: [Entry]] = [:]
    /// The notes and tasks the shown reminders belong to (D49), by id.
    private(set) var items: [String: NotebookItem] = [:]
    /// The person's calendars, for the list and the editor (D97); empty while the calendar is off.
    private(set) var calendars: [CalendarInfo] = []
    /// The Notebook's collections, for a new task.
    private(set) var collections: [NotebookCollection] = []

    /// The selected thing (arrows move it, Return opens it, Delete removes it).
    var selection: String?
    /// The thing whose details are open beside it.
    var inspecting: String?
    /// A new thing being placed: the time dragged or double-clicked, before its editor adds it.
    var draft: CalendarNewDraft?
    /// The first change to the Mac's calendar waits for the person's yes (D97).
    var asksForWrites = false
    private var afterWrites: (() async -> Void)?
    /// What the last change couldn't do.
    var problem: UserFacingError?

    var hourHeight: CGFloat
    var sidebarShown: Bool

    let services: AppServices
    /// Today's model: editing, ticking, snoozing and opening a reminder's note work as they do there.
    let now: NowModel
    var runtime: SidefolkRuntime { services.runtime }
    var calendar: Calendar { .autoupdatingCurrent }
    /// The settings the page draws from, kept here so the page redraws when they change (the store isn't observed).
    private(set) var calendarOn = false
    private(set) var writesOn = false
    private(set) var hidden: Set<String> = []
    /// A reload replaced by a newer one leaves what it read.
    private var generation = 0

    /// How many days the Agenda shows from its first.
    static let listDays = 14
    /// The continuous month's rows on screen, and how many more are read around them so scrolling finds them there.
    static let monthRows = 6
    static let monthMargin = 2

    init(services: AppServices, now: NowModel) {
        self.services = services
        self.now = now
        let page = services.runtime.settings.current.calendarPage
        hidden = page.hidden
        hourHeight = CGFloat(page.hourHeight)
        sidebarShown = page.sidebar
        mode = Mode(word: page.view) ?? .agenda
        monthTop = CalendarGrid.weekStart(of: monthStart(anchor), calendar: calendar)
        listenForChanges()
    }

    // MARK: What's in view

    /// The days on screen: the day, the week, the continuous month's rows, the year's days, the Agenda's two weeks.
    var days: [Date] {
        switch mode {
        case .day: [calendar.startOfDay(for: anchor)]
        case .week: CalendarGrid.weekDays(of: anchor, calendar: calendar)
        case .month: CalendarGrid.weeks(from: monthTop, count: Self.monthRows, calendar: calendar)
        case .year:
            CalendarGrid.yearMonths(of: anchor, calendar: calendar).flatMap { month -> [Date] in
                let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
                return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: month) }
            }
        case .agenda:
            (0..<Self.listDays).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: anchor)) }
        }
    }

    /// What is read: the days on screen, and around the continuous month a margin of weeks to scroll into.
    private var range: (start: Date, end: Date)? {
        let days = mode == .month
            ? CalendarGrid.weeks(from: calendar.date(byAdding: .weekOfYear, value: -Self.monthMargin, to: monthTop) ?? monthTop,
                                 count: Self.monthRows + 2 * Self.monthMargin, calendar: calendar)
            : self.days
        guard let first = days.first, let last = days.last, let end = calendar.date(byAdding: .day, value: 1, to: last) else { return nil }
        return (first, end)
    }

    /// "Sunday 1 November 2026", "November 2026", "2026"; the Agenda's two weeks as a span.
    var title: String {
        switch mode {
        case .day: return anchor.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            let days = self.days
            guard let first = days.first, let last = days.last else { return "" }
            return calendar.isDate(first, equalTo: last, toGranularity: .month)
                ? first.formatted(.dateTime.month(.wide).year())
                : (first..<last).formatted(.interval.month(.abbreviated).year())
        case .month: return shownMonth.formatted(.dateTime.month(.wide).year())
        case .year: return anchor.formatted(.dateTime.year())
        case .agenda:
            let days = self.days
            guard let first = days.first, let last = days.last else { return "" }
            return (first..<last).formatted(.interval.day().month(.abbreviated).year())
        }
    }

    /// The line under the toolbar's title: the Agenda's span, the week's number, or how much is on screen.
    var subtitle: String {
        switch mode {
        case .agenda: return String(localized: "Next \(Self.listDays) days", comment: "Under the Calendar's title")
        case .week:
            let week = calendar.component(.weekOfYear, from: anchor)
            return String(localized: "Week \(week)", comment: "Under the Calendar's title: the week's number in the year")
        case .day, .month, .year:
            let first = days.first ?? anchor
            let end = days.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? anchor
            let count = entries.filter { $0.start >= first && $0.start < end }.count
            return String(localized: "\(count) things", comment: "Under the Calendar's title: how many things are on screen")
        }
    }

    /// The month the continuous month is showing: its days are the bright ones.
    var shownMonth: Date { mode == .month ? CalendarGrid.mainMonth(of: days, calendar: calendar) ?? anchor : monthStart(anchor) }

    /// The day the mini month marks as chosen.
    var chosenDay: Date { calendar.startOfDay(for: anchor) }

    /// What's on a day, all-day events first, then by time.
    func entries(on day: Date) -> [Entry] { byDay[calendar.startOfDay(for: day)] ?? [] }

    func entry(id: String?) -> Entry? { id.flatMap { id in entries.first { $0.id == id } } }

    func item(of reminder: Reminder) -> NotebookItem? { reminder.itemId.flatMap { items[$0] } }

    func kind(_ entry: Entry) -> Entry.Kind { entry.kind(item: entry.reminder.flatMap(item)) }

    func calendarInfo(_ event: CalendarEvent) -> CalendarInfo? { calendars.first { $0.id == event.calendarId } }

    /// The calendars a new event can go in, the default first.
    var writableCalendars: [CalendarInfo] {
        calendars.filter(\.writable).sorted { ($0.isDefault ? 0 : 1, $0.title) < ($1.isDefault ? 0 : 1, $1.title) }
    }

    // MARK: Moving through time

    /// One step back or ahead: a day, a week, a month, a year, or the Agenda's two weeks.
    func go(_ step: Int) {
        let (unit, count) = mode.step
        lastStep = step
        selection = nil
        inspecting = nil
        if mode == .month {
            showMonth(calendar.date(byAdding: .month, value: step, to: monthStart(shownMonth)) ?? shownMonth)
            return
        }
        anchor = calendar.date(byAdding: unit, value: count * step, to: anchor) ?? anchor
        Task { await reload() }
    }

    func today() {
        lastStep = Date() < anchor ? -1 : 1
        jump(to: Date())
    }

    /// The period that has this day.
    func jump(to day: Date) {
        anchor = day
        if mode == .month { showMonth(day); return }
        Task { await reload() }
    }

    /// A day's own view: the Day, from a week's header, a month's "+3 more" or the year.
    func show(day: Date) {
        anchor = day
        if mode == .day { Task { await reload() } } else { mode = .day }
    }

    private func monthStart(_ date: Date) -> Date { calendar.dateInterval(of: .month, for: date)?.start ?? date }

    private func showMonth(_ month: Date) {
        anchor = monthStart(month)
        monthTop = CalendarGrid.weekStart(of: anchor, calendar: calendar)
        monthScroll = 0
        Task { await reload() }
    }

    /// The continuous month scrolled by `delta` points with rows `row` tall: whole rows move its first week, and what
    /// is read follows.
    func scrollMonth(by delta: CGFloat, row: CGFloat) {
        guard row > 0 else { return }
        monthScroll += delta
        var moved = 0
        while monthScroll >= row { monthScroll -= row; moved += 1 }
        while monthScroll < 0 { monthScroll += row; moved -= 1 }
        guard moved != 0 else { return }
        monthTop = calendar.date(byAdding: .weekOfYear, value: moved, to: monthTop) ?? monthTop
        anchor = monthStart(shownMonth)
        Task { await reload() }
    }

    /// Where the month rests when the fingers and their momentum stop: on a whole row.
    func settleMonth(row: CGFloat) {
        guard monthScroll != 0, row > 0 else { return }
        if monthScroll > row / 2 { scrollMonth(by: row - monthScroll, row: row) } else { monthScroll = 0 }
    }

    // MARK: Reading

    func reload() async {
        guard let range else { return }
        generation += 1
        let mine = generation
        let rt = runtime
        let due = await rt.scheduler.occurrences(from: range.start, to: range.end).map(Entry.reminder)
        let finished = ((try? await rt.reminderStore.finished(from: range.start, to: range.end)) ?? [])
            .map { Entry.finished($0, at: $0.lastFiredAt ?? $0.fireAt) }
        let events = (await rt.calendarReader.events(from: range.start, to: range.end) ?? []).map(Entry.event)
        let reminders = due + finished
        let ids = Set(reminders.compactMap { $0.reminder?.itemId })
        let found = ids.isEmpty ? [] : ((try? await rt.notebook.items(ids: Array(ids))) ?? [])
        let calendars = await rt.calendarReader.calendars() ?? []
        guard mine == generation else { return }
        let settings = rt.settings.current
        calendarOn = settings.showCalendar
        writesOn = rt.calendarReader.writesOn
        hidden = settings.calendarPage.hidden
        items = Dictionary(found.filter { $0.deletedAt == nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.calendars = calendars
        let shown = reminders.filter { entry in kind(entry).listId.map { !hidden.contains($0) } ?? true }
        entries = (shown + events).sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        byDay = index(entries)
        if let selection, entry(id: selection) == nil { self.selection = nil }
    }

    /// Each thing under the day it starts, an all-day event under every day it covers; all-day ones first.
    private func index(_ entries: [Entry]) -> [Date: [Entry]] {
        var out: [Date: [Entry]] = [:]
        for entry in entries {
            var day = calendar.startOfDay(for: entry.start)
            if entry.allDay {
                repeat {
                    out[day, default: []].append(entry)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                } while day < entry.end
            } else {
                out[day, default: []].append(entry)
            }
        }
        return out.mapValues { $0.filter(\.allDay) + $0.filter { !$0.allDay } }
    }

    /// The Notebook's collections, for a new task's menu; read when the editor opens.
    func loadCollections() async {
        collections = ((try? await runtime.notebook.collections()) ?? []).filter { $0.kind != .profile }
    }

    /// The Mac's calendar changed (here, in Calendar, or synced from the phone): read it again, once per burst.
    private func listenForChanges() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: MacCalendar.changed).map({ _ in () }) {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                await self.reload()
            }
        }
    }

    // MARK: Selection and the keyboard

    /// What the arrows step through: the things on screen in time order.
    private var ordered: [Entry] {
        let days = self.days
        guard let first = days.first, let last = days.last, let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        return entries.filter { $0.start < end && ($0.end > first || $0.start >= first) }
    }

    /// The next or previous thing; the first still to come when nothing is selected.
    func moveSelection(_ step: Int) {
        let list = ordered
        guard !list.isEmpty else { return }
        if let selection, let at = list.firstIndex(where: { $0.id == selection }) {
            self.selection = list[min(max(at + step, 0), list.count - 1)].id
        } else {
            self.selection = (list.first { $0.start >= Date() } ?? list[0]).id
        }
        inspecting = nil
    }

    /// Return: the selected thing's details.
    func openSelection() {
        guard let selection else { return }
        inspecting = selection
    }

    // MARK: The page's own settings

    func setHidden(_ id: String, _ hide: Bool) {
        if hide { hidden.insert(id) } else { hidden.remove(id) }
        let settings = runtime.settings
        Task {
            // Written before reading again: the reader leaves hidden calendars out.
            await settings.update { if hide { $0.calendarPage.hidden.insert(id) } else { $0.calendarPage.hidden.remove(id) } }
            await reload()
        }
    }

    func setHourHeight(_ height: CGFloat) {
        let bounds = CalendarPageSettings.hourHeights
        hourHeight = min(max(height, CGFloat(bounds.lowerBound)), CGFloat(bounds.upperBound))
    }

    /// The pinch ended: keep the height for next time.
    func keepHourHeight() {
        let height = Double(hourHeight)
        remember { $0.hourHeight = height }
    }

    func toggleSidebar() {
        sidebarShown.toggle()
        let shown = sidebarShown
        remember { $0.sidebar = shown }
    }

    private func remember(_ change: @escaping @Sendable (inout CalendarPageSettings) -> Void) {
        let settings = runtime.settings
        Task { await settings.update { change(&$0.calendarPage) } }
    }

    /// Shows the calendar's events too; macOS asks the first time (D57).
    func showCalendar() async {
        await services.showCalendar(true)
        await now.reload()
        await reload()
    }

    // MARK: Asking before the first change to the Mac's calendar (D97)

    /// Runs a change to the Mac's calendar now if the person allowed changes, else after they say yes in the sheet.
    func whenWritesAllowed(_ change: @escaping () async -> Void) {
        if writesOn {
            Task { await change() }
        } else {
            afterWrites = change
            asksForWrites = true
        }
    }

    func answerWrites(_ allow: Bool) {
        asksForWrites = false
        let next = afterWrites
        afterWrites = nil
        guard allow else { return }
        Task {
            await services.allowCalendarChanges(true)
            await next?()
        }
    }
}

/// A new thing being placed on the Calendar: when, before its editor adds it.
struct CalendarNewDraft: Identifiable, Equatable {
    var start: Date
    var end: Date
    var allDay = false
    /// Opened from the toolbar's +, so its editor points from there rather than from a place on the grid.
    var fromButton = false
    var id: Date { start }
}
