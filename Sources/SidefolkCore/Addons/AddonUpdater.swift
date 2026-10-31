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

/// What one look at the gallery for newer add-ons found and did (D70).
public struct AddonUpdateReport: Sendable {
    public var companions: [InstalledCompanion] = []
    public var themes: [InstalledTheme] = []
    public var extensions: [ExtensionInfo] = []
    /// Extension updates that would let it do more: they wait for the person's look, whatever the switch says.
    public var review: [AddonEntry] = []
    /// Updates left for the person, because add-ons don't update by themselves (the switch is off).
    public var waiting: [AddonEntry] = []

    public init() {}

    public var installed: Int { companions.count + themes.count + extensions.count }
}

/// Keeps the gallery's add-ons on this Mac up to date (D55, D70), following Settings › Updates: its channel
/// (releases, or snapshots too, D65) and "Update add-ons automatically". Everything is fetched and checked as the
/// gallery does (`AddonStore`); extensions go through `ExtensionHost`'s own install, as when the person clicks Update.
public struct AddonUpdater: Sendable {
    let store: AddonStore
    let extensions: ExtensionHost
    let themes: ThemeLibrary

    public init(store: AddonStore, extensions: ExtensionHost, themes: ThemeLibrary) {
        self.store = store
        self.extensions = extensions
        self.themes = themes
    }

    /// The gallery's extensions on this Mac (installed from it: origin `official`) that `catalog` has a newer
    /// version of on `channel`. Built-ins follow the app; an extension from a folder is the person's own copy.
    public func extensionUpdates(in catalog: AddonCatalog, channel: UpdateChannel) async -> [AddonEntry] {
        await extensions.extensions().filter { $0.kind == .sidefolk && $0.origin == .official }.compactMap { have in
            guard let entry = catalog.entry(have.id, on: channel), entry.kind == .extension,
                  channel.offers(entry.version, over: have.version) else { return nil }
            return entry
        }
    }

    /// One look: with `automatic`, installs what the rule allows and leaves the rest for review; without, installs
    /// nothing and says what waits. A failure leaves the old copy and is tried again at the next look.
    public func run(channel: UpdateChannel, automatic: Bool) async -> AddonUpdateReport {
        var report = AddonUpdateReport()
        guard store.source != nil, let catalog = try? await store.catalog() else { return report }
        let companions = await store.companionUpdates(in: catalog, channel: channel)
        let themes = await store.themeUpdates(in: catalog, library: self.themes, channel: channel)
        let extensions = await extensionUpdates(in: catalog, channel: channel)
        guard automatic else {
            report.waiting = companions + themes + extensions
            return report
        }
        report.companions = await store.updateCompanions(channel: channel)
        for entry in themes {
            do {
                report.themes.append(try await store.install(theme: entry, into: self.themes))
            } catch {
                Log.shared.warning("addons", "theme not updated", ["id": entry.id, "error": String(describing: error)])
            }
        }
        for entry in extensions {
            switch await update(extension: entry) {
            case .installed(let info): report.extensions.append(info)
            case .review: report.review.append(entry)
            case .failed: break
            }
        }
        if report.installed > 0 || !report.review.isEmpty {
            Log.shared.info("addons", "updated by themselves", [
                "companions": report.companions.map(\.id).joined(separator: ","), "themes": report.themes.map(\.id).joined(separator: ","),
                "extensions": report.extensions.map(\.id).joined(separator: ","), "review": report.review.map(\.id).joined(separator: ","),
            ])
        }
        return report
    }

    enum ExtensionOutcome {
        case installed(ExtensionInfo)
        case review
        case failed
    }

    /// Fetches and checks the pack, compares it with what is installed, and installs it only if it asks for nothing
    /// new. An extension that was off stays off.
    func update(extension entry: AddonEntry) async -> ExtensionOutcome {
        let folder: URL
        do {
            folder = try await store.fetch(entry)
        } catch {
            Log.shared.warning("addons", "extension not updated", ["id": entry.id, "error": String(describing: error)])
            return .failed
        }
        let outcome = await install(entry, from: folder)
        // The host keeps its own copy; the download goes either way (a review fetches it again).
        await store.discard(entry)
        return outcome
    }

    private func install(_ entry: AddonEntry, from folder: URL) async -> ExtensionOutcome {
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
            Log.shared.info("addons", "extension updated by itself", ["id": entry.id, "version": entry.version, "enabled": String(wasOn)])
            return .installed(info)
        } catch {
            Log.shared.warning("addons", "extension not updated", ["id": entry.id, "error": String(describing: error)])
            return .failed
        }
    }
}
