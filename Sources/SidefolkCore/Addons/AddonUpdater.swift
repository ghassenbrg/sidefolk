import Foundation

/// Which gallery updates may install by themselves (D70). A companion only draws and a theme is data, so they
/// may. An extension may only when it asks for nothing new: no permission it didn't have, no tool at a higher
/// risk, no running in the background. Anything else waits for the person, in the install sheet that says what is
/// new; so does an update the sheet would refuse.
public enum AddonUpdateRule {
    public enum Verdict: Sendable, Equatable {
        case install
        case review
    }

    public static func verdict(_ kind: AddonEntry.Kind, preview: InstallPreview? = nil) -> Verdict {
        switch kind {
        case .companion, .theme: return .install
        case .extension:
            guard let preview, preview.canInstall, let diff = preview.update, !diff.widens else { return .review }
            return .install
        }
    }
}

/// What one look at the gallery for newer add-ons found and did (D70), or what Update all did (D89).
public struct AddonUpdateReport: Sendable {
    public var companions: [InstalledCompanion] = []
    public var themes: [InstalledTheme] = []
    public var extensions: [ExtensionInfo] = []
    /// Extension updates that would let it do more: they wait for the person's look, whatever the switch says.
    public var review: [AddonEntry] = []
    /// Updates left for the person, because add-ons don't update by themselves (the switch is off).
    public var waiting: [AddonEntry] = []
    /// Updates that couldn't be installed this time (a download that failed, a pack this copy refuses); the old copy
    /// stays and they are tried again.
    public var failed: [AddonEntry] = []

    public init() {}

    public var installed: Int { companions.count + themes.count + extensions.count }

    /// What Update all did in a few words: "3 updated, 1 needs your review". Nil when it did nothing at all.
    public var summary: String? { Self.summary(installed: installed, review: review.count, failed: failed.count) }

    public static func summary(installed: Int, review: Int, failed: Int) -> String? {
        var parts: [String] = []
        if installed > 0 { parts.append(String(localized: "\(installed) updated", comment: "Update all's summary: “3 updated”")) }
        if review > 0 {
            parts.append(String(localized: "\(review) needs your review", comment: "Update all's summary: “1 needs your review”"))
        }
        if failed > 0 {
            parts.append(String(localized: "\(failed) couldn't update", comment: "Update all's summary: “1 couldn't update”"))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: String(localized: ", ", comment: "Between the parts of Update all's summary: “3 updated, 1 needs your review”"))
    }
}

/// Where one add-on is while Update all runs (D89), for its row.
public enum AddonUpdateStep: Sendable, Equatable {
    case updating
    case updated
    /// It would be allowed to do more: the install sheet, on the person's look.
    case needsReview
    case failed(String)
}

/// What updating one add-on came to.
public enum AddonUpdateOutcome: Sendable {
    case companion(InstalledCompanion)
    case theme(InstalledTheme)
    case `extension`(ExtensionInfo)
    case review
    case failed(UserFacingError)

    public var step: AddonUpdateStep {
        switch self {
        case .companion, .theme, .extension: .updated
        case .review: .needsReview
        case .failed(let error): .failed(error.message)
        }
    }
}

/// Keeps the gallery's add-ons on this Mac up to date (D55, D70), following Settings › Updates: its channel
/// (releases, or snapshots too, D65) and "Update add-ons automatically". Everything is fetched and checked as the
/// gallery does (`AddonStore`); extensions go through `ExtensionHost`'s own install, as when the person clicks Update.
/// A timed look and the person's Update all (D89) take the same path, one add-on at a time (`update(_:)`).
public struct AddonUpdater: Sendable {
    let store: AddonStore
    let extensions: ExtensionHost
    let themes: ThemeLibrary

    public init(store: AddonStore, extensions: ExtensionHost, themes: ThemeLibrary) {
        self.store = store
        self.extensions = extensions
        self.themes = themes
    }

    /// The gallery's extensions on this Mac (installed from it: origin `official`) that `catalog` has a newer version of
    /// on `channel`. Built-ins follow the app; an extension from a folder is the person's own copy.
    public func extensionUpdates(in catalog: AddonCatalog, channel: UpdateChannel) async -> [AddonEntry] {
        await extensions.extensions().filter { $0.kind == .sidefolk && $0.origin == .official }.compactMap { have in
            guard let entry = catalog.entry(have.id, on: channel), entry.kind == .extension,
                  catalog.offers(entry, over: have.version, on: channel) else { return nil }
            return entry
        }
    }

