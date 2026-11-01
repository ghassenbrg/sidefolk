import SidefolkCore
import SwiftUI

/// One thing on the Calendar (D66, D95): a time a reminder comes due, one done or told, or an event of the Mac's.
enum CalendarEntry: Identifiable, Hashable {
    /// A time a pending reminder comes due.
    case reminder(ReminderOccurrence)
    /// A reminder that was done, or told you, at `at`.
    case finished(Reminder, at: Date)
    case event(CalendarEvent)

    /// What it is, for its colour and the list that shows or hides it (D95).
    enum Kind: String, CaseIterable {
        case reminder, task, routine, event

        /// Sidefolk's own kinds are calendars of their own in the list.
        var listId: String? {
            switch self {
            case .reminder: CalendarPageSettings.sidefolkReminders
            case .task: CalendarPageSettings.sidefolkTasks
            case .routine: CalendarPageSettings.sidefolkRoutines
            case .event: nil
            }
        }

        /// Their identity colours: Tempo's blue for reminders (as on Today), Brew's tan for tasks, Nova's violet for
        /// routines. Identity, never status (D78): late and done say so in words and pictures.
        var hex: UInt32 {
            switch self {
            case .reminder, .event: 0x5B8DEF
            case .task: 0xC99A5B
            case .routine: 0xA68BFA
            }
        }

        var name: String {
            switch self {
            case .reminder: String(localized: "Reminders", comment: "The Calendar's list: Sidefolk's reminders as a calendar")
            case .task: String(localized: "Tasks", comment: "The Calendar's list: tasks with a time, as a calendar")
            case .routine: String(localized: "Routines", comment: "The Calendar's list: reminders that run a prompt, as a calendar")
            case .event: ""
            }
        }
    }

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

    var allDay: Bool { event?.allDay ?? false }

    var reminder: Reminder? {
        switch self {
        case .reminder(let o): o.reminder
        case .finished(let r, _): r
        case .event: nil
        }
    }

    var event: CalendarEvent? { if case .event(let e) = self { e } else { nil } }

    /// Its next time: the only one of a reminder that can be dragged elsewhere (a series' later times are where it
    /// will fall); an event Sidefolk may change (D95).
    var movable: Bool {
        switch self {
        case .reminder(let o): o.isNext
        case .finished: false
        case .event(let e): e.changeable
        }
    }

    var struck: Bool { if case .finished(let r, _) = self { r.state == .done } else { false } }

    /// Still to come and not acted on: a reminder's time already passed.
    var late: Bool { if case .reminder(let o) = self { o.at < Date() } else { false } }

    func kind(item: NotebookItem?) -> Kind {
        guard let reminder else { return .event }
        if reminder.action?.kind == .prompt { return .routine }
        return item?.kind == .task ? .task : .reminder
    }

    /// Its picture: the note or task it belongs to, an alarm, a tick when done, a bell when it told you.
    func symbol(item: NotebookItem?) -> String {
        switch self {
        case .reminder(let o): o.reminder.action?.kind == .prompt ? "sparkles" : item.map { ItemKindStyle.symbol($0.kind) } ?? "alarm"
        case .finished(let r, _): r.state == .done ? "checkmark.circle.fill" : "bell"
        case .event(let e): e.repeats ? "repeat" : "calendar"
        }
    }

    /// "10:00–11:30", kept left to right in Arabic (numbers in isolation, DESIGN.md): it would otherwise read 11:30–10:00.
    static func span(_ start: Date, _ end: Date, calendar: Calendar) -> String {
        "\u{2066}" + TimeFormat.clock(start, calendar: calendar) + "–" + TimeFormat.clock(end, calendar: calendar) + "\u{2069}"
    }

    /// "15:00 Call mom", for help and VoiceOver.
    var spoken: String {
        let time = allDay ? String(localized: "All day") : TimeFormat.clock(start, calendar: .current)
        var words = "\(time) \(title)"
        if case .finished(let r, _) = self, r.state == .done { words = String(localized: "Done: \(title)") + ", " + time }
        if let event, !event.calendar.isEmpty { words += ", " + event.calendar }
        return words
    }
}

/// A colour of the Calendar's, made readable on this theme's cards in light and dark (`CalendarPalette`, D95).
struct CalendarTint {
    var fill, edge, text, selectedFill, onSelected: Color

    @MainActor private static var cache: [String: CalendarTint] = [:]

    @MainActor static func of(_ hex: UInt32) -> CalendarTint {
        let colors = ThemeStore.shared.style.tokens.colors
        let surface = colors.surfaceRaised
        let key = "\(hex)-\(surface.light)-\(surface.dark)"
        if let known = cache[key] { return known }
        let light = CalendarPalette.colors(hex, surface: surface.light, dark: false)
        let dark = CalendarPalette.colors(hex, surface: surface.dark, dark: true)
        func pair(_ path: KeyPath<CalendarPalette.Colors, UInt32>) -> Color { Color(light: light[keyPath: path], dark: dark[keyPath: path]) }
        let tint = CalendarTint(fill: pair(\.fill), edge: pair(\.edge), text: pair(\.text), selectedFill: pair(\.selectedFill),
                                onSelected: pair(\.onSelected))
        cache[key] = tint
        return tint
    }
}

extension CalendarModel {
    /// The colour a thing is drawn in: its calendar's, or its kind's for Sidefolk's own.
    func tint(_ entry: CalendarEntry) -> CalendarTint {
        if case .event(let e) = entry { return CalendarTint.of(e.color?.hex ?? 0x8E8E93) }
        return CalendarTint.of(entry.kind(item: entry.reminder.flatMap(item)).hex)
    }
}
