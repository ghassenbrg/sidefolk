import AppKit
import SidefolkCore

extension AppCoordinator {
    // MARK: App

    var openAtLogin: Bool { LoginItem.isEnabled }

    func setOpenAtLogin(_ on: Bool) -> UserFacingError? { LoginItem.set(on) }

    func notificationsAuthorized() async -> Bool {
        let status = await notifier.authorizationStatus()
        let allowed = status == .authorized || status == .provisional
        await runtime.attention.update { $0.systemNotificationsAllowed = allowed }
        return allowed
    }

    func requestNotifications() async {
        _ = await notifier.requestAuthorization()
        _ = await notificationsAuthorized()
    }

    // MARK: Integrations

    /// Where the `sidefolk` helper lives inside the running app bundle.
    var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sidefolk").path
    }

    var integrations: AgentIntegrations {
        #if DEBUG
        let env = ["SIDEFOLK_HOME": runtime.paths.home.path]
        #else
        let env: [String: String] = [:]
        #endif
        return AgentIntegrations(locations: .standard(), helperPath: stableHelperPath, helperEnvironment: env,
                                 skill: ResourceLocator.agentSkill)
    }

    func integrationStatus() async -> IntegrationStatus {
        let all = integrations.status()
        func state(_ i: AgentIntegration) -> SidefolkCore.IntegrationStatus.State? { all.first { $0.integration == i }?.state }
        func installed(_ i: AgentIntegration) -> Bool { state(i) == .installed }
        func available(_ i: AgentIntegration) -> Bool {
            if case .unavailable = state(i) { return false }
            return state(i) != nil
        }
        func skillNote(_ i: AgentIntegration) -> String? {
            if case .unavailable(let why) = state(i), available(i == .claudeSkill ? .claudeHooks : .codexHooks) { return why }
            return nil
        }
        let claudeFound = (try? ClaudeBinary.locate(configured: runtime.settings.current.provider.claudePath).get()) != nil || available(.claudeMCP)
        return IntegrationStatus(claudeCodeFound: claudeFound, claudeMCPInstalled: installed(.claudeMCP),
                                 claudeSkillInstalled: installed(.claudeSkill), claudeSkillNote: skillNote(.claudeSkill),
                                 claudeHooksInstalled: installed(.claudeHooks), codexFound: available(.codexMCP),
                                 codexMCPInstalled: installed(.codexMCP), codexSkillInstalled: installed(.codexSkill),
                                 codexSkillNote: skillNote(.codexSkill), codexHooksInstalled: installed(.codexHooks),
                                 cliLinked: commandLineToolInstalled, helperPath: stableHelperPath)
    }

    /// Connect brings the agent to what the card shows: tools and skill in, session updates in or out.
    func connectClaudeCode(hooks: Bool) async -> UserFacingError? {
        await change(install: [.claudeMCP] + skill(.claudeSkill) + (hooks ? [.claudeHooks] : []), remove: hooks ? [] : [.claudeHooks])
    }

    func disconnectClaudeCode() async -> UserFacingError? { await change(remove: [.claudeMCP, .claudeSkill, .claudeHooks]) }

    func connectCodex(hooks: Bool) async -> UserFacingError? {
        await change(install: [.codexMCP] + skill(.codexSkill) + (hooks ? [.codexHooks] : []), remove: hooks ? [] : [.codexHooks])
    }

    func disconnectCodex() async -> UserFacingError? { await change(remove: [.codexMCP, .codexSkill, .codexHooks]) }

    /// The skill goes along when this copy of Sidefolk has one and its place isn't someone else's link;
    /// otherwise the card says why, and the tools connect without it.
    private func skill(_ integration: AgentIntegration) -> [AgentIntegration] {
        if case .unavailable = integrations.status(integration).state { return [] }
        return [integration]
    }

    /// For MCP clients Sidefolk doesn't connect itself: the command, a snippet per client, the skill's folder.
    func copySetupInstructions() {
        installHelperLink()
        let text = integrations.setupInstructions(skillFolder: ResourceLocator.agentSkillFolder?.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Shows exactly what will change in which file (and the backup), then applies it on confirmation.
    /// This is the only path by which Sidefolk edits another agent's configuration (AGENTS.md rules).
    func change(install: [AgentIntegration] = [], remove: [AgentIntegration] = []) async -> UserFacingError? {
        installHelperLink()
        let tool = integrations
        var previews: [IntegrationPreview] = []
        for (i, installing) in install.map({ ($0, true) }) + remove.map({ ($0, false) }) {
            do {
                let p = try tool.preview(i, install: installing)
                if p.changesSomething { previews.append(p) }
            } catch {
                return UserFacingError("I couldn't read \(tool.file(for: i).lastPathComponent).", recovery: "Nothing was changed.",
                                       detail: String(describing: error))
            }
        }
        guard !previews.isEmpty else { return nil }
        let body = previews.map { p in
            "\(p.integration.title) — \(FolderAccess.displayPath(p.file.path))\n" + p.changes.map { "• \($0)" }.joined(separator: "\n")
                + (p.backup.map { "\n" + String(localized: "Backup: \(FolderAccess.displayPath($0.path))") } ?? "")
        }.joined(separator: "\n\n")
        let connecting = previews.contains(where: \.install)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = connecting ? String(localized: "Connect Sidefolk to your agents?") : String(localized: "Disconnect Sidefolk from your agents?")
        alert.informativeText = body + "\n\n" + String(localized: "Restart running sessions to pick this up.")
        alert.addButton(withTitle: connecting ? String(localized: "Connect") : String(localized: "Disconnect"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        for p in previews {
            do {
                let result = p.install ? try tool.install(p.integration) : try tool.remove(p.integration)
                Log.shared.info("integrations", p.install ? "installed" : "removed",
                                ["integration": p.integration.rawValue, "backup": result.backup?.path ?? ""])
            } catch {
                return UserFacingError("I couldn't update \(p.file.lastPathComponent).", recovery: "That file was left as it was.",
                                       detail: String(describing: error))
            }
        }
        runtime.events.changed(.settings)
        return nil
    }
}

extension AppCoordinator {
    /// A stable path for the `sidefolk` helper that agent configs can point at, even if the app moves:
    /// `<data folder>/bin/sidefolk` → the helper inside this app bundle (refreshed at every launch).
    var stableHelperPath: String { runtime.paths.home.appendingPathComponent("bin/sidefolk").path }

    func installHelperLink() {
        let fm = FileManager.default
        let bundled = helperPath
        guard fm.isExecutableFile(atPath: bundled) else { return }
        let bin = runtime.paths.home.appendingPathComponent("bin", isDirectory: true)
        try? fm.createDirectory(at: bin, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let link = stableHelperPath
        if (try? fm.destinationOfSymbolicLink(atPath: link)) == bundled { return }
        try? fm.removeItem(atPath: link)
        do {
            try fm.createSymbolicLink(atPath: link, withDestinationPath: bundled)
        } catch {
            Log.shared.warning("bridge", "couldn't link helper", ["error": String(describing: error)])
        }
    }
}

/// A second copy of Sidefolk (same data folder) would fight over reminders; hand over and quit.
enum AlreadyRunning {
    static func showAndQuit() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Sidefolk is already running")
        alert.informativeText = String(localized: "Look for it on your desktop or in the menu bar. This copy will close.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
        AppDelegate.quit(prepare: false)
    }
}
