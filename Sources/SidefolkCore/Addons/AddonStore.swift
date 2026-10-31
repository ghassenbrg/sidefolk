import Foundation
import Security

/// A companion add-on on this Mac (D55): `<home>/Addons/Companions/<name>/` holds its files in the same places
/// the app's own 3D companions keep theirs (`characters/`, `assets/`, `portraits/`, `avatars/`).
public struct InstalledCompanion: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var companion: String
    public var version: String
    public var author: String
    /// One line about who it is (a companion added from a folder brings its own; D60).
    public var tagline: String?
    /// The shape of the undrawn rig under it (one added from a folder; D60).
    public var body: CompanionBody?
    /// Added from a folder on this Mac (D60), not from the gallery: unsigned, shown under "Made by you".
    public var fromFolder: Bool?

    public var addedFromFolder: Bool { fromFolder == true }
}

/// The body under a 3D companion added from a folder (D60): the 2D rig that runs undrawn beneath it, for its
/// outline, bubble anchors and moves, borrowed from a gallery companion of the same build.
public enum CompanionBody: String, Codable, Sendable, CaseIterable {
    /// Head, arms and legs, standing (Kiko's).
    case biped
    /// No legs, floating (Nimbo's).
    case floating
    /// Flat and upright (Folio's).
    case card
}

