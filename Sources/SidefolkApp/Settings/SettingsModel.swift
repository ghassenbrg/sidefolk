import AppKit
import Foundation
import Observation
import SidefolkCore

/// The Settings window's tabs.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, companion, ai, voice, agents, privacy, extensions
    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .companion: String(localized: "Companion")
        case .ai: String(localized: "AI")
        case .voice: String(localized: "Voice", comment: "A Settings tab: talking to the companion and its spoken replies. Seven tabs share one toolbar: keep it short")
        case .agents: String(localized: "Agents")
        case .privacy: String(localized: "Privacy & Permissions", comment: "A Settings tab. Six tabs share one toolbar, so keep it short (“Privacy” will do)")
        case .extensions: String(localized: "Extensions")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .companion: "face.smiling"
        case .ai: "sparkles"
        case .voice: "waveform"
        case .agents: "terminal"
        case .privacy: "hand.raised"
        case .extensions: "puzzlepiece.extension"
        }
    }
}

/// Everything the Settings window shows and changes. Settings go through `runtime.settings`,
/// Guard state through `runtime.permissions`, the rest through the facade. Nothing here is a
/// placeholder: every control changes something real.
@MainActor @Observable
final class SettingsModel {
    let services: AppServices
    var runtime: SidefolkRuntime { services.runtime }

    private(set) var settings: AppSettings

    // General
    private(set) var notificationsAllowed: Bool?
    private(set) var openAtLogin = false
    private(set) var loginError: UserFacingError?

    // AI
    @ObservationIgnored private(set) lazy var ai = AISettingsModel(parent: self)

    // Voice
    @ObservationIgnored private(set) lazy var voice = VoiceSettingsModel(parent: self)

    // Privacy & Permissions
    private(set) var storage: StorageSummary?
    private(set) var folders: [GrantedFolder] = []
    private(set) var grants: [Grant] = []
    private(set) var policy = GuardPolicy()
    /// The sheet that says what Full access means is showing (from Settings or the menu bar).
    var confirmingFullAccess = false
    private(set) var folderError: UserFacingError?
    private(set) var dataMessage: Result<String, UserFacingError>?

    // Extensions
    private(set) var extensions: [ExtensionInfo] = []
    /// Bundled samples not installed yet ("Try System Vitals").
    private(set) var samples: [(name: String, folder: URL)] = []
    private(set) var skills: [SkillInfo] = []
    private(set) var integration: IntegrationStatus?
    private(set) var extensionError: UserFacingError?
    private(set) var integrationError: UserFacingError?
    private(set) var integrationBusy = false

