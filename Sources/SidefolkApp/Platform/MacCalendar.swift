import AppKit
import EventKit
import SidefolkCore

/// Whether Sidefolk may read the calendar. Reading it never asks; showing the calendar does, once (D57).
enum CalendarAccess: Equatable {
    case allowed, notAsked, denied
}

/// The person's calendar through EventKit (D57): read-only, asked for only when they choose to show it.
@MainActor
enum MacCalendar {
    private static let store = EKEventStore()

    static var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .allowed
        case .notDetermined: .notAsked
        // Write-only access can't read, so for Sidefolk it's the same as no.
        default: .denied
        }
    }

    /// Asks macOS the first time; only ever from the person's own choice. Whether reading is allowed now.
    static func request() async -> Bool {
        if access == .allowed { return true }
        guard access == .notAsked else { return false }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func events(from: Date, to: Date) -> [CalendarEvent]? {
        guard access == .allowed else { return nil }
        let matching = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: matching).map { event in
            CalendarEvent(id: event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)-\(event.title ?? "")",
                          title: event.title ?? "", start: event.startDate, end: event.endDate, allDay: event.isAllDay,
                          calendar: event.calendar?.title ?? "")
        }
    }

    /// System Settings › Privacy & Security › Calendars.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
