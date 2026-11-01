import Foundation
import GRDB

/// Puts a backup in place of the data folder's contents (D91), and back again. Nothing is swapped while Sidefolk
/// runs: `stage` lays the checked backup beside the data, the app relaunches, and `applyAtLaunch` swaps before the
/// database opens. What was there goes to `Restore-undo-<date>`, kept seven days for Undo restore. Replace only: a
/// merge would have to match notes, reminders and settings made apart, and guess wrong.
public struct BackupRestore: Sendable {
    public let paths: SidefolkPaths

    public init(paths: SidefolkPaths) { self.paths = paths }

    /// What a restore brought back, for its follow-up after the relaunch (`RestoreFollowUp`) and for Undo.
    public struct Plan: Codable, Sendable, Equatable {
        public var backupCreated: Date
        public var app: String
        public var device: String?
        public var extensions: [BackupManifest.Extension]
        public var addons: [BackupManifest.Addon]
        public var restoredAt: Date?

        public init(backupCreated: Date, app: String, device: String?, extensions: [BackupManifest.Extension],
                    addons: [BackupManifest.Addon], restoredAt: Date? = nil) {
            (self.backupCreated, self.app, self.device, self.extensions, self.addons, self.restoredAt)
                = (backupCreated, app, device, extensions, addons, restoredAt)
        }
    }

    /// What the launch did.
    public enum Outcome: Sendable, Equatable {
        case restored(Plan)
        case undone(Plan)
    }

    public static let keepUndo: TimeInterval = 7 * 24 * 3600
    public static let reviewFolder = "Restore-review"
    static let pending = ".restore-pending"
    static let undoRequest = ".restore-undo-requested"
    static let followUp = ".restore-followup.json"
    static let undoPrefix = "Restore-undo-"
    static let planFile = "plan.json"
    /// The values a restore's keys replaced, sealed (`BackupKeys.keepBefore`).
    static let keysBefore = "keys-before.json"
    /// What a restore replaces and its undo puts back: the database and the person's folders, and what follows from
    /// them (installed add-ons, sandbox profiles, chart history). Logs, settings of the Mac and the gallery's downloads
    /// aren't data.
    static let items = ["sidefolk.sqlite", "sidefolk.sqlite-wal", "sidefolk.sqlite-shm", "ExtensionData", "Extensions",
                        "ExtensionDrafts", "Skills", "Addons", "Themes", "companions", "PageHistory", "Sandbox", reviewFolder]

    private var home: URL { paths.home }
    private func url(_ name: String) -> URL { home.appendingPathComponent(name) }

    // MARK: Staging

    /// Lays the checked backup beside the data, ready for the next launch. Extensions come back only once installed
    /// again (gallery ones from the gallery, others after a look), and MCP servers switched off: their command runs
    /// with the person's own permissions, so a backup alone never starts one.
    public func stage(_ backup: OpenedBackup, now: Date = Date()) throws {
        let fm = FileManager.default
        let pending = url(Self.pending)
        ExtensionFiles.removeTree(pending.path)
        try fm.createDirectory(at: pending, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            try BackupWriter.copy(backup.folder.appendingPathComponent(BackupLayout.data), to: pending.appendingPathComponent(BackupLayout.data))
            try BackupWriter.copy(backup.folder.appendingPathComponent(BackupLayout.review), to: pending.appendingPathComponent(Self.reviewFolder))
            try Self.sanitize(pending.appendingPathComponent("\(BackupLayout.data)/\(BackupLayout.database)"))
            let preferences = backup.folder.appendingPathComponent(BackupPreferences.file)
            if fm.fileExists(atPath: preferences.path) {
                try fm.copyItem(at: preferences, to: pending.appendingPathComponent(BackupPreferences.file))
            }
            let m = backup.manifest
            let plan = Plan(backupCreated: m.created, app: m.app, device: m.device, extensions: m.extensions, addons: m.addons)
            try BackupManifest.encoder.encode(plan).write(to: pending.appendingPathComponent(Self.planFile))
        } catch {
            ExtensionFiles.removeTree(pending.path)
            throw error
        }
        Log.shared.info("backup", "restore staged", ["created": ISO8601DateFormatter().string(from: backup.manifest.created)])
    }

