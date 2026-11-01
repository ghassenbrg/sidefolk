import Foundation
import GRDB

/// Backs up everything Sidefolk keeps into one `.sidefolkbackup` file (D91), to move it to another Mac or to start
/// fresh and come back. The database is copied with `VACUUM INTO`, a consistent copy even while Sidefolk runs, never
/// a copy of the live file. Left out: caches, logs, downloads, the sandbox profiles, the add-ons' signed files (named
/// in the manifest, fetched again), Claude Code's and Codex's configs (Connect again, D86), and, unless asked for with
/// a password, the keys.
public struct BackupWriter: Sendable {
    let runtime: SidefolkRuntime

    public init(runtime: SidefolkRuntime) { self.runtime = runtime }

    /// Writes the backup to `url` (0600) and returns its manifest. `keys` seals these with `password` (BackupKeys).
    @discardableResult
    public func write(to url: URL, keys: [String: String]? = nil, password: String? = nil, now: Date = Date(),
                      device: String? = Host.current().localizedName) async throws -> BackupManifest {
        let fm = FileManager.default
        let paths = runtime.paths
        let stage = fm.temporaryDirectory.appendingPathComponent("sidefolk-backup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage.appendingPathComponent(BackupLayout.data), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }

        let database = stage.appendingPathComponent(BackupLayout.data).appendingPathComponent(BackupLayout.database)
        try await runtime.db.writer.vacuum(into: database.path)
        for folder in BackupLayout.dataFolders {
            try Self.copy(paths.home.appendingPathComponent(folder), to: stage.appendingPathComponent("\(BackupLayout.data)/\(folder)"))
        }

        var extensions: [BackupManifest.Extension] = []
        for info in await runtime.extensions.extensions() {
            let source: BackupManifest.Source = switch (info.kind, info.origin) {
            case (.mcp, _): .mcp
            case (_, .bundled?): .builtIn
            case (_, .official?): .gallery
            default: .folder
            }
            if source == .folder {
                try Self.copy(paths.extensions.appendingPathComponent(info.id),
                              to: stage.appendingPathComponent("\(BackupLayout.reviewExtensions)/\(info.id)"))
            }
            extensions.append(.init(id: info.id, name: info.name, version: info.version, enabled: info.enabled, source: source))
        }

        var addons: [BackupManifest.Addon] = []
        let companions = paths.addons.appendingPathComponent("Companions", isDirectory: true)
        for companion in AddonStore.installedCompanions(in: companions) {
            if companion.addedFromFolder {
                try Self.copy(companions.appendingPathComponent(companion.companion),
                              to: stage.appendingPathComponent("\(BackupLayout.reviewCompanions)/\(companion.companion)"))
            } else {
                addons.append(.init(id: companion.id, kind: .companion, name: companion.name, version: companion.version))
            }
        }
        for theme in ThemeLibrary(paths: paths).all() {
            guard let folder = theme.folder else { continue }
            if AddonEntry.isOfficial(id: theme.id) {
                addons.append(.init(id: theme.id, kind: .theme, name: theme.tokens.name, version: theme.version ?? "1.0.0"))
            } else {
                try Self.copy(folder, to: stage.appendingPathComponent("\(BackupLayout.reviewThemes)/\(theme.id)"))
            }
        }

        if let keys, let password, !keys.isEmpty {
            try BackupKeys.seal(keys, password: password).write(to: stage.appendingPathComponent(BackupLayout.keys))
        }

        var counts = try await Self.counts(of: database)
        counts.extensions = extensions.filter { $0.source != .builtIn }.count
        counts.addons = addons.count
        counts.skills = (try? fm.contentsOfDirectory(atPath: paths.skills.path).filter { !$0.hasPrefix(".") }.count) ?? 0
        let manifest = BackupManifest(
            format: BackupManifest.currentFormat, app: ReleaseVersion(SidefolkVersion.running)?.shown ?? SidefolkVersion.running, version: SidefolkVersion.running, created: now,
            device: device, schema: try Self.schema(of: database), counts: counts, extensions: extensions, addons: addons,
            keys: fm.fileExists(atPath: stage.appendingPathComponent(BackupLayout.keys).path), files: try BackupFiles.digests(in: stage))
        try BackupManifest.encoder.encode(manifest).write(to: stage.appendingPathComponent(BackupManifest.fileName))

        let zip = stage.deletingLastPathComponent().appendingPathComponent("\(stage.lastPathComponent).zip")
        defer { try? fm.removeItem(at: zip) }
        let out = try await SystemTool.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", stage.path, zip.path], timeout: 1800)
        guard out.status == 0 else { throw UserFacingError("The backup couldn't be written.", detail: "ditto exited \(out.status)") }
        try? fm.removeItem(at: url)
        do {
            try fm.moveItem(at: zip, to: url)
        } catch {
            throw UserFacingError("I couldn't write the backup there.", recovery: "Choose another folder.", detail: String(describing: error))
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        Log.shared.info("backup", "written", ["files": String(manifest.files.count), "keys": String(manifest.keys)])
        return manifest
    }

    /// Copies a folder as it is, when it's there; links and other special files are left out.
    static func copy(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        guard ExtensionFS.lstat(from.path).map({ $0.st_mode & S_IFMT == S_IFDIR }) == true else { return }
        try fm.createDirectory(at: to, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for name in try fm.contentsOfDirectory(atPath: from.path) {
            let source = from.appendingPathComponent(name), dest = to.appendingPathComponent(name)
            guard let st = ExtensionFS.lstat(source.path) else { continue }
            switch st.st_mode & S_IFMT {
            case S_IFDIR: try copy(source, to: dest)
            case S_IFREG:
                try fm.copyItem(at: source, to: dest)
                // Installed extensions are read-only; their copies must stay removable.
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
            default: continue
            }
        }
    }

    static func counts(of database: URL) async throws -> BackupManifest.Counts {
        let queue = try DatabaseQueue(path: database.path, configuration: BackupFiles.readOnly)
        return try await queue.read { db in
            var c = BackupManifest.Counts()
            c.notes = try NotebookItem.filter(Column("deleted_at") == nil).fetchCount(db)
            c.collections = try NotebookCollection.fetchCount(db)
            c.reminders = try Reminder.fetchCount(db)
            c.watchers = try Watcher.fetchCount(db)
            c.conversations = try Exchange.fetchCount(db)
            c.activity = try ActivityEntry.fetchCount(db)
            return c
        }
    }

    static func schema(of database: URL) throws -> [String] {
        let queue = try DatabaseQueue(path: database.path, configuration: BackupFiles.readOnly)
        return try queue.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier") }
    }
}

/// The files of a backup folder and their digests.
enum BackupFiles {
    static var readOnly: Configuration {
        var c = Configuration()
        c.readonly = true
        return c
    }

    /// Every regular file under `root` (but the manifest), by its path inside it, with its SHA-256. A link or any other
    /// special file is refused: a backup holds plain files only.
    static func digests(in root: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        let base = root.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(atPath: base) else { return out }
        while let relative = walker.nextObject() as? String {
            let full = base + "/" + relative
            guard let st = ExtensionFS.lstat(full) else { continue }
            switch st.st_mode & S_IFMT {
            case S_IFDIR: continue
            case S_IFREG:
                if relative == BackupManifest.fileName { continue }
                out[relative] = try FileDigest.sha256(URL(fileURLWithPath: full))
            default:
                throw UserFacingError("That file isn't a Sidefolk backup.", detail: "special file: \(relative)")
            }
        }
        return out
    }
}
