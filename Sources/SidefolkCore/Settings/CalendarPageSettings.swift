import Foundation

/// How the Calendar page is set up, kept with the person's settings so it follows `SIDEFOLK_HOME` and a backup (D97).
public struct CalendarPageSettings: Codable, Sendable, Equatable {
    /// Calendars the person hid in the list, by id: the Mac's own ids, and `sidefolk.reminders`, `sidefolk.tasks` and
    /// `sidefolk.routines` for Sidefolk's.
    public var hidden: Set<String> = []
    /// The person let Sidefolk add, move, change and delete events in their writable calendars (D97). Off until they
    /// choose it in the sheet the first change asks, or in Settings › Trust › Your calendar.
    public var writes = false
    /// The view last shown ("agenda", "day", "week", "month", "year").
    public var view = "agenda"
    /// The height of an hour in Day and Week, as pinched.
    public var hourHeight = 48.0
    /// The page's own sidebar: the month to jump with and the calendars' list.
    public var sidebar = true

    public init() {}

    public static let sidefolkReminders = "sidefolk.reminders"
    public static let sidefolkTasks = "sidefolk.tasks"
    public static let sidefolkRoutines = "sidefolk.routines"

    /// The pinch's bounds: a whole day fits a laptop's height at the least, a quarter hour reads two lines at the most.
    public static let hourHeights: ClosedRange<Double> = 24...160

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ into: inout T) { if let v = try? c.decode(T.self, forKey: key) { into = v } }
        read(.hidden, &hidden)
        read(.writes, &writes)
        read(.view, &view)
        read(.hourHeight, &hourHeight)
        read(.sidebar, &sidebar)
        hourHeight = min(max(hourHeight, Self.hourHeights.lowerBound), Self.hourHeights.upperBound)
    }
}
