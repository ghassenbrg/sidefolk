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

    // MARK: Extensions and skills

    func extensions() async -> [ExtensionInfo] {
        [
            ExtensionInfo(id: "app.sidefolk.system-vitals", name: "System Vitals", version: "1.0.0",
                          description: "Tells you when your Mac runs hot, low on memory or low on battery.",
                          kind: .sidefolk, enabled: true, folk: "scout", toolNames: ["vitals_cpu", "vitals_memory", "vitals_battery"],
                          watcherNames: ["High CPU", "Low battery"],
                          permissionLines: ["Read CPU, memory and battery levels", "No internet and no access to your files"],
                          warnings: [], sandboxed: true, lastError: nil, bundled: true),
            ExtensionInfo(id: "dev.lumen.hue", name: "Hue Lights", version: "0.4.2",
                          description: "Turns your Philips Hue lights on and off.",
                          kind: .sidefolk, enabled: false, folk: "nova", toolNames: ["hue_set_scene", "hue_off"], watcherNames: [],
                          permissionLines: ["Talk to devices on your local network"],
                          warnings: [], sandboxed: true,
                          lastError: "It crashed 3 times in 5 minutes, so I turned it off. Nothing else was affected.", bundled: false),
            ExtensionInfo(id: "mcp.github", name: "GitHub", version: "",
                          description: "npx -y @modelcontextprotocol/server-github@2025.4.8",
                          kind: .mcpServer, enabled: true, folk: "byte", toolNames: ["create_issue", "list_pull_requests", "search_code"],
                          watcherNames: [], permissionLines: [], warnings: [], sandboxed: false, lastError: nil, bundled: false),
        ]
    }

    func previewExtension(at folder: URL) async -> Result<ExtensionInstallPreview, UserFacingError> {
        .success(Self.samplePreview)
    }

    static let samplePreview = ExtensionInstallPreview(
        id: "dev.example.weather", name: "Weather", version: "1.2.0",
        description: "Morning forecasts in your brief, and a heads-up before rain.",
        sourceFolder: URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/weather-extension"),
        permissionLines: ["Fetch data from api.open-meteo.com", "Read files in ~/Documents/Travel", "Keep its own data"],
        warnings: ["It can read files in ~/Documents/Travel and use the internet, so it could upload them."],
        toolNames: ["weather_today", "weather_week"], watcherNames: ["Rain soon"], isUpdate: false)

    func installExtension(_ preview: ExtensionInstallPreview) async -> UserFacingError? { nil }
    func setExtensionEnabled(_ id: String, _ enabled: Bool) async {}
    func approveToolChanges(_ id: String) async -> UserFacingError? { nil }
    func uninstallExtension(_ id: String) async -> UserFacingError? { nil }

    func installCommandLineTool() async -> UserFacingError? { nil }
    func openSettings(tab: SettingsTab?) {}
    func showAbout() {}
    func openAsk(prefill: String) {}
    func editReminder(_ id: String, title: String, when: String) async -> UserFacingError? { nil }
    func removeCommandLineTool() async -> UserFacingError? { nil }

    func sampleExtensions() async -> [(name: String, folder: URL)] { [("System Vitals", URL(fileURLWithPath: "/tmp/system-vitals"))] }

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
        codex: .ready(path: "/usr/local/bin/codex", version: "0.160.0", login: .chatGPT),
        codexModels: ["gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna", "gpt-5.5"].map { ModelOption(id: $0) },
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

    func integrationStatus() async -> IntegrationStatus {
        IntegrationStatus(claudeCodeFound: true, claudeMCPInstalled: true, claudeHooksInstalled: false, codexFound: true,
                          codexMCPInstalled: false, cliLinked: true, helperPath: "~/Library/Application Support/Sidefolk/bin/sidefolk")
    }

    func connectClaudeCode(hooks: Bool) async -> UserFacingError? { nil }
    func disconnectClaudeCode() async -> UserFacingError? { nil }
    func connectCodex() async -> UserFacingError? { nil }
    func disconnectCodex() async -> UserFacingError? { nil }

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

    // MARK: App

    func setOpenAtLogin(_ on: Bool) -> UserFacingError? {
        openAtLogin = on
        return nil
    }

    func notificationsAuthorized() async -> Bool { false }
    func requestNotifications() async {}
    func settingsChanged() {}
    func showCompanion(_ visible: Bool) {}
    func replayOnboarding() {}
}
#endif
