import Foundation

/// A calendar's own colour (EKCalendar's), as sRGB: kept as data so the Calendar page and its contrast check (D95)
/// work without AppKit.
public struct CalendarColor: Sendable, Hashable, Codable {
    public var hex: UInt32

    public init(hex: UInt32) { self.hex = hex & 0xFFFFFF }

    /// From sRGB components in 0…1.
    public init(red: Double, green: Double, blue: Double) {
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        hex = byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}

/// One of the person's calendars ("Work" on iCloud), as the Calendar page's list shows it (D95).
public struct CalendarInfo: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var color: CalendarColor
    /// The account it belongs to ("iCloud", "Google", "On My Mac"), which the list groups by.
    public var account: String
    /// Events can be added and changed in it (not a subscription, birthdays or someone's read-only calendar).
    public var writable: Bool
    /// Where macOS puts new events.
    public var isDefault: Bool

    public init(id: String, title: String, color: CalendarColor, account: String = "", writable: Bool = false, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.color = color
        self.account = account
        self.writable = writable
        self.isDefault = isDefault
    }
}

/// Someone invited to an event, read only: Sidefolk never changes an event other people are invited to (D95).
public struct CalendarAttendee: Sendable, Hashable {
    public enum Answer: String, Sendable, Hashable { case accepted, declined, tentative, pending, unknown }
    public var name: String
    public var answer: Answer
    public var organizer: Bool
    public var isYou: Bool

    public init(name: String, answer: Answer = .unknown, organizer: Bool = false, isYou: Bool = false) {
        self.name = name
        self.answer = answer
        self.organizer = organizer
        self.isYou = isYou
    }
}

/// An event on the person's calendar (D57). Titles, places and notes may come from someone else's invitation, so what
/// a tool returns of them is outside content.
public struct CalendarEvent: Sendable, Hashable, Identifiable {
    /// One occurrence: a repeating event's times share EventKit's identifier, so each carries its own time too.
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    /// The calendar it's on ("Work", "Family").
    public var calendar: String
    public var calendarId: String
    public var color: CalendarColor?
    public var location: String?
    public var notes: String?
    /// A web page the event links to (only http and https are kept).
    public var url: String?
    public var attendees: [CalendarAttendee]
    /// One time of a series.
    public var repeats: Bool
    /// Its calendar takes changes (D95); whether Sidefolk will make them is `changeable`.
    public var writable: Bool
    /// Its alerts, as seconds from its start (negative is before), kept so an Undo puts it back with them.
    public var alarms: [Double]

    public init(id: String, title: String, start: Date, end: Date, allDay: Bool = false, calendar: String = "",
                calendarId: String = "", color: CalendarColor? = nil, location: String? = nil, notes: String? = nil,
                url: String? = nil, attendees: [CalendarAttendee] = [], repeats: Bool = false, writable: Bool = false,
                alarms: [Double] = []) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.calendar = calendar
        self.calendarId = calendarId
        self.color = color
        self.location = location
        self.notes = notes
        self.url = url
        self.attendees = attendees
        self.repeats = repeats
        self.writable = writable
        self.alarms = alarms
    }

    /// Sidefolk may move, change or delete it (D95): its calendar takes changes and nobody else is invited (changing a
    /// meeting tells the people in it, so that stays in Calendar, where the person sees who is told).
    public var changeable: Bool { writable && attendees.isEmpty }

    /// Its fields as a draft: what an Undo puts back.
    public var draft: CalendarDraft {
        CalendarDraft(title: title, start: start, end: end, allDay: allDay, calendarId: calendarId.isEmpty ? nil : calendarId,
                      location: location, notes: notes, url: url, alarms: alarms)
    }
}

/// An event to add, or what an event becomes (D95).
public struct CalendarDraft: Sendable, Hashable, Codable {
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    /// Nil: the calendar macOS puts new events in.
    public var calendarId: String?
    public var location: String?
    public var notes: String?
    public var url: String?
    public var alarms: [Double]

    public init(title: String, start: Date, end: Date, allDay: Bool = false, calendarId: String? = nil, location: String? = nil,
                notes: String? = nil, url: String? = nil, alarms: [Double] = []) {
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.calendarId = calendarId
        self.location = location
        self.notes = notes
        self.url = url
        self.alarms = alarms
    }
}

/// The person's calendar, read only while they show it (D57): off by default, and nothing is read until they turn
/// it on in Settings or from Today, which is also when macOS asks them. Calendars the person hid in the Calendar's
/// list (D95) are left out everywhere: Today, the brief and the AI see what the Calendar shows.
public struct CalendarReader: Sendable {
    let platform: any PlatformBridge
    let settings: SettingsStore

    public init(platform: any PlatformBridge, settings: SettingsStore) {
        self.platform = platform
        self.settings = settings
    }

    /// Whether the person chose to show their calendar (macOS may still not allow it).
    public var isOn: Bool { settings.current.showCalendar }

    /// Whether Sidefolk may change the person's calendars (D95): shown, and changes allowed.
    public var writesOn: Bool { isOn && settings.current.calendarPage.writes }

    /// Events overlapping the range, in start order; nil while the calendar is off or macOS doesn't allow it.
    public func events(from: Date, to: Date) async -> [CalendarEvent]? {
        guard isOn, let events = await platform.calendarEvents(from: from, to: to) else { return nil }
        let hidden = settings.current.calendarPage.hidden
        return events.filter { $0.end > from && $0.start < to && !hidden.contains($0.calendarId) }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// One day's events, all-day ones first.
    public func events(on day: Date, calendar: Calendar = .autoupdatingCurrent) async -> [CalendarEvent]? {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return await events(from: start, to: end).map { $0.filter(\.allDay) + $0.filter { !$0.allDay } }
    }

    /// Every calendar of the person's, hidden ones too, for the Calendar's list; nil while off or not allowed.
    public func calendars() async -> [CalendarInfo]? {
        guard isOn else { return nil }
        return await platform.calendars()
    }

    /// One event as it is now (its occurrence id), hidden calendars included: what a change starts from.
    public func event(id: String) async -> CalendarEvent? {
        guard isOn else { return nil }
        return await platform.calendarEvent(id: id)
    }
}
