import Foundation
import Synchronization

/// Everything that makes up a running Sidefolk, assembled once. The app owns one; tests build one
/// over an in-memory database and a temp home.
public final class SidefolkRuntime: Sendable {
    public let paths: SidefolkPaths
    public let db: AppDatabase
    public let events: EventBus
    public let clock: any Clock
    public let platform: any PlatformBridge
    /// The person's calendar, while they show it (D57).
    public let calendarReader: CalendarReader
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
    public let occurrences: OccurrenceScheduler
    public let scheduler: ReminderScheduler
    public let brief: MorningBrief
    public let watchers: WatcherEngine
    public let tokens: BrainTokenRegistry
    public let gateway: ExternalToolGateway
    /// What extensions with `permissions.act` use Sidefolk's tools through (D110).
    public let actions: ExtensionActionGateway
    public let sessionTracker: SessionTracker
    public let jobTracker: JobTracker
    public let extensions: ExtensionHost
    /// Extensions Sidefolk ships, installed and updated with the app (D39).
    public let seedPacks: SeedPacks
    /// The add-on gallery: companions and extensions downloaded on demand (D55).
    public let addons: AddonStore
    /// Extensions Sidefolk's AI wrote for the person, waiting for review (D39).
    public let extensionDrafts: ExtensionDrafts
    public let skills: SkillLibrary
    /// Which Apple Notes are already in the notebook (DECISIONS D38).
    public let appleNotesLedger: AppleNotesLedger
    private let server: LocalAPIServer
    private let upkeep = DailyChore()
    private let calendarHearing = Mutex<Task<Void, Never>?>(nil)
    /// The companion's brain, once the app has made it: what `companion.job` hands a job to.
    public let companionAgent = CompanionAgentSlot()

    /// - Parameters:
    ///   - bundledResources: the app's Resources folder (bundled skills, seed packs).
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
        let calendarReader = CalendarReader(platform: platform, settings: settings)
        self.calendarReader = calendarReader
        brief = MorningBrief(db: db, attention: attention, settings: settings, clock: clock,
                             events: { day in await calendarReader.events(on: day) ?? [] })
        scheduler = ReminderScheduler(store: reminderStore, attention: attention, events: events, settings: settings,
                                      clock: clock, brief: brief)
        occurrences = OccurrenceScheduler(store: ExtensionOccurrenceStore(KVStore(db)), attention: attention, events: events, clock: clock)
        watchers = WatcherEngine(store: watcherStore, attention: attention, events: events, clock: clock,
                                 opener: { url in _ = await platform.open(url: url) })
        tokens = BrainTokenRegistry()
        gateway = ExternalToolGateway(registry: registry, permissions: permissions, broker: broker, activity: activity,
                                      events: events, clock: clock, access: { [settings] in settings.current.agentAccess })
        let actions = ExtensionActionGateway(registry: registry, permissions: permissions, broker: broker, activity: activity, events: events, clock: clock)
        self.actions = actions
        sessionTracker = SessionTracker(store: sessions, attention: attention, events: events, clock: clock,
                                        titles: ConversationTitles(locations: .forApp(paths: paths)), open: { session in
            let host = HostTrust.target(for: session)
            _ = await platform.activateApplication(pid: host.pid, bundleId: host.bundleId)
        })
        jobTracker = JobTracker(store: jobs, attention: attention, events: events, clock: clock)
        var hostConfiguration = ExtensionHost.Configuration()
        hostConfiguration.runTool = { [executor] name, input, caller, timeout in
            await executor.execute(name: name, input: input, caller: caller, timeout: timeout)
        }
        hostConfiguration.actions = actions
        hostConfiguration.askEachTimeOnline = { [permissions, clock] in (try? await permissions.policy(now: clock.now))?.internet == .askEachTime }
        hostConfiguration.aiName = { [settings] in settings.current.provider.shortName }
        hostConfiguration.currentPlace = { [settings] in settings.current.location.current }
        hostConfiguration.companionName = { [settings] in settings.current.companionName }
        hostConfiguration.carriedSettings = { [settings] section in settings.current.section(section) }
        hostConfiguration.forgetCarried = { [settings] section in await settings.update { $0.parked[section] = nil } }
        hostConfiguration.carriedStore = { [db] name in try? await KVStore(db).get(name, as: JSONValue.self) }
        hostConfiguration.forgetCarriedStore = { [db] name in try? await KVStore(db).remove(name) }
        hostConfiguration.carriedHistory = { [activity] tool in (try? await activity.recent(limit: 2000, tool: tool)) ?? [] }
        hostConfiguration.aiHeldBack = { [settings] in
            settings.current.provider.kind == .codex && CodexBackend.hasUserInstructions()
                ? String(localized: "Not while you use Codex with your own AGENTS.md: Codex always reads that file, and the answer goes to the extension.",
                         comment: "Under an extension's AI switch: why it can't use the person's AI now")
                : nil
        }
        hostConfiguration.forgetGrants = { [permissions] id in
            for grant in (try? await permissions.grants()) ?? [] where grant.scope.string("extension") == id { try? await permissions.revokeGrant(id: grant.id) }
        }
        hostConfiguration.forgetWatches = { [watchers] id in
            for watcher in await watchers.list() where watcher.source == "extension:\(id)" { _ = await watchers.remove(watcher.id) }
        }
        hostConfiguration.forgetOwnRows = { [activity] id in _ = try? await activity.delete(tool: ExtensionActivityTool.name, extensionId: id) }
        extensions = ExtensionHost(paths: paths, store: extensionStore, registry: registry, events: events, configuration: hostConfiguration,
                                   secrets: extensionSecrets)
        seedPacks = SeedPacks(directory: bundledResources?.appendingPathComponent("SeedPacks", isDirectory: true), paths: paths)
        extensionDrafts = ExtensionDrafts(paths: paths)
        addons = AddonStore(paths: paths)
        skills = SkillLibrary(userDirectory: paths.skills, bundledDirectory: bundledResources?.appendingPathComponent("Skills", isDirectory: true),
                              events: events)
        appleNotesLedger = AppleNotesLedger(db: db)
        server = LocalAPIServer(socket: paths.socket, services: BridgeServices(
            tools: gateway, tokens: tokens, sessions: sessionTracker, jobs: jobTracker, status: StatusReader(db: db)))

