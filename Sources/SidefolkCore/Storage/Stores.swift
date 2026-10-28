import Foundation
import GRDB

public struct SessionStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func save(_ s: AgentSession) async throws { try await db.writer.write { db in try s.save(db) } }
    public func session(id: String) async throws -> AgentSession? { try await db.writer.read { db in try AgentSession.fetchOne(db, key: id) } }

    /// Sessions that have not ended, most recently active first.
    public func live() async throws -> [AgentSession] {
        try await db.writer.read { db in
            try AgentSession.filter(Column("ended_at") == nil).order(Column("updated_at").desc).fetchAll(db)
        }
    }

    public func recent(limit: Int = 50) async throws -> [AgentSession] {
        try await db.writer.read { db in try AgentSession.order(Column("updated_at").desc).limit(limit).fetchAll(db) }
    }

    public func purge(olderThan cutoff: Date) async throws -> Int {
        try await db.writer.write { db in try AgentSession.filter(Column("updated_at") < cutoff.timeIntervalSince1970).deleteAll(db) }
    }
}

public struct JobStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func save(_ j: Job) async throws { try await db.writer.write { db in try j.save(db) } }
    public func job(id: String) async throws -> Job? { try await db.writer.read { db in try Job.fetchOne(db, key: id) } }
    public func running() async throws -> [Job] {
        try await db.writer.read { db in try Job.filter(Column("state") == "running").order(Column("started_at").desc).fetchAll(db) }
    }
    public func recent(limit: Int = 50) async throws -> [Job] {
        try await db.writer.read { db in try Job.order(Column("started_at").desc).limit(limit).fetchAll(db) }
    }

    /// Finished jobs started before `cutoff`. Each keeps a command line and its last stderr lines, so they
    /// don't stay forever; a job still running is kept whatever its age.
    public func purge(olderThan cutoff: Date) async throws -> Int {
        try await db.writer.write { db in
            try Job.filter(Column("state") != "running" && Column("started_at") < cutoff.timeIntervalSince1970).deleteAll(db)
        }
    }
}

/// The audit trail of every tool execution and permission decision.
public struct ActivityStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    @discardableResult
    public func log(_ entry: ActivityEntry) async throws -> ActivityEntry {
        try await db.writer.write { db in try entry.inserted(db) }
    }

    public func recent(limit: Int = 200, tool: String? = nil) async throws -> [ActivityEntry] {
        try await db.writer.read { db in
            var r = ActivityEntry.order(Column("at").desc, Column("id").desc)
            if let tool { r = r.filter(Column("tool") == tool) }
            return try r.limit(limit).fetchAll(db)
        }
    }

    public func purge(olderThan cutoff: Date) async throws -> Int {
        try await db.writer.write { db in try ActivityEntry.filter(Column("at") < cutoff.timeIntervalSince1970).deleteAll(db) }
    }

    public func count() async throws -> Int { try await db.writer.read { db in try ActivityEntry.fetchCount(db) } }
}

/// Short-term conversation history (kept for a limited time).
public struct ExchangeStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func append(_ e: Exchange) async throws { try await db.writer.write { db in try e.insert(db) } }

    /// The latest `limit` exchanges of a thread, oldest first.
    public func recent(threadId: String, limit: Int = 20) async throws -> [Exchange] {
        try await db.writer.read { db in
            try Exchange.filter(Column("thread_id") == threadId).order(Column("created_at").desc, Column("id").desc)
                .limit(limit).fetchAll(db).reversed()
        }
    }

    public func latest(limit: Int = 50) async throws -> [Exchange] {
        try await db.writer.read { db in
            try Exchange.order(Column("created_at").desc).limit(limit).fetchAll(db).reversed()
        }
    }

    public func purge(olderThan cutoff: Date) async throws -> Int {
        try await db.writer.write { db in try Exchange.filter(Column("created_at") < cutoff.timeIntervalSince1970).deleteAll(db) }
    }

    public func deleteAll() async throws { _ = try await db.writer.write { db in try Exchange.deleteAll(db) } }
    public func count() async throws -> Int { try await db.writer.read { db in try Exchange.fetchCount(db) } }
}

