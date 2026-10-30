import Foundation

/// One add-on in the gallery (D55): a companion, an extension or a theme, published in the sidefolk-addons repository's
/// releases. Everything here comes from the catalog, which is itself signed; the pack it points at is checked on
/// its own before anything of it is used.
public struct AddonEntry: Codable, Sendable, Hashable, Identifiable {
    /// Themes are data (D58, D64); a copy of Sidefolk from before them skips their entries.
    public enum Kind: String, Codable, Sendable { case companion, `extension`, theme }

    /// Reverse DNS: `dev.sidefolk.companions.ember`, `dev.sidefolk.git`. The pack's signature names it too.
    public var id: String
    public var kind: Kind
    public var name: String
    /// One line, at most 60 characters.
    public var tagline: String
    public var description: String
    public var author: String
    public var version: String
    /// The oldest Sidefolk it works with ("0.1.0").
    public var minimumSidefolk: String?
    /// The pack's file name in the release (`ember-1.0.0.zip`).
    public var file: String
    public var bytes: Int64
    public var sha256: String
    /// A picture in the catalog itself (`previews/ember.png`): a companion's profile picture, an extension's icon.
    public var preview: String?
    /// A companion's character (`ember`): its files are `characters/ember.js`, `assets/ember.glb`…
    public var companion: String?
    /// The 3D engine a companion was made for.
    public var engine: Int?
    public var license: String?
    /// Where an extension sits in the gallery (`AddonCategory`); one this copy doesn't know shows under Other.
    public var category: String?

    /// Made by Sidefolk. Only Sidefolk signs packs and catalogs (D55), and review refuses this prefix to anyone
    /// else, so the id is enough.
    public var official: Bool { id.hasPrefix("dev.sidefolk.") }

    enum CodingKeys: String, CodingKey {
        case id, kind, name, tagline, description, author, version, file, bytes, sha256, preview, companion, engine, license, category
        case minimumSidefolk = "minimum_sidefolk"
    }
}

/// The gallery's list, as read from a checked catalog bundle.
public struct AddonCatalog: Sendable, Equatable {
    /// The format this copy of Sidefolk reads.
    public static let format = 1
    /// The 3D engine in `Resources/Companions3D` (bump when a change would break characters made for it).
    public static let engine = 1
    public static let maxBytes: Int64 = 64 * 1024 * 1024

    public var addons: [AddonEntry]
    /// Where the catalog's previews are on this Mac.
    public var folder: URL
    public var fetched: Date

    public init(addons: [AddonEntry], folder: URL, fetched: Date) {
        self.addons = addons
        self.folder = folder
        self.fetched = fetched
    }

    public func entry(_ id: String) -> AddonEntry? { addons.first { $0.id == id } }

    public func companion(_ name: String) -> AddonEntry? { addons.first { $0.kind == .companion && $0.companion == name } }

