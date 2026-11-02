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
        await runtime.extensions.setNotificationStatus(status == .notDetermined ? "unknown" : allowed ? "allowed" : "denied")
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

    /// The person's agent configs only when this copy runs on their own data folder; any other data folder
    /// gets stand-ins inside it (D86). The helper is told which folder unless it is the person's own.
    var integrations: AgentIntegrations {
        let paths = runtime.paths
        let env = paths.isDefaultHome ? [:] : ["SIDEFOLK_HOME": paths.home.path]
        return AgentIntegrations(locations: .forApp(paths: paths), helperPath: stableHelperPath, helperEnvironment: env,
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
                                 cliLinked: commandLineToolInstalled, helperPath: stableHelperPath,
                                 places: integrations.locations.shownPlaces(commandLineTool: URL(fileURLWithPath: commandLineToolPath))
                                    .map { IntegrationStatus.ShownPlace(usual: $0.usual, shown: $0.shown) })
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
        guard confirmed(alert) else { return nil }
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

extension AppCoordinator {
    /// The person's answer to a Connect or command-link dialog. A debug copy on a QA folder may be told to
    /// accept the next one (`connect:` below): it writes only stand-ins there (D86), and the log keeps the
    /// dialog's words so a QA run can read what the person would have been shown.
    func confirmed(_ alert: NSAlert) -> Bool {
        #if DEBUG
        if devAcceptsNextConfirmation, !runtime.paths.isDefaultHome {
            devAcceptsNextConfirmation = false
            Log.shared.info("integrations", "dev accepted", ["title": alert.messageText, "text": alert.informativeText])
            return true
        }
        #endif
        return alert.runModal() == .alertFirstButtonReturn
    }

    #if DEBUG
    /// connect:claude|codex[:hooks] | connect:cli | disconnect:claude|codex|cli, as the Connections cards do,
    /// with their dialog accepted. Refused on the person's own data folder: there it would be a click nobody made.
    func devConnect(_ command: String) -> Bool {
        let parts = command.split(separator: ":").map(String.init)
        guard parts.count >= 2, ["connect", "disconnect"].contains(parts[0]) else { return false }
        guard !runtime.paths.isDefaultHome else {
            Log.shared.warning("integrations", "dev connect refused on the default data folder")
            return true
        }
        let connect = parts[0] == "connect", hooks = parts.contains("hooks")
        devAcceptsNextConfirmation = true
        Task {
            let error: UserFacingError? = switch (parts[1], connect) {
            case ("claude", true): await connectClaudeCode(hooks: hooks)
            case ("claude", false): await disconnectClaudeCode()
            case ("codex", true): await connectCodex(hooks: hooks)
            case ("codex", false): await disconnectCodex()
            case ("cli", true): await installCommandLineTool()
            case ("cli", false): await removeCommandLineTool()
            default: nil
            }
            devAcceptsNextConfirmation = false
            if let error { Log.shared.warning("integrations", "dev connect failed", ["error": error.message]) }
        }
        return true
    }
    #endif
}
