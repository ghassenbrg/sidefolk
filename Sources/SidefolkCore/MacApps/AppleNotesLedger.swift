import Foundation
import GRDB
import Synchronization

/// Which Apple Notes are already in the notebook, and as which item. A second "copy my notes" skips
/// them, a list can leave them out, and "move" removes a note from Notes only when its copy is there
/// and whole. Kept in `kv` (key `applenotes.copied`), so no migration and "delete everything" clears it.
public final class AppleNotesLedger: Sendable {
    public struct Entry: Codable, Sendable, Hashable {
        public var itemId: String
        public var title: String
        /// "iCloud › Recipes", where the note was when it was copied.
        public var place: String
        /// The note's modification date when it was copied: a later edit in Notes isn't in the copy.
        public var modified: Date?
        /// Nothing stayed behind: the body wasn't cut and the note had no attachments.
        public var complete: Bool
        public var copiedAt: Date
    }

    static let key = "applenotes.copied"
    private let db: AppDatabase
    /// The stored map, loaded once; approval summaries read it without waiting.
    private let mirror = Mutex<[String: Entry]?>(nil)

    public init(db: AppDatabase) { self.db = db }

    /// Notes' id → entry.
    @discardableResult
    public func load() async throws -> [String: Entry] {
        if let loaded = mirror.withLock({ $0 }) { return loaded }
        let stored = try await db.writer.read { db in try KeyValue.fetchOne(db, key: Self.key) }
        let entries = (try? stored?.value.decode([String: Entry].self)) ?? [:]
        mirror.withLock { $0 = entries }
        return entries
    }

    /// The entry for a note named by its short id or Notes' own id, from what is loaded (nil before `load`).
    public func cached(note: String) -> Entry? {
        mirror.withLock { map in map?[note] ?? map?.first { AppleNotes.handle(for: $0.key) == note }?.value }
    }

    public var isLoaded: Bool { mirror.withLock { $0 != nil } }

    /// Adds or replaces entries in one transaction, so parallel copies can't drop each other's.
    public func record(_ entries: [String: Entry]) async throws {
        try await change { map in for (id, entry) in entries { map[id] = entry } }
    }

    public func forget(_ ids: [String]) async throws {
        try await change { map in for id in ids { map[id] = nil } }
    }

    private func change(_ edit: @escaping @Sendable (inout [String: Entry]) -> Void) async throws {
        let updated = try await db.writer.write { db -> [String: Entry] in
            var map = (try? KeyValue.fetchOne(db, key: Self.key)?.value.decode([String: Entry].self)) ?? [:]
            edit(&map)
            try KeyValue(key: Self.key, value: try JSONValue.from(map)).save(db)
            return map
        }
        mirror.withLock { $0 = updated }
    }
}
