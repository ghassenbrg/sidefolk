import AppKit
import SidefolkCore

/// Back up and restore (D91): the backup file, the restore staged and the relaunch that swaps it in, Undo restore, and
/// after the relaunch the gallery's add-ons installed again while what came from a folder waits for a look.
extension AppCoordinator {
    static let restoreKind = "restore"

    var restore: RestoreModel { restoreModel }

    func backUp(to url: URL, password: String?) async -> UserFacingError? {
        do {
            var keys: [String: String]?
            if let password, !password.isEmpty {
                let servers = await runtime.extensions.extensions().filter { $0.kind == .mcp }.map(\.id)
                keys = BackupKeys.collect(from: secrets, mcpServers: servers)
            }
            let defaults = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
            try await BackupWriter(runtime: runtime).write(to: url, keys: keys, password: password, preferences: BackupPreferences.pick(defaults))
            return nil
        } catch {
            return Self.userFacing(error, fallback: String(localized: "I couldn't back up your data."))
        }
    }

    func openBackup(_ url: URL) async -> Result<OpenedBackup, UserFacingError> {
        do {
            return .success(try await BackupReader.open(url))
        } catch {
            return .failure(Self.userFacing(error, fallback: String(localized: "That backup couldn't be opened.")))
        }
    }

    /// The keys are opened first (a wrong password changes nothing), the backup is staged, then the keys are saved (what
    /// they replace kept for Undo restore) and Sidefolk relaunches; the swap happens before the database opens again.
    func restore(_ backup: OpenedBackup, password: String?) async -> UserFacingError? {
        do {
            let keys = try password.flatMap { $0.isEmpty || !backup.hasKeys ? nil : try backup.keys(password: $0) }
            let restore = BackupRestore(paths: runtime.paths)
            try restore.stage(backup)
            if let keys {
                do { try restore.saveKeys(keys, to: secrets) } catch { restore.cancelStaged(secrets: secrets); throw error }
            }
            backup.discard()
        } catch {
            return Self.userFacing(error, fallback: String(localized: "That backup couldn't be restored."))
        }
        // Not only the language: quits and opens this copy again with the same SIDEFOLK_ variables.
        AppLanguage.relaunch()
        return nil
    }

    func undoRestore() -> UserFacingError? {
        do {
            try BackupRestore(paths: runtime.paths).requestUndo()
        } catch {
            return Self.userFacing(error, fallback: String(localized: "The restore couldn't be undone."))
        }
        AppLanguage.relaunch()
        return nil
    }

    func reviewRestored(_ item: RestoreFollowUp.ReviewItem) {
        switch item.kind {
        case .extension: settingsWindow.review(folder: item.folder)
        case .companion:
            Task {
                await settingsWindow.addRestoredCompanion(folder: item.folder)
                await refreshRestoreReview()
            }
        }
    }

    // MARK: After the relaunch

    /// What this launch's restore (or its undo) did goes in History; the add-ons it names come back in the background.
    func resumeRestore() async {
        restoreModel.undoable = BackupRestore(paths: runtime.paths).undoable?.plan
        await runtime.attention.onAction(kind: Self.restoreKind) { [weak self] _, action in
            guard action == "show" else { return }
            await MainActor.run { self?.openSettings(tab: .trust) }
        }
        switch restoreOutcome {
        case .restored(let plan)?:
            await logRestore(String(localized: "Restored from a backup made on \(Self.when(plan.backupCreated))",
                                    comment: "History: “Restored from a backup made on 1 Nov 2026 at 10:42”"))
        case .undone(let plan)?:
            await logRestore(String(localized: "Undid the restore of the backup made on \(Self.when(plan.backupCreated))",
                                    comment: "History: “Undid the restore of the backup made on 1 Nov 2026 at 10:42”"))
        case nil: break
        }
        let followUp = RestoreFollowUp(paths: runtime.paths)
        if let plan = followUp.pending { Task { await runFollowUp(plan) } }
        await refreshRestoreReview()
        let stream = runtime.events.stream()
        Task { [weak self] in
            for await event in stream {
                guard case .dataChanged(.extensions) = event else { continue }
                await self?.refreshRestoreReview()
            }
        }
    }

