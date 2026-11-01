import AppKit
import EventKit
import SidefolkCore

/// Whether Sidefolk may read the calendar. Reading it never asks; showing the calendar does, once (D57).
enum CalendarAccess: Equatable {
    case allowed, notAsked, denied
}

/// The person's calendar through EventKit (D57), asked for only when they choose to show it. Writing (D95) happens
/// only from `calendar.create`, `.update` and `.delete`, through Guard, and only to one time of an event on a
/// calendar that takes changes with nobody else invited; the tools check that before calling here.
@MainActor
enum MacCalendar {
    private static let store = EKEventStore()

    /// Posted when anything in the person's calendars changes, here or anywhere they sync.
    static let changed = Notification.Name.EKEventStoreChanged

    static var access: CalendarAccess {
        #if DEBUG
        // A debug app on the sample calendar never asks macOS for the person's own.
        if SampleCalendar.live != nil { return .allowed }
        #endif
        return switch EKEventStore.authorizationStatus(for: .event) {
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

    static func calendars() -> [CalendarInfo]? {
        guard access == .allowed else { return nil }
        let main = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event).map { c in
            CalendarInfo(id: c.calendarIdentifier, title: c.title, color: color(c.cgColor), account: c.source?.title ?? "",
                         writable: writable(c), isDefault: c.calendarIdentifier == main)
        }
    }

    static func events(from: Date, to: Date) -> [CalendarEvent]? {
        guard access == .allowed else { return nil }
        let matching = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: matching).map(event)
    }

    static func event(id: String) -> CalendarEvent? {
        guard access == .allowed else { return nil }
        return find(id).map(event)
    }

    static func create(_ draft: CalendarDraft) throws -> CalendarEvent {
        let new = EKEvent(eventStore: store)
        try apply(draft, to: new)
        try store.save(new, span: .thisEvent, commit: true)
        return event(new)
    }

    /// One time of an event changes; a repeating event's other times stay as they are, as Calendar's "Only this event".
    static func update(id: String, to draft: CalendarDraft) throws -> CalendarEvent {
        guard let found = find(id) else { throw UserFacingError("That event isn't on your calendar anymore.") }
        try apply(draft, to: found)
        try store.save(found, span: .thisEvent, commit: true)
        return event(found)
    }

    static func delete(id: String) throws {
        guard let found = find(id) else { throw UserFacingError("That event isn't on your calendar anymore.") }
        try store.remove(found, span: .thisEvent, commit: true)
    }

    /// Shows the event in Calendar, or Calendar at its day when it can't be found by id.
    static func open(_ event: CalendarEvent) {
        let plain = event.id.split(separator: "|").first.map(String.init) ?? event.id
        let encoded = plain.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? plain
        if let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"), NSWorkspace.shared.open(url) { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// System Settings › Privacy & Security › Calendars.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: EventKit to Sidefolk

    private static func writable(_ c: EKCalendar) -> Bool {
        c.allowsContentModifications && !c.isImmutable && c.type != .subscription && c.type != .birthday
    }

    private static func color(_ cg: CGColor?) -> CalendarColor {
        guard let cg, let rgb = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else { return CalendarColor(hex: 0x8E8E93) }
        return CalendarColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    /// A repeating event's times share one identifier, so each time's id adds when it was meant to happen.
    private static func id(of e: EKEvent) -> String {
        let base = e.eventIdentifier ?? e.calendarItemIdentifier
        guard e.hasRecurrenceRules, let at = e.occurrenceDate else { return base }
        return "\(base)|\(Int(at.timeIntervalSince1970))"
    }

    private static func find(_ id: String) -> EKEvent? {
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard let base = parts.first else { return nil }
        guard parts.count == 2, let seconds = Double(parts[1]) else { return store.event(withIdentifier: base) }
        // A time moved by hand keeps the date it was meant for, which the search must still cover.
        let at = Date(timeIntervalSince1970: seconds)
        let near = store.predicateForEvents(withStart: at.addingTimeInterval(-45 * 86400), end: at.addingTimeInterval(45 * 86400), calendars: nil)
        return store.events(matching: near).first { $0.eventIdentifier == base && $0.occurrenceDate == at }
    }

    private static func event(_ e: EKEvent) -> CalendarEvent {
        let calendar = e.calendar
        let organizer = e.organizer?.url
        let attendees = (e.attendees ?? []).map { p in
            CalendarAttendee(name: p.name ?? p.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""), answer: answer(p.participantStatus),
                             organizer: p.url == organizer, isYou: p.isCurrentUser)
        }
        let link = e.url.flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0.absoluteString : nil }
        return CalendarEvent(
            id: id(of: e), title: e.title ?? "", start: e.startDate, end: e.endDate, allDay: e.isAllDay,
            calendar: calendar?.title ?? "", calendarId: calendar?.calendarIdentifier ?? "", color: color(calendar?.cgColor),
            location: e.location?.nilIfBlank, notes: e.notes?.nilIfBlank, url: link, attendees: attendees,
            repeats: e.hasRecurrenceRules, writable: calendar.map(writable) ?? false,
            alarms: (e.alarms ?? []).compactMap { $0.absoluteDate == nil ? $0.relativeOffset : nil })
    }

    private static func answer(_ status: EKParticipantStatus) -> CalendarAttendee.Answer {
        switch status {
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        case .pending: .pending
        default: .unknown
        }
    }

    private static func apply(_ draft: CalendarDraft, to e: EKEvent) throws {
        let target = draft.calendarId.flatMap { store.calendar(withIdentifier: $0) } ?? e.calendar ?? store.defaultCalendarForNewEvents
        guard let target, writable(target) else {
            throw UserFacingError("That calendar can't be changed from here.", recovery: "Choose another calendar.")
        }
        e.calendar = target
        e.title = draft.title
        e.isAllDay = draft.allDay
        e.startDate = draft.start
        e.endDate = draft.end
        e.location = draft.location
        e.notes = draft.notes
        e.url = draft.url.flatMap(URL.init(string:))
        if e.alarms?.isEmpty ?? true, !draft.alarms.isEmpty {
            e.alarms = draft.alarms.map { EKAlarm(relativeOffset: $0) }
        }
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
