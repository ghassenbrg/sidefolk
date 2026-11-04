#if DEBUG
import AppKit
import SidefolkCore

/// A stand-in for the real app services, for rendering the windows with sample data (UISnapshots).
/// Store-backed actions really change the in-memory runtime; engine actions return plausible values.
/// Dev only: nothing here touches the user's files, Keychain, agent configs or network.
@MainActor
final class FixtureServices: AppServices {
    let runtime: SidefolkRuntime
    private(set) var openAtLogin = false
    /// Saved API keys; snapshots change them to show each provider's states.
    var keys: Set<APIKeyTarget> = []
    /// What Settings › AI finds; snapshots change it to show each provider's states.
    var detection = FixtureServices.sampleDetection
    let voice = FixtureVoiceServices()
    var voiceServices: any VoiceServices { voice }
    /// A published snapshot that looked an hour ago; snapshots set other phases.
    let updates: UpdateModel = {
        let model = UpdateModel()
        model.running = "0.1.0 snapshot 411"
        model.version = ReleaseVersion("0.1.0-snapshot.411")!
        model.lastCheck = Date().addingTimeInterval(-3600)
        model.phase = .upToDate
        return model
    }()
    /// Nothing restored; snapshots fill it to show a restore's follow-up.
    let restore = RestoreModel()
    let location = FixtureLocationServices()
    var locationServices: any LocationServices { location }

    init(runtime: SidefolkRuntime, keys: Set<APIKeyTarget> = []) {
        self.runtime = runtime
        self.keys = keys
    }

    // MARK: Reminders

    func completeReminder(_ id: String) async { await changeReminder(id) { $0.state = .done } }
    func cancelReminder(_ id: String) async { await changeReminder(id) { $0.state = .cancelled } }

    func snoozeReminder(_ id: String, until: Date) async {
        await changeReminder(id) {
            $0.state = .snoozed
            $0.snoozedUntil = until
        }
    }

    func createReminder(title: String, when: String) async -> UserFacingError? {
        guard let minutes = Int(when.filter(\.isNumber)), when.contains("min") else {
            return UserFacingError("I couldn't tell when “\(when)” is. Nothing was saved.", recovery: "Try “in 20 min” or “tomorrow 9:00”.")
        }
        try? await runtime.reminderStore.save(Reminder(title: title, fireAt: Date().addingTimeInterval(Double(minutes) * 60), source: "user"))
        runtime.events.changed(.reminders)
        return nil
    }

    func remind(about item: NotebookItem, when: String) async -> UserFacingError? {
        guard let date = ISO8601DateFormatter().date(from: when) else { return UserFacingError("I couldn't tell when “\(when)” is.") }
        var reminder = Reminder(title: item.title, fireAt: date, source: "user")
        reminder.itemId = item.id
        try? await runtime.reminderStore.save(reminder)
        runtime.events.changed(.reminders)
        return nil
    }

    private func changeReminder(_ id: String, _ change: (inout Reminder) -> Void) async {
        guard var r = try? await runtime.reminderStore.reminder(id: id) else { return }
        change(&r)
        r.updatedAt = Date()
        try? await runtime.reminderStore.save(r)
        runtime.events.changed(.reminders)
    }

    // MARK: Watchers

    func pauseWatcher(_ id: String) async { await changeWatcher(id) { $0.state = .paused } }
    func resumeWatcher(_ id: String) async { await changeWatcher(id) { $0.state = .active } }
    func reorderWatchers(_ ids: [String]) async { _ = ids }
    func setWatcherDisplay(_ id: String, _ display: Watcher.Display) async -> String? {
        await changeWatcher(id) { $0.display = display }
        return nil
    }
    func setWatcherAffixes(_ id: String, prefix: String?, suffix: String?) async {
        await changeWatcher(id) { $0.valuePrefix = prefix; $0.valueSuffix = suffix }
    }
    func checkWatcherNow(_ id: String) async { await changeWatcher(id) { $0.lastCheckedAt = Date() } }

    func stopWatcher(_ id: String) async {
        try? await runtime.watcherStore.delete(id: id)
        runtime.events.changed(.watchers)
    }

