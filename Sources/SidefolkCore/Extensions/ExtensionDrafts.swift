import Darwin
import Foundation

/// Extensions Sidefolk's AI writes for the person (D39), one folder per draft in `ExtensionDrafts/` under
/// the Sidefolk home, until the person installs one through the normal install preview. A draft is text
/// only (scripts, JSON, notes): no binaries, no links, no executable bits, no icon. Nothing in it runs
/// except a start in a sandbox with every permission removed, to see that it answers.
public final class ExtensionDrafts: Sendable {
    /// Drafts are `local.<name>`: never a company's reverse-DNS id, never a built-in one.
    public static let idPrefix = "local."
    public static let namePattern = #"^[a-z0-9][a-z0-9-]{0,39}$"#
    /// What the manifest says wrote it; shown on the install sheet like any author.
    public static let author = "Sidefolk, for you"
    static let maxFiles = 20
    static let maxDrafts = 20
    static let maxFileBytes = 200 * 1024
    static let maxTotalBytes = 1024 * 1024
    static let fileTypes: Set<String> = ["py", "js", "mjs", "cjs", "sh", "json", "txt", "md", "csv"]

    public struct Draft: Sendable, Hashable, Identifiable {
        public var id: String
        /// The short name the AI chose (`strava-runs`).
        public var name: String
        /// The manifest's display name, or the short name when the manifest can't be read.
        public var title: String
        public var version: String?
        public var folder: URL
        public var modified: Date
    }

    public let directory: URL

    private let trash: @Sendable (URL) throws -> Void

    /// - Parameter trash: moves a deleted draft to the Trash (tests pass one that only removes it).
    public init(directory: URL, trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.directory = directory
        self.trash = trash
    }

    public convenience init(paths: SidefolkPaths) { self.init(directory: paths.extensionDrafts) }

    public static func id(for name: String) -> String { idPrefix + name }

    public func folder(name: String) -> URL { directory.appendingPathComponent(Self.id(for: name), isDirectory: true) }

    public func exists(name: String) -> Bool {
        Self.isName(name) && ExtensionFS.lstat(folder(name: name).path).map(ExtensionFS.isDirectory) == true
    }

    static func isName(_ name: String) -> Bool { name.range(of: namePattern, options: .regularExpression) != nil }

    // MARK: Writing

    /// Replaces the draft `name` with exactly this manifest and these files. The manifest's `id` and
    /// `author` are Sidefolk's to set; everything else is checked by the install validator afterwards.
    @discardableResult
    public func write(name: String, manifest: JSONValue, files: [String: String]) throws -> URL {
        guard Self.isName(name) else {
            throw UserFacingError(verbatim: "The draft's name must be lowercase letters, digits and dashes, like strava-runs (at most 40).")
        }
        guard var object = manifest.objectValue else { throw UserFacingError(verbatim: "The manifest must be a JSON object.") }
        guard object["icon"] == nil else {
            throw UserFacingError(verbatim: "Leave “icon” out: a draft can only hold text files, and gets Sidefolk's default icon.")
        }
        object["id"] = .string(Self.id(for: name))
        object["author"] = .string(Self.author)
        try Self.check(files)
        // A model writing draft after draft under new names would otherwise fill the folder without end.
        guard exists(name: name) || list().count < Self.maxDrafts else {
            throw UserFacingError(verbatim: "There are already \(Self.maxDrafts) extension drafts. Reuse one's name, or ask the person to delete some in Settings › Extensions.")
        }

        try ExtensionFS.makePrivateDirectory(directory)
        removeLeftoverStaging()
        let staging = directory.appendingPathComponent(".staging-\(Identifier.make())", isDirectory: true).path
        do {
            guard mkdir(staging, 0o700) == 0 else { throw ExtensionError.io("Couldn't create \(staging)") }
            try Self.writeFile(staging + "/" + ExtensionManifest.fileName, text: JSONValue.object(object).prettyString + "\n")
            for (path, text) in files.sorted(by: { $0.key < $1.key }) {
                var dir = staging
                for part in path.split(separator: "/").dropLast() {
                    dir += "/" + part
                    if ExtensionFS.lstat(dir) == nil, mkdir(dir, 0o700) != 0 { throw ExtensionError.io("Couldn't create \(dir)") }
                }
                try Self.writeFile(staging + "/" + path, text: text)
            }
            let final = folder(name: name).path
            ExtensionFiles.removeTree(final)
            guard rename(staging, final) == 0 else { throw ExtensionError.io("Couldn't save the draft: \(String(cString: strerror(errno)))") }
            return URL(fileURLWithPath: final, isDirectory: true)
        } catch {
            ExtensionFiles.removeTree(staging)
            throw error
        }
    }

    /// A write interrupted by a quit or crash leaves its staging folder; the next write clears any older than an hour.
    private func removeLeftoverStaging(now: Date = Date()) {
        for entry in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where entry.hasPrefix(".staging-") {
            let path = directory.appendingPathComponent(entry).path
            guard let st = ExtensionFS.lstat(path), now.timeIntervalSince1970 - TimeInterval(st.st_mtimespec.tv_sec) > 3600 else { continue }
            ExtensionFiles.removeTree(path)
        }
    }

