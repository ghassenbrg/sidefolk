import CryptoKit
import Foundation
import GRDB

/// One check of a watch, or a run of checks in a row that found the same thing (D87): a watch that looks every 30 s
/// and sees nothing new for a day is one row with a count, not 2,880.
public struct WatchCheck: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "watch_checks"
    public enum Result: String, Codable, Sendable, CaseIterable {
        case unchanged, changed, failed, paused

        /// Whether another check with the same result (and reason) joins this one's run. A change is always its own
        /// row, and so is a pause: each is a moment worth seeing on the timeline.
        var runs: Bool { self == .unchanged || self == .failed }
    }

    public var id: Int64?
    public var watcherId: String
    public var result: Result
    public var firstAt: Date
    public var lastAt: Date
    public var count: Int
    /// Changed: what the notice said ("example.com/pricing changed"). Failed: why, in a few words.
    public var reason: String?
    /// How long the last check of the run took, when it was measured.
    public var durationMs: Int?

    public init(id: Int64? = nil, watcherId: String, result: Result, at: Date, count: Int = 1, reason: String? = nil,
                durationMs: Int? = nil) {
        self.id = id
        self.watcherId = watcherId
        self.result = result
        firstAt = at
        lastAt = at
        self.count = count
        self.reason = reason
        self.durationMs = durationMs
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// Whether a check that found `result` for `reason` continues this run.
    func continues(_ result: Result, reason: String?) -> Bool {
        result.runs && self.result == result && self.reason == reason
    }
}

/// A version of the text a page or file watch compared (D87): the page's readable lines (never its HTML) or a text
/// file's lines, cut at `WatchHistoryLimits.versionCharacters`. The last two are kept, so the latest change can be shown.
public struct WatchVersion: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "watch_versions"
    public var id: Int64?
    public var watcherId: String
    public var at: Date
    public var text: String
    public var hash: String

    public init(watcherId: String, at: Date, text: String) {
        self.watcherId = watcherId
        self.at = at
        self.text = Self.capped(text)
        hash = Self.hash(self.text)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// Whole lines up to the cap, then "…", so a long page keeps its top and every kept line is complete.
    static func capped(_ text: String) -> String {
        let limit = WatchHistoryLimits.versionCharacters
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        let cut = head.lastIndex(of: "\n").map { head[..<$0] } ?? head
        return String(cut) + "\n…"
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// How much history a watch keeps (D87).
public enum WatchHistoryLimits {
    /// Checks older than this go at the daily tidy.
    public static let keepDays = 30
    /// Rows (runs) per watch, whatever their age: a watch that flips between two outcomes all day stays small.
    public static let rowsPerWatch = 500
    /// Each kept version of a page's or file's text.
    public static let versionCharacters = 32_000
    /// Versions per watch: the latest change's before and after.
    public static let versionsPerWatch = 2
    static let reasonCharacters = 200
}

/// Reads and writes watches' check logs and kept versions. Rows go with their watch (foreign keys, cascade).
public struct WatchHistoryStore: Sendable {
    public let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    /// Inserts a new run or updates one already saved; a new run trims the watch to its cap.
    @discardableResult
    public func save(_ check: WatchCheck) async throws -> WatchCheck {
        try await db.writer.write { db in
            if check.id != nil {
                try check.update(db)
                return check
            }
            let saved = try check.inserted(db)
            try db.execute(sql: """
                DELETE FROM watch_checks WHERE watcher_id = ? AND id NOT IN
                    (SELECT id FROM watch_checks WHERE watcher_id = ? ORDER BY id DESC LIMIT ?)
                """, arguments: [check.watcherId, check.watcherId, WatchHistoryLimits.rowsPerWatch])
            return saved
        }
    }

    /// A watch's runs, newest first.
    public func checks(watcherId: String, limit: Int = WatchHistoryLimits.rowsPerWatch) async throws -> [WatchCheck] {
        try await db.writer.read { db in
            try WatchCheck.filter(Column("watcher_id") == watcherId).order(Column("id").desc).limit(limit).fetchAll(db)
        }
    }

    /// The newest `rows` runs of each watch, newest first, in one query (On duty's bars).
    public func latest(watcherIds: [String], rows: Int) async throws -> [String: [WatchCheck]] {
        guard !watcherIds.isEmpty else { return [:] }
        let marks = Array(repeating: "?", count: watcherIds.count).joined(separator: ",")
        let found = try await db.writer.read { db in
            try WatchCheck.fetchAll(db, sql: """
                SELECT id, watcher_id, result, first_at, last_at, count, reason, duration_ms FROM (
                    SELECT *, ROW_NUMBER() OVER (PARTITION BY watcher_id ORDER BY id DESC) AS n
                    FROM watch_checks WHERE watcher_id IN (\(marks))
                ) WHERE n <= ? ORDER BY id DESC
                """, arguments: StatementArguments(watcherIds) + StatementArguments([rows]))
        }
        return Dictionary(grouping: found, by: \.watcherId)
    }

    /// The newest change each watch saw, for `watch.list`.
    public func lastChanges(watcherIds: [String]) async throws -> [String: WatchCheck] {
        guard !watcherIds.isEmpty else { return [:] }
        return try await db.writer.read { db in
            let rows = try WatchCheck.filter(watcherIds.contains(Column("watcher_id")) && Column("result") == WatchCheck.Result.changed.rawValue)
                .order(Column("id").desc).fetchAll(db)
            var newest: [String: WatchCheck] = [:]
            for row in rows where newest[row.watcherId] == nil { newest[row.watcherId] = row }
            return newest
        }
    }

    /// Keeps `text` as the watch's newest version unless it already is; only the newest two stay.
    @discardableResult
    public func addVersion(watcherId: String, text: String, at: Date) async throws -> Bool {
        let version = WatchVersion(watcherId: watcherId, at: at, text: text)
        return try await db.writer.write { db in
            let newest = try WatchVersion.filter(Column("watcher_id") == watcherId).order(Column("id").desc).fetchOne(db)
            if newest?.hash == version.hash { return false }
            try version.insert(db)
            try db.execute(sql: """
                DELETE FROM watch_versions WHERE watcher_id = ? AND id NOT IN
                    (SELECT id FROM watch_versions WHERE watcher_id = ? ORDER BY id DESC LIMIT ?)
                """, arguments: [watcherId, watcherId, WatchHistoryLimits.versionsPerWatch])
            return true
        }
    }

    /// The kept versions, oldest first: the latest change's before, then after.
    public func versions(watcherId: String) async throws -> [WatchVersion] {
        try await db.writer.read { db in
            try WatchVersion.filter(Column("watcher_id") == watcherId).order(Column("id")).fetchAll(db)
        }
    }

    /// Removes checks that ended before `cutoff`. Versions stay while their watch does: two at most, and the newer is
    /// what the next change is compared with.
    @discardableResult
    public func purge(olderThan cutoff: Date) async throws -> Int {
        try await db.writer.write { db in try WatchCheck.filter(Column("last_at") < cutoff.timeIntervalSince1970).deleteAll(db) }
    }
}

extension WatchCheck {
    /// The newest `count` checks as one result each, oldest first, from runs newest first: a run of 40 unchanged
    /// checks is 40 ticks.
    public static func ticks(_ runs: [WatchCheck], count: Int) -> [Result] {
        var out: [Result] = []
        for run in runs {
            let take = min(run.count, count - out.count)
            out.append(contentsOf: Array(repeating: run.result, count: max(0, take)))
            if out.count >= count { break }
        }
        return out.reversed()
    }
}
