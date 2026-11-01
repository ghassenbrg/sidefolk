#if DEBUG
import Foundation
import SidefolkCore
import Synchronization

/// A Mac calendar as snapshots and a debug app see it (D95), with the colours of iCloud's own calendars, a
/// subscription and birthdays that can't be changed, an invitation with people in it, a repeating standup, a trip
/// over three days and a busy hour with more than a week's column has room for side by side. It takes changes in
/// memory, so the Calendar's dragging and editing can be tried without anyone's real calendar
/// (`SIDEFOLK_SAMPLE_CALENDAR=1` in a debug app).
nonisolated final class SampleCalendar: Sendable {
    /// The debug app's, when it was started with `SIDEFOLK_SAMPLE_CALENDAR=1`.
    static let live: SampleCalendar? = ProcessInfo.processInfo.environment["SIDEFOLK_SAMPLE_CALENDAR"] == nil ? nil : SampleCalendar()

    static let calendars = [
        CalendarInfo(id: "work", title: "Work", color: CalendarColor(hex: 0xFF9500), account: "iCloud", writable: true, isDefault: true),
        CalendarInfo(id: "home", title: "Home", color: CalendarColor(hex: 0x1BADF8), account: "iCloud", writable: true),
        CalendarInfo(id: "family", title: "Family", color: CalendarColor(hex: 0x63DA38), account: "iCloud", writable: true),
        CalendarInfo(id: "gym", title: "Gym", color: CalendarColor(hex: 0xCC73E1), account: "Google", writable: true),
        CalendarInfo(id: "holidays", title: "Holidays", color: CalendarColor(hex: 0xFF2968), account: "Subscribed"),
        CalendarInfo(id: "birthdays", title: "Birthdays", color: CalendarColor(hex: 0xA2845E), account: "Other"),
    ]

    private let events: Mutex<[CalendarEvent]>
    private let counter = Mutex(0)

    init(today: Date = Calendar.current.startOfDay(for: Date())) {
        events = Mutex(Self.sample(today))
    }

    func list(from: Date, to: Date) -> [CalendarEvent] {
        events.withLock { $0.filter { $0.end > from && $0.start < to } }
    }

    func event(id: String) -> CalendarEvent? { events.withLock { $0.first { $0.id == id } } }

    func create(_ draft: CalendarDraft) throws -> CalendarEvent {
        let id = "new-\(counter.withLock { $0 += 1; return $0 })"
        let event = Self.make(id, draft)
        events.withLock { $0.append(event) }
        changed()
        return event
    }

    func update(id: String, to draft: CalendarDraft) throws -> CalendarEvent {
        guard let old = event(id: id) else { throw UserFacingError("That event isn't on your calendar anymore.") }
        var next = Self.make(id, draft)
        next.attendees = old.attendees
        next.repeats = old.repeats
        events.withLock { list in list = list.map { $0.id == id ? next : $0 } }
        changed()
        return next
    }

    func delete(id: String) throws {
        events.withLock { $0.removeAll { $0.id == id } }
        changed()
    }

    /// As EventKit says a change happened.
    private func changed() {
        Task { @MainActor in NotificationCenter.default.post(name: MacCalendar.changed, object: nil) }
    }

    private static func make(_ id: String, _ draft: CalendarDraft) -> CalendarEvent {
        let info = calendars.first { $0.id == draft.calendarId } ?? calendars[0]
        return CalendarEvent(id: id, title: draft.title, start: draft.start, end: draft.end, allDay: draft.allDay, calendar: info.title,
                             calendarId: info.id, color: info.color, location: draft.location, notes: draft.notes, url: draft.url,
                             writable: info.writable, alarms: draft.alarms)
    }

    private static func sample(_ today: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        func at(_ day: Int, _ hour: Double) -> Date {
            (cal.date(byAdding: .day, value: day, to: today) ?? today).addingTimeInterval(hour * 3600)
        }
        func on(_ id: String, _ calendar: String, _ title: String, _ start: Date, _ end: Date, allDay: Bool = false, location: String? = nil,
                notes: String? = nil, attendees: [CalendarAttendee] = [], repeats: Bool = false) -> CalendarEvent {
            let info = calendars.first { $0.id == calendar } ?? calendars[0]
            return CalendarEvent(id: id, title: title, start: start, end: end, allDay: allDay, calendar: info.title, calendarId: info.id,
                                 color: info.color, location: location, notes: notes, attendees: attendees, repeats: repeats,
                                 writable: info.writable, alarms: [-900])
        }
        let team = [CalendarAttendee(name: "Priya Raman", answer: .accepted, organizer: true),
                    CalendarAttendee(name: "Sam Okafor", answer: .accepted), CalendarAttendee(name: "Lea Martin", answer: .tentative),
                    CalendarAttendee(name: "You", answer: .accepted, isYou: true)]
        // The week's busy day: the first after tomorrow in this week, else one before today.
        let week = CalendarGrid.weekDays(of: today, calendar: cal)
        let busy = week.firstIndex { $0 > at(1, 0) }.map { cal.dateComponents([.day], from: today, to: week[$0]).day ?? 2 }
            ?? week.firstIndex { $0 < today }.map { cal.dateComponents([.day], from: today, to: week[$0]).day ?? -1 } ?? 2
        var all: [CalendarEvent] = []
        for day in -35...35 where cal.isDateInWeekend(at(day, 12)) == false {
            all.append(on("standup|\(day)", "work", "Team standup", at(day, 9.75), at(day, 10), repeats: true))
        }
        all += [
            on("library", "home", "Library books due", at(0, 0), at(1, 0), allDay: true),
            on("lunch", "home", "Lunch with Priya", at(0, 12.5), at(0, 13.5), location: "Café Kitsuné, 51 Galerie de Montpensier, Paris",
               notes: "Bring the sketchbook. Ask about the Lisbon flat."),
            on("review", "work", "Design review", at(0, 15), at(0, 16.5), location: "Room 4 · Studio", notes: "Calendar v2: day, week, month, year.",
               attendees: team),
            on("gym", "gym", "Climbing", at(0, 18.5), at(0, 20), location: "Arkose Nation"),
            on("dentist", "home", "Dentist", at(1, 9.5), at(1, 10.25), location: "12 rue des Martyrs"),
            on("call-mum", "family", "Call mum", at(1, 19), at(1, 19.5)),
            on("trip", "family", "Lisbon trip", at(4, 0), at(7, 0), allDay: true),
            on("flight", "family", "Flight TP 433", at(4, 7.25), at(4, 9.5), location: "CDG Terminal 1"),
            on("armistice", "holidays", "Armistice Day", at(10, 0), at(11, 0), allDay: true),
            on("ines", "birthdays", "Inès's birthday", at(-2, 0), at(-1, 0), allDay: true),
            on("planning", "work", "Planning", at(busy, 11), at(busy, 12), attendees: team),
            on("one-on-one", "work", "1:1 with Sam", at(busy, 11), at(busy, 11.5)),
            on("interview", "work", "Interview", at(busy, 11.25), at(busy, 12)),
            on("vendor", "work", "Vendor call", at(busy, 11.5), at(busy, 12.5)),
            on("yoga", "gym", "Yoga", at(-1, 8), at(-1, 9)),
            on("offsite", "work", "Team offsite", at(14, 0), at(16, 0), allDay: true),
        ]
        return all
    }
}

#endif
