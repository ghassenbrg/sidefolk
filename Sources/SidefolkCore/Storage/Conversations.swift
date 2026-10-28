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

extension ExchangeStore {
    /// Conversations, most recently active first. With `query`, only those where every word appears in a request
    /// or a reply (as typed: `%` and `_` are literal).
    public func conversations(matching query: String = "", limit: Int = 200) async throws -> [ConversationSummary] {
        let words = query.prefix(NotebookStore.maxQueryLength).split(whereSeparator: \.isWhitespace).prefix(8)
        return try await db.writer.read { db in
            var sql = """
                SELECT e.thread_id AS id, MIN(e.created_at) AS started, MAX(e.created_at) AS updated,
                       SUM(e.role = 'user') AS requests,
                       MAX(e.role = 'user' AND json_extract(e.meta, '$.spoken') = 1) AS spoken,
                       (SELECT f.content FROM exchanges f WHERE f.thread_id = e.thread_id AND f.role = 'user'
                        ORDER BY f.created_at, f.id LIMIT 1) AS title
                FROM exchanges e
                """
            var args: [any DatabaseValueConvertible] = []
            if !words.isEmpty {
                sql += " WHERE " + words.map { _ in
                    #"e.thread_id IN (SELECT thread_id FROM exchanges WHERE role IN ('user', 'assistant') AND content LIKE ? ESCAPE '\')"#
                }.joined(separator: " AND ")
                args += words.map { "%" + NotebookStore.escapeLike(String($0)) + "%" }
            }
            sql += " GROUP BY e.thread_id ORDER BY updated DESC LIMIT ?"
            args.append(limit)
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).compactMap { row in
                // A thread whose request is gone (a failure note only) has nothing to call it by.
                guard let title: String = row["title"] else { return nil }
                return ConversationSummary(id: row["id"], title: title,
                                           startedAt: Date(timeIntervalSince1970: row["started"]),
                                           updatedAt: Date(timeIntervalSince1970: row["updated"]),
                                           requests: row["requests"], spoken: (row["spoken"] as Int?) == 1)
            }
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
