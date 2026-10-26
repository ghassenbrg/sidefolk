import AppKit
import SidefolkCore

// The window UI (Home, Settings) talks to the rest of Sidefolk only through `AppServices`.
// Reads that are plain data come straight from the runtime's stores; actions that need an engine
// (scheduler, watcher engine, extension host, installers) go through these methods.

struct ExtensionInfo: Identifiable, Hashable {
    enum Kind: Hashable { case sidefolk, mcpServer }
    var id: String
    var name: String
    var version: String
    var description: String
    var kind: Kind
    var enabled: Bool
    var folk: String
    var toolNames: [String]
    var watcherNames: [String]
    var permissionLines: [String]
    var warnings: [String]
    var sandboxed: Bool
    var lastError: String?
    var bundled: Bool
    /// Tools that changed or appeared since the user approved the extension; on hold until approved again.
    var pendingTools: [String] = []
}

/// What installing an extension would allow, shown before the user confirms.
struct ExtensionInstallPreview: Identifiable, Hashable {
    var id: String
    var name: String
    var version: String
    var description: String
    var sourceFolder: URL
    var permissionLines: [String]
    var warnings: [String]
    var toolNames: [String]
    var watcherNames: [String]
    var isUpdate: Bool
}

struct SkillInfo: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var description: String
    var bundled: Bool
}

/// What Settings › AI shows next to each provider. Everything here is read locally: no prompt, no quota.
struct ProviderDetection: Hashable {
    var claude: CLIStatus
    var codex: CLIStatus
    /// Codex's own model list (bundled with the CLI); empty when it can't be read.
    var codexModels: [ModelOption] = []
    var ollama: LocalServerState
    var lmStudio: LocalServerState
}

/// Where an API key belongs: Anthropic's, or an OpenAI-compatible preset's (bound to its host).
enum APIKeyTarget: Hashable {
    case anthropic
    case preset(ProviderPreset)
}

struct IntegrationStatus: Hashable {
    var claudeCodeFound: Bool
    var claudeMCPInstalled: Bool
    var claudeHooksInstalled: Bool
    var codexFound: Bool
    var codexMCPInstalled: Bool
    var cliLinked: Bool
    var helperPath: String
}

/// Counts and locations for the Privacy page.
struct StorageSummary: Hashable {
    var dataFolder: String
    var logsFolder: String
    var notes: Int
    var reminders: Int
    var watchers: Int
    var activity: Int
    var exchanges: Int
    var databaseBytes: Int64
}

@MainActor
protocol AppServices: AnyObject {
    var runtime: SidefolkRuntime { get }

    // Reminders
    func completeReminder(_ id: String) async
    func snoozeReminder(_ id: String, until: Date) async
    func cancelReminder(_ id: String) async
    func createReminder(title: String, when: String) async -> UserFacingError?
    /// Renames and/or re-times a reminder; `when` is natural language ("tomorrow 9am"), empty keeps the time.
    func editReminder(_ id: String, title: String, when: String) async -> UserFacingError?

    // Watchers
    func pauseWatcher(_ id: String) async
    func resumeWatcher(_ id: String) async
    func stopWatcher(_ id: String) async
    func checkWatcherNow(_ id: String) async

    // Sessions and jobs
    func openSession(_ session: AgentSession)

    // Notebook
    func open(item: NotebookItem)

    // Extensions and skills
    func extensions() async -> [ExtensionInfo]
    func previewExtension(at folder: URL) async -> Result<ExtensionInstallPreview, UserFacingError>
    func installExtension(_ preview: ExtensionInstallPreview) async -> UserFacingError?
    func setExtensionEnabled(_ id: String, _ enabled: Bool) async
    func uninstallExtension(_ id: String) async -> UserFacingError?
    /// Lets the changed tools of an extension run (after the user read what changed).
    func approveToolChanges(_ id: String) async -> UserFacingError?
    func addMCPServer(name: String, command: String, arguments: [String]) async -> UserFacingError?
    /// Sample extensions shipped with the app that aren't installed yet.
    func sampleExtensions() async -> [(name: String, folder: URL)]
    func skills() async -> [SkillInfo]
    func deleteSkill(_ name: String) async

    // AI. The provider is passed in, not read from the store: Settings has just changed it, and saving is async.
    func detectProviders(_ provider: ProviderSettings) async -> ProviderDetection
    /// One tiny request to the provider (it counts toward the user's usage): only on a click.
    func testProvider(_ provider: ProviderSettings) async -> Result<String, UserFacingError>
    /// An OpenAI-compatible preset's models, with its saved key. Free: no tokens.
    func listModels(_ provider: ProviderSettings) async -> Result<[ModelOption], UserFacingError>
    /// - Parameter customAddress: where the custom endpoint's key is bound.
    func hasAPIKey(_ target: APIKeyTarget, customAddress: String) -> Bool
    func setAPIKey(_ key: String?, for target: APIKeyTarget, customAddress: String)
    /// Binds the custom endpoint's key to a new address, after the user agreed to send it there.
    func moveCustomKey(from oldAddress: String, to newAddress: String)
    func lastContextPreview() async -> String?

    // Integrations (each asks for confirmation and makes a backup before changing anything)
    func integrationStatus() async -> IntegrationStatus
    func connectClaudeCode(hooks: Bool) async -> UserFacingError?
    func disconnectClaudeCode() async -> UserFacingError?
    func connectCodex() async -> UserFacingError?
    func disconnectCodex() async -> UserFacingError?
    /// Links the `sidefolk` command into ~/.local/bin (after confirmation), so `sidefolk run` works in a terminal.
    func installCommandLineTool() async -> UserFacingError?
    func removeCommandLineTool() async -> UserFacingError?

    // Privacy and data
    func storageSummary() async -> StorageSummary
    func exportData(to url: URL) async -> UserFacingError?
    func deleteAllData() async -> UserFacingError?
    func revealDataFolder()
    func exportDiagnostics(to url: URL) async -> UserFacingError?

    // App
    var openAtLogin: Bool { get }
    func setOpenAtLogin(_ on: Bool) -> UserFacingError?
    func notificationsAuthorized() async -> Bool
    func requestNotifications() async
    func settingsChanged()
    func showCompanion(_ visible: Bool)
    func replayOnboarding()
    /// Opens Settings › Agents (connect Claude Code / Codex, install the sidefolk command).
    func openAgentSettings()
    /// Opens the Ask panel with the start of a sentence typed in, for the user to finish.
    func openAsk(prefill: String)
}