    private var eventTask: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
        settings = services.runtime.settings.current
    }

    // MARK: Lifecycle

    /// Follows changes made elsewhere (the Ask panel, an approval, an installer) while the window is open.
    func start() {
        guard eventTask == nil else { return }
        let stream = runtime.events.stream()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard case .dataChanged(let domain) = event, let self else { continue }
                switch domain {
                case .settings:
                    settings = runtime.settings.current
                    integration = await services.integrationStatus()
                case .permissions: await loadPermissions()
                case .extensions:
                    extensions = await services.extensions()
                    samples = await services.sampleExtensions()
                case .skills: skills = await services.skills()
                default: break
                }
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
    }

    /// Reads everything the tabs show. Cheap enough to run whenever the window opens.
    func refresh() async {
        settings = runtime.settings.current
        openAtLogin = services.openAtLogin
        notificationsAllowed = await services.notificationsAuthorized()
        await loadPermissions()
        storage = await services.storageSummary()
        extensions = await services.extensions()
        samples = await services.sampleExtensions()
        skills = await services.skills()
        integration = await services.integrationStatus()
        await ai.refresh()
        await voice.refresh()
    }

    func loadPermissions() async {
        folders = (try? await runtime.permissions.folders()) ?? []
        grants = (try? await runtime.permissions.grants()) ?? []
        policy = (try? await runtime.permissions.policy()) ?? GuardPolicy()
    }

    // MARK: Settings

    /// Applies a change to the local copy at once, then persists it and tells the app.
    func update(_ change: @escaping @Sendable (inout AppSettings) -> Void) {
        change(&settings)
        let services = self.services
        let store = runtime.settings
        Task {
            await store.update(change)
            services.settingsChanged()
        }
    }

    // MARK: General

    func setOpenAtLogin(_ on: Bool) {
        loginError = services.setOpenAtLogin(on)
        openAtLogin = services.openAtLogin
    }

    func requestNotifications() async {
        await services.requestNotifications()
        notificationsAllowed = await services.notificationsAuthorized()
    }

    /// Quiet mode lives in settings (so it survives a relaunch) and in Attention (which holds bubbles).
    func setQuiet(until date: Date?) {
        update { $0.quietUntil = date }
        let quiet = date != nil
        let attention = runtime.attention
        Task { await attention.update { $0.quiet = quiet } }
    }

    func tomorrowMorning(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        return cal.date(bySettingHour: settings.morningHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    func setDebugLogging(_ on: Bool) {
        update { $0.debugLogging = on }
        Log.shared.setDebug(on)
    }

    // MARK: Privacy & Permissions

    func grantFolder(_ url: URL) async {
        folderError = nil
        do {
            try await runtime.permissions.grantFolder(url.path, access: .readwrite)
            runtime.events.changed(.permissions)
        } catch let error as UserFacingError {
            folderError = error
        } catch {
            folderError = UserFacingError("I couldn't add that folder. Nothing was changed.", detail: String(describing: error))
        }
        await loadPermissions()
    }

    /// Re-grants a folder with different access (the store only ever upgrades, so revoke first).
    func setAccess(_ folder: GrantedFolder, _ access: GrantedFolder.Access) async {
        guard folder.access != access else { return }
        try? await runtime.permissions.revokeFolder(folder.path)
        try? await runtime.permissions.grantFolder(folder.path, access: access)
        runtime.events.changed(.permissions)
        await loadPermissions()
    }

    func removeFolder(_ folder: GrantedFolder) async {
        try? await runtime.permissions.revokeFolder(folder.path)
        runtime.events.changed(.permissions)
        await loadPermissions()
    }

    func revoke(_ grant: Grant) async {
        try? await runtime.permissions.revokeGrant(id: grant.id)
        runtime.events.changed(.permissions)
        await loadPermissions()
    }

    func setPolicy(_ change: (inout GuardPolicy) -> Void) async {
        var next = policy
        change(&next)
        policy = next
        try? await runtime.permissions.setPolicy(next)
        runtime.events.changed(.permissions)
    }

    /// Full access only after its sheet (`FullAccessSheet`); every other mode at once.
    func setMode(_ mode: GuardMode) async {
        await setPolicy { $0.mode = mode }
    }

    func toolTitle(_ name: String) -> String {
        runtime.registry.tool(named: name)?.spec.title ?? Describe.toolName(name)
    }

    func exportData(to url: URL) async {
        if let error = await services.exportData(to: url) {
            dataMessage = .failure(error)
        } else {
            dataMessage = .success(String(localized: "Exported to \(FolderAccess.displayPath(url.path))."))
        }
    }

    func exportDiagnostics(to url: URL) async {
        if let error = await services.exportDiagnostics(to: url) {
            dataMessage = .failure(error)
        } else {
            dataMessage = .success(String(localized: "Diagnostics saved to \(FolderAccess.displayPath(url.path)). They contain no notes or messages."))
        }
    }

    func deleteAllData() async -> UserFacingError? {
        let error = await services.deleteAllData()
        if error == nil { await refresh() }
        return error
    }

    // MARK: Extensions

    func setEnabled(_ ext: ExtensionInfo, _ on: Bool) async {
        await services.setExtensionEnabled(ext.id, on)
        extensions = await services.extensions()
    }

    /// Asks before letting changed tools run: they can do things the user never agreed to.
    func reviewToolChanges(_ ext: ExtensionInfo) async {
        let alert = NSAlert()
        alert.messageText = String(localized: "Let \(ext.name) use its changed tools?")
        alert.informativeText = String(localized: """
            These changed or appeared since you installed it: \(Wording.list(ext.pendingTools)). \
            Approve only if you expected an update from \(ext.name).
            """)
        alert.addButton(withTitle: String(localized: "Approve"))
        alert.addButton(withTitle: String(localized: "Not now"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        extensionError = await services.approveToolChanges(ext.id)
        extensions = await services.extensions()
    }

    func preview(folder: URL) async -> ExtensionInstallPreview? {
        extensionError = nil
        switch await services.previewExtension(at: folder) {
        case .success(let preview): return preview
        case .failure(let error):
            extensionError = error
            return nil
        }
    }

    func install(_ preview: ExtensionInstallPreview) async -> UserFacingError? {
        let error = await services.installExtension(preview)
        extensions = await services.extensions()
        samples = await services.sampleExtensions()
        return error
    }

    func uninstall(_ ext: ExtensionInfo) async {
        extensionError = await services.uninstallExtension(ext.id)
        extensions = await services.extensions()
    }

    func addMCPServer(name: String, command: String, arguments: [String]) async -> UserFacingError? {
        let error = await services.addMCPServer(name: name, command: command, arguments: arguments)
        extensions = await services.extensions()
        return error
    }

    func deleteSkill(_ skill: SkillInfo) async {
        await services.deleteSkill(skill.name)
        skills = await services.skills()
    }

    func connectClaudeCode(hooks: Bool) async {
        await integrate { await $0.connectClaudeCode(hooks: hooks) }
    }

    func disconnectClaudeCode() async { await integrate { await $0.disconnectClaudeCode() } }
    func connectCodex() async { await integrate { await $0.connectCodex() } }
    func installCommandLineTool() async { await integrate { await $0.installCommandLineTool() } }
    func removeCommandLineTool() async { await integrate { await $0.removeCommandLineTool() } }
    func disconnectCodex() async { await integrate { await $0.disconnectCodex() } }

    private func integrate(_ action: @MainActor (AppServices) async -> UserFacingError?) async {
        integrationBusy = true
        integrationError = await action(services)
        integration = await services.integrationStatus()
        integrationBusy = false
    }

    func clearExtensionError() { extensionError = nil }
}
