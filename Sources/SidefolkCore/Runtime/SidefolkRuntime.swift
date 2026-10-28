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
    public let scheduler: ReminderScheduler
    public let brief: MorningBrief
    public let watchers: WatcherEngine
    public let tokens: BrainTokenRegistry
    public let gateway: ExternalToolGateway
    public let sessionTracker: SessionTracker
    public let jobTracker: JobTracker
    public let extensions: ExtensionHost
    /// Extensions Sidefolk ships, installed and updated with the app (D39).
    public let bundledExtensions: BundledExtensions
    /// Extensions Sidefolk's AI wrote for the person, waiting for review (D39).
    public let extensionDrafts: ExtensionDrafts
    public let skills: SkillLibrary
    /// Which Apple Notes are already in the notebook (DECISIONS D38).
    public let appleNotesLedger: AppleNotesLedger
    private let server: LocalAPIServer
    private let upkeep = DailyChore()

    /// - Parameters:
    ///   - bundledResources: the app's Resources folder (bundled skills, built-in and sample extensions).
    ///   - extensionSecrets: environment values for an MCP server, read from the Keychain by server id.
    ///   - appleEvents: how Notes and Reminders are reached; tests pass a fake.
    ///   - approvalMinute: how long a minute of an unanswered approval lasts (D37); the UI snapshots
    ///     shorten it to show steps that were skipped.
    public init(paths: SidefolkPaths, db: AppDatabase, platform: any PlatformBridge, clock: any Clock = SystemClock(),
                bundledResources: URL? = nil,
                extensionSecrets: @escaping @Sendable (String) async -> [String: String] = { _ in [:] },
                appleEvents: any AppleEventsRunner = OsascriptRunner(),
                approvalMinute: TimeInterval = 60) async {
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
                                events: events, clock: clock, minute: approvalMinute)
        attention = AttentionCenter(store: AttentionStore(db), events: events, clock: clock)
        brief = MorningBrief(db: db, attention: attention, settings: settings, clock: clock)
        scheduler = ReminderScheduler(store: reminderStore, attention: attention, events: events, settings: settings,
                                      clock: clock, brief: brief)
        watchers = WatcherEngine(store: watcherStore, attention: attention, events: events, clock: clock,
                                 opener: { url in _ = await platform.open(url: url) })
        tokens = BrainTokenRegistry()
        gateway = ExternalToolGateway(registry: registry, permissions: permissions, broker: broker, activity: activity,
                                      events: events, clock: clock)
        sessionTracker = SessionTracker(store: sessions, attention: attention, events: events, clock: clock, open: { session in
            let host = HostTrust.target(for: session)
            _ = await platform.activateApplication(pid: host.pid, bundleId: host.bundleId)
        })
        jobTracker = JobTracker(store: jobs, attention: attention, events: events, clock: clock)
        extensions = ExtensionHost(paths: paths, store: extensionStore, registry: registry, events: events, secrets: extensionSecrets)
        bundledExtensions = BundledExtensions(directory: bundledResources?.appendingPathComponent("Extensions", isDirectory: true))
        extensionDrafts = ExtensionDrafts(paths: paths)
        skills = SkillLibrary(userDirectory: paths.skills, bundledDirectory: bundledResources?.appendingPathComponent("Skills", isDirectory: true),
                              events: events)
        appleNotesLedger = AppleNotesLedger(db: db)
        server = LocalAPIServer(socket: paths.socket, services: BridgeServices(
            tools: gateway, tokens: tokens, sessions: sessionTracker, jobs: jobTracker, status: StatusReader(db: db)))

        registry.register(BuiltinTools.make(notebook: notebook, platform: platform, events: events,
                                            reminders: ReminderTools.shared(scheduler: scheduler, settings: settings)))
        registry.register(MacAppTools.make(runner: appleEvents, notebook: notebook, events: events, ledger: appleNotesLedger, clock: clock))
        registry.register(ReminderTools.make(scheduler: scheduler, settings: settings))
        registry.register(WatchTools.make(engine: watchers, parser: { [settings] in WhenParser(settings: settings.current) }))
        registry.register(AgendaTool(scheduler: scheduler, notebook: notebook, watchers: watchers,
                                     parser: { [settings] in WhenParser(settings: settings.current) }))
        registry.register(AgentFacingTools.make(attention: attention))
        registry.register(AgentFacingTools.status(StatusReader(db: db)))
        registry.register(SkillTools.all(skills))
        registry.register(ExtensionWatchTool(host: extensions, engine: watchers))
        registry.register(ExtensionBuilderTools.all(drafts: extensionDrafts, host: extensions, events: events))
    }

    /// The local language understanding, configured with the user's idea of "morning" and "evening",
    /// and the companion's current name ("mochi, remind me…").
    public var intentParser: IntentParser {
        let s = settings.current
        return IntentParser(when: WhenParser(settings: s), companionNames: ["sidefolk", "pip", s.companionName])
    }

    /// Starts the background engines and the local API other agents connect to.
    /// Throws `BridgeError.alreadyRunning` when another Sidefolk owns the socket.
    public func start() async throws {
        do {
            try server.start()
        } catch BridgeError.alreadyRunning {
            throw BridgeError.alreadyRunning
        } catch {
            // Agents can't reach Sidefolk without the socket, but reminders and watchers must still run.
            Log.shared.error("bridge", "local API failed to start", ["error": String(describing: error)])
        }
        await scheduler.start()
        await extensions.start()
        // Off the launch path: the first launch installs each built-in extension (a short start of each).
        let bundled = bundledExtensions, host = extensions
        Task { await bundled.install(into: host) }
        await watchers.register(ExtensionWatcherProbe(host: extensions))
        await watchers.start()
        await sessionTracker.start()
        _ = await jobTracker.reconcile()
        // Approval cards for removing Apple Notes name them from this, without waiting.
        _ = try? await appleNotesLedger.load()
        await attention.restoreWaiting()
        // The app tidied up at launch; this keeps doing it for as long as Sidefolk runs.
        await upkeep.start { [weak self] in await self?.housekeeping() }
    }

    /// After sleep or a clock change: re-arm timers.
    public func rearm() async {
        await scheduler.reschedule()
        await watchers.rearm()
    }

    /// Before quitting: stop timers and the socket, and return what system notifications should cover
    /// while Sidefolk is off.
    public func stop() async -> [FallbackNotification] {
        let fallback = await scheduler.fallbackNotifications(horizon: 7 * 86400)
        await scheduler.stop()
        await watchers.stop()
        await extensions.shutdown()
        server.stop()
        await upkeep.stop()
        return fallback
    }

    /// Opens (creating if needed) the database under `paths`.
    public static func open(paths: SidefolkPaths, platform: any PlatformBridge, bundledResources: URL? = nil,
                            extensionSecrets: @escaping @Sendable (String) async -> [String: String] = { _ in [:] }) async throws -> SidefolkRuntime {
        try paths.prepare()
        let db = try AppDatabase.open(at: paths.database)
        let runtime = await SidefolkRuntime(paths: paths, db: db, platform: platform, bundledResources: bundledResources,
                                            extensionSecrets: extensionSecrets)
        try await runtime.notebook.inbox()
        return runtime
    }

    /// Removes expired history, old activity, runs and jobs, and long-trashed notes.
    public func housekeeping() async {
        let s = settings.current
        let now = clock.now
        _ = try? await exchanges.purge(olderThan: now.addingTimeInterval(-Double(s.historyDays) * 86400))
        _ = try? await activity.purge(olderThan: now.addingTimeInterval(-Double(s.activityDays) * 86400))
        _ = try? await notebook.purgeTrash(olderThan: now.addingTimeInterval(-30 * 86400))
        _ = try? await sessions.purge(olderThan: now.addingTimeInterval(-14 * 86400))
        _ = try? await jobs.purge(olderThan: now.addingTimeInterval(-14 * 86400))
        _ = try? await runs.purge(olderThan: now.addingTimeInterval(-Double(s.activityDays) * 86400))
        _ = try? await AttentionStore(db).purge(olderThan: now.addingTimeInterval(-30 * 86400))
    }
}
