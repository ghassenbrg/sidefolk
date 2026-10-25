import Foundation

/// Everything that makes up a running Sidefolk, assembled once. The app owns one; tests build one
/// over an in-memory database and a temp home.
public final class SidefolkRuntime: Sendable {
    public let paths: SidefolkPaths
    public let db: AppDatabase
    public let events: EventBus
    public let clock: any Clock
    public let platform: any PlatformBridge
    public let settings: SettingsStore

    public let notebook: NotebookStore
    public let reminderStore: ReminderStore
    public let watcherStore: WatcherStore
    public let sessions: SessionStore
    public let jobs: JobStore
    public let activity: ActivityStore
    public let exchanges: ExchangeStore
    public let runs: AgentRunStore
    public let extensionStore: ExtensionStore
    public let permissions: PermissionStore

    public let registry: ToolRegistry
    public let broker: ApprovalBroker
    public let executor: ToolExecutor
    public let attention: AttentionCenter

    public init(paths: SidefolkPaths, db: AppDatabase, platform: any PlatformBridge, clock: any Clock = SystemClock()) async {
        self.paths = paths
        self.db = db
        self.platform = platform
        self.clock = clock
        let events = EventBus()
        self.events = events
        settings = await SettingsStore(db: db, events: events)

        notebook = NotebookStore(db)
        reminderStore = ReminderStore(db)
        watcherStore = WatcherStore(db)
        sessions = SessionStore(db)
        jobs = JobStore(db)
        activity = ActivityStore(db)
        exchanges = ExchangeStore(db)
        runs = AgentRunStore(db)
        extensionStore = ExtensionStore(db)
        permissions = PermissionStore(db)

        registry = ToolRegistry()
        broker = ApprovalBroker(events: events)
        executor = ToolExecutor(registry: registry, permissions: permissions, broker: broker, activity: activity,
                                events: events, clock: clock)
        attention = AttentionCenter(store: AttentionStore(db), events: events, clock: clock)
    }

    /// Opens (creating if needed) the database under `paths`.
    public static func open(paths: SidefolkPaths, platform: any PlatformBridge) async throws -> SidefolkRuntime {
        try paths.prepare()
        let db = try AppDatabase.open(at: paths.database)
        let runtime = await SidefolkRuntime(paths: paths, db: db, platform: platform)
        try await runtime.notebook.inbox()
        return runtime
    }

    /// Removes expired history, old activity and long-trashed notes.
    public func housekeeping() async {
        let s = settings.current
        let now = clock.now
        _ = try? await exchanges.purge(olderThan: now.addingTimeInterval(-Double(s.historyDays) * 86400))
        _ = try? await activity.purge(olderThan: now.addingTimeInterval(-Double(s.activityDays) * 86400))
        _ = try? await notebook.purgeTrash(olderThan: now.addingTimeInterval(-30 * 86400))
        _ = try? await sessions.purge(olderThan: now.addingTimeInterval(-14 * 86400))
        _ = try? await AttentionStore(db).purge(olderThan: now.addingTimeInterval(-30 * 86400))
    }
}
