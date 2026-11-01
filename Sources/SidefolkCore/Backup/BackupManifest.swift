import Foundation

/// What a backup holds (D91), its first file. A backup is a zip (`.sidefolkbackup`): this manifest, `data/` (the
/// database copied with `VACUUM INTO`, ExtensionData, ExtensionDrafts, Skills and companions made as data),
/// `review/` (what is code or checked again before it is used: extensions and companions added from a folder, themes
/// of the person's own), and, only when the person chose it, `keys.json`, sealed with their password.
/// Gallery add-ons are named here, never copied: a restore fetches them again from the gallery, signatures checked.
public struct BackupManifest: Codable, Sendable, Equatable {
    /// The layout this copy writes and reads. A backup in a higher one was made by a newer Sidefolk.
    public static let currentFormat = 1
    public static let fileName = "manifest.json"
    public static let fileExtension = "sidefolkbackup"

    public struct Counts: Codable, Sendable, Equatable {
        public var notes = 0
        public var collections = 0
        public var reminders = 0
        public var watchers = 0
        public var conversations = 0
        public var activity = 0
        public var extensions = 0
        public var addons = 0
        public var skills = 0

        public init() {}
    }

    /// Where an extension came from, which decides how it comes back.
    public enum Source: String, Codable, Sendable {
        /// Comes with Sidefolk: only whether it was on.
        case builtIn = "built-in"
        /// From the gallery: installed again from it.
        case gallery
        /// From a folder, or written for the person: its files are in `review/extensions/<id>`, installed again only
        /// after the person looks at it.
        case folder
        /// An MCP server the person added: it comes back switched off.
        case mcp
    }

    public struct Extension: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var version: String
        public var enabled: Bool
        public var source: Source

        public init(id: String, name: String, version: String, enabled: Bool, source: Source) {
            (self.id, self.name, self.version, self.enabled, self.source) = (id, name, version, enabled, source)
        }
    }

    /// A companion or theme from the gallery, installed again from it.
    public struct Addon: Codable, Sendable, Equatable {
        public var id: String
        public var kind: AddonEntry.Kind
        public var name: String
        public var version: String
    }

    public var format: Int
    /// "0.1.0 snapshot 673", as people read it.
    public var app: String
    /// `SidefolkVersion.running`.
    public var version: String
    public var created: Date
    /// The Mac it was made on ("Ghassen's MacBook Air").
    public var device: String?
    /// The database's migrations: a restore refuses one this copy doesn't know (a newer Sidefolk's).
    public var schema: [String]
    public var counts: Counts
    public var extensions: [Extension]
    public var addons: [Addon]
    /// Whether `keys.json` is there.
    public var keys: Bool
    /// SHA-256 of every other file, by its path in the backup.
    public var files: [String: String]

    public init(format: Int = currentFormat, app: String, version: String, created: Date, device: String?, schema: [String],
                counts: Counts, extensions: [Extension], addons: [Addon], keys: Bool, files: [String: String]) {
        (self.format, self.app, self.version, self.created, self.device, self.schema) = (format, app, version, created, device, schema)
        (self.counts, self.extensions, self.addons, self.keys, self.files) = (counts, extensions, addons, keys, files)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Paths inside a backup, and in the data folder they come from or go to.
enum BackupLayout {
    static let data = "data"
    static let review = "review"
    static let keys = "keys.json"
    static let database = "sidefolk.sqlite"
    /// Copied as they are: the person's own data, used again without a look.
    static let dataFolders = ["ExtensionData", "ExtensionDrafts", "Skills", "companions"]
    static let reviewExtensions = "review/extensions"
    static let reviewCompanions = "review/companions"
    static let reviewThemes = "review/themes"
}
