import Foundation

/// An event on the person's calendar (D57). Sidefolk only reads them; titles may come from someone else's
/// invitation, so what a tool returns of them is outside content.
public struct CalendarEvent: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    /// The calendar it's on ("Work", "Family").
    public var calendar: String

    public init(id: String, title: String, start: Date, end: Date, allDay: Bool = false, calendar: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.calendar = calendar
    }
}

/// The person's calendar, read only while they show it (D57): off by default, and nothing is read until they turn
/// it on in Settings or from Today, which is also when macOS asks them.
public struct CalendarReader: Sendable {
    let platform: any PlatformBridge
    let settings: SettingsStore

    public init(platform: any PlatformBridge, settings: SettingsStore) {
        self.platform = platform
        self.settings = settings
    }

    /// Whether the person chose to show their calendar (macOS may still not allow it).
    public var isOn: Bool { settings.current.showCalendar }

    /// Events overlapping the range, in start order; nil while the calendar is off or macOS doesn't allow it.
    public func events(from: Date, to: Date) async -> [CalendarEvent]? {
        guard isOn, let events = await platform.calendarEvents(from: from, to: to) else { return nil }
        return events.filter { $0.end > from && $0.start < to }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// One day's events, all-day ones first.
    public func events(on day: Date, calendar: Calendar = .autoupdatingCurrent) async -> [CalendarEvent]? {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return await events(from: start, to: end).map { $0.filter(\.allDay) + $0.filter { !$0.allDay } }
    }
}
