import Foundation

/// The order every result is shown in (D75): the build-up first (the hands pumping, the coin spinning, the dice
/// tumbling, the person's pick pressed beside the companion's sealed card), then the reveal, then the verdict a beat
/// after: colours, the score, words, the companion's reaction, sounds and what VoiceOver hears. A game sends its next
/// board with the verdict in it; this is what the panel shows until the verdict's moment comes.
public enum GameSuspense {
    /// How long a reveal plays before the verdict.
    public static let revealSeconds: TimeInterval = 1.5
    /// The beat between an answer and whether it was right.
    public static let beatSeconds: TimeInterval = 0.8

    /// The board to show first, and for how long, or nil when `next` gives nothing away.
    /// - Parameter picked: the answer the person just gave, drawn pressed meanwhile.
    public static func buildUp(from previous: GameBoard?, to next: GameBoard, picked: Int?) -> (board: GameBoard, seconds: TimeInterval)? {
        if next.reveal != nil {
            var parts: [GameBoard.Part] = []
            if let score = previous?.score { parts.append(.score(score)) }
            for part in next.parts {
                switch part {
                case .reveal: parts.append(part)
                case .answers(let a): parts.append(.answers(pending(a, picked)))
                default: break
                }
            }
            if let prompt = previous?.parts.first(where: { if case .prompt = $0 { true } else { false } }) {
                parts.insert(prompt, at: min(parts.count, parts.firstIndex { if case .answers = $0 { true } else { false } } ?? parts.count))
            }
            return (GameBoard(parts: parts), revealSeconds)
        }
        guard let answers = next.answers, answers.locked, answers.tiles.contains(where: { $0.state == .right || $0.state == .wrong }),
              let previous, let before = previous.answers, !before.locked else { return nil }
        let parts = previous.parts.compactMap { part -> GameBoard.Part? in
            switch part {
            case .answers(let a): .answers(pending(a, picked))
            case .button, .timer, .choice: nil
            default: part
            }
        }
        return (GameBoard(parts: parts), beatSeconds)
    }

    /// The tiles while the verdict waits: the person's pick pressed, nothing judged, the companion's pick still hidden.
    static func pending(_ a: GameBoard.Answers, _ picked: Int?) -> GameBoard.Answers {
        var a = a
        for i in a.tiles.indices {
            a.tiles[i].state = i == picked ? .picked : .none
            a.tiles[i].companion = false
        }
        a.locked = true
        return a
    }

    /// Whether a board gives a result away: a judged tile, the companion's revealed pick, an end card, a fact, a cue,
    /// or words of its own. A build-up board must have none of these.
    public static func showsVerdict(_ board: GameBoard) -> Bool {
        if board.cue != nil || board.said != nil || board.over { return true }
        for part in board.parts {
            switch part {
            case .answers(let a) where a.tiles.contains(where: { $0.state == .right || $0.state == .wrong || $0.companion }): return true
            case .result, .note: return true
            default: continue
            }
        }
        return false
    }
}
