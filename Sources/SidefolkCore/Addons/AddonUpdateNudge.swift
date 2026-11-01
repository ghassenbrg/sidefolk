import Foundation

/// When add-on updates that wait for the person earn one gentle word (D89). With "Update add-ons automatically" off,
/// nothing installs by itself and the updates sit in Settings and the Gallery, where nobody looks on purpose. After
/// they have waited a day, one whisper says how many there are; then nothing more about them, only about an update
/// that comes later and waits a day in its turn.
public struct AddonUpdateNudge: Sendable, Equatable, Codable {
    /// How long an update waits before it is mentioned.
    public static let after: TimeInterval = 24 * 3600

    /// When each waiting update (`id@version`) was first seen waiting.
    public var seen: [String: Date] = [:]
    /// The updates already mentioned.
    public var told: Set<String> = []

    public init() {}

    public static func mark(_ entry: AddonEntry) -> String { "\(entry.id)@\(entry.version)" }

    /// What waits now: new ones are seen from `now`, those no longer waiting are forgotten.
    public mutating func note(_ waiting: [AddonEntry], now: Date) {
        let marks = Set(waiting.map(Self.mark))
        seen = seen.filter { marks.contains($0.key) }
        for mark in marks where seen[mark] == nil { seen[mark] = now }
        told.formIntersection(marks)
    }

    /// Whether to whisper now: add-ons don't update by themselves and an update not yet mentioned has waited a day.
    /// When it says yes, everything waiting counts as told: the whisper names them all.
    public mutating func due(automatic: Bool, now: Date) -> Bool {
        guard !automatic else { return false }
        let ripe = seen.contains { mark, since in !told.contains(mark) && now.timeIntervalSince(since) >= Self.after }
        guard ripe else { return false }
        told.formUnion(seen.keys)
        return true
    }
}
