import Foundation
import GRDB

/// Exports everything Sidefolk keeps as one readable JSON file, and deletes it all on request.
public struct DataPorter: Sendable {
    public let runtime: SidefolkRuntime
    public init(runtime: SidefolkRuntime) { self.runtime = runtime }

    /// Writes notebook, reminders, watchers, history, activity and settings to `url` (0600).
    public func export(to url: URL) async throws {
        let db = runtime.db
        let payload: JSONValue = try await db.writer.read { db in
            func all<T: SidefolkRecord>(_ type: T.Type) throws -> JSONValue { try JSONValue.from(T.fetchAll(db)) }
            return [
                "exportedAt": .string(ISO8601DateFormatter().string(from: Date())),
                "app": .string("Sidefolk \(SidefolkVersion.current)"),
                "collections": try all(NotebookCollection.self),
                "items": try all(NotebookItem.self),
                "reminders": try all(Reminder.self),
                "watchers": try all(Watcher.self),
                "exchanges": try all(Exchange.self),
                "activity": try JSONValue.from(ActivityEntry.order(Column("at").desc).limit(5000).fetchAll(db)),
                "sessions": try all(AgentSession.self),
                "jobs": try all(Job.self),
                "grants": try all(Grant.self),
                "folders": try all(GrantedFolder.self),
                "extensions": try all(ExtensionRecord.self),
            ]
        }
        var object = payload.objectValue ?? [:]
        object["settings"] = try JSONValue.from(runtime.settings.current)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(JSONValue.object(object))
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw UserFacingError("I couldn't write the export there.", recovery: "Choose another folder.")
        }
    }

    /// What "Delete everything" removed, and what it couldn't.
    public struct DeletionReport: Sendable, Equatable {
        /// Every extension and MCP server whose record was removed (their Keychain items are "mcp.<id>").
        public var extensionIds: [String]
        /// Folders or Keychain items that are still there.
        public var leftovers: [String]
    }

    /// Removes every row Sidefolk stored and its folders (extensions, skills, logs, run state), and,
    /// given the Keychain, the provider keys with their host bindings and every MCP server's secrets.
    /// The extension list is read before its rows go, so their secrets can still be found. Installed
    /// extensions are read-only on disk, so their folders are unlocked first. Throws, after doing
    /// everything it can, when something is left behind; the app quits afterwards.
    @discardableResult
    public func deleteEverything(secrets: (any SecretStore)? = nil) async throws -> DeletionReport {
        let db = runtime.db
        let ids = try await runtime.extensionStore.all().map(\.id)
        var leftovers: [String] = []
        if let secrets {
            let keys = ProviderKeys(store: secrets)
            for account in SecretKey.providerKeys {
                do { try keys.remove(account: account) } catch { leftovers.append(String(localized: "Keychain item \(account)")) }
            }
            for id in ids {
                do { try secrets.delete(SecretKey.mcpServer(id)) } catch {
                    leftovers.append(String(localized: "Keychain item \(SecretKey.mcpServer(id))"))
                }
            }
        }
        try await db.writer.write { db in
            for table in ["items", "collections", "reminders", "watchers", "exchanges", "activity", "grants", "folders",
                          "extensions", "agent_runs", "attention", "sessions", "jobs", "kv"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
        let p = runtime.paths
        for dir in [p.extensions, p.extensionData, p.extensionDrafts, p.skills, p.brainWorkdir, p.run, p.home.appendingPathComponent("Sandbox"),
                    p.home.appendingPathComponent("snapshots"), p.home.appendingPathComponent("bin"), p.logs] {
            ExtensionFiles.removeTree(dir.path)
            if ExtensionFS.lstat(dir.path) != nil { leftovers.append(FolderAccess.displayPath(dir.path)) }
        }
        try await db.writer.vacuum()
        let report = DeletionReport(extensionIds: ids, leftovers: leftovers)
        guard leftovers.isEmpty else {
            throw UserFacingError("I deleted your data, but couldn't remove: \(Wording.list(leftovers)).",
                                  recovery: "Remove what's left in Finder (or Keychain Access), then quit Sidefolk.",
                                  changedNothing: false)
        }
        return report
    }

    /// Counts for the Privacy page.
    public func counts() async -> (notes: Int, reminders: Int, watchers: Int, activity: Int, exchanges: Int) {
        (try? await runtime.db.writer.read { db in
            (try NotebookItem.fetchCount(db), try Reminder.fetchCount(db), try Watcher.fetchCount(db),
             try ActivityEntry.fetchCount(db), try Exchange.fetchCount(db))
        }) ?? (0, 0, 0, 0, 0)
    }

    public var databaseBytes: Int64 {
        let p = runtime.paths.database.path
        return [p, p + "-wal", p + "-shm"].reduce(0) { sum, path in
            sum + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0)
        }
    }
}