    private func runFollowUp(_ plan: BackupRestore.Plan) async {
        let model = restoreModel
        let seeds = Set(runtime.seedPacks.seeds().map(\.id))
        model.total = plan.addons.count + plan.extensions.filter { ($0.source == .gallery || $0.source == .builtIn) && !seeds.contains($0.id) }.count
        model.done = 0
        model.running = true
        let report = await RestoreFollowUp(paths: runtime.paths).run(
            plan, store: runtime.addons, host: runtime.extensions, themes: ThemeLibrary.app(runtime.paths),
            channel: runtime.settings.current.updates.effectiveChannel, seeds: seeds) { _ in await MainActor.run { model.done += 1 } }
        model.running = false
        model.report = report
        companionsUpdated([])
        await refreshRestoreReview()
        _ = await runtime.attention.post(Self.restoreNotice(report, review: model.review.count))
    }

    func refreshRestoreReview() async {
        let extensions = Set(await runtime.extensions.extensions().map(\.id))
        let companions = Set(AddonStore.installedCompanions(in: runtime.paths.addons.appendingPathComponent("Companions")).map(\.companion))
        restoreModel.review = RestoreFollowUp(paths: runtime.paths)
            .toReview(plan: restoreModel.undoable, installedExtensions: extensions, installedCompanions: companions)
    }

    private func logRestore(_ summary: String) async {
        _ = try? await runtime.activity.log(ActivityEntry(caller: "user", tool: "app.restore", risk: "low", decision: .allowed, summary: summary))
        runtime.events.changed(.activity)
    }

    static func restoreNotice(_ report: RestoreFollowUp.Report, review: Int) -> AttentionRequest {
        var lines: [String] = []
        if !report.installed.isEmpty {
            lines.append(String(localized: "\(report.installed.count) add-ons are back.", locale: Wording.locale, comment: "After a restore: “4 add-ons are back.”"))
        }
        if !report.failed.isEmpty {
            lines.append(String(localized: "Not back: \(Wording.list(report.failed.map(\.name))).", comment: "After a restore: “Not back: Tea Timer.”"))
        }
        if review > 0 {
            lines.append(String(localized: "\(review) from a folder wait for your look in Settings.", locale: Wording.locale,
                                comment: "After a restore: extensions or companions from a folder, not installed until reviewed"))
        }
        return AttentionRequest(level: .gentle, source: "companion", title: String(localized: "Your backup is restored"),
                                body: lines.joined(separator: " "),
                                actions: [AttentionAction(id: "show", title: String(localized: "Show", comment: "Opens Settings › Trust › Your data"), isPrimary: true)],
                                refKind: restoreKind)
    }

    /// "1 Nov 2026 at 10:42", in the person's language.
    static func when(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
}

#if DEBUG
extension AppCoordinator {
    /// `backup:<file>` writes a backup there (no keys); `restoreFile:<file>` opens it in Settings' restore sheet, and
    /// `restoreConfirm` answers that sheet's Replace;
    /// `restoreNow:<file>` restores it at once (stage and relaunch); `undoRestore` undoes the last one (D91).
    func devBackup(_ command: String) -> Bool {
        func file(_ prefix: String) -> URL? {
            command.hasPrefix(prefix) ? URL(fileURLWithPath: String(command.dropFirst(prefix.count))) : nil
        }
        if let url = file("backup:") {
            Task {
                let error = await backUp(to: url, password: nil)
                Log.shared.info("dev", "backup", ["file": url.path, "error": error?.message ?? ""])
            }
        } else if let url = file("restoreFile:") {
            settingsWindow.showRestore(of: url)
        } else if let url = file("restoreNow:") {
            Task {
                switch await openBackup(url) {
                case .success(let backup):
                    if let error = await restore(backup, password: nil) { Log.shared.warning("dev", "restore failed", ["error": error.message]) }
                case .failure(let error): Log.shared.warning("dev", "restore failed", ["error": error.message])
                }
            }
        } else if command == "restoreConfirm" {
            settingsWindow.confirmRestore()
        } else if command == "undoRestore" {
            if let error = undoRestore() { Log.shared.warning("dev", "undo failed", ["error": error.message]) }
        } else {
            return false
        }
        return true
    }
}
#endif
