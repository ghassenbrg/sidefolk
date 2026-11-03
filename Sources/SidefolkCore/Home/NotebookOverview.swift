import Foundation

/// What the Notebook's own page shows (D134): what the sidebar can't. The open tasks that are late or due within a week,
/// each collection's size and when it last changed, and what's pinned anywhere. Worked out from what's already loaded.
public struct NotebookOverview: Sendable, Equatable {
    public struct Tile: Sendable, Equatable {
        public var items = 0
        public var openTasks = 0
        public var lastChange: Date?

        public init() {}
    }

    public static let tasksShown = 5
    public static let pinnedShown = 6
    /// Today and the seven days after it: further off belongs to the Calendar.
    static let daysAhead = 8

    /// The Inbox and the person's collections, in their order; You has its own place in the sidebar.
    public var collections: [NotebookCollection] = []
    public var tiles: [String: Tile] = [:]
    public var itemCount = 0
    public var needsDoing: [NotebookItem] = []
    /// How many tasks are late or due soon, those not shown included.
    public var needsDoingCount = 0
    public var pinned: [NotebookItem] = []

    public init() {}

    /// - Parameter collections: the live ones, in the sidebar's order: what's in an archived one is out of the way on purpose.
    public init(collections: [NotebookCollection], items: [NotebookItem], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        self.collections = collections.filter { $0.kind != .profile }
        let shown = Set(self.collections.map(\.id))
        let live = items.filter { shown.contains($0.collectionId) && $0.deletedAt == nil }
        itemCount = live.count
        for item in live {
            var tile = tiles[item.collectionId] ?? Tile()
            tile.items += 1
            if item.kind == .task, item.status == .open { tile.openTasks += 1 }
            tile.lastChange = max(tile.lastChange ?? item.updatedAt, item.updatedAt)
            tiles[item.collectionId] = tile
        }
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: Self.daysAhead, to: today) ?? today
        let soon = live.filter { $0.kind == .task && $0.status == .open && ($0.dueAt ?? .distantFuture) < end }
            .sorted { ($0.dueAt ?? .distantFuture, $0.id) < ($1.dueAt ?? .distantFuture, $1.id) }
        needsDoingCount = soon.count
        needsDoing = Array(soon.prefix(Self.tasksShown))
        // Once is enough: a pinned task due soon is in the tasks above.
        let above = Set(needsDoing.map(\.id))
        pinned = Array(live.filter { $0.pinnedAt != nil && !above.contains($0.id) }
            .sorted { ($0.pinnedAt ?? .distantPast, $0.id) > ($1.pinnedAt ?? .distantPast, $1.id) }
            .prefix(Self.pinnedShown))
    }
}