    private func changeWatcher(_ id: String, _ change: (inout Watcher) -> Void) async {
        guard var w = try? await runtime.watcherStore.watcher(id: id) else { return }
        change(&w)
        w.updatedAt = Date()
        try? await runtime.watcherStore.save(w)
        runtime.events.changed(.watchers)
    }

    // MARK: Sessions, notebook

    func openSession(_ session: AgentSession) {}
    func open(item: NotebookItem) {}
    func openConversation(_ thread: String?) {}
    func openActivity() {}
    func hint(for text: String) -> String? {
        IntentParser().parse(text, now: Date(), knownCollections: [])?.hint ?? String(localized: "Ask \("Claude")")
    }
    func understands(_ text: String) -> Bool { IntentParser().parse(text, now: Date(), knownCollections: []) != nil }
    func plan(for text: String) -> IntentPlan? { IntentParser().parse(text, now: Date(), knownCollections: [])?.plan() }
    func ask(_ text: String, how: AskHow) {}
    func open(_ found: Found) {}

    // MARK: Extensions and skills

    /// The developer sample's icon in the repository, standing in for an extension's own (snapshots run from the repository).
    static let sampleIcon = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("extensions/hello-folk/icon.pdf").path


    /// From the add-on gallery (D55).
    static let repoPal = ExtensionInfo(
        id: SampleAddons.repoPal, name: "Repo Pal", version: "1.0.0",
        description: "Clone public repositories into a folder you choose, and check, update and read the history of the ones you have.",
        tagline: "Clone, update and check your repositories",
        kind: .sidefolk, enabled: true, folk: "byte",
        toolNames: ["Clone a repository", "Recent commits", "Pull the latest changes", "Repository status"], watcherNames: [],
        permissionLines: ["Can use the internet", "Can read and change files in a folder you name, for that request only",
                          "Can run git (/Applications/Xcode.app/Contents/Developer/usr/bin/git)"],
        warnings: ["It can use the internet while it works in a folder you name, so it could upload what's in that folder."],
        sandboxed: true, lastError: nil, iconPath: sampleIcon, fromGallery: true,
        examples: ["clone https://github.com/octocat/Hello-World into ~/Downloads"], signedBySidefolk: true)

