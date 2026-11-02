import AppKit
import Foundation
import Observation
import SidefolkCore

/// Everything the Settings window shows and changes. Settings go through `runtime.settings`,
/// Guard state through `runtime.permissions`, the rest through the facade. Nothing here is a
/// placeholder: every control changes something real.
@MainActor @Observable
final class SettingsModel {
    let services: AppServices
    var runtime: SidefolkRuntime { services.runtime }

    private(set) var settings: AppSettings
    /// The open tab, the search and where a jump lands (D84).
    @ObservationIgnored let navigation = SettingsNavigation()

    // General
    private(set) var notificationsAllowed: Bool?
    private(set) var openAtLogin = false
    private(set) var loginError: UserFacingError?

    // Attention
    private(set) var heldCount = 0
    /// The agents What may interrupt you lists, by client name (D88): Claude Code and Codex, then every other app that
    /// reached Sidefolk or has a level set.
    private(set) var noticeAgents = ["claude-code", "codex"]
    /// Titles of the watches set apart, by id.
    private(set) var watchTitles: [String: String] = [:]

    // AI
    @ObservationIgnored private(set) lazy var ai = AISettingsModel(parent: self)

    // Voice
    @ObservationIgnored private(set) lazy var voice = VoiceSettingsModel(parent: self)

    // Privacy & Permissions
    @ObservationIgnored private(set) lazy var location = LocationSettingsModel(parent: self)
    private(set) var storage: StorageSummary?
    private(set) var folders: [GrantedFolder] = []
    private(set) var grants: [Grant] = []
    private(set) var policy = GuardPolicy()
    /// The sheet that says what Full access means is showing (from Settings or the menu bar).
    var confirmingFullAccess = false
    private(set) var folderError: UserFacingError?
    private(set) var dataMessage: Result<String, UserFacingError>?
    // Back up and restore (D91): the Back up sheet, a backup chosen and checked for the restore sheet, and what happened.
    var backingUp = false
    var restoreCandidate: RestoreCandidate?
    var backupMessage: Result<String, UserFacingError>?

    // Extensions
    private(set) var extensions: [ExtensionInfo] = []
    /// Samples shipped with the app, not installed yet ("Try Hello Folk").
    /// Built-in extensions this Mac can't run yet.
    private(set) var unavailable: [UnavailableExtension] = []
    /// Extensions Sidefolk's AI wrote, waiting for review (D39).
    private(set) var drafts: [ExtensionDraftInfo] = []
    /// The install preview on screen, from a folder, a sample, a draft, or Sidefolk handing one over.
    var installPreview: ExtensionInstallPreview?
    private(set) var skills: [SkillInfo] = []
    /// Companions and extensions from the add-on gallery (D55).
    @ObservationIgnored private(set) lazy var gallery = AddonGalleryModel(parent: self)
    /// Settings › Companion's grid of the person's companions and its gallery page.
    @ObservationIgnored private(set) lazy var chooser = CompanionChooserModel(parent: self)
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
                    // A companion may have been updated by Update all or by itself (D89): its card no longer offers one.
                    await gallery.readInstalled()
                    await loadNoticeSources()
                case .permissions: await loadPermissions()
                case .attention: await refreshHeld()
                case .extensions:
                    await loadExtensions()
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
        await loadExtensions()
        skills = await services.skills()
        integration = await services.integrationStatus()
        await ai.refresh()
        await voice.refresh()
        location.refresh()
        await refreshHeld()
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

    /// Open, Focus or Quiet until `until` (D84). The settings keep it across a relaunch; the app tells Attention.
    func setAttention(_ mode: AttentionMode, until: Date?) {
        update { $0.setAttention(mode, until: until, now: Date()) }
        Task { await refreshHeld() }
    }

    /// The agents that reached Sidefolk (a tool call or a session) and the watches set apart, for What may interrupt you.
    func loadNoticeSources() async {
        let calls = (try? await runtime.activity.recent(limit: 500)) ?? []
        var names = Set(calls.compactMap { call in
            call.caller.hasPrefix("external:") ? InterruptSource.agentName(String(call.caller.dropFirst("external:".count))) : nil
        })
        names.formUnion(((try? await runtime.sessions.recent(limit: 50)) ?? []).map { InterruptSource.agentName($0.agent) })
        for case .agent(let name) in settings.interruptions.named { names.insert(name) }
        let fixed = ["claude-code", "codex"]
        noticeAgents = fixed + names.subtracting(fixed).filter { !$0.isEmpty }.sorted()
        var titles: [String: String] = [:]
        for id in settings.interruptions.watchOverrides.keys {
            if let w = try? await runtime.watcherStore.watcher(id: id) { titles[id] = w.title }
        }
        watchTitles = titles
    }