        registry.register(BuiltinTools.make(notebook: notebook, platform: platform, events: events,
                                            reminders: ReminderTools.shared(scheduler: scheduler, settings: settings)))
        registry.register(MacAppTools.make(runner: appleEvents, notebook: notebook, events: events, ledger: appleNotesLedger, clock: clock))
        registry.register(ReminderTools.make(scheduler: scheduler, settings: settings))
        registry.register([CalendarTodayTool(reader: calendarReader),
                           CalendarFindTool(reader: calendarReader, parser: { [settings] in WhenParser(settings: settings.current) })])
        registry.register(CalendarWriteTools.make(reader: calendarReader, platform: platform, settings: settings))
        registry.register(WatchTools.make(engine: watchers, parser: { [settings] in WhenParser(settings: settings.current) },
                                          here: { [settings] in settings.current.location.current }))
        registry.register(AgendaTool(scheduler: scheduler, notebook: notebook, watchers: watchers,
                                     parser: { [settings] in WhenParser(settings: settings.current) }))
        registry.register(AgentFacingTools.make(attention: attention))
        registry.register(AgentFacingTools.status(StatusReader(db: db)))
        registry.register(HistoryRecentTool(activity: activity, alerts: AttentionStore(db)))
        registry.register(AgentSessionsTool(sessions: sessions))
        registry.register(SkillTools.all(skills))
        registry.register(ExtensionWatchTool(host: extensions, engine: watchers))
        registry.register(ExtensionBuilderTools.all(drafts: extensionDrafts, host: extensions, events: events))
        registry.register(SurfacesOpenTool(events: events, shelf: extensions.surfaceShelf))
        let host = extensions
        registry.register(ExtensionSettingTool(host: host))
        registry.register(ExtensionActivityTool(shelfName: { id in host.shelf.names[id] }))
        registry.register(ExtensionConsentTool(host: host))
        registry.register(FolderShareTool(permissions: permissions, events: events))
        registry.register(ExtensionOccurrencesTool(host: host))
        registry.register(ExtensionPlaceSearchTool(shelfName: { id in host.shelf.names[id] }))
        registry.register(ExtensionPlanEndTool(host: host))
        registry.register(CompanionJobTool(agent: companionAgent))
        registry.register(AttentionSetTool(settings: settings, attention: attention, events: events))
        registry.register(VoiceSayTool(settings: settings, events: events))
        registry.register(AppearanceTool(settings: settings, themes: ThemeLibrary(paths: paths, bundled: bundledResources?.appendingPathComponent("Themes", isDirectory: true)), installedCompanions: { [addons] in await addons.installedCompanions().map(\.companion) }, events: events))
        AgentFacingTools.extensionNames.withLock { $0 = { id in host.shelf.names[id] } }
    }

    /// The local language understanding, configured with the user's idea of "morning" and "evening",
    /// and the companion's current name ("mochi, remind me…").
    public var intentParser: IntentParser {
        let s = settings.current
        // Only switched-on extensions register tools, so their commands are the ones that count (D50).
        let commandTools = registry.all.compactMap { $0 as? ExtensionTool }.filter { $0.commands != nil }
        return IntentParser(when: WhenParser(settings: s), companionNames: ["sidefolk", "pip", s.companionName],
                            here: s.location.current?.name, commandTools: commandTools, surfaces: extensions.surfaceShelf.all)
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
        await extensions.setOccurrences(occurrences)
        await extensions.start()
        await occurrences.start(extensions: await extensions.scheduling())
        await extensions.startPlanning()
        // Off the launch path: a fresh Mac's first launch installs each seed pack (a short start of each, D98).
        let seeds = seedPacks, host = extensions, store = addons
        Task { await seeds.install(into: host, store: store) }
        await addons.tidy()
        await watchers.register(ExtensionWatcherProbe(host: extensions))
        await watchers.start()
        await sessionTracker.start()
        _ = await jobTracker.reconcile()
        // Approval cards for removing Apple Notes name them from this, without waiting.
        _ = try? await appleNotesLedger.load()
        await attention.restoreWaiting()
        // The app tidied up at launch; this keeps doing it for as long as Sidefolk runs.
        await upkeep.start { [weak self] in await self?.housekeeping() }
        startHearingTheCalendar()
    }

    /// Says when a meeting is five minutes away, each once, while anyone listens (D129): the calendar has no such event of its own.
    private func startHearingTheCalendar() {
        let hearing = Task { [weak self] in
            var told = Set<String>()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, await self.extensions.hearsHappenings else { continue }
                // The person's switch for the calendar holds here too.
                if (try? await self.permissions.policy())?.disabled.contains(.calendar) == true { continue }
                let now = self.clock.now
                for event in await self.calendarReader.events(from: now, to: now.addingTimeInterval(5 * 60)) ?? [] where !event.allDay && event.start > now {
                    let key = "\(event.id)\(event.start.timeIntervalSince1970)"
                    guard told.insert(key).inserted else { continue }
                    self.events.publish(.happened(Happening(name: "calendar.starting", title: event.title)))
                }
                if told.count > 512 { told.removeAll() }
            }
        }
        calendarHearing.withLock { $0 = hearing }
    }

    /// After sleep or a clock change: re-arm timers.
    public func rearm() async {
        events.publish(.happened(Happening(name: "mac.woke")))
        await scheduler.reschedule()
        await watchers.rearm()
        await occurrences.reschedule()
        await extensions.replanIfMoved()
    }

    /// Before quitting: stop timers and the socket, and return what system notifications should cover
    /// while Sidefolk is off.
    public func stop() async -> [FallbackNotification] {
        calendarHearing.withLock { $0?.cancel() }
        let fallback = await scheduler.fallbackNotifications(horizon: 7 * 86400) + (await occurrences.fallbackNotifications())
        await scheduler.stop()
        await occurrences.stop()
        await watchers.stop()
        await watchers.flushHistory()
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

    /// Removes expired history, old activity, runs and jobs, long-trashed notes and watches' old checks (D87).
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
        _ = try? await WatchHistoryStore(db).purge(olderThan: now.addingTimeInterval(-Double(WatchHistoryLimits.keepDays) * 86400))
    }

    /// The person's answer to a card. One choice does more than answer it: "Let agents read my notes" sets that group to Allow
    /// (D185), the same setting Trust shows. Only here, and only for the card that offered it, so nothing but the person's own
    /// click on that card can open the group.
    public func answer(_ request: ApprovalRequest, _ decision: ApprovalDecision) async {
        var decision = decision
        if decision == .allowAgentsToRead {
            if request.canAllowAgentsToRead, request.caller.kind == "external" {
                await settings.update { $0.agentAccess.read = .allow }
            } else {
                decision = .allowOnce
            }
        }
        await broker.resolve(id: request.id, decision: decision)
    }
}