    func extensions() async -> [ExtensionInfo] {
        ([Self.repoPal] + [
            ExtensionInfo(id: SampleAddons.timeZones, name: "Time Zones", version: "1.0.0",
                          description: "The time anywhere in the world, and a time converted between places, with daylight saving worked out exactly.",
                          tagline: "The time anywhere, and times between places",
                          kind: .sidefolk, enabled: true, folk: "tempo", toolNames: ["Convert a time between places", "Time around the world"],
                          watcherNames: [], permissionLines: ["No access to your files or the internet"],
                          warnings: [], sandboxed: true, lastError: nil, iconPath: Self.sampleIcon, fromGallery: true,
                          commands: ["time in …", "what time is it in …", "what's the time in …", "current time in …"],
                          examples: ["what time is it in Tokyo?"], signedBySidefolk: true),
            ExtensionInfo(id: SampleAddons.macPulse, name: "Mac Pulse", version: "1.0.0",
                          description: "Quick answers on battery, disk and memory, and a nudge when the battery or the disk runs low. For a page with live charts, add Mac Pulse+ from the gallery.",
                          tagline: "Quick answers on battery, disk and memory",
                          kind: .sidefolk, enabled: true, folk: "byte", toolNames: ["Battery status", "Disk space", "Memory use"],
                          watcherNames: ["Battery low", "Disk space low"],
                          permissionLines: ["Can run /usr/bin/pmset", "Can run /usr/bin/vm_stat", "Can run /usr/sbin/sysctl",
                                            "No access to your files or the internet"],
                          warnings: [], sandboxed: true, lastError: nil, iconPath: nil, fromGallery: true,
                          examples: ["how much disk space do I have left?"], signedBySidefolk: true),
            ExtensionInfo(id: SampleAddons.skyWatch, name: "Sky Watch", version: "1.0.0",
                          description: "Today's weather and the week ahead for any place, and a heads-up before rain, from Open-Meteo. Only the place you ask about leaves your Mac.",
                          tagline: "Today's weather and the week ahead",
                          kind: .sidefolk, enabled: false, folk: "scout", toolNames: ["Weather forecast"], watcherNames: ["Rain soon"],
                          permissionLines: ["Can use the internet"], warnings: [], sandboxed: true, lastError: nil,
                          iconPath: nil, fromGallery: true, examples: ["will it rain in Lisbon this week?"],
                          services: [.init(name: "Open-Meteo", hosts: ["api.open-meteo.com", "geocoding-api.open-meteo.com"])], signedBySidefolk: true),
            ExtensionInfo(id: "local.hacker-news", name: "Hacker News", version: "0.1.0",
                          description: "The top stories on Hacker News, with their scores and links.",
                          kind: .sidefolk, enabled: true, folk: nil, toolNames: ["Top stories", "Story comments"], watcherNames: [],
                          permissionLines: ["Can use the internet"],
                          warnings: ["Some tools changed since you installed it; they're on hold until you approve the change."],
                          sandboxed: true, lastError: nil, pendingTools: ["Story comments"], fromDraft: true),
            ExtensionInfo(id: "dev.example.air-quality", name: "Air Quality", version: "0.4.2",
                          description: "Air quality and pollen for any place, from Open-Meteo.",
                          kind: .sidefolk, enabled: false, folk: "seed", toolNames: ["air_quality", "pollen"], watcherNames: [],
                          permissionLines: ["Can use the internet"],
                          warnings: [], sandboxed: true,
                          lastError: "It crashed 3 times in 5 minutes, so I turned it off. Nothing else was affected.",
                          services: [.init(name: "Open-Meteo", hosts: ["air-quality-api.open-meteo.com"])]),
            // A copy made for an older Sidefolk (D101): listed, with its update instead of a switch.
            ExtensionInfo(id: "dev.example.marbles", name: "Marbles", version: "1.0.0", description: "A game of marbles on the desktop.",
                          kind: .sidefolk, enabled: true, folk: nil, toolNames: [], watcherNames: [], permissionLines: [], warnings: [],
                          sandboxed: true, lastError: nil, fromGallery: true, needsAnUpdate: true),
            ExtensionInfo(id: "mcp.github", name: "GitHub", version: "", description: "",
                          kind: .mcpServer, enabled: true, folk: "byte", toolNames: ["create_issue", "list_pull_requests", "search_code"],
                          watcherNames: [], permissionLines: [], warnings: [], sandboxed: false, lastError: nil,
                          command: "npx -y @modelcontextprotocol/server-github@2025.4.8"),
        ]).map(Self.searchable)
    }

    /// What the host hands a search beyond the row, as `ExtensionListQuery.texts(for:)` would: what each may do,
    /// without "No access to…".
    private static func searchable(_ ext: ExtensionInfo) -> ExtensionInfo {
        var ext = ext
        ext.hiddenSearchTexts = ext.permissionLines.filter { !$0.hasPrefix("No access") }
        return ext
    }

    func previewExtension(at folder: URL) async -> Result<ExtensionInstallPreview, UserFacingError> {
        .success(Self.samplePreview)
    }

    func installExtension(_ preview: ExtensionInstallPreview) async -> UserFacingError? { nil }
    func setExtensionEnabled(_ id: String, _ enabled: Bool) async {}
    func approveToolChanges(_ id: String) async -> UserFacingError? { nil }
    func uninstallExtension(_ id: String) async -> UserFacingError? { nil }

    func installCommandLineTool() async -> UserFacingError? { nil }
    func openSettings(tab: SettingsTab?) {}
    func openPalette(_ id: String) {}
    func chooseFilesForCard() {}
    func showAbout() {}
    func openGallery() {}
    func openAsk(prefill: String) {}
    func editReminder(_ id: String, title: String, when: String) async -> UserFacingError? { nil }
    func moveReminder(_ id: String, to date: Date) async -> UserFacingError? {
        _ = try? await runtime.scheduler.snooze(id: id, until: date)
        return nil
    }
    var calendarAccess: CalendarAccess { .allowed }
    func showCalendar(_ on: Bool) async { await runtime.settings.update { $0.showCalendar = on } }
    func openCalendarSettings() {}
    func allowCalendarChanges(_ on: Bool) async { await runtime.settings.update { $0.calendarPage.writes = on } }
    func removeCommandLineTool() async -> UserFacingError? { nil }

