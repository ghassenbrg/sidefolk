#if DEBUG
import Foundation
import SidefolkCore

/// The Mac as snapshots see it: nothing to open or copy, and a calendar (`SampleCalendar`, D95) read only while the
/// sample shows the calendar, as on a real Mac.
struct SamplePlatform: PlatformBridge {
    let calendar = SampleCalendar()

    func clipboardText() async -> String? { nil }
    func setClipboard(_ text: String) async {}
    func open(url: URL) async -> Bool { false }
    func openApplication(_ nameOrBundleId: String) async -> Bool { false }
    func reveal(path: String) async {}
    func frontmostApplication() async -> FrontmostApp? { nil }

    func calendarEvents(from: Date, to: Date) async -> [CalendarEvent]? { calendar.list(from: from, to: to) }
    func calendars() async -> [CalendarInfo]? { SampleCalendar.calendars }
    func calendarEvent(id: String) async -> CalendarEvent? { calendar.event(id: id) }
    func createCalendarEvent(_ draft: CalendarDraft) async throws -> CalendarEvent { try calendar.create(draft) }
    func updateCalendarEvent(id: String, to draft: CalendarDraft) async throws -> CalendarEvent { try calendar.update(id: id, to: draft) }
    func deleteCalendarEvent(id: String) async throws { try calendar.delete(id: id) }
}
#endif