    static func sanitize(_ database: URL) throws {
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "DELETE FROM extensions WHERE kind = 'sidefolk'")
            try db.execute(sql: "UPDATE extensions SET enabled = 0")
            // Sessions and running commands belonged to the other Mac's processes.
            try db.execute(sql: "DELETE FROM sessions")
            try db.execute(sql: "UPDATE jobs SET state = 'cancelled' WHERE state = 'running'")
        }
    }

    public var isStaged: Bool { FileManager.default.fileExists(atPath: url(Self.pending).appendingPathComponent(Self.planFile).path) }

    /// Forgets a staged restore that wasn't applied, putting back any keys it saved.
    public func cancelStaged(secrets: (any SecretStore)? = nil) {
        if let secrets { BackupKeys.putBack(from: url(Self.pending).appendingPathComponent(Self.keysBefore), to: secrets) }
        ExtensionFiles.removeTree(url(Self.pending).path)
    }

    /// Saves a staged restore's keys, replacing those with the same names, and keeps what they replace for Undo
    /// restore (sealed beside the staged backup, then in its undo folder). Call after `stage`.
    public func saveKeys(_ keys: [String: String], to store: any SecretStore) throws {
        let before = url(Self.pending).appendingPathComponent(Self.keysBefore)
        try BackupKeys.keepBefore(keys, from: store, to: before)
        do {
            try BackupKeys.save(keys, to: store)
        } catch {
            BackupKeys.putBack(from: before, to: store)
            throw error
        }
    }

    // MARK: At launch

    /// Runs before the database opens: a staged restore swaps in, an asked-for undo swaps back, and undo copies older
    /// than seven days go. A swap that fails half way is rolled back, so the data folder is always one or the other.
    /// `secrets` and `defaults` are the Keychain and the app's defaults: Undo restore puts back the keys and the
    /// preferences a restore replaced, and a restore that fails puts back its keys.
    @discardableResult
    public func applyAtLaunch(now: Date = Date(), secrets: (any SecretStore)? = nil, defaults: UserDefaults? = nil) -> Outcome? {
        expire(now: now, secrets: secrets)
        if FileManager.default.fileExists(atPath: url(Self.undoRequest).path) {
            try? FileManager.default.removeItem(at: url(Self.undoRequest))
            return undo(secrets: secrets, defaults: defaults).map(Outcome.undone)
        }
        let pending = url(Self.pending)
        guard let data = FileManager.default.contents(atPath: pending.appendingPathComponent(Self.planFile).path),
              var plan = try? BackupManifest.decoder.decode(Plan.self, from: data) else {
            cancelStaged(secrets: secrets)
            return nil
        }
        plan.restoredAt = now
        let stamp = Self.stamp(now)
        let undo = url(Self.undoPrefix + stamp)
        do {
            try FileManager.default.createDirectory(at: undo, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try BackupManifest.encoder.encode(plan).write(to: undo.appendingPathComponent(Self.planFile))
            try swap(out: home, aside: undo, in: [pending.appendingPathComponent(BackupLayout.data), pending])
            try BackupManifest.encoder.encode(plan).write(to: url(Self.followUp))
        } catch {
            Log.shared.error("backup", "restore failed; data left as it was", ["error": String(describing: error)])
            ExtensionFiles.removeTree(undo.path)
            cancelStaged(secrets: secrets)
            return nil
        }
        // What the keys replaced goes with the undo copy; the preferences are set now, what they replace kept there too.
        try? FileManager.default.moveItem(at: pending.appendingPathComponent(Self.keysBefore), to: undo.appendingPathComponent(Self.keysBefore))
        if let defaults, let data = FileManager.default.contents(atPath: pending.appendingPathComponent(BackupPreferences.file).path),
           let values = try? BackupManifest.decoder.decode([String: JSONValue].self, from: data) {
            let replaced = BackupPreferences.apply(values, to: defaults)
            try? BackupManifest.encoder.encode(replaced).write(to: undo.appendingPathComponent(BackupPreferences.before))
        }
        ExtensionFiles.removeTree(pending.path)
        Log.shared.info("backup", "restored", ["undo": undo.lastPathComponent])
        return .restored(plan)
    }

    /// Moves the data items out of `home` into `aside`, then the ones found in `sources` (first found wins) into
    /// `home`. On any failure what moved is put back.
    private func swap(out home: URL, aside: URL, in sources: [URL]) throws {
        let fm = FileManager.default
        var movedOut: [String] = [], movedIn: [String] = []
        do {
            for name in Self.items where ExtensionFS.lstat(home.appendingPathComponent(name).path) != nil {
                try fm.moveItem(at: home.appendingPathComponent(name), to: aside.appendingPathComponent(name))
                movedOut.append(name)
            }
            for name in Self.items {
                guard let source = sources.map({ $0.appendingPathComponent(name) }).first(where: { ExtensionFS.lstat($0.path) != nil }) else { continue }
                try fm.moveItem(at: source, to: home.appendingPathComponent(name))
                movedIn.append(name)
            }
        } catch {
            for name in movedIn { ExtensionFiles.removeTree(home.appendingPathComponent(name).path) }
            for name in movedOut { try? fm.moveItem(at: aside.appendingPathComponent(name), to: home.appendingPathComponent(name)) }
            throw error
        }
    }

    // MARK: Undo

    /// The latest restore that can still be undone, and its plan.
    public var undoable: (folder: URL, plan: Plan)? {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []).filter { $0.hasPrefix(Self.undoPrefix) }.sorted()
        for name in names.reversed() {
            let folder = url(name)
            if let data = FileManager.default.contents(atPath: folder.appendingPathComponent(Self.planFile).path),
               let plan = try? BackupManifest.decoder.decode(Plan.self, from: data) {
                return (folder, plan)
            }
        }
        return nil
    }

    /// Asks the next launch to put the data from before the restore back.
    public func requestUndo() throws {
        guard undoable != nil else { throw UserFacingError("There's no restore to undo any more.") }
        try Data().write(to: url(Self.undoRequest))
    }

    private func undo(secrets: (any SecretStore)?, defaults: UserDefaults?) -> Plan? {
        guard let (folder, plan) = undoable else { return nil }
        let discard = url(".restore-discard-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: discard, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try swap(out: home, aside: discard, in: [folder])
        } catch {
            Log.shared.error("backup", "undo failed; data left as it was", ["error": String(describing: error)])
            ExtensionFiles.removeTree(discard.path)
            return nil
        }
        ExtensionFiles.removeTree(discard.path)
        if let secrets { BackupKeys.putBack(from: folder.appendingPathComponent(Self.keysBefore), to: secrets) }
        if let defaults, let data = FileManager.default.contents(atPath: folder.appendingPathComponent(BackupPreferences.before).path),
           let replaced = try? BackupManifest.decoder.decode([String: JSONValue?].self, from: data) {
            BackupPreferences.putBack(replaced, to: defaults)
        }
        ExtensionFiles.removeTree(folder.path)
        try? FileManager.default.removeItem(at: url(Self.followUp))
        Log.shared.info("backup", "restore undone")
        return plan
    }

    /// Undo copies older than `keepUndo` go, with what was left to review from that restore and the keys it replaced.
    func expire(now: Date, secrets: (any SecretStore)? = nil) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [] where name.hasPrefix(Self.undoPrefix) {
            let folder = url(name)
            let when = (try? FileManager.default.attributesOfItem(atPath: folder.path)[.creationDate] as? Date) ?? now
            guard now.timeIntervalSince(when) > Self.keepUndo else { continue }
            if let secrets { BackupKeys.forget(folder.appendingPathComponent(Self.keysBefore), store: secrets) }
            ExtensionFiles.removeTree(folder.path)
            if undoable == nil { ExtensionFiles.removeTree(url(Self.reviewFolder).path) }
        }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}