/// The add-on gallery (D55): reads the signed catalog, downloads a pack, checks it, and installs or removes
/// companions. Extensions are handed back as a checked folder for the normal install preview, so the person
/// sees what one may do before it is installed, as with any extension.
///
/// Nothing is believed about a download but its signature: the catalog bundle and each pack must be signed with
/// a Developer ID of the team the app names (`AddonSource`), and carry the identifier asked for. The size and
/// SHA-256 in the (signed) catalog must match the pack too, so a pack can't be swapped for another signed one.
public actor AddonStore {
    public nonisolated let source: AddonSource?
    private let folder: URL
    private let downloader: UpdateDownloading
    private let checker: CodeChecking
    private let now: @Sendable () -> Date
    /// When this store began: `tidy()` leaves what this run has started.
    private let started: Date
    private var cached: AddonCatalog?

    /// How long a fetched catalog is used before the gallery asks again.
    public static let freshFor: TimeInterval = 30 * 60
    static let catalogLimit: Int64 = 16 * 1024 * 1024

    public init(paths: SidefolkPaths, source: AddonSource? = AddonSource.current(), downloader: UpdateDownloading? = nil,
                checker: CodeChecking = AddonCodeCheck(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        folder = paths.addons
        self.downloader = downloader ?? (source?.base.isFileURL == true ? LocalCopy() : UpdateDownloader())
        self.checker = checker
        self.now = now
        started = now()
    }

    var companionsFolder: URL { folder.appendingPathComponent("Companions", isDirectory: true) }
    var catalogFolder: URL { folder.appendingPathComponent("Catalog", isDirectory: true) }
    var downloads: URL { folder.appendingPathComponent("Downloads", isDirectory: true) }

    // MARK: Catalog

    /// The gallery's list: the one fetched within `freshFor` unless `refresh`, else a new one. When the new one
    /// can't be fetched, the last good one (if any) is returned, so the gallery still shows offline.
    public func catalog(refresh: Bool = false) async throws -> AddonCatalog {
        if !refresh, let cached, now().timeIntervalSince(cached.fetched) < Self.freshFor { return cached }
        do {
            let fresh = try await fetchCatalog()
            cached = fresh
            return fresh
        } catch {
            if let last = cached ?? stored() {
                cached = last
                Log.shared.warning("addons", "catalog fetch failed; using the last one", ["error": String(describing: error)])
                return last
            }
            throw error
        }
    }

    /// The last catalog checked on this Mac, without going online (at launch, before anyone opens the gallery).
    public func stored() -> AddonCatalog? {
        if let cached { return cached }
        let file = catalogFolder.appendingPathComponent("catalog.json")
        guard let data = FileManager.default.contents(atPath: file.path) else { return nil }
        let fetched = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? .distantPast
        cached = try? AddonCatalog.parse(data, folder: catalogFolder, fetched: fetched)
        return cached
    }

    private func fetchCatalog() async throws -> AddonCatalog {
        guard let source else { throw UserFacingError("This copy of Sidefolk has no add-on gallery.") }
        let work = try fresh(downloads.appendingPathComponent("catalog", isDirectory: true))
        defer { try? FileManager.default.removeItem(at: work) }
        let zip = work.appendingPathComponent(AddonSource.catalogFile)
        try await downloader.download(source.base.appendingPathComponent(AddonSource.catalogFile), to: zip,
                                      expectedBytes: Self.catalogLimit, progress: { _ in })
        let resources = try await unpack(zip, into: work.appendingPathComponent("unpacked", isDirectory: true),
                                         id: AddonSource.catalogID, version: nil, source: source)
        let data = try Data(contentsOf: resources.appendingPathComponent("catalog.json"))
        let fetched = now()
        // Checked before it replaces the last one: a list that can't be read never wipes a good one.
        _ = try AddonCatalog.parse(data, folder: catalogFolder, fetched: fetched)
        let staged = folder.appendingPathComponent(".catalog-\(UUID().uuidString)", isDirectory: true)
        try ExtensionFiles.copy(from: resources.path, to: staged.path, quarantine: .none)
        try replace(catalogFolder, with: staged)
        let file = catalogFolder.appendingPathComponent("catalog.json")
        try? FileManager.default.setAttributes([.modificationDate: fetched], ofItemAtPath: file.path)
        return try AddonCatalog.parse(data, folder: catalogFolder, fetched: fetched)
    }

    // MARK: Packs

    /// Downloads `entry`'s pack and checks it; returns the folder of its files (`Downloads/<id>/…/Resources`).
    /// The folder stays until `discard(_:)` or the next launch.
    public func fetch(_ entry: AddonEntry, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try await fetchCurrent(entry, progress: progress).folder
    }

    /// `fetch`, and the entry the pack matched. A pack that doesn't arrive as `entry` describes may be newer than
    /// the catalog it was looked up in (the release changed since that catalog was fetched): when the catalog,
    /// fetched again, describes it otherwise, the pack is fetched once more as the new entry says.
    private func fetchCurrent(_ entry: AddonEntry, progress: @escaping @Sendable (Double) -> Void) async throws -> (folder: URL, entry: AddonEntry) {
        do {
            return (try await download(entry, progress: progress), entry)
        } catch {
            // The same kind of version as asked for: a release isn't swapped for a snapshot.
            let channel: UpdateChannel = ReleaseVersion(entry.version)?.isPrerelease == false ? .releases : .snapshots
            guard let newer = try? await catalog(refresh: true).entry(entry.id, on: channel), newer != entry,
                  newer.kind == entry.kind, newer.companion == entry.companion else { throw error }
            Log.shared.info("addons", "the gallery changed since its catalog was fetched; trying again", ["id": entry.id])
            return (try await download(newer, progress: progress), newer)
        }
    }

    private func download(_ entry: AddonEntry, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let source else { throw UserFacingError("This copy of Sidefolk has no add-on gallery.") }
        let work = try fresh(downloads.appendingPathComponent(entry.id, isDirectory: true))
        do {
            let zip = work.appendingPathComponent(entry.file)
            try await downloader.download(source.base.appendingPathComponent(entry.file), to: zip, expectedBytes: entry.bytes,
                                          progress: { progress(min(1, Double($0) / Double(max(entry.bytes, 1)))) })
            let size = (try? FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? NSNumber)?.int64Value
            guard size == entry.bytes, try FileDigest.sha256(zip) == entry.sha256 else {
                throw UserFacingError("\(entry.name) didn't arrive as the gallery describes it, so it wasn't installed.",
                                      recovery: "Try again later.")
            }
            let resources = try await unpack(zip, into: work.appendingPathComponent("unpacked", isDirectory: true),
                                             id: entry.id, version: entry.version, source: source)
            try? FileManager.default.removeItem(at: zip)
            return resources
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    /// Removes what `fetch` left for `entry`.
    public func discard(_ entry: AddonEntry) { discard(id: entry.id) }

    public func discard(id: String) {
        guard !id.contains("/"), !id.hasPrefix(".") else { return }
        try? FileManager.default.removeItem(at: downloads.appendingPathComponent(id, isDirectory: true))
    }

    /// Removes what earlier runs left in the downloads folder and half-made copies (a fetch interrupted by
    /// quitting leaves its files). Not what this run has started: at launch a companion coming back by itself may
    /// already be downloading.
    public func tidy() {
        let fm = FileManager.default
        func old(_ url: URL) -> Bool {
            ((try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date ?? .distantPast) < started
        }
        for name in (try? fm.contentsOfDirectory(atPath: downloads.path)) ?? [] {
            let url = downloads.appendingPathComponent(name)
            if old(url) { try? fm.removeItem(at: url) }
        }
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            if old(url) { try? fm.removeItem(at: url) }
        }
    }

    /// Unzips `zip` and checks the one bundle inside: signed as `source` requires for `id`, its Info.plist naming
    /// `id` and `version`. Returns its `Contents/Resources`.
    private func unpack(_ zip: URL, into dest: URL, id: String, version: String?, source: AddonSource) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let out = try await SystemTool.run("/usr/bin/ditto", ["-x", "-k", zip.path, dest.path], timeout: 120)
        guard out.status == 0 else { throw UserFacingError("The download couldn't be opened.", detail: "ditto exited \(out.status)") }
        let names = try fm.contentsOfDirectory(atPath: dest.path).filter { $0 != "__MACOSX" }
        guard names.count == 1, let name = names.first, name.hasSuffix(".sidefolkaddon"),
              let st = ExtensionFS.lstat(dest.appendingPathComponent(name).path), st.st_mode & S_IFMT == S_IFDIR else {
            throw UserFacingError("The download isn't a Sidefolk add-on.")
        }
        let bundle = dest.appendingPathComponent(name, isDirectory: true)
        try checker.check(bundle, requirement: source.requirement(identifier: id))
        let info = bundle.appendingPathComponent("Contents/Info.plist")
        guard let plist = (try? PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil)) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == id,
              version == nil || plist["CFBundleShortVersionString"] as? String == version else {
            throw UserFacingError("The download isn't the add-on the gallery lists.")
        }
        return bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
    }

    // MARK: Companions

    /// Downloads, checks and installs a companion, replacing an older copy.
    @discardableResult
    public func install(companion entry: AddonEntry, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> InstalledCompanion {
        guard entry.kind == .companion, let name = entry.companion else { throw UserFacingError("That add-on isn't a companion.") }
        let (resources, entry) = try await fetchCurrent(entry, progress: progress)
        defer { discard(entry) }
        try Self.checkCompanionFiles(resources, name: name)
        let staged = folder.appendingPathComponent(".companion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: companionsFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // The files were checked against the signature; their copies lose the download mark, as a built-in's do.
        try ExtensionFiles.copy(from: resources.path, to: staged.path, quarantine: .none)
        let installed = InstalledCompanion(id: entry.id, name: entry.name, companion: name, version: entry.version, author: entry.author)
        try JSONEncoder().encode(installed).write(to: staged.appendingPathComponent("addon.json"))
        try replace(companionsFolder.appendingPathComponent(name, isDirectory: true), with: staged)
        Log.shared.info("addons", "installed companion", ["id": entry.id, "version": entry.version])
        return installed
    }

    /// The gallery's companions on this Mac (not those added from a folder) that `catalog` has a newer version of.
    /// The catalog already leaves out what this Sidefolk can't run (a newer engine or app), so such a version waits;
    /// a snapshot waits too unless the person chose snapshots (`channel`).
    public func companionUpdates(in catalog: AddonCatalog, channel: UpdateChannel) -> [AddonEntry] {
        installedCompanions().filter { !$0.addedFromFolder }.compactMap { have in
            guard let entry = catalog.companion(have.companion, on: channel), entry.id == have.id,
                  channel.offers(entry.version, over: have.version) else { return nil }
            return entry
        }
    }

    /// Installs the newer version of each gallery companion on this Mac, without asking: a companion only draws.
    /// Returns those it updated. One that fails keeps its old copy (a pack is swapped in only once checked) and is
    /// tried again at the next look.
    public func updateCompanions(channel: UpdateChannel) async -> [InstalledCompanion] {
        guard source != nil, let catalog = try? await catalog() else { return [] }
        var updated: [InstalledCompanion] = []
        for entry in companionUpdates(in: catalog, channel: channel) {
            do {
                updated.append(try await install(companion: entry))
            } catch {
                Log.shared.warning("addons", "companion not updated", ["id": entry.id, "error": String(describing: error)])
            }
        }
        return updated
    }

    // MARK: Themes

    /// Downloads a theme from the gallery, checks its signature, then installs it as any theme is: checked again,
    /// its images decoded and written anew. Only the signed gallery may use Sidefolk's own ids.
    @discardableResult
    public func install(theme entry: AddonEntry, into library: ThemeLibrary,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> InstalledTheme {
        guard entry.kind == .theme else { throw UserFacingError("That add-on isn't a theme.") }
        let (resources, entry) = try await fetchCurrent(entry, progress: progress)
        defer { discard(entry) }
        let (theme, _) = try library.install(from: resources, own: entry.official)
        guard theme.id == entry.id else {
            try? library.remove(id: theme.id)
            throw UserFacingError("The download isn't the theme the gallery lists.")
        }
        Log.shared.info("addons", "installed theme", ["id": entry.id, "version": entry.version])
        return theme
    }

    /// The gallery's themes on this Mac that `catalog` has a newer version of, a snapshot only on `channel` snapshots.
    public func themeUpdates(in catalog: AddonCatalog, library: ThemeLibrary, channel: UpdateChannel) -> [AddonEntry] {
        library.all().compactMap { have in
            guard have.folder != nil, let entry = catalog.entry(have.id, on: channel), entry.kind == .theme,
                  let old = have.version, channel.offers(entry.version, over: old) else { return nil }
            return entry
        }
    }

    /// The four files a 3D companion needs, named after it, and nothing else.
    static func checkCompanionFiles(_ root: URL, name: String) throws {
        let expected = ["characters/\(name).js", "assets/\(name).glb", "portraits/\(name).png", "avatars/\(name).png"]
        let files = try ExtensionFiles.walk(root.path).filter { !$0.isDirectory }.map(\.path)
        let extra = Set(files).subtracting(expected)
        guard Set(expected).isSubset(of: files), extra.isEmpty else {
            throw UserFacingError("That companion is missing files or carries others.",
                                  detail: "missing: \(Set(expected).subtracting(files).sorted()), extra: \(extra.sorted())")
        }
    }

    public func installedCompanions() -> [InstalledCompanion] { Self.installedCompanions(in: companionsFolder) }

    /// The companions in `folder` (`<home>/Addons/Companions`), as their `addon.json` describe them.
    public nonisolated static func installedCompanions(in folder: URL) -> [InstalledCompanion] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().compactMap { name in
            let file = folder.appendingPathComponent(name).appendingPathComponent("addon.json")
            guard let data = FileManager.default.contents(atPath: file.path),
                  let c = try? JSONDecoder().decode(InstalledCompanion.self, from: data), c.companion == name else { return nil }
            return c
        }
    }

    public func remove(companion name: String) throws {
        guard name.range(of: #"^[a-z][a-z0-9-]{0,30}$"#, options: .regularExpression) != nil else { return }
        let target = companionsFolder.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
        Log.shared.info("addons", "removed companion", ["companion": name])
    }

    // MARK: Files

    /// An empty folder at `url`, made anew.
    private func fresh(_ url: URL) throws -> URL {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    /// Puts `staged` where `target` is, in one rename when there was nothing, or a swap then a removal.
    func replace(_ target: URL, with staged: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) {
            try BundleSwap.swap(target, staged)
            try? fm.removeItem(at: staged)
        } else {
            try fm.moveItem(at: staged, to: target)
        }
    }

    /// For a gallery in a folder (development and tests): a copy, with the same size limit.
    struct LocalCopy: UpdateDownloading {
        func download(_ url: URL, to destination: URL, expectedBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) async throws {
            guard url.isFileURL else { throw UserFacingError("The add-on's address isn't in the gallery's folder.") }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size <= expectedBytes + 1024 else { throw UserFacingError("The add-on is larger than the gallery says.") }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            progress(size)
        }
    }
}

/// Checks an add-on's signature (the catalog's too): every file intact, strictly, and meeting the requirement.
public struct AddonCodeCheck: CodeChecking {
    public init() {}

    public func check(_ url: URL, requirement: String) throws {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else {
            throw UserFacingError("The add-on carries no signature Sidefolk can read, so it wasn't used.")
        }
        var error: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, req, &error)
        guard status == errSecSuccess else {
            let detail = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "OSStatus \(status)"
            throw status == errSecCSReqFailed
                ? UserFacingError("The add-on isn't signed by Sidefolk's developer, so it wasn't used.", detail: detail)
                : UserFacingError("The add-on's signature doesn't check out, so it wasn't used.", detail: detail)
        }
    }
}
