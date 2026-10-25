import Foundation
import GRDB

/// "Always allow" grants, granted folders and the Guard policy, persisted.
public struct PermissionStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func grants() async throws -> [Grant] {
        try await db.writer.read { db in try Grant.order(Column("created_at").desc).fetchAll(db) }
    }

    public func addGrant(_ g: Grant) async throws { try await db.writer.write { db in try g.save(db) } }

    public func revokeGrant(id: String) async throws {
        _ = try await db.writer.write { db in try Grant.deleteOne(db, key: id) }
    }

    public func touchGrant(id: String, now: Date = Date()) async throws {
        _ = try await db.writer.write { db in
            try Grant.filter(key: id).updateAll(db, Column("last_used_at").set(to: now.timeIntervalSince1970))
        }
    }

    public func folders() async throws -> [GrantedFolder] {
        try await db.writer.read { db in try GrantedFolder.order(Column("path")).fetchAll(db) }
    }

    /// Grants a folder (upgrading read to read/write if asked); stores the canonical path.
    public func grantFolder(_ path: String, access: GrantedFolder.Access, now: Date = Date()) async throws {
        let canonical = FolderAccess.canonical(path)
        try await db.writer.write { db in
            if let existing = try GrantedFolder.fetchOne(db, key: canonical), existing.access == .readwrite { return }
            try GrantedFolder(path: canonical, access: access, now: now).save(db)
        }
    }

    public func revokeFolder(_ path: String) async throws {
        _ = try await db.writer.write { db in try GrantedFolder.deleteOne(db, key: path) }
    }

    public func policy() async throws -> GuardPolicy {
        try await KVStore(db).get("guard.policy", as: GuardPolicy.self) ?? GuardPolicy()
    }

    public func setPolicy(_ p: GuardPolicy) async throws { try await KVStore(db).set("guard.policy", p) }
}
