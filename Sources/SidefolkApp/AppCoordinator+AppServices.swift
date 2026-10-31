import AppKit
import SidefolkCore

/// What the Home and Settings windows can ask of Sidefolk (see Services/AppServices.swift).
extension AppCoordinator: AppServices {
    // MARK: Reminders

    func completeReminder(_ id: String) async { _ = try? await runtime.scheduler.complete(id: id) }
    func snoozeReminder(_ id: String, until: Date) async { _ = try? await runtime.scheduler.snooze(id: id, until: until) }

    func moveReminder(_ id: String, to date: Date) async -> UserFacingError? {
        do {
            if (try await runtime.reminderStore.reminder(id: id))?.recurrence == nil {
                try await runtime.scheduler.edit(id: id, title: nil, fireAt: date, recurrence: nil)
            } else {
                _ = try await runtime.scheduler.snooze(id: id, until: date)
            }
            return nil
        } catch let error as UserFacingError {
            return error
        } catch {
            return UserFacingError("I couldn't move that reminder.")
        }
    }

    var calendarAccess: CalendarAccess { MacCalendar.access }

    func showCalendar(_ on: Bool) async {
        if on { _ = await MacCalendar.request() }
        await runtime.settings.update { $0.showCalendar = on }
    }

    func openCalendarSettings() { MacCalendar.openSettings() }
    func openActivity() { home.show(section: .activity) }
    func cancelReminder(_ id: String) async { _ = try? await runtime.scheduler.cancel(id: id) }

    func createReminder(title: String, when: String) async -> UserFacingError? {
        let out = await runtime.executor.execute(name: "reminders.create", input: ["title": .string(title), "when": .string(when)],
                                                 caller: .user)
        return out.problem
    }

