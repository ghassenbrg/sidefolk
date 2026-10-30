import Foundation
import GRDB

/// One conversation with Sidefolk's AI, as Home › Conversations lists it (D45): the exchanges of one thread.
public struct ConversationSummary: Sendable, Hashable, Identifiable {
    /// The thread's id.
    public var id: String
    /// The person's first request, as typed or said.
    public var title: String
    public var startedAt: Date
    public var updatedAt: Date
    /// How many requests were made in it.
    public var requests: Int
    /// Some of it was said with the talk key.
    public var spoken: Bool

    public init(id: String, title: String, startedAt: Date, updatedAt: Date, requests: Int, spoken: Bool) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.requests = requests
        self.spoken = spoken
    }
}

/// The conversations a notebook item was made in and later changed in (D58), as its Connected list shows them.
public struct ItemConversations: Sendable, Equatable {
    /// Where Sidefolk's agent saved it, while that conversation is kept.
    public var madeIn: ConversationSummary?
    /// Where it was changed or moved to the Trash afterwards, most recent first, without the one it was made in.
    public var changedIn: [ConversationSummary]

    public init(madeIn: ConversationSummary? = nil, changedIn: [ConversationSummary] = []) {
        self.madeIn = madeIn
        self.changedIn = changedIn
    }
}

extension ExchangeStore {
    /// Conversations, most recently active first. With `query`, only those where every word appears in a request
    /// or a reply (as typed: `%` and `_` are literal).
    public func conversations(matching query: String = "", limit: Int = 200) async throws -> [ConversationSummary] {
        let words = query.prefix(NotebookStore.maxQueryLength).split(whereSeparator: \.isWhitespace).prefix(8)
        return try await db.writer.read { db in
            var filters: [String] = []
            var args: [any DatabaseValueConvertible] = []
            if !words.isEmpty {
                filters += words.map { _ in
                    #"e.thread_id IN (SELECT thread_id FROM exchanges WHERE role IN ('user', 'assistant') AND content LIKE ? ESCAPE '\')"#
                }
                args += words.map { "%" + NotebookStore.escapeLike(String($0)) + "%" }
            }
            return try Self.summaries(db, filters: filters, arguments: args, limit: limit)
        }
    }

    /// The kept conversation each of these runs was part of, by run id. A run whose conversation was deleted, or
    /// that had none (another agent's call), has no entry. Replies carry their run's id (`ExchangeMeta.assistant`).
    public func conversations(ofRuns runIds: [String]) async throws -> [String: ConversationSummary] {
        let runIds = Array(Set(runIds))
        guard !runIds.isEmpty else { return [:] }
        return try await db.writer.read { db in try Self.conversations(db, ofRuns: runIds) }
    }

    /// Where `item` was made and later changed: its own run, then the Activity rows of `notes.update` and
    /// `notes.trash` that name it and ran. Reading or searching notes doesn't count; those touch many notes at once.
    public func conversations(about item: NotebookItem) async throws -> ItemConversations {
        try await db.writer.read { db in
            let changes = try String.fetchAll(db, sql: """
                SELECT run_id FROM activity
                WHERE run_id IS NOT NULL AND tool IN ('notes.update', 'notes.trash') AND json_extract(args, '$.id') = ?
                  AND error IS NULL AND decision NOT IN ('denied', 'blocked', 'failed', 'skipped')
                ORDER BY at DESC, id DESC
                """, arguments: [item.id])
            let found = try Self.conversations(db, ofRuns: Array(Set(changes + [item.runId].compactMap { $0 })))
            let madeIn = item.runId.flatMap { found[$0] }
            var seen = Set([madeIn?.id].compactMap { $0 })
            let changedIn = changes.compactMap { found[$0] }.filter { seen.insert($0.id).inserted }
            return ItemConversations(madeIn: madeIn, changedIn: changedIn)
        }
    }

    private static func conversations(_ db: Database, ofRuns runIds: [String]) throws -> [String: ConversationSummary] {
        guard !runIds.isEmpty else { return [:] }
        let marks = Array(repeating: "?", count: runIds.count).joined(separator: ", ")
        let threads = try Row.fetchAll(db, sql: """
            SELECT DISTINCT json_extract(meta, '$.runId') AS run, thread_id FROM exchanges
            WHERE json_extract(meta, '$.runId') IN (\(marks))
            """, arguments: StatementArguments(runIds))
        let threadOfRun = Dictionary(threads.map { ($0["run"] as String, $0["thread_id"] as String) }, uniquingKeysWith: { a, _ in a })
        let threadIds = Array(Set(threadOfRun.values))
        guard !threadIds.isEmpty else { return [:] }
        let summaries = try summaries(db, filters: ["e.thread_id IN (\(Array(repeating: "?", count: threadIds.count).joined(separator: ", ")))"],
                                      arguments: threadIds, limit: threadIds.count)
        let byThread = Dictionary(summaries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return threadOfRun.compactMapValues { byThread[$0] }
    }

    /// One summary per thread matching every filter, most recently active first.
    private static func summaries(_ db: Database, filters: [String], arguments: [any DatabaseValueConvertible],
                                  limit: Int) throws -> [ConversationSummary] {
        var sql = """
            SELECT e.thread_id AS id, MIN(e.created_at) AS started, MAX(e.created_at) AS updated,
                   SUM(e.role = 'user') AS requests,
                   MAX(e.role = 'user' AND json_extract(e.meta, '$.spoken') = 1) AS spoken,
                   (SELECT f.content FROM exchanges f WHERE f.thread_id = e.thread_id AND f.role = 'user'
                    ORDER BY f.created_at, f.id LIMIT 1) AS title
            FROM exchanges e
            """
        if !filters.isEmpty { sql += " WHERE " + filters.joined(separator: " AND ") }
        sql += " GROUP BY e.thread_id ORDER BY updated DESC LIMIT ?"
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments + [limit])).compactMap { row in
            // A thread whose request is gone (a failure note only) has nothing to call it by.
            guard let title: String = row["title"] else { return nil }
            return ConversationSummary(id: row["id"], title: title,
                                       startedAt: Date(timeIntervalSince1970: row["started"]),
                                       updatedAt: Date(timeIntervalSince1970: row["updated"]),
                                       requests: row["requests"], spoken: (row["spoken"] as Int?) == 1)
        }
    }

    /// Every exchange of one conversation, oldest first (the newest `limit` of a very long one).
    public func conversation(_ threadId: String, limit: Int = 400) async throws -> [Exchange] {
        try await recent(threadId: threadId, limit: limit)
    }

    /// Whether anything of the thread is still kept (history is deleted after `historyDays`, or by the person).
    public func contains(threadId: String) async throws -> Bool {
        try await db.writer.read { db in try Exchange.filter(Column("thread_id") == threadId).fetchCount(db) > 0 }
    }

    @discardableResult
    public func delete(threadId: String) async throws -> Int {
        try await db.writer.write { db in try Exchange.filter(Column("thread_id") == threadId).deleteAll(db) }
    }
}

extension ActivityStore {
    /// The tool steps of these runs, oldest first: what a conversation did between a request and its reply.
    public func steps(ofRuns runIds: [String]) async throws -> [ActivityEntry] {
        guard !runIds.isEmpty else { return [] }
        return try await db.writer.read { db in
            try ActivityEntry.filter(runIds.contains(Column("run_id"))).order(Column("at"), Column("id")).fetchAll(db)
        }
    }
}
