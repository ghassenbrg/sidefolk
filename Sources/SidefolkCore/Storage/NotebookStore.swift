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
            let inbox = NotebookCollection(name: Self.inboxName, kind: .inbox, now: now)
            try inbox.insert(db)
            return inbox
        }
    }

    public func collections(includeArchived: Bool = false) async throws -> [NotebookCollection] {
        try await db.writer.read { db in
            var request = NotebookCollection.order(sql: "CASE kind WHEN 'inbox' THEN 0 ELSE 1 END, sort_order, name COLLATE NOCASE")
            if !includeArchived { request = request.filter(Column("archived_at") == nil) }
            return try request.fetchAll(db)
        }
    }

    public func collection(id: String) async throws -> NotebookCollection? {
        try await db.writer.read { db in try NotebookCollection.fetchOne(db, key: id) }
    }

    /// Finds a collection by name (see `match`).
    public func findCollection(named name: String) async throws -> NotebookCollection? {
        Self.match(name, in: try await collections(includeArchived: false))
    }

    /// The collection a typed name means: the exact name (ignoring case), or else the one collection
    /// whose name starts with it as whole words ("Reading" → "Reading list"). Never a longer word or
    /// a name merely containing it: "Work" isn't "Workout" and "Smart home" isn't "Art". Two
    /// candidates mean nothing is certain, so nil.
    static func match(_ name: String, in all: [NotebookCollection]) -> NotebookCollection? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        if let exact = all.first(where: { $0.name.lowercased() == wanted }) { return exact }
        let prefixed = all.filter { c in
            let n = c.name.lowercased()
            guard n.hasPrefix(wanted), let next = n.dropFirst(wanted.count).first else { return false }
            return !(next.isLetter || next.isNumber)
        }
        if prefixed.count == 1 { return prefixed[0] }
        // "Sidefolk Dev" for "Sidefolk-Dev": the same words, however they're joined or accented. Only as sure as one.
        let loose = looseName(wanted)
        guard !loose.isEmpty, prefixed.isEmpty else { return nil }
        let same = all.filter { looseName($0.name) == loose }
        return same.count == 1 ? same[0] : nil
    }

    /// A name's letters and digits, without case or accents.
    static func looseName(_ name: String) -> String {
        String(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber })
    }

    /// Puts collections in this order (D117). The Inbox stays first, and any not named follow, as they were.
    public func arrangeCollections(_ ids: [String], now: Date = Date()) async throws {
        try await db.writer.write { db in
            let all = try NotebookCollection.order(sql: "sort_order, name COLLATE NOCASE").fetchAll(db)
            var seen = Set<String>()
            let named = ids.filter { seen.insert($0).inserted }.compactMap { id in all.first { $0.id == id } }
            let rest = all.filter { c in !named.contains { $0.id == c.id } }
            for (i, var c) in (named + rest).enumerated() where c.sortOrder != i + 1 {
                c.sortOrder = i + 1
                c.updatedAt = now
                try c.update(db)
            }
        }
    }

    /// Open tasks due from `start` until `end`, soonest first, for the Calendar and the day's plan (D117).
    public func dueTasks(from start: Date, to end: Date) async throws -> [NotebookItem] {
        try await db.writer.read { db in
            try NotebookItem.filter(Column("deleted_at") == nil && Column("kind") == NotebookItem.Kind.task.rawValue
                                    && Column("status") == NotebookItem.Status.open.rawValue
                                    && Column("due_at") >= start.timeIntervalSince1970 && Column("due_at") < end.timeIntervalSince1970)
                .order(Column("due_at"))
                .fetchAll(db)
        }
    }

    /// Returns the named collection, creating it when it does not exist. The look-up and the insert
    /// share one write transaction, so parallel calls (an agent batching saves) create it once.
    /// - Parameters:
    ///   - excluding: kinds a name never resolves to (the profile is not a filing target).
    ///   - source: who names it, if it has to be created.
    public func collection(named name: String, kind: NotebookCollection.Kind = .project, excluding: Set<NotebookCollection.Kind> = [],
                           source: String = "user", now: Date = Date()) async throws -> (NotebookCollection, created: Bool) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).clipped(60)
        guard !clean.isEmpty else { throw ToolError.invalidInput(String(localized: "a collection needs a name.")) }
        let skipped = excluding.map(\.rawValue)
        return try await db.writer.write { db in
            let live = try NotebookCollection.filter(Column("archived_at") == nil).filter(!skipped.contains(Column("kind"))).fetchAll(db)
            if let found = Self.match(clean, in: live) { return (found, false) }
            var created = NotebookCollection(name: clean, kind: kind, source: source, now: now)
            created.sortOrder = try Self.nextOrder(db)
            try created.insert(db)
            return (created, true)
        }
    }

    /// Creates a collection with exactly this name (no fuzzy matching). Refuses a name an existing
    /// collection already has (ignoring case), checked in the same transaction as the insert.
    public func createCollection(name: String, kind: NotebookCollection.Kind, source: String = "user",
                                 now: Date = Date()) async throws -> NotebookCollection {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).clipped(60)
        let created = NotebookCollection(name: clean, kind: kind, source: source, now: now)
        return try await db.writer.write { db in
            let taken = try NotebookCollection.filter(sql: "name = ? COLLATE NOCASE", arguments: [clean]).fetchCount(db) > 0
            if taken { throw UserFacingError("There's already a collection called “\(clean)”.") }
            var placed = created
            placed.sortOrder = try Self.nextOrder(db)
            try placed.insert(db)
            return placed
        }
    }

    /// Saves a collection as it stands, for the tool that changes it.
    public func updateCollection(_ c: NotebookCollection) async throws {
        try await db.writer.write { db in try c.update(db) }
    }

    /// Undo of that tool: only what it changed, so whatever happened since stays, and one deleted since is left alone.
    public func restoreLook(of old: NotebookCollection) async throws {
        try await db.writer.write { db in
            guard var c = try NotebookCollection.fetchOne(db, key: old.id) else { return }
            c.name = old.name
            c.source = old.source
            c.emoji = old.emoji
            c.symbol = old.symbol
            c.color = old.color
            try c.update(db)
        }
    }

    /// Undo of arranging: each its old place, leaving the rest of it alone.
    public func restoreOrder(of old: [NotebookCollection]) async throws {
        try await db.writer.write { db in
            for was in old {
                guard var c = try NotebookCollection.fetchOne(db, key: was.id) else { continue }
                c.sortOrder = was.sortOrder
                try c.update(db)
            }
        }
    }

    /// Where a new collection goes: alphabetical until someone arranges them, then at the end.
    private static func nextOrder(_ db: Database) throws -> Int {
        let most = try Int.fetchOne(db, sql: "SELECT MAX(sort_order) FROM collections") ?? 0
        return most > 0 ? most + 1 : 0
    }

    /// The user renaming a collection in the app: the new name is their own words.
    public func rename(collectionId: String, to name: String, now: Date = Date()) async throws {
        try await db.writer.write { db in
            guard var c = try NotebookCollection.fetchOne(db, key: collectionId) else { return }
            c.name = name.clipped(60)
            c.source = "user"
            c.updatedAt = now
            try c.update(db)
        }
    }

    /// The person's look for a collection (D53): an emoji or a symbol, and a colour; nil goes back to the kind's.
    public func setLook(collectionId: String, emoji: String?, symbol: String?, color: String?, now: Date = Date()) async throws {
        try await db.writer.write { db in
            guard var c = try NotebookCollection.fetchOne(db, key: collectionId) else { return }
            c.emoji = emoji.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8)) }.flatMap { $0.isEmpty ? nil : $0 }
            c.symbol = symbol.map { String($0.prefix(60)) }
            c.color = color.map { String($0.prefix(20)) }
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

    /// Saves an edited item. Reminders that carry the item's own title follow a rename (D49); one given words of its
    /// own ("send it to Anna") keeps them.
    public func update(_ item: NotebookItem) async throws {
        try await db.writer.write { db in
            let before = try NotebookItem.fetchOne(db, key: item.id)
            try item.update(db)
            guard let before, before.title != item.title, !item.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            try db.execute(sql: "UPDATE reminders SET title = ? WHERE item_id = ? AND title = ?",
                           arguments: [item.title.clipped(200), item.id, before.title.clipped(200)])
        }
    }

    public func item(id: String) async throws -> NotebookItem? {
        try await db.writer.read { db in try NotebookItem.fetchOne(db, key: id) }
    }

    /// The items with these ids, in the Trash or not.
    public func items(ids: [String]) async throws -> [NotebookItem] {
        guard !ids.isEmpty else { return [] }
        return try await db.writer.read { db in try NotebookItem.filter(keys: ids).fetchAll(db) }
    }

    public func items(
        collectionId: String? = nil, kinds: [NotebookItem.Kind]? = nil, status: NotebookItem.Status? = nil,
        includeDeleted: Bool = false, dueFrom: Date? = nil, dueBefore: Date? = nil, limit: Int = 200
    ) async throws -> [NotebookItem] {
        try await db.writer.read { db in
            var r = NotebookItem.all()
            // By due date, soonest first; what has none doesn't count.
            if dueFrom != nil || dueBefore != nil {
                r = r.filter(Column("due_at") != nil)
                if let dueFrom { r = r.filter(Column("due_at") >= dueFrom.timeIntervalSince1970) }
                if let dueBefore { r = r.filter(Column("due_at") < dueBefore.timeIntervalSince1970) }
                r = r.order(Column("due_at"))
            }
            if let collectionId { r = r.filter(Column("collection_id") == collectionId) }
            if let kinds { r = r.filter(kinds.map(\.rawValue).contains(Column("kind"))) }
            if let status { r = r.filter(Column("status") == status.rawValue) }
            if !includeDeleted { r = r.filter(Column("deleted_at") == nil) }
            if dueFrom == nil, dueBefore == nil { r = r.order(sql: "pinned_at IS NULL, pinned_at DESC, created_at DESC") }
            return try r.limit(limit).fetchAll(db)
        }
    }

    /// Pins an item to the top of its collection, or unpins it. Pinning isn't an edit, so `updatedAt` stays.
    public func setPinned(itemId: String, _ pinned: Bool, now: Date = Date()) async throws {
        try await db.writer.write { db in
            guard var item = try NotebookItem.fetchOne(db, key: itemId) else { return }
            item.pinnedAt = pinned ? now : nil
            try item.update(db)
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

    /// Permanently removes everything in the Trash. Only the user can do this ("Empty Trash").
    public func emptyTrash() async throws -> Int {
        try await db.writer.write { db in try NotebookItem.filter(Column("deleted_at") != nil).deleteAll(db) }
    }

    public func purgeTrash(olderThan cutoff: Date) async throws -> Int {
        try await db.writer.write { db in
            try NotebookItem.filter(Column("deleted_at") != nil && Column("deleted_at") < cutoff.timeIntervalSince1970).deleteAll(db)
        }
    }

    /// Full-text search over title, body and tags, best matches first; falls back to substring match.
    public func search(_ query: String, collectionId: String? = nil, kinds: [NotebookItem.Kind]? = nil, limit: Int = 20) async throws -> [NotebookItem] {
        // Longer than any real search, and SQLite refuses a LIKE pattern past 50,000 bytes.
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxQueryLength))
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
            if results.isEmpty, !query.isEmpty {
                // What the user typed is literal text: `%` and `_` are escaped, not wildcards.
                let like = "%" + Self.escapeLike(query) + "%"
                var r = NotebookItem.filter(Column("deleted_at") == nil)
                    .filter(sql: #"(title LIKE ? ESCAPE '\' OR body LIKE ? ESCAPE '\' OR tags LIKE ? ESCAPE '\')"#, arguments: [like, like, like])
                if let collectionId { r = r.filter(Column("collection_id") == collectionId) }
                if let kinds { r = r.filter(kinds.map(\.rawValue).contains(Column("kind"))) }
                results = try r.order(Column("updated_at").desc).limit(limit).fetchAll(db)
            }
            // A collection's name finds what's in it, after what says the words itself ("sidefolk", all of Sidefolk-Dev).
            if collectionId == nil, results.count < limit, !query.isEmpty {
                // Not About you, whose facts aren't a list to be found by "about"; not a word too short to mean a name.
                let loose = Self.looseName(query)
                let named = try NotebookCollection.filter(Column("archived_at") == nil && Column("kind") != NotebookCollection.Kind.profile.rawValue).fetchAll(db)
                    .filter { loose.count >= 3 && Self.looseName($0.name).contains(loose) }.map(\.id)
                if !named.isEmpty {
                    let found = Set(results.map(\.id))
                    var r = NotebookItem.filter(Column("deleted_at") == nil).filter(named.contains(Column("collection_id")))
                    if let kinds { r = r.filter(kinds.map(\.rawValue).contains(Column("kind"))) }
                    let more = try r.order(Column("updated_at").desc).limit(limit).fetchAll(db).filter { !found.contains($0.id) }
                    results += more.prefix(limit - results.count)
                }
            }
            return results
        }
    }

    public static let maxQueryLength = 1_000

    static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
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