public struct ReminderStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func save(_ r: Reminder) async throws { try await db.writer.write { db in try r.save(db) } }
    public func reminder(id: String) async throws -> Reminder? { try await db.writer.read { db in try Reminder.fetchOne(db, key: id) } }
    public func delete(id: String) async throws { _ = try await db.writer.write { db in try Reminder.deleteOne(db, key: id) } }

    /// Scheduled and snoozed reminders, soonest first.
    public func pending() async throws -> [Reminder] {
        try await db.writer.read { db in
            try Reminder.filter(["scheduled", "snoozed"].contains(Column("state"))).fetchAll(db)
                .sorted { ($0.nextDue ?? .distantFuture) < ($1.nextDue ?? .distantFuture) }
        }
    }

    public func all(limit: Int = 500) async throws -> [Reminder] {
        try await db.writer.read { db in try Reminder.order(Column("fire_at").desc).limit(limit).fetchAll(db) }
    }

    public func recentlyFinished(limit: Int = 50) async throws -> [Reminder] {
        try await db.writer.read { db in
            try Reminder.filter(["fired", "done", "cancelled"].contains(Column("state")))
                .order(Column("updated_at").desc).limit(limit).fetchAll(db)
        }
    }

    /// The soonest waiting reminder of each notebook item that has one (D49); `itemIds` nil means every item.
    public func next(forItems itemIds: [String]? = nil) async throws -> [String: Reminder] {
        let waiting = try await db.writer.read { db in
            var request = Reminder.filter(["scheduled", "snoozed"].contains(Column("state"))).filter(Column("item_id") != nil)
            if let itemIds { request = request.filter(itemIds.contains(Column("item_id"))) }
            return try request.fetchAll(db)
        }
        var soonest: [String: Reminder] = [:]
        for r in waiting {
            guard let item = r.itemId, let due = r.nextDue else { continue }
            if soonest[item].flatMap(\.nextDue).map({ due < $0 }) ?? true { soonest[item] = r }
        }
        return soonest
    }
}

public struct WatcherStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func save(_ w: Watcher) async throws { try await db.writer.write { db in try w.save(db) } }
    public func watcher(id: String) async throws -> Watcher? { try await db.writer.read { db in try Watcher.fetchOne(db, key: id) } }
    public func delete(id: String) async throws { _ = try await db.writer.write { db in try Watcher.deleteOne(db, key: id) } }

    public func active() async throws -> [Watcher] {
        try await db.writer.read { db in try Watcher.filter(Column("state") == "active").fetchAll(db) }
    }

    public func all(limit: Int = 500) async throws -> [Watcher] {
        try await db.writer.read { db in try Watcher.order(Column("created_at").desc).limit(limit).fetchAll(db) }
    }
}

public struct AttentionStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func save(_ a: AttentionItem) async throws { try await db.writer.write { db in try a.save(db) } }
    public func item(id: String) async throws -> AttentionItem? { try await db.writer.read { db in try AttentionItem.fetchOne(db, key: id) } }

    public func open() async throws -> [AttentionItem] {
        try await db.writer.read { db in
            try AttentionItem.filter(["pending", "shown"].contains(Column("state"))).order(Column("created_at")).fetchAll(db)
        }
    }

    public func recent(limit: Int = 100) async throws -> [AttentionItem] {
        try await db.writer.read { db in try AttentionItem.order(Column("created_at").desc).limit(limit).fetchAll(db) }
    }

    public func purge(olderThan cutoff: Date) async throws -> Int {
        try await db.writer.write { db in
            try AttentionItem.filter(["acknowledged", "expired"].contains(Column("state")) && Column("created_at") < cutoff.timeIntervalSince1970).deleteAll(db)
        }
    }
}

public struct AgentRunStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func save(_ r: AgentRun) async throws { try await db.writer.write { db in try r.save(db) } }
    public func purge(olderThan cutoff: Date) async throws -> Int {
        try await db.writer.write { db in try AgentRun.filter(Column("started_at") < cutoff.timeIntervalSince1970).deleteAll(db) }
    }
    public func recent(limit: Int = 100) async throws -> [AgentRun] {
        try await db.writer.read { db in try AgentRun.order(Column("started_at").desc).limit(limit).fetchAll(db) }
    }
    public func totals(since: Date) async throws -> (runs: Int, input: Int, output: Int) {
        try await db.writer.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS n, COALESCE(SUM(input_tokens),0) AS i, COALESCE(SUM(output_tokens),0) AS o
                FROM agent_runs WHERE started_at >= ?
                """, arguments: [since.timeIntervalSince1970])
            return (row?["n"] ?? 0, row?["i"] ?? 0, row?["o"] ?? 0)
        }
    }
}

public struct ExtensionStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func save(_ r: ExtensionRecord) async throws { try await db.writer.write { db in try r.save(db) } }
    public func all() async throws -> [ExtensionRecord] { try await db.writer.read { db in try ExtensionRecord.order(Column("id")).fetchAll(db) } }
    public func record(id: String) async throws -> ExtensionRecord? { try await db.writer.read { db in try ExtensionRecord.fetchOne(db, key: id) } }
    public func delete(id: String) async throws { _ = try await db.writer.write { db in try ExtensionRecord.deleteOne(db, key: id) } }
}

/// Small typed settings that belong with the data (not UI preferences).
public struct KVStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func get<T: Decodable>(_ key: String, as type: T.Type) async throws -> T? {
        let value = try await db.writer.read { db in try KeyValue.fetchOne(db, key: key) }
        return try value?.value.decode(T.self)
    }

    public func set<T: Encodable>(_ key: String, _ value: T) async throws {
        let json = try JSONValue.from(value)
        try await db.writer.write { db in try KeyValue(key: key, value: json).save(db) }
    }

    public func remove(_ key: String) async throws {
        _ = try await db.writer.write { db in try KeyValue.deleteOne(db, key: key) }
    }
}
