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

struct ProviderDetection: Hashable {
    var claudePath: String?
    var claudeVersion: String?
    var ollamaRunning: Bool
    var ollamaModels: [String]
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
    func addMCPServer(name: String, command: String, arguments: [String]) async -> UserFacingError?
    /// Sample extensions shipped with the app that aren't installed yet.
    func sampleExtensions() async -> [(name: String, folder: URL)]
    func skills() async -> [SkillInfo]
    func deleteSkill(_ name: String) async

    // AI
    func detectProviders() async -> ProviderDetection
    func checkProvider() async -> Result<String, UserFacingError>
    func hasAPIKey(for kind: ProviderKind) -> Bool
    func setAPIKey(_ key: String?, for kind: ProviderKind)
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
}