    func remind(about item: NotebookItem, when: String) async -> UserFacingError? {
        let out = await runtime.executor.execute(name: "reminders.create", input: ["item": .string(item.id), "when": .string(when)],
                                                 caller: .user)
        return out.problem
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
        // Built-ins in the catalog's order rather than by name, so the list reads as the catalog intends.
        let order = Dictionary(runtime.bundledExtensions.entries().enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let infos = await runtime.extensions.extensions().map(Self.info)
        return infos.enumerated().sorted { a, b in
            (order[a.element.id] ?? Int.max, a.offset) < (order[b.element.id] ?? Int.max, b.offset)
        }.map(\.element)
    }

    func previewExtension(at folder: URL) async -> Result<ExtensionInstallPreview, UserFacingError> {
        let preview = await runtime.extensions.preview(folder: folder)
        guard let manifest = preview.report.manifest else {
            return .failure(UserFacingError(verbatim: String(localized: "That folder isn't a Sidefolk extension."), recovery: preview.report.text.clipped(400)))
        }
        guard preview.canInstall else {
            return .failure(UserFacingError(verbatim: preview.conflict ?? String(localized: "That extension has problems."), recovery: preview.report.text.clipped(400)))
        }
        let drafts = runtime.extensionDrafts.directory.resolvingSymlinksInPath().path
        let source: InstallSource = folder.resolvingSymlinksInPath().path.hasPrefix(drafts + "/") ? .draft
            : Self.fromGallery(folder, paths: runtime.paths) ? .gallery : .folder
        guard let review = InstallReview(preview, source: source) else {
            return .failure(UserFacingError(verbatim: String(localized: "That extension has problems."), recovery: preview.report.text.clipped(400)))
        }
        // In the person's language, as the extension will be named everywhere once installed (D76).
        guard let words = preview.report.shownWords(official: source == .gallery && AddonEntry.isOfficial(id: manifest.id)) else {
            return .failure(UserFacingError(verbatim: String(localized: "That extension has problems."), recovery: preview.report.text.clipped(400)))
        }
        return .success(ExtensionInstallPreview(
            id: manifest.id, name: words.name, version: manifest.version, description: words.description,
            sourceFolder: folder, review: review,
            // Titles, as the person will see the tools everywhere else.
            toolNames: words.tools,
            watcherNames: words.watchers,
            commands: manifest.tools.keys.sorted().flatMap { ToolCommands(manifest.tools[$0]?.commands ?? [], words: manifest.words)?.shown ?? [] },
            pageNames: words.pages,
            pagesInBackground: manifest.pages.values.contains { $0.history == true || $0.widget == true },
            folk: manifest.folk, iconPath: preview.report.iconPath))
    }

    /// A folder the add-on gallery downloaded and checked (`AddonStore.fetch`): Sidefolk's own extension (D55).
    static func fromGallery(_ folder: URL, paths: SidefolkPaths) -> Bool {
        let downloads = paths.addons.appendingPathComponent("Downloads").resolvingSymlinksInPath().path
        return folder.resolvingSymlinksInPath().path.hasPrefix(downloads + "/")
    }

    func installExtension(_ preview: ExtensionInstallPreview) async -> UserFacingError? {
        do {
            _ = try await runtime.extensions.install(from: preview.sourceFolder, origin: preview.fromGallery ? .official : nil)
            if preview.fromGallery { await runtime.addons.discard(id: preview.id) }
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
        return runtime.bundledExtensions.samples().compactMap { folder in
            guard let manifest = Self.manifest(in: folder), !installed.contains(manifest.id) else { return nil }
            return (manifest.name, folder)
        }
    }

    func unavailableExtensions() async -> [UnavailableExtension] {
        let folders = Dictionary(runtime.bundledExtensions.entries().map { ($0.id, $0.folder) }, uniquingKeysWith: { a, _ in a })
        return runtime.bundledExtensions.unavailable.map { problem in
            // The app's own copy, signed with the app: its icon is drawn as shipped.
            let manifest = folders[problem.id].flatMap(Self.manifest)
            let icon = folders[problem.id].flatMap { folder in manifest?.icon.map { folder.appendingPathComponent($0).path } }
            return UnavailableExtension(id: problem.id, name: problem.name, message: problem.message,
                                        look: ExtensionLook(name: problem.name, iconPath: icon, folk: manifest?.folk))
        }
    }

    func retryBuiltInExtensions() async { await runtime.bundledExtensions.install(into: runtime.extensions) }

    func extensionDrafts() async -> [ExtensionDraftInfo] {
        runtime.extensionDrafts.list().map {
            ExtensionDraftInfo(id: $0.id, name: $0.name, title: $0.title, version: $0.version, folder: $0.folder, modified: $0.modified)
        }
    }

    func deleteExtensionDraft(_ name: String) async -> UserFacingError? {
        do {
            try runtime.extensionDrafts.delete(name: name)
            runtime.events.changed(.extensions)
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't move that draft to the Trash."))
        }
    }

    func revealExtensionDraft(_ draft: ExtensionDraftInfo) { NSWorkspace.shared.activateFileViewerSelecting([draft.folder]) }

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
            // Whether a place is shared helps a bug report; where the person is doesn't (D48).
            s.location.place = nil
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
        applyAppearance()
        applyTheme()
        updater.settingsChanged()
        addonUpdater.settingsChanged()
    }

    /// Light or dark for every window, or nil to follow the Mac. Theme's colours follow it.
    func applyAppearance() {
        switch runtime.settings.current.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func openAsk(prefill: String) { showAsk(prefill: prefill.isEmpty ? nil : prefill) }

    func understands(_ text: String) -> Bool {
        runtime.intentParser.parse(LocalIntentRunner.expandSlash(text), now: Date(), knownCollections: knownCollections,
                                   watching: knownWatches) != nil
    }

    func ask(_ text: String, how: AskHow) {
        showAsk()
        switch how {
        case .auto, .ai:
            ask.text = text
            ask.submit(askAI: how == .ai)
        case .note:
            saveAsNote(text, in: ask)
        }
    }

    func open(_ found: Found) {
        askPanel.hide()
        switch found {
        case .note(let item): openHome(item: item)
        case .conversation(let conversation): openConversation(conversation.id)
        case .reminder(let reminder):
            // A reminder about a note opens the note; the others are on Today.
            Task {
                if let id = reminder.itemId, let item = try? await runtime.notebook.item(id: id), item.deletedAt == nil {
                    openHome(item: item)
                } else {
                    openNow()
                }
            }
        case .watch: openNow()
        case .activity(let entry): home.show(activityRow: entry.id)
        }
    }

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

    static func info(_ e: SidefolkCore.ExtensionInfo) -> ExtensionInfo {
        ExtensionInfo(
            id: e.id, name: e.name, version: e.version, description: e.description ?? "", tagline: e.tagline ?? "",
            kind: e.kind == .mcp ? .mcpServer : .sidefolk, enabled: e.enabled, folk: e.folk,
            toolNames: e.tools.map { $0.title.isEmpty ? $0.name : $0.title }, watcherNames: e.watchers.map(\.title),
            permissionLines: e.summary.lines.map(\.text), warnings: e.summary.warnings + (e.hasPendingToolChanges
                ? [String(localized: "Some tools changed since you installed it; they're on hold until you approve the change.")] : [])
                + e.toolWarnings,
            sandboxed: e.summary.sandboxed, lastError: e.lastError, bundled: e.origin == .bundled,
            pendingTools: e.tools.filter(\.quarantined).map { $0.title.isEmpty ? $0.name : $0.title },
            iconPath: e.iconPath, fromDraft: e.origin == .draft, fromGallery: e.origin == .official, command: e.command, author: e.author,
            hiddenSearchTexts: ExtensionListQuery.texts(for: e), commands: e.tools.flatMap(\.commands), restingFor: e.restingFor)
    }

    /// The manifest of an extension folder shipped inside the app, or nil.
    static func manifest(in folder: URL) -> ExtensionManifest? {
        FileManager.default.contents(atPath: folder.appendingPathComponent(ExtensionManifest.fileName).path)
            .flatMap { try? ExtensionManifest.decode($0) }
    }
}
