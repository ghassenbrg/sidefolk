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

    /// Forgets every "Always allow", for every tool and caller (Trust › Forget everything I allowed). Folders the person
    /// shared are a different list with their own Remove, and the policy is untouched.
    public func revokeAllGrants() async throws {
        _ = try await db.writer.write { db in try Grant.deleteAll(db) }
    }

    /// Allows Sidefolk's own agent to read a site for good, from Settings (D47): "example.com" or a full address.
    /// It is the grant "Always allow" on a page card makes, so it holds the same way. Returns the site's name.
    @discardableResult
    public func allowSite(_ text: String, now: Date = Date()) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard UserMentions.isWebAddress(address), let url = URL(string: address), let site = UserMentions.host(url), site.contains(".") else {
            throw UserFacingError("That doesn't look like a site on the internet.", recovery: "Write it like example.com.")
        }
        let known = try await grants().contains {
            $0.tool == Self.siteReadTool && $0.callerKind == "agent" && $0.scope.string("host").flatMap(UserMentions.site) == site
        }
        if !known { try await addGrant(Grant(tool: Self.siteReadTool, scope: ["host": .string(site)], callerKind: "agent", now: now)) }
        return site
    }

    /// The tool a site grant from Settings covers: reading a page.
    static let siteReadTool = "web.fetch"

    public func touchGrant(id: String, now: Date = Date()) async throws {
        _ = try await db.writer.write { db in
            try Grant.filter(key: id).updateAll(db, Column("last_used_at").set(to: now.timeIntervalSince1970))
        }
    }

    public func folders() async throws -> [GrantedFolder] {
        try await db.writer.read { db in try GrantedFolder.order(Column("path")).fetchAll(db) }
    }

    /// Grants a folder (upgrading read to read/write if asked); stores the canonical path.
    /// `exactly`: only this path as it stands now, for a yes to a question that named it: a link swapped in since gets nothing.
    public func grantFolder(_ path: String, access: GrantedFolder.Access, now: Date = Date(), exactly: Bool = false) async throws {
        guard let canonical = FolderAccess.canonical(path), FolderAccess.isGrantable(canonical) else {
            throw UserFacingError("That folder can't be shared with Sidefolk.", recovery: "Choose a more specific folder.")
        }
        if exactly, canonical != path { throw UserFacingError("That folder changed. Nothing was shared.") }
        try await db.writer.write { db in
            if let existing = try GrantedFolder.fetchOne(db, key: canonical), existing.access == .readwrite { return }
            try GrantedFolder(path: canonical, access: access, now: now).save(db)
        }
    }

    public func revokeFolder(_ path: String) async throws {
        _ = try await db.writer.write { db in try GrantedFolder.deleteOne(db, key: path) }
    }

    /// The policy as it holds at `now`: Full access that has ended reads as the mode it replaced (D84).
    public func policy(now: Date = Date()) async throws -> GuardPolicy {
        (try await KVStore(db).get(Self.policyKey, as: GuardPolicy.self) ?? GuardPolicy()).current(at: now)
    }

    public func setPolicy(_ p: GuardPolicy) async throws { try await KVStore(db).set(Self.policyKey, p) }

    /// Changes one part of the policy in one step. Reading it with `try?` and saving a default when the read
    /// failed would switch back on every capability the person had turned off; this throws instead.
    public func updatePolicy(_ change: @escaping @Sendable (inout GuardPolicy) -> Void) async throws {
        try await db.writer.write { db in
            // An ended Full access is changed as what it became, so the change can't bring it back.
            var policy = (try KeyValue.fetchOne(db, key: Self.policyKey)?.value.decode(GuardPolicy.self) ?? GuardPolicy()).current(at: Date())
            change(&policy)
            try KeyValue(key: Self.policyKey, value: try JSONValue.from(policy)).save(db)
        }
    }

    /// Turns Full access off, back to the mode it replaced (`GuardPolicy.endFullAccess`).
    public func turnOffFullAccess() async throws { try await updatePolicy { $0.endFullAccess() } }

    static let policyKey = "guard.policy"
}
