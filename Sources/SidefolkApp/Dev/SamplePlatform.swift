#if DEBUG
import Foundation
import SidefolkCore

/// The Mac as snapshots see it: nothing to open or copy, and a calendar with a few events today and tomorrow (D57),
/// read only while the sample shows the calendar, as on a real Mac.
struct SamplePlatform: PlatformBridge {
    func clipboardText() async -> String? { nil }
    func setClipboard(_ text: String) async {}
    func open(url: URL) async -> Bool { false }
    func openApplication(_ nameOrBundleId: String) async -> Bool { false }
    func reveal(path: String) async {}
    func frontmostApplication() async -> FrontmostApp? { nil }

    func calendarEvents(from: Date, to: Date) async -> [CalendarEvent]? {
        let today = Calendar.current.startOfDay(for: Date())
        func at(_ day: Double, _ hour: Double) -> Date { today.addingTimeInterval(day * 86400 + hour * 3600) }
        return [
            CalendarEvent(id: "library", title: "Library books due", start: at(0, 0), end: at(1, 0), allDay: true, calendar: "Personal"),
            CalendarEvent(id: "standup", title: "Team standup", start: at(0, 10), end: at(0, 10.5), calendar: "Work"),
            CalendarEvent(id: "lunch", title: "Lunch with Priya", start: at(0, 13), end: at(0, 14), calendar: "Personal"),
            CalendarEvent(id: "review", title: "Design review", start: at(0, 16), end: at(0, 17), calendar: "Work"),
            CalendarEvent(id: "dentist", title: "Dentist", start: at(1, 9.5), end: at(1, 10.25), calendar: "Personal"),
        ]
    }
}
#endif
