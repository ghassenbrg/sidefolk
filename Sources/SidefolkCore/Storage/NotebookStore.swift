import Foundation
import GRDB

extension JSONValue: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { jsonString.databaseValue }
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> JSONValue? {
        String.fromDatabaseValue(dbValue).flatMap { try? JSONValue.parse($0) }
    }
}

/// Collections (projects, topics, lists, the Inbox) and the notes, ideas, tasks and links in them.
public struct NotebookStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public static let inboxName = "Inbox"

    // MARK: Collections

    @discardableResult
    public func inbox(now: Date = Date()) async throws -> NotebookCollection {
        try await db.writer.write { db in
            if let existing = try NotebookCollection.filter(Column("kind") == NotebookCollection.Kind.inbox.rawValue).fetchOne(db) {
                return existing
            }
            let inbox = NotebookCollection(name: Self.inboxName, kind: .inbox, emoji: "📥", now: now)
            try inbox.insert(db)
            return inbox
        }
    }

    public func collections(includeArchived: Bool = false) async throws -> [NotebookCollection] {
        try await db.writer.read { db in
            var request = NotebookCollection.order(sql: "CASE kind WHEN 'inbox' THEN 0 ELSE 1 END, name COLLATE NOCASE")
            if !includeArchived { request = request.filter(Column("archived_at") == nil) }
            return try request.fetchAll(db)
        }
    }

    public func collection(id: String) async throws -> NotebookCollection? {
        try await db.writer.read { db in try NotebookCollection.fetchOne(db, key: id) }
    }

    /// Finds a collection by name: exact (case-insensitive), then prefix, then containment.
    public func findCollection(named name: String) async throws -> NotebookCollection? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        let all = try await collections(includeArchived: false)
        if let exact = all.first(where: { $0.name.lowercased() == wanted }) { return exact }
        if let prefix = all.first(where: { $0.name.lowercased().hasPrefix(wanted) }) { return prefix }
        return all.first(where: { $0.name.lowercased().contains(wanted) || wanted.contains($0.name.lowercased()) })
    }

    /// Returns the named collection, creating it when it does not exist.
    public func collection(named name: String, kind: NotebookCollection.Kind = .project, now: Date = Date()) async throws -> (NotebookCollection, created: Bool) {
        if let found = try await findCollection(named: name) { return (found, false) }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).clipped(60)
        let created = NotebookCollection(name: clean, kind: kind, now: now)
        try await db.writer.write { db in try created.insert(db) }
        return (created, true)
    }

    public func rename(collectionId: String, to name: String, now: Date = Date()) async throws {
        try await db.writer.write { db in
            guard var c = try NotebookCollection.fetchOne(db, key: collectionId) else { return }
            c.name = name.clipped(60)
            c.updatedAt = now
            try c.update(db)
        }
    }

    public func setArchived(collectionId: String, _ archived: Bool, now: Date = Date()) async throws {
        try await db.writer.write { db in
            guard var c = try NotebookCollection.fetchOne(db, key: collectionId), c.kind != .inbox else { return }
            c.archivedAt = archived ? now : nil
            c.updatedAt = now
            try c.update(db)
        }
    }

    public func deleteCollection(id: String) async throws {
        _ = try await db.writer.write { db in
            try NotebookCollection.filter(key: id).filter(Column("kind") != "inbox").deleteAll(db)
        }
    }

    // MARK: Items

    public func add(_ item: NotebookItem) async throws {
        try await db.writer.write { db in try item.insert(db) }
    }

    public func update(_ item: NotebookItem) async throws {
        try await db.writer.write { db in try item.update(db) }
    }

    public func item(id: String) async throws -> NotebookItem? {
        try await db.writer.read { db in try NotebookItem.fetchOne(db, key: id) }
    }

    public func items(
        collectionId: String? = nil, kinds: [NotebookItem.Kind]? = nil, status: NotebookItem.Status? = nil,
        includeDeleted: Bool = false, limit: Int = 200
    ) async throws -> [NotebookItem] {
        try await db.writer.read { db in
            var r = NotebookItem.all()
            if let collectionId { r = r.filter(Column("collection_id") == collectionId) }
            if let kinds { r = r.filter(kinds.map(\.rawValue).contains(Column("kind"))) }
            if let status { r = r.filter(Column("status") == status.rawValue) }
            if !includeDeleted { r = r.filter(Column("deleted_at") == nil) }
            return try r.order(Column("created_at").desc).limit(limit).fetchAll(db)
        }
    }

    public func deletedItems(limit: Int = 200) async throws -> [NotebookItem] {
        try await db.writer.read { db in
            try NotebookItem.filter(Column("deleted_at") != nil).order(Column("deleted_at").desc).limit(limit).fetchAll(db)
        }
    }

    public func setStatus(itemId: String, _ status: NotebookItem.Status, now: Date = Date()) async throws -> NotebookItem? {
        try await db.writer.write { db in
            guard var item = try NotebookItem.fetchOne(db, key: itemId) else { return nil }
            item.status = status
            item.updatedAt = now
            try item.update(db)
            return item
        }
    }

    /// Moves an item to the Trash (kept 30 days, restorable).
    public func trash(itemId: String, now: Date = Date()) async throws -> NotebookItem? {
        try await db.writer.write { db in
            guard var item = try NotebookItem.fetchOne(db, key: itemId) else { return nil }
            item.deletedAt = now
            item.updatedAt = now
            try item.update(db)
            return item
        }
    }

    public func restore(itemId: String, now: Date = Date()) async throws {
        try await db.writer.write { db in
            guard var item = try NotebookItem.fetchOne(db, key: itemId) else { return }
            item.deletedAt = nil
            item.updatedAt = now
            try item.update(db)
        }
    }

    /// Permanently removes an item. Only the user can do this, from the Trash.
    public func purge(itemId: String) async throws {
        _ = try await db.writer.write { db in try NotebookItem.deleteOne(db, key: itemId) }
    }

    public func purgeTrash(olderThan cutoff: Date) async throws -> Int {
        try await db.writer.write { db in
            try NotebookItem.filter(Column("deleted_at") != nil && Column("deleted_at") < cutoff.timeIntervalSince1970).deleteAll(db)
        }
    }

    /// Full-text search over title, body and tags, best matches first; falls back to substring match.
    public func search(_ query: String, collectionId: String? = nil, kinds: [NotebookItem.Kind]? = nil, limit: Int = 20) async throws -> [NotebookItem] {
        let pattern = FTSQuery.pattern(for: query)
        return try await db.writer.read { db in
            var results: [NotebookItem] = []
            if let pattern {
                var sql = """
                    SELECT items.* FROM items JOIN items_fts ON items_fts.rowid = items.rowid
                    WHERE items_fts MATCH ? AND items.deleted_at IS NULL
                    """
                var args: [any DatabaseValueConvertible] = [pattern]
                if let collectionId { sql += " AND items.collection_id = ?"; args.append(collectionId) }
                if let kinds, !kinds.isEmpty {
                    sql += " AND items.kind IN (\(kinds.map { _ in "?" }.joined(separator: ",")))"
                    args.append(contentsOf: kinds.map(\.rawValue))
                }
                sql += " ORDER BY bm25(items_fts, 5.0, 1.0, 2.0) LIMIT ?"
                args.append(limit)
                results = try NotebookItem.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            }
            if results.isEmpty {
                let like = "%\(query.trimmingCharacters(in: .whitespacesAndNewlines))%"
                var r = NotebookItem.filter(Column("deleted_at") == nil)
                    .filter(Column("title").like(like) || Column("body").like(like) || Column("tags").like(like))
                if let collectionId { r = r.filter(Column("collection_id") == collectionId) }
                if let kinds { r = r.filter(kinds.map(\.rawValue).contains(Column("kind"))) }
                results = try r.order(Column("updated_at").desc).limit(limit).fetchAll(db)
            }
            return results
        }
    }

    public func counts() async throws -> (collections: Int, items: Int, trashed: Int) {
        try await db.writer.read { db in
            (try NotebookCollection.fetchCount(db),
             try NotebookItem.filter(Column("deleted_at") == nil).fetchCount(db),
             try NotebookItem.filter(Column("deleted_at") != nil).fetchCount(db))
        }
    }
}

/// Builds safe FTS5 match patterns from free text.
enum FTSQuery {
    static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "i", "in", "is", "it", "my", "of", "on",
        "or", "that", "the", "this", "to", "was", "what", "with", "did", "do", "me", "about", "all", "any", "saved",
    ]

    /// `"word"*` terms joined with OR so partial matches still rank; nil when nothing searchable remains.
    static func pattern(for text: String) -> String? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopwords.contains($0) }
        guard !words.isEmpty else { return nil }
        return Array(Set(words)).sorted().prefix(12).map { "\"\($0)\"*" }.joined(separator: " OR ")
    }
}
