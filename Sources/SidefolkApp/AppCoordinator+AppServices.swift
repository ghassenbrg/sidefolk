import AppKit
import SidefolkCore

/// What the Home and Settings windows can ask of Sidefolk (see Services/AppServices.swift).
extension AppCoordinator: AppServices {
    // MARK: Reminders

    func completeReminder(_ id: String) async { _ = try? await runtime.scheduler.complete(id: id) }
    func snoozeReminder(_ id: String, until: Date) async { _ = try? await runtime.scheduler.snooze(id: id, until: until) }
    func cancelReminder(_ id: String) async { _ = try? await runtime.scheduler.cancel(id: id) }

    func createReminder(title: String, when: String) async -> UserFacingError? {
        let out = await runtime.executor.execute(name: "reminders.create", input: ["title": .string(title), "when": .string(when)],
                                                 caller: .user)
        switch out.status {
        case .ok: return nil
        case .denied(let why): return UserFacingError(verbatim: why)
        case .failed(let e): return e
        }
    }

    func editReminder(_ id: String, title: String, when: String) async -> UserFacingError? {
        var date: Date?
        var recurrence: Recurrence??
        let phrase = when.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phrase.isEmpty {
            guard let parsed = whenParser.parse(phrase, now: Date()), parsed.date > Date() else {
                return UserFacingError("I didn't understand “\(phrase)” as a time.", recovery: "Try “tomorrow 9am” or “every monday at 10”.")
            }
            date = parsed.date
            recurrence = .some(parsed.recurrence)
        }
        do {
            _ = try await runtime.scheduler.edit(id: id, title: title, fireAt: date, recurrence: recurrence)
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't change that reminder."))
        }
    }

    // MARK: Watchers

    func pauseWatcher(_ id: String) async { _ = try? await runtime.watchers.pause(id) }
    func resumeWatcher(_ id: String) async { _ = try? await runtime.watchers.resume(id) }
    func stopWatcher(_ id: String) async { _ = await runtime.watchers.remove(id) }
    func checkWatcherNow(_ id: String) async { _ = await runtime.watchers.checkNow(id) }

    // MARK: Sessions, notebook