    /// The preview's file, if the catalog brought one.
    public func preview(for entry: AddonEntry) -> URL? {
        guard let path = entry.preview else { return nil }
        let url = folder.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Reads `catalog.json`: entries that are malformed, or need a newer Sidefolk or engine, are left out, so one bad
    /// entry never hides the others. A file in another format is refused whole.
    public static func parse(_ data: Data, folder: URL, fetched: Date, running: String = SidefolkVersion.current) throws -> AddonCatalog {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let items = root["addons"] as? [Any] else {
            throw UserFacingError("The add-on gallery's list couldn't be read.")
        }
        guard (root["format"] as? Int) == format else {
            throw UserFacingError("The add-on gallery needs a newer Sidefolk.", recovery: "Update Sidefolk, then try again.")
        }
        let decoder = JSONDecoder()
        var seen = Set<String>()
        let addons = items.compactMap { item -> AddonEntry? in
            guard let json = try? JSONSerialization.data(withJSONObject: item),
                  let entry = try? decoder.decode(AddonEntry.self, from: json),
                  valid(entry), fits(entry, running: running), seen.insert(entry.id).inserted else { return nil }
            return entry
        }
        return AddonCatalog(addons: addons, folder: folder, fetched: fetched)
    }

    static func valid(_ e: AddonEntry) -> Bool {
        func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        guard matches(e.id, #"^[a-z0-9]+(\.[a-z0-9][a-z0-9-]*){2,5}$"#), e.id.count <= 80,
              matches(e.file, #"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}\.zip$"#), !e.file.contains(".."),
              (1...maxBytes).contains(e.bytes),
              matches(e.sha256, #"^[0-9a-f]{64}$"#),
              ReleaseVersion(e.version) != nil,
              !e.name.isEmpty, e.name.count <= 40, e.tagline.count <= 60, e.description.count <= 1000, e.author.count <= 60 else { return false }
        if let category = e.category, !matches(category, #"^[a-z][a-z-]{0,23}$"#) { return false }
        if let preview = e.preview, !matches(preview, #"^previews/[A-Za-z0-9][A-Za-z0-9._-]{0,80}\.(png|pdf)$"#) || preview.contains("..") {
            return false
        }
        switch e.kind {
        case .companion:
            guard let name = e.companion, matches(name, #"^[a-z][a-z0-9-]{0,30}$"#), e.engine != nil else { return false }
        case .extension, .theme:
            guard e.companion == nil else { return false }
        }
        return true
    }

    static func fits(_ e: AddonEntry, running: String) -> Bool {
        if let engine = e.engine, engine > Self.engine { return false }
        guard let needed = e.minimumSidefolk else { return true }
        guard let need = ReleaseVersion(needed), let have = ReleaseVersion(running) else { return false }
        // A snapshot of 0.2.0 counts as 0.2.0 here: snapshots are how a version is tried before it ships.
        return ReleaseVersion(have.numbers.map(String.init).joined(separator: "."))! >= need
    }
}

/// Where the gallery is published, and whose signature its packs must carry. Both come from the app's own
/// Info.plist (`SidefolkAddons`, `SidefolkAddonsTeam`): a fork signed by someone else points at its own.
public struct AddonSource: Sendable, Equatable {
    /// The release's download folder: `<base>/catalog.zip`, `<base>/<entry.file>`.
    public var base: URL
    /// The Team ID of the Developer ID that signs packs and the catalog.
    public var team: String

    public init?(base: URL, team: String) {
        guard team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil,
              base.scheme == "https" || base.isFileURL else { return nil }
        self.base = base
        self.team = team
    }

    public static let catalogID = "dev.sidefolk.addons.catalog"
    public static let catalogFile = "catalog.zip"

    /// From the app's Info.plist. `SIDEFOLK_ADDONS` moves the gallery to a folder for development and tests, in a
    /// copy that isn't a published release (a release never reads it).
    public static func current(_ bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> AddonSource? {
        guard let team = bundle.object(forInfoDictionaryKey: "SidefolkAddonsTeam") as? String else { return nil }
        if bundle.object(forInfoDictionaryKey: "SidefolkRelease") == nil, let folder = environment["SIDEFOLK_ADDONS"], !folder.isEmpty {
            return AddonSource(base: URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true), team: team)
        }
        guard let text = bundle.object(forInfoDictionaryKey: "SidefolkAddons") as? String, let base = URL(string: text) else { return nil }
        return AddonSource(base: base, team: team)
    }

    /// What a pack or the catalog must be signed with: a Developer ID Application certificate of this team, under
    /// Apple's anchor, carrying exactly this identifier.
    func requirement(identifier: String) -> String {
        "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] and "
            + "certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[subject.OU] = \"\(team)\" and "
            + "identifier \"\(identifier)\""
    }
}

/// The gallery's shelves for extensions (D56). The catalog may name others later; this copy lists them under Other.
public enum AddonCategory: String, CaseIterable, Sendable {
    case everyday, files, developer, fun
}

extension AddonEntry {
    public var shelf: AddonCategory? { category.flatMap(AddonCategory.init(rawValue:)) }

    /// Whether every word of `text` is in its name, tagline, description, author or `extra` (a category's title),
    /// ignoring case, accents and width, as Settings' other searches do.
    public func matches(_ text: String, extra: [String] = []) -> Bool {
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil) }
        let haystack = fold(([shownName, shownTagline, shownDescription, author, name] + extra).joined(separator: "\n"))
        return text.split(whereSeparator: \.isWhitespace).allSatisfy { haystack.contains(fold(String($0))) }
    }

    /// Sidefolk's own extensions in the person's language (their words are in the app's string catalog, D28);
    /// anyone else's as published.
    private var translated: Bool { official && kind == .extension }
    public var shownName: String { translated ? BuiltInExtensionWords.name(id) ?? name : name }
    public var shownTagline: String { translated ? BuiltInExtensionWords.tagline(id) ?? tagline : tagline }
    public var shownDescription: String { translated ? BuiltInExtensionWords.description(id) ?? description : description }
}