    /// How many things wait for Focus or Quiet to end.
    func refreshHeld() async {
        heldCount = await runtime.attention.heldCount
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

    /// Lets Sidefolk read a site without asking from now on (D47); the problem to show, if any.
    func allowSite(_ text: String) async -> UserFacingError? {
        do {
            try await runtime.permissions.allowSite(text)
        } catch {
            return error as? UserFacingError ?? UserFacingError("Sidefolk couldn't save that site.", detail: String(describing: error))
        }
        runtime.events.changed(.permissions)
        await loadPermissions()
        return nil
    }

    /// Changes the stored policy, not this window's copy of it: a copy that failed to load is the default, and
    /// saving it would switch back on what the person turned off.
    func setPolicy(_ change: @escaping @Sendable (inout GuardPolicy) -> Void) async {
        change(&policy)
        try? await runtime.permissions.updatePolicy(change)
        if let saved = try? await runtime.permissions.policy() { policy = saved }
        runtime.events.changed(.permissions)
    }

    /// Full access only after its sheet (`FullAccessSheet`), with its end; every other mode at once.
    func setMode(_ mode: GuardMode, fullAccessEnds: Date? = nil) async {
        await setPolicy { $0.choose(mode, fullAccessEnds: fullAccessEnds) }
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

    /// Every conversation with the AI, and nothing else (D45).
    func deleteConversationHistory() async {
        if let error = await services.deleteAllConversations() {
            dataMessage = .failure(error)
        } else {
            dataMessage = .success(String(localized: "Conversation history deleted."))
        }
        storage = await services.storageSummary()
    }

    // MARK: Extensions

    func loadExtensions() async {
        extensions = await services.extensions()
        unavailable = await services.unavailableExtensions()
        drafts = await services.extensionDrafts()
    }

    /// Shows the install preview for `folder` over Settings (a draft's Review… button).
    func review(folder: URL) async {
        installPreview = await preview(folder: folder)
    }

    func retrySeedPacks() async {
        await services.retrySeedPacks()
        await loadExtensions()
    }

    func deleteDraft(_ draft: ExtensionDraftInfo) async {
        extensionError = await services.deleteExtensionDraft(draft.name)
        await loadExtensions()
    }

    func revealDraft(_ draft: ExtensionDraftInfo) { services.revealExtensionDraft(draft) }

    func setEnabled(_ ext: ExtensionInfo, _ on: Bool) async {
        await services.setExtensionEnabled(ext.id, on)
        extensions = await services.extensions()
    }

    /// A setting an extension declared (D100): through the same tool as any change to it.
    func set(_ row: ExtensionSettingRow, to value: JSONValue) async {
        let outcome = await services.runtime.executor.execute(name: ExtensionSettingRow.tool, input: ["extension": .string(row.extensionId), "key": .string(row.key), "value": value],
                                                              caller: .user)
        extensionError = outcome.problem.map { UserFacingError(verbatim: $0.message) } ?? nil
        extensions = await services.extensions()
    }

    /// What extensions that are on declare and a search finds (D100), best first.
    func addonSettings(matching query: String) -> [ExtensionSettingRow] {
        // The shelf isn't observed. `extensions` is, and changes after every set, so a row found here redraws with its new value.
        _ = extensions
        let all = services.runtime.extensions.shelf.settings.filter(\.listed)
        return SettingsSearch.find(query, in: all.map(\.searchEntry)).compactMap { found in all.first { $0.id == found.id } }
    }

    /// The person's switch for an extension's use of their AI (D100).
    func setAI(_ on: Bool, extensionId id: String) async {
        await services.runtime.extensions.setAIAllowed(extensionId: id, on)
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
        await loadExtensions()
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
    func connectCodex(hooks: Bool) async { await integrate { await $0.connectCodex(hooks: hooks) } }
    func copySetupInstructions() { services.copySetupInstructions() }
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
