import Foundation
import GRDB

/// A backup opened and checked (D91), unpacked in a private temporary folder until it is restored or let go.
public struct OpenedBackup: Sendable {
    public let manifest: BackupManifest
    /// The unpacked backup: `manifest.json`, `data/`, `review/`, maybe `keys.json`.
    public let folder: URL

    public init(manifest: BackupManifest, folder: URL) {
        self.manifest = manifest
        self.folder = folder
    }

    public var hasKeys: Bool { manifest.keys }

    /// The sealed keys, opened with the person's password (`BackupKeys.open`).
    public func keys(password: String) throws -> [String: String] {
        try BackupKeys.open(Data(contentsOf: folder.appendingPathComponent(BackupLayout.keys)), password: password)
    }

    public func discard() { try? FileManager.default.removeItem(at: folder) }
}

/// Opens a `.sidefolkbackup` and refuses anything it can't vouch for, before a byte of it is used: a file that isn't a
/// zip or a backup, a path that would leave its folder, a link, a file the manifest doesn't list or whose digest
/// differs, a layout or database from a newer Sidefolk.
public enum BackupReader {
    /// A backup larger than this isn't one Sidefolk wrote for a person's data.
    static let maxBytes: Int64 = 8 * 1024 * 1024 * 1024

    public static func open(_ url: URL, knownSchema: Set<String> = AppDatabase.migrationIdentifiers) async throws -> OpenedBackup {
        let fm = FileManager.default
        let notABackup = UserFacingError("That file isn't a Sidefolk backup.", recovery: "Choose a file whose name ends in .sidefolkbackup.")
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= maxBytes else { throw notABackup }

        // Every entry's path is looked at before anything is unpacked: none may leave the folder.
        let listing = try await SystemTool.run("/usr/bin/zipinfo", ["-1", url.path], timeout: 120)
        guard listing.status == 0 else { throw notABackup }
        let entries = String(decoding: listing.output, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
        guard entries.contains(BackupManifest.fileName),
              entries.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else { throw notABackup }

        let folder = fm.temporaryDirectory.appendingPathComponent("sidefolk-restore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let out = try await SystemTool.run("/usr/bin/ditto", ["-x", "-k", url.path, folder.path], timeout: 1800)
            guard out.status == 0 else { throw notABackup }
            let backup = try check(folder, knownSchema: knownSchema, notABackup: notABackup)
            Log.shared.info("backup", "opened", ["format": String(backup.manifest.format), "files": String(backup.manifest.files.count)])
            return backup
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }

    static func check(_ folder: URL, knownSchema: Set<String>, notABackup: UserFacingError) throws -> OpenedBackup {
        guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(BackupManifest.fileName).path),
              let manifest = try? BackupManifest.decoder.decode(BackupManifest.self, from: data) else { throw notABackup }
        let newer = UserFacingError("This backup was made by a newer Sidefolk (\(manifest.app)).",
                                    recovery: "Update Sidefolk, then restore it.")
        guard manifest.format <= BackupManifest.currentFormat else { throw newer }
        guard manifest.format >= 1 else { throw notABackup }
        let damaged = UserFacingError("This backup is damaged: its files don't match what it lists, so nothing was restored.",
                                      recovery: "Make the backup again on the other Mac, or try another copy of it.")
        guard try BackupFiles.digests(in: folder) == manifest.files else { throw damaged }
        let database = folder.appendingPathComponent("\(BackupLayout.data)/\(BackupLayout.database)")
        guard FileManager.default.fileExists(atPath: database.path) else { throw damaged }
        // Its migrations must all be ones this copy knows; older ones are run when the database opens after the restore.
        let schema: [String]
        do { schema = try BackupWriter.schema(of: database) } catch { throw damaged }
        guard Set(schema).isSubset(of: knownSchema) else { throw newer }
        return OpenedBackup(manifest: manifest, folder: folder)
    }
}
