import Foundation

/// What a restore leaves for after the relaunch (D91): the gallery's add-ons installed again from the gallery
/// (signatures and digests checked as for any install), what the app carries as seed packs from there (D98), the
/// person's own themes checked and installed again, and what is code from a folder listed for the person to look at first.
public struct RestoreFollowUp: Sendable {
    public struct Failure: Sendable, Equatable, Identifiable {
        public var name: String
        public var reason: String
        public var id: String { name }

        public init(name: String, reason: String) { (self.name, self.reason) = (name, reason) }
    }

    /// Something to look at before it's back: an extension's install sheet, or a companion's question (D60).
    public struct ReviewItem: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable { case `extension`, companion }
        public var kind: Kind
        public var id: String
        public var name: String
        public var folder: URL

        public init(kind: Kind, id: String, name: String, folder: URL) { (self.kind, self.id, self.name, self.folder) = (kind, id, name, folder) }
    }

    public struct Report: Sendable, Equatable {
        public var installed: [String] = []
        public var failed: [Failure] = []
        public init() {}
    }

    let paths: SidefolkPaths
    let seedWait: TimeInterval

    public init(paths: SidefolkPaths, seedWait: TimeInterval = 60) {
        self.paths = paths
        self.seedWait = seedWait
    }

    private var file: URL { paths.home.appendingPathComponent(BackupRestore.followUp) }
    private var review: URL { paths.home.appendingPathComponent(BackupRestore.reviewFolder) }

    /// The restore whose add-ons are still to install, if any.
    public var pending: BackupRestore.Plan? {
        FileManager.default.contents(atPath: file.path).flatMap { try? BackupManifest.decoder.decode(BackupRestore.Plan.self, from: $0) }
    }

    /// Installs again what the restore names, each in turn; `step` hears each name once it's done (or failed).
    /// - Parameter seeds: the extensions this copy carries as seed packs (`SeedPacks`), which come back without the gallery.
    public func run(_ plan: BackupRestore.Plan, store: AddonStore, host: ExtensionHost, themes: ThemeLibrary, channel: UpdateChannel,
                    seeds: Set<String> = [], step: @Sendable (String) async -> Void = { _ in }) async -> Report {
        var report = Report()
        // Seed packs are installed at launch, beside this: each gets its switch back once it's there (a minute at most).
        // One that didn't come, or that this copy doesn't carry, comes from the gallery like the rest.
        let deadline = Date().addingTimeInterval(seedWait)
        var fromGallery: [BackupManifest.Extension] = []
        for e in plan.extensions where e.source == .builtIn || e.source == .gallery {
            if seeds.contains(e.id) {
                while await host.info(id: e.id) == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(300)) }
            }
            if seeds.contains(e.id), let info = await host.info(id: e.id) {
                if info.enabled != e.enabled { try? await host.setEnabled(e.enabled, id: e.id) }
            } else {
                fromGallery.append(e)
            }
        }
        let gallery = fromGallery.map { ($0.id, $0.name, AddonEntry.Kind.extension, $0.enabled) }
            + plan.addons.map { ($0.id, $0.name, $0.kind, true) }
        if !gallery.isEmpty {
            let catalog: AddonCatalog?
            do { catalog = store.source == nil ? nil : try await store.catalog(refresh: true) } catch { catalog = nil }
            for (id, name, kind, enabled) in gallery {
                do {
                    guard let catalog else { throw UserFacingError("The add-on gallery couldn't be reached.") }
                    guard let entry = catalog.entry(id, on: channel) ?? catalog.entry(id), entry.kind == kind else {
                        throw UserFacingError("It's no longer in the gallery, or needs a newer Sidefolk.")
                    }
                    switch kind {
                    case .companion: try await store.install(companion: entry)
                    case .theme: try await store.install(theme: entry, into: themes)
                    case .extension:
                        let folder = try await store.fetch(entry)
                        do {
                            try await host.install(from: folder, origin: .official, enabled: enabled)
                        } catch {
                            await store.discard(entry)
                            throw error
                        }
                        await store.discard(entry)
                    }
                    report.installed.append(name)
                } catch {
                    report.failed.append(Failure(name: name, reason: (error as? UserFacingError)?.message ?? String(describing: error)))
                }
                await step(name)
            }
        }
        // The person's own themes are data: checked again as any theme added from a folder, then kept.
        let ownThemes = review.appendingPathComponent("themes", isDirectory: true)
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: ownThemes.path)) ?? []).sorted() where !name.hasPrefix(".") {
            let folder = ownThemes.appendingPathComponent(name)
            do {
                report.installed.append(try themes.install(from: folder).theme.tokens.name)
            } catch {
                report.failed.append(Failure(name: name, reason: (error as? UserFacingError)?.message ?? String(describing: error)))
            }
            ExtensionFiles.removeTree(folder.path)
            await step(name)
        }
        try? FileManager.default.removeItem(at: file)
        Log.shared.info("backup", "add-ons back", ["installed": String(report.installed.count), "failed": String(report.failed.count)])
        return report
    }

    /// What from the backup waits for a look: extensions and companions from a folder, not installed yet.
    public func toReview(plan: BackupRestore.Plan?, installedExtensions: Set<String>, installedCompanions: Set<String>) -> [ReviewItem] {
        func folders(_ sub: String) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: review.appendingPathComponent(sub).path)) ?? [])
                .filter { !$0.hasPrefix(".") }.sorted()
        }
        let extensions = folders("extensions").filter { !installedExtensions.contains($0) }.map { id in
            ReviewItem(kind: .extension, id: id, name: plan?.extensions.first { $0.id == id }?.name ?? id,
                       folder: review.appendingPathComponent("extensions/\(id)"))
        }
        let companions = folders("companions").filter { !installedCompanions.contains($0) }.map { name in
            ReviewItem(kind: .companion, id: name, name: name.capitalized, folder: review.appendingPathComponent("companions/\(name)"))
        }
        return extensions + companions
    }
}