    func openSession(_ session: AgentSession) {
        let platform = runtime.platform
        // The stored pid only while it still runs the app it was verified as (pids get reused).
        let host = HostTrust.target(for: session)
        Task {
            guard await !platform.activateApplication(pid: host.pid, bundleId: host.bundleId) else { return }
            // Ended, or started somewhere Sidefolk can't verify: say so instead of doing nothing.
            let place = session.projectName.map { String(localized: "It was in \($0).") } ?? ""
            let item = AttentionItem(level: .gentle, source: Self.ownVoice,
                                     title: String(localized: "I can't bring that session to the front."),
                                     body: [String(localized: "Its window may be closed."), place].filter { !$0.isEmpty }.joined(separator: " "))
            bubbles.present(item, .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
        }
    }

    func open(item: NotebookItem) { openHome(item: item) }

    // MARK: Extensions and skills

    func extensions() async -> [ExtensionInfo] {
        let bundledIds = Set(Self.sampleManifests().map(\.id))
        return await runtime.extensions.extensions().map { Self.info($0, bundled: bundledIds.contains($0.id)) }
    }

    func previewExtension(at folder: URL) async -> Result<ExtensionInstallPreview, UserFacingError> {
        let preview = await runtime.extensions.preview(folder: folder)
        guard let manifest = preview.report.manifest else {
            return .failure(UserFacingError(verbatim: String(localized: "That folder isn't a Sidefolk extension."), recovery: preview.report.text.clipped(400)))
        }
        guard preview.canInstall else {
            return .failure(UserFacingError(verbatim: preview.conflict ?? String(localized: "That extension has problems."), recovery: preview.report.text.clipped(400)))
        }
        let summary = preview.report.summary
        var warnings = (summary?.warnings ?? []) + preview.report.warnings
        if let diff = preview.update {
            warnings.insert(String(localized: "Updates \(diff.fromVersion) to \(diff.toVersion).", comment: "Two version numbers"), at: 0)
            warnings += diff.addedPermissions.map { String(localized: "New permission: \($0)") }
        }
        return .success(ExtensionInstallPreview(
            id: manifest.id, name: manifest.name, version: manifest.version, description: manifest.description ?? "",
            sourceFolder: folder, permissionLines: summary?.lines.map(\.text) ?? [], warnings: warnings,
            toolNames: manifest.tools.keys.sorted(), watcherNames: manifest.watchers.keys.sorted(), isUpdate: preview.update != nil))
    }

    func installExtension(_ preview: ExtensionInstallPreview) async -> UserFacingError? {
        do {
            _ = try await runtime.extensions.install(from: preview.sourceFolder)
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't install \(preview.name)."))
        }
    }

    func setExtensionEnabled(_ id: String, _ enabled: Bool) async { try? await runtime.extensions.setEnabled(enabled, id: id) }

    func uninstallExtension(_ id: String) async -> UserFacingError? {
        do {
            try await runtime.extensions.uninstall(id: id)
            try? MCPServerSecrets.save([:], for: id, store: secrets)
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't remove that extension."))
        }
    }

    func approveToolChanges(_ id: String) async -> UserFacingError? {
        do {
            try await runtime.extensions.approveToolChanges(id: id)
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't approve those tools."))
        }
    }

    func addMCPServer(name: String, command: String, arguments: [String]) async -> UserFacingError? {
        let preview = await runtime.extensions.previewMCPServer(name: name, command: command, arguments: arguments)
        if let problem = preview.errors.first { return UserFacingError(verbatim: problem) }
        do {
            _ = try await runtime.extensions.addMCPServer(name: name, command: command, arguments: arguments)
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't add that MCP server."))
        }
    }

    func sampleExtensions() async -> [(name: String, folder: URL)] {
        let installed = Set(await runtime.extensions.extensions().map(\.id))
        return Self.sampleManifests().filter { !installed.contains($0.id) }.map { sample in
            let json = (try? Data(contentsOf: sample.folder.appendingPathComponent(ExtensionManifest.fileName)))
                .flatMap { try? JSONValue.parse(String(decoding: $0, as: UTF8.self)) }
            return (json?.string("name") ?? sample.id, sample.folder)
        }
    }

    func skills() async -> [SkillInfo] {
        runtime.skills.skills().map { SkillInfo(name: $0.name, description: $0.description, bundled: $0.origin == .bundled) }
    }

    func deleteSkill(_ name: String) async { _ = try? runtime.skills.delete(name: name) }

    // AI: AppCoordinator+AIServices.swift

    // MARK: Privacy and data

    func storageSummary() async -> StorageSummary {
        let porter = DataPorter(runtime: runtime)
        let c = await porter.counts()
        return StorageSummary(dataFolder: FolderAccess.displayPath(runtime.paths.home.path),
                              logsFolder: FolderAccess.displayPath(runtime.paths.logs.path),
                              notes: c.notes, reminders: c.reminders, watchers: c.watchers, activity: c.activity,
                              exchanges: c.exchanges, databaseBytes: porter.databaseBytes)
    }

    func exportData(to url: URL) async -> UserFacingError? {
        do {
            try await DataPorter(runtime: runtime).export(to: url)
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't export your data."))
        }
    }

    func deleteAllData() async -> UserFacingError? {
        do {
            _ = await runtime.stop()
            // Also removes the provider keys and every extension's Keychain item (read before the rows go).
            try await DataPorter(runtime: runtime).deleteEverything(secrets: secrets)
            _ = LoginItem.set(false)
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "app.sidefolk")
            Log.shared.info("app", "all data deleted")
            AppDelegate.quit(prepare: false)
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't delete everything."))
        }
    }