    /// One look: with `automatic`, installs what the rule allows and leaves the rest for review; without, installs
    /// nothing and says what waits. A failure leaves the old copy and is tried again at the next look. `refresh`
    /// fetches the gallery's list even when the one kept is recent (the person asked to check now).
    public func run(channel: UpdateChannel, automatic: Bool, refresh: Bool = false) async -> AddonUpdateReport {
        guard store.source != nil, let catalog = try? await store.catalog(refresh: refresh) else { return AddonUpdateReport() }
        let pending = await store.companionUpdates(in: catalog, channel: channel)
            + store.themeUpdates(in: catalog, library: themes, channel: channel)
            + extensionUpdates(in: catalog, channel: channel)
        guard automatic else {
            var report = AddonUpdateReport()
            report.waiting = pending
            return report
        }
        let report = await updateAll(pending)
        if report.installed > 0 || !report.review.isEmpty {
            Log.shared.info("addons", "updated by themselves", [
                "companions": report.companions.map(\.id).joined(separator: ","), "themes": report.themes.map(\.id).joined(separator: ","),
                "extensions": report.extensions.map(\.id).joined(separator: ","), "review": report.review.map(\.id).joined(separator: ","),
            ])
        }
        return report
    }

    /// Update all (D89), and a timed look with the switch on: each of `entries` in turn, by the same rule as by
    /// themselves (`AddonUpdateRule`). One that would be allowed to do more is left for review; one that fails keeps
    /// its old copy and the rest go on. `step` hears where each one is, for its row.
    public func updateAll(_ entries: [AddonEntry],
                          step: @Sendable (AddonEntry, AddonUpdateStep) async -> Void = { _, _ in }) async -> AddonUpdateReport {
        var report = AddonUpdateReport()
        for entry in entries {
            await step(entry, .updating)
            let outcome = await update(entry)
            switch outcome {
            case .companion(let c): report.companions.append(c)
            case .theme(let t): report.themes.append(t)
            case .extension(let info): report.extensions.append(info)
            case .review: report.review.append(entry)
            case .failed: report.failed.append(entry)
            }
            await step(entry, outcome.step)
        }
        return report
    }

    /// Updates one add-on: a companion or theme at once (they only draw), an extension only when its new version
    /// asks for nothing new. An extension that was off stays off.
    public func update(_ entry: AddonEntry) async -> AddonUpdateOutcome {
        do {
            switch entry.kind {
            case .companion: return .companion(try await store.install(companion: entry))
            case .theme: return .theme(try await store.install(theme: entry, into: themes))
            case .extension: return await update(extension: entry)
            }
        } catch {
            Log.shared.warning("addons", "not updated", ["id": entry.id, "error": String(describing: error)])
            return .failed(error as? UserFacingError ?? UserFacingError("\(entry.shownName) couldn't be updated.", detail: String(describing: error)))
        }
    }

    /// Fetches and checks the pack, compares it with what is installed, and installs it only if it asks for nothing
    /// new.
    func update(extension entry: AddonEntry) async -> AddonUpdateOutcome {
        let folder: URL
        do {
            folder = try await store.fetch(entry)
        } catch {
            Log.shared.warning("addons", "extension not updated", ["id": entry.id, "error": String(describing: error)])
            return .failed(error as? UserFacingError ?? UserFacingError("\(entry.shownName) couldn't be downloaded.", detail: String(describing: error)))
        }
        let outcome = await install(entry, from: folder)
        // The host keeps its own copy; the download goes either way (a review fetches it again).
        await store.discard(entry)
        return outcome
    }

    private func install(_ entry: AddonEntry, from folder: URL) async -> AddonUpdateOutcome {
        let preview = await extensions.preview(folder: folder)
        guard AddonUpdateRule.verdict(.extension, preview: preview) == .install else {
            Log.shared.info("addons", "extension update waits for review", [
                "id": entry.id, "version": entry.version, "added": preview.update?.addedPermissions.joined(separator: "; ") ?? "",
                "riskier": preview.update?.riskierTools.joined(separator: ",") ?? "",
            ])
            return .review
        }
        let wasOn = await extensions.info(id: entry.id)?.enabled ?? true
        do {
            let info = try await extensions.install(from: folder, origin: .official, enabled: wasOn)
            Log.shared.info("addons", "extension updated", ["id": entry.id, "version": entry.version, "enabled": String(wasOn)])
            return .extension(info)
        } catch {
            Log.shared.warning("addons", "extension not updated", ["id": entry.id, "error": String(describing: error)])
            return .failed(error as? UserFacingError ?? UserFacingError("\(entry.shownName) couldn't be updated.", detail: String(describing: error)))
        }
    }
}