    func unavailableExtensions() async -> [UnavailableExtension] { [] }

    func retrySeedPacks() async {}

    func extensionDrafts() async -> [ExtensionDraftInfo] {
        [ExtensionDraftInfo(id: "local.pomodoro-log", name: "pomodoro-log", title: "Pomodoro Log", version: "0.1.0",
                            folder: URL(fileURLWithPath: "/tmp/local.pomodoro-log"), modified: Date().addingTimeInterval(-300))]
    }

    func deleteExtensionDraft(_ name: String) async -> UserFacingError? { nil }
    func revealExtensionDraft(_ draft: ExtensionDraftInfo) {}

    func addMCPServer(name: String, command: String, arguments: [String]) async -> UserFacingError? { nil }

    func skills() async -> [SkillInfo] {
        [
            SkillInfo(name: "weekly-review", description: "Gathers the week's finished tasks and open reminders into one note.", bundled: false),
            SkillInfo(name: "tidy-downloads", description: "Sorts new files in Downloads into the folders you shared.", bundled: true),
        ]
    }

    func deleteSkill(_ name: String) async {}

    // MARK: AI

    static let sampleDetection = ProviderDetection(
        claude: .ready(path: NSHomeDirectory() + "/.local/bin/claude", version: "2.1.12", login: nil),
        claudeEfforts: [.low, .medium, .high, .xhigh, .max],
        codex: .ready(path: "/usr/local/bin/codex", version: "0.160.0", login: .chatGPT),
        codexModels: ["gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna"].map { ModelOption(id: $0, efforts: [.low, .medium, .high, .xhigh, .max],
                                                                                  defaultEffort: .medium) }
            + [ModelOption(id: "gpt-5.5", efforts: [.low, .medium, .high, .xhigh], defaultEffort: .medium)],
        ollama: .running(models: [ModelOption(id: "qwen3:8b", usesTools: true), ModelOption(id: "llama3.1:8b", usesTools: true),
                                  ModelOption(id: "gemma3:4b", usesTools: false), ModelOption(id: "glm-5.2:cloud", usesTools: true, cloud: true)]),
        lmStudio: .notInstalled)

    func detectProviders(_ provider: ProviderSettings) async -> ProviderDetection { detection }

    func testProvider(_ provider: ProviderSettings) async -> Result<String, UserFacingError> {
        .success("Codex answered “ok” in 3.1 s using its default model.")
    }

    func listModels(_ provider: ProviderSettings) async -> Result<[ModelOption], UserFacingError> {
        let preset = provider.preset
        switch preset {
        case .ollama, .lmStudio:
            guard case .running(let models) = preset == .ollama ? detection.ollama : detection.lmStudio else {
                return .failure(UserFacingError("I couldn't reach \(preset.name) on this Mac."))
            }
            return .success(models)
        case .openAI:
            return .success(["gpt-5-mini", "gpt-4.1-mini", "gpt-5", "gpt-5.5", "o3"].map { ModelOption(id: $0) })
        default:
            return .success((preset.suggestedModels + preset.suggestedSmartModels).map { ModelOption(id: $0) })
        }
    }

    func hasAPIKey(_ target: APIKeyTarget, customAddress: String) -> Bool { keys.contains(target) }

    func setAPIKey(_ key: String?, for target: APIKeyTarget, customAddress: String) {
        if key == nil { keys.remove(target) } else { keys.insert(target) }
    }

    func moveCustomKey(from oldAddress: String, to newAddress: String) {}

    func lastContextPreview() async -> String? {
        """
        [system] You are Sidefolk, a calm desktop companion. Be brief. Mon 26 Oct, 09:41, Europe/Paris.
        [context] Frontmost app: Xcode. Quiet mode: off.
        [about you] Prefers short, direct answers. · Mornings are for deep work. · Works in Swift and TypeScript.
        [notebook] Sidefolk › “Extensions could bring their own folk” (idea, 2 days ago)
        [live] 3 reminders today · watching 3 things · Codex working in pockito
        [user] what ideas did I save for sidefolk?
        [tools] notebook_search, notebook_add, reminder_create, watch_create, web_fetch (5 of 23)
        """
    }

