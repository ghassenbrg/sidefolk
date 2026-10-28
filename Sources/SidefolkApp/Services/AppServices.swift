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
    var folk: String?
    var toolNames: [String]
    var watcherNames: [String]
    var permissionLines: [String]
    var warnings: [String]
    var sandboxed: Bool
    var lastError: String?
    /// Ships with Sidefolk (D39): it can be switched off, not uninstalled.
    var bundled: Bool
    /// Tools that changed or appeared since the user approved the extension; on hold until approved again.
    var pendingTools: [String] = []
    var iconPath: String?
    /// Sidefolk's AI wrote it for the person, who installed it from the drafts.
    var fromDraft = false

    var look: ExtensionLook { ExtensionLook(name: name, iconPath: iconPath, folk: folk) }
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
    var folk: String?
    var iconPath: String?
    /// A draft Sidefolk's AI wrote at the person's request (D39), not a folder from elsewhere.
    var fromDraft = false

    var look: ExtensionLook { ExtensionLook(name: name, iconPath: iconPath, folk: folk) }
}

/// An extension draft Sidefolk's AI wrote, waiting in the drafts folder for review (D39).
struct ExtensionDraftInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var title: String
    var version: String?
    var folder: URL
    var modified: Date
}

/// A built-in extension that couldn't be installed on this Mac (git missing, for example).
struct UnavailableExtension: Identifiable, Hashable {
    var id: String
    var name: String
    var message: String
    var look: ExtensionLook
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
    /// The levels Claude Code's `--effort` takes; empty when it has no such flag.
    var claudeEfforts: [ReasoningEffort] = []
    var codex: CLIStatus
    /// Codex's own model list (bundled with the CLI), with each model's efforts; empty when it can't be read.
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
    var claudeSkillInstalled: Bool
    /// Why the skill can't be installed in Claude Code (a link of the person's own in its place), if so.
    var claudeSkillNote: String? = nil
    var claudeHooksInstalled: Bool
    var codexFound: Bool
    var codexMCPInstalled: Bool
    var codexSkillInstalled: Bool
    var codexSkillNote: String? = nil
    var codexHooksInstalled: Bool
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
    /// Settings › Voice's side: microphone, languages, voices, the ElevenLabs key, the test.
    var voiceServices: any VoiceServices { get }

    // Reminders
    func completeReminder(_ id: String) async
    func snoozeReminder(_ id: String, until: Date) async
    func cancelReminder(_ id: String) async
    func createReminder(title: String, when: String) async -> UserFacingError?
    /// A reminder that belongs to a note or task (D49); `when` is natural language or ISO 8601.
    func remind(about item: NotebookItem, when: String) async -> UserFacingError?
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
    /// Built-in extensions this Mac can't run yet, and why.
    func unavailableExtensions() async -> [UnavailableExtension]
    /// Tries the built-in extensions again (after installing git, say).
    func retryBuiltInExtensions() async
    /// Drafts Sidefolk's AI wrote, newest first.
    func extensionDrafts() async -> [ExtensionDraftInfo]
    /// Moves a draft to the Trash.
    func deleteExtensionDraft(_ name: String) async -> UserFacingError?
    func revealExtensionDraft(_ draft: ExtensionDraftInfo)
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
    func connectCodex(hooks: Bool) async -> UserFacingError?
    func disconnectCodex() async -> UserFacingError?
    /// Copies how to add Sidefolk to any other MCP client (command, config snippets, the skill's folder).
    func copySetupInstructions()
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
    /// Opens Settings, on `tab` if given (Agents: connect Claude Code / Codex, install the sidefolk command).
    func openSettings(tab: SettingsTab?)
    /// Opens the About window: the logo, the version, the notices.
    func showAbout()
    /// Opens the Ask panel with the start of a sentence typed in, for the user to finish; with an
    /// empty one, as it was left.
    func openAsk(prefill: String)
}
