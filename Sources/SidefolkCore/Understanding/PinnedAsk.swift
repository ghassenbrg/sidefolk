import Foundation
import GRDB

/// A result the person pinned in Ask, as it's kept across quitting (D136). A saved card is what it said: an undo or
/// "think harder" belonged to the moment it was made, so those don't come back. Reply continues its conversation
/// while History still has it; a pin stays until it's unpinned, as a note would (SECURITY T19).
public struct SavedAskRequest: Codable, Sendable, Equatable {
    public enum Part: Codable, Sendable, Equatable {
        case result(ResultCard)
        case answer(String, tainted: Bool, thread: String?)
        case list(title: String, cards: [ResultCard])
        case info(String)
        case doneWithoutAsking(String, fullAccess: Bool)
        case skipped(String, why: String)
    }

    public var caption: String?
    public var createdAt: Date
    public var seenAt: Date?
    public var parts: [Part]

    public init(caption: String?, createdAt: Date, seenAt: Date?, parts: [Part]) {
        self.caption = caption
        self.createdAt = createdAt
        self.seenAt = seenAt
        self.parts = parts
    }
}

/// In the database's `kv`, so a backup carries them and Delete everything takes them.
public struct PinnedAskStore: Sendable {
    static let key = "ask.pinned"
    let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    public func save(_ requests: [SavedAskRequest]) async throws {
        let value = try JSONValue.from(requests)
        try await db.writer.write { db in
            if requests.isEmpty {
                _ = try KeyValue.deleteOne(db, key: Self.key)
            } else {
                try KeyValue(key: Self.key, value: value).save(db)
            }
        }
    }

    /// What can't be read any more isn't worth stopping for: the answers are in History too. An answer whose conversation
    /// has since gone from History comes back without it, so nothing offers to continue what isn't there.
    public func load(conversationKept: @Sendable (String) async -> Bool = { _ in true }) async -> [SavedAskRequest] {
        let stored = try? await db.writer.read { db in try KeyValue.fetchOne(db, key: Self.key) }
        var requests = (try? stored?.value.decode([SavedAskRequest].self)) ?? []
        for r in requests.indices {
            for p in requests[r].parts.indices {
                if case .answer(let text, let tainted, let thread?) = requests[r].parts[p], await !conversationKept(thread) {
                    requests[r].parts[p] = .answer(text, tainted: tainted, thread: nil)
                }
            }
        }
        return requests
    }
}
