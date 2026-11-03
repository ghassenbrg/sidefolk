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

    /// Ask is a shortcut, not an archive (D136): results go soon, and History keeps them. How soon depends on whether the
    /// person was there. A result they watched arrive, or saw another way (an animation, said aloud), has done its job.
    public static let quickWatched: TimeInterval = 20
    public static let normalWatched: TimeInterval = 120
    /// One that came while they were away gets longer from their first look, and nothing goes before that look.
    public static let quickLater: TimeInterval = 60
    public static let normalLater: TimeInterval = 600
    /// First seen this soon after it appeared: they were there.
    static let watchedWithin: TimeInterval = 5

    /// Whether a result should go now. `seenAt`: when it first reached the person. `pinned`: they kept it.
    public static func expired(_ weight: Weight, createdAt: Date, seenAt: Date?, pinned: Bool, now: Date) -> Bool {
        guard !pinned, let seenAt else { return false }
        let watched = seenAt.timeIntervalSince(createdAt) <= watchedWithin
        let age = now.timeIntervalSince(seenAt)
        return switch weight {
        case .needsYou: false
        case .quick: age >= (watched ? quickWatched : quickLater)
        case .normal: age >= (watched ? normalWatched : normalLater)
        }
    }

    /// Which requests go so Ask never holds more than `limit` (oldest first). The ones the person kept don't count and
    /// never go; what waits for an answer isn't a request at all.
    public static func overflow<ID: Hashable>(_ requests: [(id: ID, kept: Bool)], limit: Int) -> Set<ID> {
        Set(requests.filter { !$0.kept }.dropLast(limit).map(\.id))
    }

    /// A card with a tree on it says what was just made (D125): that's worth the second look, whatever its kind.
    public static func weight(of card: ResultCard) -> Weight {
        card.tree == nil ? weight(of: card.kind) : .normal
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
