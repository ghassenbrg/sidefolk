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
        if let answers = next.answers, answers.locked, answers.tiles.contains(where: { $0.state == .right || $0.state == .wrong }),
           let previous, let before = previous.answers, !before.locked {
            let parts = previous.parts.compactMap { part -> GameBoard.Part? in
                switch part {
                case .answers(let a): .answers(pending(a, picked))
                case .button, .timer, .choice: nil
                default: part
                }
            }
            return (GameBoard(parts: parts), beatSeconds)
        }
        guard let previous else { return nil }
        // A row of letters just played: its tiles flip one by one (the reveal), and what it means waits until they have.
        if let letters = next.letters, letters.flip != nil, letters.rows.count > (previous.letters?.rows.count ?? 0) {
            return (withheld(next, previous), letters.flipSeconds)
        }
        return decides(next, after: previous) ? (withheld(next, previous), beatSeconds) : nil
    }

    /// Whether `next` settles something `previous` left open: a point scored, a line won, the cups lifted, a reflex
    /// timed, a guess judged, a card turned with the companion's reaction, the end card.
    static func decides(_ next: GameBoard, after previous: GameBoard) -> Bool {
        if next.result != nil, previous.result == nil { return true }
        if let s = next.score, let p = previous.score, s.you > p.you || s.companion > p.companion { return true }
        if let g = next.grid, g.cells.contains(where: { $0.state == .win }), previous.grid?.cells.contains(where: { $0.state == .win }) != true { return true }
        if let g = next.grid, next.cue != nil, g.cells.contains(where: { $0.animate == .flip }) { return true }
        if next.cups?.revealed == true, previous.cups?.revealed != true { return true }
        if next.reflex?.shows != nil, previous.reflex?.armed == true { return true }
        if let n = next.numberField, n.history.count > (previous.numberField?.history.count ?? 0) { return true }
        return false
    }

    /// `next` with what it decides held back: the previous score, words, keys, guesses and lives, no win drawn, the cups
    /// still down with the pick pressed, the reflex waiting, nothing to press, no end card, notes or cue.
    static func withheld(_ next: GameBoard, _ previous: GameBoard) -> GameBoard {
        let before = previous.parts.first { if case .prompt = $0 { true } else { false } }
        var parts = next.parts.compactMap { part -> GameBoard.Part? in
            switch part {
            case .score: return previous.score.map(GameBoard.Part.score)
            // The game's words may say what happened ("You win this game!"): the previous ones stay meanwhile.
            case .prompt: return before
            case .keys: return previous.keys.map { var k = $0; k.locked = true; return .keys(k) }
            case .lives: return previous.lives.map(GameBoard.Part.lives) ?? part
            case .result, .note, .facts, .button, .timer, .choice, .entry: return nil
            case .board(var g):
                for i in g.cells.indices where g.cells[i].state == .win { g.cells[i].state = .none }
                g.locked = true
                return .board(g)
            case .cups(var c):
                c.revealed = false
                c.gem = nil
                c.swaps = []
                c.locked = true
                return .cups(c)
            case .reflex(var r):
                r.after = nil
                r.shows = nil
                return .reflex(r)
            case .number(var n):
                n.history = previous.numberField?.history ?? []
                n.locked = true
                return .number(n)
            case .sticks(var s):
                s.locked = true
                return .sticks(s)
            case .pads(var p):
                p.play = []
                p.locked = true
                return .pads(p)
            default: return part
            }
        }
        if let before, !parts.contains(before) {
            parts.insert(before, at: parts.firstIndex { if case .score = $0 { false } else { true } } ?? parts.count)
        }
        return GameBoard(parts: parts)
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
            case .board(let g) where g.cells.contains(where: { $0.state == .win }): return true
            case .cups(let c) where c.revealed: return true
            case .reflex(let r) where r.shows != nil: return true
            default: continue
            }
        }
        return false
    }
}
