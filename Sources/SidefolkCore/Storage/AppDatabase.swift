import Foundation
import GRDB

/// Owns the SQLite database (WAL, one writer, concurrent readers) and its schema.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The database file Sidefolk uses, created with owner-only permissions.
    public static func open(at url: URL) throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.label = "sidefolk"
        let pool = try DatabasePool(path: url.path, configuration: config)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return try AppDatabase(pool)
    }

    /// In-memory database for tests.
    public static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabaseQueue(configuration: config))
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "collections") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("emoji", .text)
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
                t.column("archived_at", .double)
            }
            try db.create(index: "collections_name", on: "collections", columns: ["name"])

            try db.create(table: "items") { t in
                t.primaryKey("id", .text)
                t.column("collection_id", .text).notNull().references("collections", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text).notNull().defaults(to: "")
                t.column("url", .text)
                t.column("tags", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull().defaults(to: "open")
                t.column("due_at", .double)
                t.column("source", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
                t.column("deleted_at", .double)
            }
            try db.create(index: "items_collection", on: "items", columns: ["collection_id", "deleted_at"])
            try db.create(virtualTable: "items_fts", using: FTS5()) { t in
                t.synchronize(withTable: "items")
                t.tokenizer = .porter(wrapping: .unicode61())
                t.column("title")
                t.column("body")
                t.column("tags")
            }

            try db.create(table: "sessions") { t in
                t.primaryKey("id", .text)
                t.column("agent", .text).notNull()
                t.column("cwd", .text)
                t.column("title", .text)
                t.column("state", .text).notNull()
                t.column("detail", .text)
                t.column("host_app", .text)
                t.column("host_pid", .integer)
                t.column("tty", .text)
                t.column("started_at", .double).notNull()
                t.column("updated_at", .double).notNull()
                t.column("ended_at", .double)
            }

            try db.create(table: "jobs") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("command", .text)
                t.column("cwd", .text)
                t.column("pid", .integer)
                t.column("state", .text).notNull()
                t.column("exit_code", .integer)
                t.column("output_tail", .text)
                t.column("level", .text).notNull()
                t.column("source", .text).notNull()
                t.column("started_at", .double).notNull()
                t.column("ended_at", .double)
            }

            try db.create(table: "reminders") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("notes", .text)
                t.column("fire_at", .double).notNull()
                t.column("timezone", .text).notNull()
                t.column("recurrence", .text)
                t.column("state", .text).notNull()
                t.column("snoozed_until", .double)
                t.column("last_fired_at", .double)
                t.column("fired_count", .integer).notNull().defaults(to: 0)
                t.column("level", .text).notNull()
                t.column("action", .text)
                t.column("item_id", .text).references("items", onDelete: .setNull)
                t.column("source", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
            }
            try db.create(index: "reminders_due", on: "reminders", columns: ["state", "fire_at"])

            try db.create(table: "watchers") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("config", .text).notNull()
                t.column("condition", .text).notNull()
                t.column("interval_s", .double).notNull()
                t.column("state", .text).notNull()
                t.column("mode", .text).notNull()
                t.column("level", .text).notNull()
                t.column("last_checked_at", .double)
                t.column("next_check_at", .double)
                t.column("last_state", .text)
                t.column("last_error", .text)
                t.column("error_count", .integer).notNull().defaults(to: 0)
                t.column("fire_count", .integer).notNull().defaults(to: 0)
                t.column("expires_at", .double)
                t.column("source", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
            }

            try db.create(table: "exchanges") { t in
                t.primaryKey("id", .text)
                t.column("thread_id", .text).notNull()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("meta", .text)
                t.column("created_at", .double).notNull()
            }
            try db.create(index: "exchanges_thread", on: "exchanges", columns: ["thread_id", "created_at"])

            try db.create(table: "activity") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("at", .double).notNull()
                t.column("caller", .text).notNull()
                t.column("tool", .text).notNull()
                t.column("risk", .text).notNull()
                t.column("decision", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("args", .text)
                t.column("outcome", .text)
                t.column("error", .text)
                t.column("run_id", .text)
            }
            try db.create(index: "activity_at", on: "activity", columns: ["at"])

            try db.create(table: "grants") { t in
                t.primaryKey("id", .text)
                t.column("tool", .text).notNull()
                t.column("scope", .text).notNull()
                t.column("caller_kind", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("last_used_at", .double)
            }

            try db.create(table: "folders") { t in
                t.primaryKey("path", .text)
                t.column("access", .text).notNull()
                t.column("created_at", .double).notNull()
            }

            try db.create(table: "extensions") { t in
                t.primaryKey("id", .text)
                t.column("version", .text).notNull()
                t.column("path", .text).notNull()
                t.column("enabled", .boolean).notNull()
                t.column("kind", .text).notNull()
                t.column("granted", .text)
                t.column("manifest_hash", .text)
                t.column("installed_at", .double).notNull()
                t.column("last_error", .text)
            }

            try db.create(table: "agent_runs") { t in
                t.primaryKey("id", .text)
                t.column("thread_id", .text).notNull()
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("started_at", .double).notNull()
                t.column("ended_at", .double)
                t.column("steps", .integer).notNull().defaults(to: 0)
                t.column("input_tokens", .integer).notNull().defaults(to: 0)
                t.column("output_tokens", .integer).notNull().defaults(to: 0)
                t.column("outcome", .text)
                t.column("error", .text)
            }

            try db.create(table: "attention") { t in
                t.primaryKey("id", .text)
                t.column("level", .text).notNull()
                t.column("source", .text).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text)
                t.column("actions", .text).notNull()
                t.column("ref_kind", .text)
                t.column("ref_id", .text)
                t.column("state", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("shown_at", .double)
                t.column("acknowledged_at", .double)
                t.column("renudged", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "attention_state", on: "attention", columns: ["state", "created_at"])

            try db.create(table: "kv") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        return m
    }
}