    /// Paths are plain relative names (`main.py`, `lib/strava.py`) of known text types, small and few.
    static func check(_ files: [String: String]) throws {
        guard !files.isEmpty else { throw UserFacingError(verbatim: "A draft needs at least its program, like main.py.") }
        guard files.count <= maxFiles else { throw UserFacingError(verbatim: "A draft can hold at most \(maxFiles) files.") }
        var total = 0
        for (path, text) in files {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.isEmpty, path.count <= 120, !path.hasPrefix("/"), parts.count <= 4,
                  parts.allSatisfy({ $0.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil }),
                  !parts.contains(where: { $0.hasPrefix(".") || $0.contains("..") }) else {
                throw UserFacingError(verbatim: "“\(path)” isn't a plain relative file name like main.py or lib/client.py.")
            }
            guard path != ExtensionManifest.fileName else {
                throw UserFacingError(verbatim: "Pass the manifest as “manifest”, not as a file.")
            }
            guard fileTypes.contains((path as NSString).pathExtension.lowercased()) else {
                throw UserFacingError(verbatim: "“\(path)” must be one of: \(fileTypes.sorted().map { "." + $0 }.joined(separator: " ")).")
            }
            let bytes = text.utf8.count
            guard bytes <= maxFileBytes else { throw UserFacingError(verbatim: "“\(path)” is larger than 200 KB.") }
            total += bytes
        }
        guard total <= maxTotalBytes else { throw UserFacingError(verbatim: "The draft's files add up to more than 1 MB.") }
    }

    /// New files only, owner read-write, never executable, never through a link.
    private static func writeFile(_ path: String, text: String) throws {
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ExtensionError.io("Couldn't write \(path)") }
        defer { close(fd) }
        let ok = Data(text.utf8).withUnsafeBytes { raw in raw.isEmpty || Darwin.write(fd, raw.baseAddress, raw.count) == raw.count }
        guard ok else { throw ExtensionError.io("Couldn't write \(path)") }
    }

    // MARK: Reading

    /// Every draft, newest first.
    public func list() -> [Draft] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { entry -> Draft? in
            guard entry.hasPrefix(Self.idPrefix) else { return nil }
            let name = String(entry.dropFirst(Self.idPrefix.count))
            guard Self.isName(name), let st = ExtensionFS.lstat(folder(name: name).path), ExtensionFS.isDirectory(st) else { return nil }
            let manifest = FileManager.default.contents(atPath: folder(name: name).appendingPathComponent(ExtensionManifest.fileName).path)
                .flatMap { try? ExtensionManifest.decode($0) }
            let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            return Draft(id: entry, name: name, title: manifest?.name ?? name, version: manifest?.version,
                         folder: folder(name: name), modified: modified)
        }
        .sorted { $0.modified > $1.modified }
    }

    /// The draft's files as text, the manifest first, for the AI to change them.
    public func read(name: String) throws -> [(path: String, text: String)] {
        guard exists(name: name) else { throw ToolError.notFound(String(localized: "a draft called “\(name)”")) }
        let root = folder(name: name).path
        let entries = try ExtensionFiles.walk(root).filter { !$0.isDirectory }
        return entries.map { e in (e.path, String(decoding: FileManager.default.contents(atPath: root + "/" + e.path) ?? Data(), as: UTF8.self)) }
            .sorted { ($0.path == ExtensionManifest.fileName ? 0 : 1, $0.path) < ($1.path == ExtensionManifest.fileName ? 0 : 1, $1.path) }
    }

    /// Moves the draft to the Trash, like everything else people delete in Sidefolk.
    public func delete(name: String) throws {
        guard exists(name: name) else { throw ToolError.notFound(String(localized: "a draft called “\(name)”")) }
        try trash(folder(name: name))
    }

    // MARK: Trying

    /// Starts a copy of the draft with every permission removed (no network, no folders, no programs):
    /// does it answer `initialize` and list the tools its manifest describes? Its code runs, but can
    /// touch nothing but a throwaway folder; the person hasn't approved anything yet.
    public func trial(name: String) async -> ExtensionValidator.TrialReport {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-draft-\(UUID().uuidString)", isDirectory: true)
        defer { ExtensionFiles.removeTree(scratch.path) }
        let copy = scratch.appendingPathComponent(Self.id(for: name), isDirectory: true)
        do {
            try ExtensionFS.makePrivateDirectory(scratch)
            try ExtensionFiles.copy(from: folder(name: name).path, to: copy.path)
            let file = copy.appendingPathComponent(ExtensionManifest.fileName)
            guard var manifest = try JSONValue.parse(String(decoding: Data(contentsOf: file), as: UTF8.self)).objectValue else {
                return ExtensionValidator.TrialReport(tools: [], warnings: [], problem: "The manifest isn't a JSON object.")
            }
            manifest["permissions"] = .object([:])
            try FileManager.default.removeItem(at: file)
            try Data(JSONValue.object(manifest).jsonString.utf8).write(to: file)
        } catch {
            return ExtensionValidator.TrialReport(tools: [], warnings: [], problem: "The draft couldn't be copied for a trial: \(error)")
        }
        return await ExtensionValidator.trial(at: copy)
    }
}
