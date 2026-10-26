import Foundation

/// Recent undoable actions, kept for 15 minutes. An older one is neither offered nor performed:
/// what it would put back may have changed since.
public actor UndoCenter {
    public static let lifetime: TimeInterval = 900
    private var entries: [String: (UndoAction, Date)] = [:]
    /// Activity rows (by row id) and the call each logged, so Activity offers the same Undo the
    /// Ask panel does: whatever mode it ran in, it can be taken back from where it is listed (D37).
    private var rows: [Int64: String] = [:]
    public init() {}

    public func register(_ action: UndoAction, id: String, now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.1) < Self.lifetime }
        rows = rows.filter { entries[$0.value] != nil }
        entries[id] = (action, now)
    }

    func link(row: Int64, to id: String) { rows[row] = id }

    public func has(_ id: String, now: Date = Date()) -> Bool {
        guard let (_, at) = entries[id] else { return false }
        return now.timeIntervalSince(at) < Self.lifetime
    }

    /// The Activity rows that can still be undone.
    public func undoableRows(now: Date = Date()) -> Set<Int64> {
        Set(rows.filter { has($0.value, now: now) }.keys)
    }

    public func undo(_ id: String, now: Date = Date()) async throws -> String? {
        guard let (action, at) = entries.removeValue(forKey: id), now.timeIntervalSince(at) < Self.lifetime else { return nil }
        try await action.perform()
        return action.label
    }

    /// Undoes what an Activity row did; nil when it can't be undone anymore.
    public func undo(row: Int64, now: Date = Date()) async throws -> String? {
        guard let id = rows.removeValue(forKey: row) else { return nil }
        return try await undo(id, now: now)
    }
}
