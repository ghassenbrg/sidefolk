#if DEBUG
import Foundation
import SidefolkCore

/// The Mac as snapshots see it: nothing to open or copy, and a calendar with a few events today and tomorrow (D57),
/// read only while the sample shows the calendar, as on a real Mac, and a busy hour on another day of this week: more
/// than a week's column has room for side by side.
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
        ] + busyHour(today)
    }

    private func busyHour(_ today: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let week = CalendarGrid.weekDays(of: today, calendar: calendar)
        guard let day = week.first(where: { $0 > today.addingTimeInterval(86400) }) ?? week.first(where: { $0 < today }) else { return [] }
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
        return [
            CalendarEvent(id: "planning", title: "Planning", start: at(11), end: at(12), calendar: "Work"),
            CalendarEvent(id: "one-on-one", title: "1:1 with Sam", start: at(11), end: at(11.5), calendar: "Work"),
            CalendarEvent(id: "interview", title: "Interview", start: at(11.25), end: at(12), calendar: "Work"),
            CalendarEvent(id: "vendor", title: "Vendor call", start: at(11.5), end: at(12.5), calendar: "Work"),
        ]
    }
}
#endif
