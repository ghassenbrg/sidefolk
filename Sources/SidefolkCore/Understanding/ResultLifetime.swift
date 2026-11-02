import Foundation

/// How long a result stays in Ask (D90): by its weight, so Ask tidies itself as people come and go without clearing it.
/// Everything that goes is still in History.
public enum ResultLifetime {
    public enum Weight: Sendable, Equatable {
        /// A value read now, a calculation, a lookup, a "done": read once, it has done its job.
        case quick
        /// An answer, or something made (a note saved, a reminder set): worth a second look for a while.
        case normal
        /// A question waiting, an approval, a failure to retry: it stays until dealt with.
        case needsYou
    }

    /// A quick result goes this long after it was first seen; so Ask opened again five minutes later is clear of it.
    public static let quickAfterSeen: TimeInterval = 120
    /// A normal one goes after half an hour, or with the day: the next day's first look starts clean.
    public static let normal: TimeInterval = 1800

    /// Whether a result should go now. `seenAt`: when it was first on screen in Ask (a quick result nobody saw yet
    /// waits for its look). `pinned`: the person kept it.
    public static func expired(_ weight: Weight, createdAt: Date, seenAt: Date?, pinned: Bool, now: Date,
                               calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard !pinned else { return false }
        switch weight {
        case .needsYou:
            return false
        case .quick:
            guard let seenAt else { return false }
            return now.timeIntervalSince(seenAt) >= quickAfterSeen
        case .normal:
            return now.timeIntervalSince(createdAt) >= normal || !calendar.isDate(createdAt, inSameDayAs: now)
        }
    }

    /// A result card's weight by its kind: values and lookups are quick; what was made or found to keep is
    /// normal.
    public static func weight(of card: ResultCard.Kind) -> Weight {
        switch card {
        case .reading, .info, .extensionResult, .web: .quick
        case .note, .reminder, .watcher, .memory, .file, .list, .collection: .normal
        }
    }
}
