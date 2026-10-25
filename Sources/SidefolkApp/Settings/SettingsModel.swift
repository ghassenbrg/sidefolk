import AppKit
import Foundation
import Observation
import SidefolkCore

/// The Settings window's tabs.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, companion, ai, privacy, extensions
    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .companion: "Companion"
        case .ai: "AI"
        case .privacy: "Privacy & Permissions"
        case .extensions: "Extensions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .companion: "face.smiling"
        case .ai: "sparkles"
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
    private(set) var detection: ProviderDetection?
    private(set) var checking = false
    private(set) var checkResult: Result<String, UserFacingError>?
    private(set) var contextPreview: String?
    private(set) var keySaved: [ProviderKind: Bool] = [:]
    private(set) var baseURLError: UserFacingError?

    // Privacy & Permissions
    private(set) var storage: StorageSummary?
    private(set) var folders: [GrantedFolder] = []
    private(set) var grants: [Grant] = []
    private(set) var policy = GuardPolicy()
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
                case .settings: settings = runtime.settings.current
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
        refreshKeys()
        notificationsAllowed = await services.notificationsAuthorized()
        await loadPermissions()
        storage = await services.storageSummary()
        extensions = await services.extensions()
        skills = await services.skills()
        integration = await services.integrationStatus()
        contextPreview = await services.lastContextPreview()
        detection = await services.detectProviders()
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

    // MARK: AI

    func setProvider(_ kind: ProviderKind) {
        guard settings.provider.kind != kind else { return }
        let model = Self.defaultModel(kind)
        let defaultURL = Self.presets[0].url
        update { s in
            s.provider.kind = kind
            s.provider.model = model
            s.provider.smartModel = ""
            if kind == .openAICompatible, s.provider.baseURL.isEmpty { s.provider.baseURL = defaultURL }
        }
        checkResult = nil
    }

    static func defaultModel(_ kind: ProviderKind) -> String {
        switch kind {
        case .none, .openAICompatible: ""
        case .claudeCode: "sonnet"
        case .anthropic: "claude-sonnet-4-5"
        }
    }

    static let presets: [(name: String, url: String)] = [
        ("OpenAI", "https://api.openai.com/v1"),
        ("Ollama", "http://localhost:11434/v1"),
        ("LM Studio", "http://localhost:1234/v1"),
        ("OpenRouter", "https://openrouter.ai/api/v1"),
    ]

    func checkProvider() async {
        checking = true
        checkResult = nil
        checkResult = await services.checkProvider()
        checking = false
        contextPreview = await services.lastContextPreview()
    }

    func redetect() async { detection = await services.detectProviders() }

    func refreshKeys() {
        for kind in [ProviderKind.anthropic, .openAICompatible] { keySaved[kind] = services.hasAPIKey(for: kind) }
    }

    func saveKey(_ key: String, for kind: ProviderKind) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        services.setAPIKey(clean, for: kind)
        refreshKeys()
        checkResult = nil
    }

    func removeKey(for kind: ProviderKind) {
        services.setAPIKey(nil, for: kind)
        refreshKeys()
        checkResult = nil
    }

    enum BaseURLCheck: Equatable {
        case ok
        case invalid
        /// A key is saved for another host; sending it to this one needs the user's yes (SECURITY T18).
        case needsKeyConfirmation(oldHost: String, newHost: String)
    }

    /// Checks a new OpenAI-compatible address: http(s) only, plain http only on this Mac.
    func checkBaseURL(_ text: String) -> BaseURLCheck {
        baseURLError = nil
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty
        else {
            baseURLError = UserFacingError("That isn't a web address. Nothing was saved.", recovery: "It should look like https://api.example.com/v1.")
            return .invalid
        }
        if scheme == "http", !["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) {
            baseURLError = UserFacingError("Plain http is only allowed for servers on this Mac. Nothing was saved.",
                                           recovery: "Use an https address.")
            return .invalid
        }
        let oldHost = URL(string: settings.provider.baseURL)?.host?.lowercased() ?? ""
        if keySaved[.openAICompatible] == true, !oldHost.isEmpty, oldHost != host {
            return .needsKeyConfirmation(oldHost: oldHost, newHost: host)
        }
        return .ok
    }

    func setBaseURL(_ text: String, removingKey: Bool = false) {
        if removingKey { removeKey(for: .openAICompatible) }
        update { $0.provider.baseURL = text }
        baseURLError = nil
        checkResult = nil
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
            folderError = UserFacingError("I couldn't add that folder. Nothing changed.", detail: String(describing: error))
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

    func toolTitle(_ name: String) -> String {
        runtime.registry.tool(named: name)?.spec.title ?? Describe.toolName(name)
    }

    func exportData(to url: URL) async {
        if let error = await services.exportData(to: url) {
            dataMessage = .failure(error)
        } else {
            dataMessage = .success("Exported to \(FolderAccess.displayPath(url.path)).")
        }
    }

    func exportDiagnostics(to url: URL) async {
        if let error = await services.exportDiagnostics(to: url) {
            dataMessage = .failure(error)
        } else {
            dataMessage = .success("Diagnostics saved to \(FolderAccess.displayPath(url.path)). They contain no notes or messages.")
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
    func disconnectCodex() async { await integrate { await $0.disconnectCodex() } }

    private func integrate(_ action: @MainActor (AppServices) async -> UserFacingError?) async {
        integrationBusy = true
        integrationError = await action(services)
        integration = await services.integrationStatus()
        integrationBusy = false
    }

    func clearExtensionError() { extensionError = nil }
}
