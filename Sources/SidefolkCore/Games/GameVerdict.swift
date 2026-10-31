import Foundation

/// What a result means for the person, and so how every game draws it (D75): the same meaning always gets the same
/// colour, with a symbol or a word beside it, never colour alone.
/// - a win for the person: success (green), a ✓ or a crown;
/// - a loss, the companion winning included: a calm warm tone, never the danger red (which means something went wrong
///   or can't be undone), with an ✕ or a thumbs-up for a good game;
/// - a draw: neutral ink, an = sign; never red or green.
public enum GameVerdict: String, Sendable, Hashable, CaseIterable {
    case win, loss, draw

    /// The drawing role the app maps to its theme: `success`, `lost` (the games' calm warm tone) or `neutral`.
    public enum Role: String, Sendable { case success, lost, neutral }

    public var role: Role {
        switch self {
        case .win: .success
        case .loss: .lost
        case .draw: .neutral
        }
    }

    /// The SF Symbol drawn with it, so the meaning never rests on colour.
    public var symbol: String {
        switch self {
        case .win: "checkmark.circle.fill"
        case .loss: "xmark.circle.fill"
        case .draw: "equal.circle.fill"
        }
    }

    /// A tile once answered: right is the person's win, wrong their loss, their own pick left unjudged (a draw).
    public init?(tile: GameBoard.Answers.State, locked: Bool) {
        switch tile {
        case .right: self = .win
        case .wrong: self = .loss
        case .picked where locked: self = .draw
        default: return nil
        }
    }

    /// An end card's tone: good is a win, bad a loss, anything else a draw.
    public init(tone: GameBoard.Tone) {
        switch tone {
        case .good: self = .win
        case .bad: self = .loss
        default: self = .draw
        }
    }

    /// Rock, paper, scissors from the person's side.
    public init(you: Hand, companion: Hand) {
        self = you == companion ? .draw : you.beats == companion ? .win : .loss
    }

    /// What a toss meant for the person: a hand won or lost, a coin they called; nil when nothing was at stake (a coin
    /// not called, dice), which is drawn neutral.
    public init?(_ toss: Toss) {
        switch toss {
        case .hands(let person, let companion): self.init(you: person, companion: companion)
        case .coins: guard let right = toss.called else { return nil }
            self = right ? .win : .loss
        case .dice: return nil
        }
    }
}
