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

    /// Removes every row Sidefolk stored and its folders (extensions, skills, logs, run state).
    /// The app quits afterwards; secrets in the Keychain are removed by the caller.
    public func deleteEverything() async throws {
        let db = runtime.db
        try await db.writer.write { db in
            for table in ["items", "collections", "reminders", "watchers", "exchanges", "activity", "grants", "folders",
                          "extensions", "agent_runs", "attention", "sessions", "jobs", "kv"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
        let fm = FileManager.default
        let p = runtime.paths
        for dir in [p.extensions, p.extensionData, p.skills, p.brainWorkdir, p.home.appendingPathComponent("Sandbox"),
                    p.home.appendingPathComponent("snapshots"), p.logs] {
            try? fm.removeItem(at: dir)
        }
        try await db.writer.vacuum()
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
