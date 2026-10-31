import Foundation

/// What each side of a rock, paper, scissors reveal shows at a moment of it (D75), for the Play panel and the desktop
/// alike. Both hands stay sealed while the fists pump (a closed hand is not a rock: drawing one there read as the
/// companion having played rock), then each side opens on its own throw and keeps it to the end: the person's side
/// is only ever the person's hand, the companion's only ever its own.
public struct HandsReveal: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case pumping, clash, outcome }

    /// When the hands open, and when the winner acts on the loser, as parts of the whole reveal (0–1).
    public static let opens = 0.45
    public static let acts = 0.62

    public var phase: Phase
    /// nil while sealed.
    public var you: Hand?
    public var companion: Hand?
    /// Shown only once the outcome plays: who won, from the person's side.
    public var verdict: GameVerdict?

    public init(you: Hand, companion: Hand, at p: Double) {
        if p < Self.opens {
            phase = .pumping
            self.you = nil
            self.companion = nil
            verdict = nil
        } else {
            phase = p < Self.acts ? .clash : .outcome
            self.you = you
            self.companion = companion
            verdict = p < Self.acts ? nil : GameVerdict(you: you, companion: companion)
        }
    }
}
