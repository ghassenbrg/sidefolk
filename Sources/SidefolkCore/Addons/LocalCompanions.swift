import Foundation

/// 3D companions added from a folder on this Mac (D60): the person's own, made the way the gallery's are
/// (`companions-3d/`) but never published. Nothing vouches for them, so they are checked as strictly as a file can
/// be (the manifest, exactly the four files, their size and kind) and installed beside the gallery's, in
/// `<home>/Addons/Companions/<name>/`, marked as added from a folder. The character file is code the 3D page runs;
/// Settings says so before adding one.
extension AddonStore {
    /// Largest each file may be: a character file is a few kilobytes, a model a few megabytes.
    static let localLimits: [String: Int64] = ["js": 512 * 1024, "glb": 64 * 1024 * 1024, "png": 8 * 1024 * 1024]

    /// What `folder` would add, read and checked, nothing copied: its `addon.json` (as the gallery's add-ons write
    /// it: `name`, `companion`, and optionally `tagline`, `author`, `version`, `engine`, `body`) and exactly
    /// `characters/<companion>.js`, `assets/<companion>.glb`, `portraits/<companion>.png` and `avatars/<companion>.png`.
    public nonisolated static func readLocalCompanion(_ folder: URL) throws -> InstalledCompanion {
        let manifestFile = folder.appendingPathComponent("addon.json")
        guard let data = FileManager.default.contents(atPath: manifestFile.path) else {
            throw UserFacingError("That folder isn't a companion: it has no addon.json.")
        }
        let manifest: LocalManifest
        do { manifest = try JSONDecoder().decode(LocalManifest.self, from: data) } catch {
            throw UserFacingError("The companion's addon.json can't be read.", detail: String(describing: error))
        }
        let name = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = manifest.companion
        guard manifest.kind == nil || manifest.kind == "companion" else { throw UserFacingError("That add-on isn't a companion.") }
        guard !name.isEmpty, name.count <= 40 else { throw UserFacingError("The companion needs a name of up to 40 characters.") }
        guard id.range(of: #"^[a-z][a-z0-9-]{0,30}$"#, options: .regularExpression) != nil else {
            throw UserFacingError("The companion's id must be lowercase letters, digits and dashes.", detail: "companion: \(id)")
        }
        // Its folder would stand in for (or be hidden by) one of Sidefolk's own, or one from the gallery.
        guard CompanionChoice(rawValue: id) == nil else {
            throw UserFacingError("“\(id)” is already one of Sidefolk's companions.", recovery: "Give yours another id in its addon.json.")
        }
        guard (manifest.engine ?? 1) <= AddonCatalog.engine else {
            throw UserFacingError("\(name) was made for a newer Sidefolk.", recovery: "Update Sidefolk, then add it again.")
        }
        var body: CompanionBody?
        if let raw = manifest.body {
            guard let known = CompanionBody(rawValue: raw) else {
                throw UserFacingError("The companion's body must be biped, floating or card.", detail: "body: \(raw)")
            }
            body = known
        }
        try checkLocalFiles(folder, name: id)
        return InstalledCompanion(id: "local.\(id)", name: name, companion: id, version: manifest.version ?? "1.0.0",
                                  author: manifest.author ?? "", tagline: manifest.tagline, body: body, fromFolder: true)
    }

    /// Exactly the four files a 3D companion needs beside its `addon.json`, each no larger than it should be and of
    /// its kind (a glTF binary, PNGs): no links, no other files (Finder's litter aside).
    nonisolated static func checkLocalFiles(_ folder: URL, name: String) throws {
        let entries = try ExtensionFiles.walk(folder.path, skipping: ExtensionFiles.skippedNames)
        let expected = ["characters/\(name).js", "assets/\(name).glb", "portraits/\(name).png", "avatars/\(name).png"]
        let files = Set(entries.filter { !$0.isDirectory }.map(\.path))
        let folders = Set(entries.filter(\.isDirectory).map(\.path))
        let missing = expected.filter { !files.contains($0) }
        let extra = files.subtracting(expected + ["addon.json"]).union(folders.subtracting(["characters", "assets", "portraits", "avatars"]))
        guard missing.isEmpty else {
            throw UserFacingError("The companion is missing \(missing.joined(separator: ", ")).")
        }
        guard extra.isEmpty else {
            throw UserFacingError("The companion's folder holds more than it should: \(extra.sorted().joined(separator: ", ")).",
                                  recovery: "Keep only addon.json and the four files it needs.")
        }
        for entry in entries where !entry.isDirectory && entry.path != "addon.json" {
            let ext = (entry.path as NSString).pathExtension
            guard Int64(entry.st.st_size) <= localLimits[ext, default: 0] else {
                throw UserFacingError("\(entry.path) is too large for a companion.")
            }
            let head = FileHandle(forReadingAtPath: folder.appendingPathComponent(entry.path).path).flatMap { try? $0.read(upToCount: 8) } ?? Data()
            let magic: [UInt8]? = ext == "glb" ? Array("glTF".utf8) : ext == "png" ? [0x89, 0x50, 0x4E, 0x47] : nil
            if let magic, !head.starts(with: magic) {
                throw UserFacingError("\(entry.path) isn't the kind of file its name says.")
            }
        }
    }

    /// Adds the companion in `folder` (checked as `readLocalCompanion` does), replacing one added before under the
    /// same id. The copies lose any download mark: the person chose this folder and agreed to add it.
    @discardableResult
    public func install(companionFolder folder: URL) throws -> InstalledCompanion {
        let companion = try Self.readLocalCompanion(folder)
        let target = companionsFolder.appendingPathComponent(companion.companion, isDirectory: true)
        // A gallery companion this copy doesn't know yet may already live under that name.
        if let there = Self.installedCompanions(in: companionsFolder).first(where: { $0.companion == companion.companion }),
           !there.addedFromFolder {
            throw UserFacingError("“\(companion.companion)” is already one of Sidefolk's companions.",
                                  recovery: "Give yours another id in its addon.json.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: companionsFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staged = companionsFolder.deletingLastPathComponent().appendingPathComponent(".companion-\(UUID().uuidString)", isDirectory: true)
        do {
            try ExtensionFiles.copy(from: folder.path, to: staged.path, quarantine: .none)
            try Self.checkLocalFiles(staged, name: companion.companion)
            try JSONEncoder().encode(companion).write(to: staged.appendingPathComponent("addon.json"))
            try replace(target, with: staged)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
        Log.shared.info("addons", "added companion from a folder", ["companion": companion.companion])
        return companion
    }
}

/// `addon.json` as the gallery's add-ons write it (sidefolk-addons), read for a companion added from a folder.
private struct LocalManifest: Decodable {
    var kind: String?
    var name: String
    var companion: String
    var tagline: String?
    var author: String?
    var version: String?
    var engine: Int?
    var body: String?
}