    // MARK: Integrations

    /// A copy on another data folder (D86): its stand-ins, where the cards say Connect writes.
    var devCopy = false

    func integrationStatus() async -> IntegrationStatus {
        // Claude Code connected with everything; Codex connected before the skill shipped, so its card offers the update.
        // A dev copy: nothing connected yet, and every place inside its folder.
        let home = NSHomeDirectory() + "/sidefolk/build/qa-1"
        let places = devCopy
            ? IntegrationLocations.forApp(paths: SidefolkPaths(home: URL(fileURLWithPath: home, isDirectory: true)))
                .shownPlaces(commandLineTool: URL(fileURLWithPath: home + "/agent-configs/.local/bin/sidefolk"))
                .map { IntegrationStatus.ShownPlace(usual: $0.usual, shown: $0.shown) }
            : []
        return IntegrationStatus(claudeCodeFound: true, claudeMCPInstalled: !devCopy, claudeSkillInstalled: !devCopy, claudeHooksInstalled: !devCopy,
                                 codexFound: true, codexMCPInstalled: !devCopy, codexSkillInstalled: false, codexHooksInstalled: false,
                                 cliLinked: !devCopy, helperPath: "~/Library/Application Support/Sidefolk/bin/sidefolk", places: places)
    }

    func connectClaudeCode(hooks: Bool) async -> UserFacingError? { nil }
    func disconnectClaudeCode() async -> UserFacingError? { nil }
    func connectCodex(hooks: Bool) async -> UserFacingError? { nil }
    func disconnectCodex() async -> UserFacingError? { nil }
    func copySetupInstructions() {}

    // MARK: Conversations

    /// Snapshots never reach a model: the page shows how it looks without one.
    func continueConversation(_ thread: String, text: String) async -> AgentRunHandle? { nil }
    func stopConversation(run runId: String) async {}
    func deleteConversation(_ thread: String) async -> UserFacingError? {
        _ = try? await runtime.exchanges.delete(threadId: thread)
        return nil
    }
    func deleteAllConversations() async -> UserFacingError? {
        try? await runtime.exchanges.deleteAll()
        return nil
    }

    // MARK: Privacy and data

    func storageSummary() async -> StorageSummary {
        let notes = (try? await runtime.notebook.counts())?.items ?? 0
        return StorageSummary(
            dataFolder: NSHomeDirectory() + "/Library/Application Support/Sidefolk", logsFolder: NSHomeDirectory() + "/Library/Logs/Sidefolk",
            notes: notes, reminders: ((try? await runtime.reminderStore.all()) ?? []).count,
            watchers: ((try? await runtime.watcherStore.all()) ?? []).count, activity: (try? await runtime.activity.count()) ?? 0,
            exchanges: (try? await runtime.exchanges.count()) ?? 0, databaseBytes: 1_843_200)
    }

    func exportData(to url: URL) async -> UserFacingError? { nil }
    func deleteAllData() async -> UserFacingError? { nil }
    func revealDataFolder() {}
    func exportDiagnostics(to url: URL) async -> UserFacingError? { nil }
    func backUp(to url: URL, password: String?) async -> UserFacingError? { nil }
    func openBackup(_ url: URL) async -> Result<OpenedBackup, UserFacingError> { .failure(UserFacingError(verbatim: "Not in snapshots.")) }
    func restore(_ backup: OpenedBackup, password: String?) async -> UserFacingError? { nil }
    func undoRestore() -> UserFacingError? { nil }
    func reviewRestored(_ item: RestoreFollowUp.ReviewItem) {}

    // MARK: App

    func setOpenAtLogin(_ on: Bool) -> UserFacingError? {
        openAtLogin = on
        return nil
    }

    func notificationsAuthorized() async -> Bool { false }
    func requestNotifications() async {}
    func settingsChanged() {}
    func companionsUpdated(_ names: [String]) {}
    func showCompanion(_ visible: Bool) {}
    func replayOnboarding() {}
}
#endif