    func revealDataFolder() { NSWorkspace.shared.activateFileViewerSelecting([runtime.paths.home]) }

    /// Logs plus a summary without personal content (versions, settings minus secrets, counts).
    func exportDiagnostics(to url: URL) async -> UserFacingError? {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("sidefolk-diagnostics-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            if fm.fileExists(atPath: runtime.paths.logs.path) {
                // Each line redacted again on the way out (paths, tokens), not the raw files.
                try Log.copySanitized(from: runtime.paths.logs, to: staging.appendingPathComponent("Logs"))
            }
            var s = runtime.settings.current
            s.companionName = "(hidden)"
            let c = await DataPorter(runtime: runtime).counts()
            let summary: JSONValue = [
                "app": .string(SidefolkVersion.current),
                "macOS": .string(ProcessInfo.processInfo.operatingSystemVersionString),
                "settings": (try? JSONValue.from(s)) ?? .null,
                "counts": ["notes": .number(Double(c.notes)), "reminders": .number(Double(c.reminders)),
                           "watchers": .number(Double(c.watchers)), "activity": .number(Double(c.activity))],
                "extensions": .array(((try? await runtime.extensionStore.all()) ?? []).map {
                    ["id": .string($0.id), "version": .string($0.version), "enabled": .bool($0.enabled), "lastError": .string($0.lastError ?? "")]
                }),
            ]
            try Data(summary.jsonString.utf8).write(to: staging.appendingPathComponent("summary.json"))
            try? fm.removeItem(at: url)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", "--sequesterRsrc", staging.path, url.path]
            try SpawnLock.withLock { try ditto.run() }
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw UserFacingError("Zipping the diagnostics failed.") }
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't export diagnostics."))
        }
    }

    // MARK: App

    func settingsChanged() {
        let s = runtime.settings.current
        Log.shared.setDebug(s.debugLogging)
        Task {
            await runtime.attention.update { env in
                env.quiet = s.isQuiet(at: Date())
                env.presence = s.presence
                env.sounds = s.sounds
            }
        }
        applyCompanionSettings()
    }

    func openAsk(prefill: String) { showAsk(prefill: prefill.isEmpty ? nil : prefill) }

    func replayOnboarding() {
        Task { await runtime.settings.update { $0.onboardingDone = false } }
        onboarding.start()
    }

    // MARK: Helpers

    /// `fallback` is already worded in the app's language.
    static func userFacing(_ error: Error, fallback: String) -> UserFacingError {
        if let e = error as? UserFacingError { return e }
        return UserFacingError(verbatim: fallback, detail: String(describing: error))
    }

    static func info(_ e: SidefolkCore.ExtensionInfo, bundled: Bool) -> ExtensionInfo {
        ExtensionInfo(
            id: e.id, name: e.name, version: e.version, description: e.description ?? "",
            kind: e.kind == .mcp ? .mcpServer : .sidefolk, enabled: e.enabled, folk: e.folk ?? "byte",
            toolNames: e.tools.map { $0.title.isEmpty ? $0.name : $0.title }, watcherNames: e.watchers.map(\.title),
            permissionLines: e.summary.lines.map(\.text), warnings: e.summary.warnings + (e.hasPendingToolChanges
                ? [String(localized: "Some tools changed since you installed it; they're on hold until you approve the change.")] : [])
                + e.toolWarnings,
            sandboxed: e.summary.sandboxed, lastError: e.lastError, bundled: bundled,
            pendingTools: e.tools.filter(\.quarantined).map { $0.title.isEmpty ? $0.name : $0.title })
    }

    /// Sample extensions shipped inside the app.
    static func sampleManifests() -> [(id: String, folder: URL)] {
        guard let dir = ResourceLocator.sampleExtensions,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.compactMap { name in
            let folder = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(ExtensionManifest.fileName)),
                  let json = try? JSONValue.parse(String(decoding: data, as: UTF8.self)), let id = json.string("id") else { return nil }
            return (id, folder)
        }
    }
}
