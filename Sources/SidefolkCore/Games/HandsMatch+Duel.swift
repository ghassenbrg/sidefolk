import Foundation

/// Two people's names for a game they play each other on this Mac (D96): the ones Sidefolk passes (`options.names`,
/// the last pair a game showed), or "Player 1" (the Mac account's first name when it has one) and "Player 2".
public enum TwoPlayers {
    /// The longest name a game shows.
    public static let longestName = 24

    public static func names(_ given: JSONValue?) -> [String] {
        let typed = (given?.arrayValue ?? []).compactMap { clean($0.stringValue) }
        if typed.count == 2 { return typed }
        return [clean(NSFullUserName().split(separator: " ").first.map(String.init)) ?? defaultName(0), defaultName(1)]
    }

    public static func defaultName(_ i: Int) -> String {
        i == 0 ? String(localized: "Player 1", comment: "Two people play each other: the first one's name until they type their own")
            : String(localized: "Player 2", comment: "Two people play each other: the second one's name until they type their own")
    }

    /// A name as typed: one line, trimmed, at most `longestName` characters; nil when nothing is left.
    public static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let line = ExtensionText.clean(raw).components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : String(line.prefix(longestName))
    }
}

/// Rock, paper, scissors between two people (D96): names first, then each round the first player picks while the
/// second looks away, a cover passes the Mac over, the second picks, and both hands show at once. Nothing on a board
/// before that reveal says which hand the first player chose.
extension HandsMatch {
    func duel(_ move: GameMove) async -> GameBoard {
        switch move {
        case .text(let name, let value) where name == "player1" || name == "player2":
            let s = state.withLock { s -> State in
                guard let i = s.naming, name == "player\(i + 1)", var players = s.players else { return s }
                players[i] = TwoPlayers.clean(value) ?? players[i]
                s.players = players
                s.naming = i == 0 ? 1 : nil
                return s
            }
            return board(s, cue: s.naming == nil ? GameCue(move: .ready, line: .yourTurn, look: .panel) : nil)
        case .button("start"):
            let s = state.withLock { s -> State in
                s.naming = nil
                return s
            }
            return board(s, cue: GameCue(move: .ready, line: .yourTurn, look: .panel))
        case .answer(let i) where Hand.allCases.indices.contains(i):
            let picked = Hand.allCases[i]
            var finished: (first: Hand, second: Hand)?
            let s = state.withLock { s -> State in
                guard s.naming == nil, s.last == nil, !s.over else { return s }
                guard let first = s.firstHand else {
                    s.firstHand = picked
                    s.handedOver = false
                    return s
                }
                guard s.handedOver else { return s }
                s.last = (first, picked)
                s.firstHand = nil
                s.handedOver = false
                if first.beats == picked { s.you += 1 } else if picked.beats == first { s.companion += 1 }
                finished = (first, picked)
                return s
            }
            guard let finished else { return board(s, cue: s.firstHand != nil ? GameCue(move: .nod, sound: .tap, look: .away) : nil) }
            if s.over, let players = s.players {
                await score.duel(players, winner: s.you > s.companion ? 0 : 1)
            }
            return board(s, cue: refereeing(s, finished.first, finished.second))
        case .button("ready"):
            let s = state.withLock { s -> State in
                if s.firstHand != nil { s.handedOver = true }
                return s
            }
            return board(s, cue: GameCue(move: .ready, look: .panel))
        case .button("next"):
            let s = state.withLock { s -> State in
                guard s.last != nil, !s.over else { return s }
                s.last = nil
                s.round += 1
                return s
            }
            return board(s, cue: GameCue(move: .ready, look: .panel))
        case .button("again"):
            let s = state.withLock { s -> State in
                s = State(players: s.players)
                return s
            }
            return board(s, cue: GameCue(move: .ready, line: .yourTurn, look: .panel))
        default:
            return board(state.withLock { $0 }, cue: nil)
        }
    }

    /// The first board's choice: against the companion, or two people on this Mac.
    func opponents(_ companion: String, two: Bool) -> GameBoard.Choice {
        GameBoard.Choice(name: "opponent", label: nil, style: .segmented, options: [
            .init(value: "companion", label: String(localized: "vs \(companion)", comment: "A game against the companion (named)"), detail: nil, symbol: nil),
            .init(value: "two", label: String(localized: "2 players", comment: "Two people play each other on this Mac"), detail: nil, symbol: "person.2.fill"),
        ], selected: two ? "two" : "companion")
    }

    /// Switches before the first throw: a fresh match either way, names first for two people.
    func opponent(_ two: Bool) -> GameBoard {
        let names = TwoPlayers.names(nil)
        let s = state.withLock { s -> State in
            guard s.round == 1, s.last == nil, s.firstHand == nil else { return s }
            if two {
                s = State(players: s.players ?? names)
                s.naming = 0
            } else if s.players != nil {
                s = State(sealed: Hand.allCases[random(0...2)])
                s.thrown = [s.sealed!]
            }
            return s
        }
        return board(s, cue: nil)
    }

    /// The companion referees: a nod for a round, a shrug for a draw, confetti for the match, and never "I win".
    private func refereeing(_ s: State, _ first: Hand, _ second: Hand) -> GameCue {
        if s.over { return GameCue(move: .cheer, effect: .confetti, sound: .fanfare) }
        return first == second ? GameCue(move: .shrug, line: .draw, sound: .boop) : GameCue(move: .nod, sound: .snap)
    }

    func duelBoard(_ s: State, players: [String], cue: GameCue?) -> GameBoard {
        var parts: [GameBoard.Part] = [.score(GameBoard.Score(you: s.you, companion: s.companion, streak: nil, best: nil, rounds: Self.toWin,
                                                              companionPicked: false, players: players))]
        if let i = s.naming {
            parts.append(.prompt(GameBoard.Prompt(text: String(localized: "Who's playing?", comment: "Two people play each other: the board where they type their names"),
                                                  eyebrow: String(localized: "2 players", comment: "Two people play each other on this Mac"), chip: nil)))
            parts.append(.facts([GameBoard.Fact(label: TwoPlayers.defaultName(0), value: players[0]),
                                 GameBoard.Fact(label: TwoPlayers.defaultName(1), value: players[1])]))
            parts.append(.entry(GameBoard.Entry(name: "player\(i + 1)", kind: .text,
                                                label: String(localized: "\(TwoPlayers.defaultName(i))'s name",
                                                              comment: "Two people play each other: the field for one player's name (“Player 1's name”)"),
                                                placeholder: players[i], button: i == 0 ? String(localized: "Next", comment: "A button: on to the second player's name")
                                                    : String(localized: "Start", comment: "A button: start the game"),
                                                max: TwoPlayers.longestName, locked: false)))
            parts.append(.button(GameBoard.Button(label: String(localized: "Start", comment: "A button: start the game"), move: "start", style: .primary,
                                                  symbol: "play.fill", key: nil, disabled: false)))
            parts.append(.choice(opponents(companionName, two: true)))
            return finish(GameBoard(parts: parts, cue: cue, over: false))
        }
        let tiles = Hand.allCases.map { hand -> GameBoard.Answers.Tile in
            var state = GameBoard.Answers.State.none
            if let last = s.last {
                // Each player's own hand; the third steps back. Colours say whose, never who won (D96).
                state = hand == last.you || hand == last.companion ? .picked : .faded
            }
            return GameBoard.Answers.Tile(label: hand.title, state: state, companion: false, art: GameArt(rawValue: hand.rawValue))
        }
        let eyebrow = Self.roundTitle(s.round)
        if let last = s.last {
            parts.append(.reveal(.hands(you: last.you, companion: last.companion)))
            parts.append(.prompt(GameBoard.Prompt(text: Self.verdict(last.you, last.companion, players), eyebrow: eyebrow, chip: nil)))
            parts.append(.answers(GameBoard.Answers(tiles: tiles, layout: .row, locked: true)))
        } else if s.firstHand == nil {
            parts.append(.prompt(GameBoard.Prompt(text: String(localized: "\(players[0]), pick your hand.", comment: "Two players: the first picks while the second looks away"),
                                                  eyebrow: String(localized: "\(players[1]), look away!", comment: "Two players: the other one mustn't see the pick"),
                                                  chip: nil)))
            parts.append(.answers(GameBoard.Answers(tiles: tiles, layout: .row, locked: false)))
        } else if !s.handedOver {
            // The cover: the first hand is in, and nothing here says which.
            parts.append(.prompt(GameBoard.Prompt(text: String(localized: "Pass the Mac to \(players[1]).", comment: "Two players: a hidden pick is in; hand over"),
                                                  eyebrow: String(localized: "\(players[0]), look away!", comment: "Two players: the other one mustn't see the pick"),
                                                  chip: nil)))
            parts.append(.button(GameBoard.Button(label: String(localized: "I'm \(players[1]): ready", comment: "Two players: the second says they have the Mac"),
                                                  move: "ready", style: .primary, symbol: "eye.slash", key: nil, disabled: false)))
        } else {
            parts.append(.prompt(GameBoard.Prompt(text: String(localized: "\(players[1]), pick your hand.", comment: "Two players: the second picks while the first looks away"),
                                                  eyebrow: String(localized: "\(players[0]), look away!", comment: "Two players: the other one mustn't see the pick"),
                                                  chip: nil)))
            parts.append(.answers(GameBoard.Answers(tiles: tiles, layout: .row, locked: false)))
        }
        if s.over {
            let winner = s.you > s.companion ? players[0] : players[1]
            parts.append(.result(GameBoard.Result(
                figure: "\(Toss.number(s.you)) – \(Toss.number(s.companion))",
                line: String(localized: "\(winner) wins the match!", comment: "Two players: the end of rock, paper, scissors, the winner named"),
                ribbon: nil, tone: .neutral, facts: [],
                actions: [GameBoard.Button(label: String(localized: "Rematch", comment: "A button: play the best of three again"), move: "again",
                                           style: .primary, symbol: "arrow.clockwise", key: nil, disabled: false)])))
        } else if s.last != nil {
            parts.append(.button(GameBoard.Button(label: String(localized: "Next round", comment: "A button in rock, paper, scissors"), move: "next",
                                                  style: .primary, symbol: "arrow.right", key: nil, disabled: false)))
        }
        return finish(GameBoard(parts: parts, cue: cue, over: s.over))
    }

    private func finish(_ board: GameBoard) -> GameBoard {
        var board = board
        board.keepOnePrimary()
        return board
    }

    /// "Rock beats scissors: a point for Ana." or "Both rock: a draw."
    static func verdict(_ first: Hand, _ second: Hand, _ players: [String]) -> String {
        if first == second {
            return String(localized: "Both \(first.title): a draw.", comment: "Two players threw the same hand in rock, paper, scissors")
        }
        let (win, lose, name) = first.beats == second ? (first, second, players[0]) : (second, first, players[1])
        return String(localized: "\(win.title) beats \(lose.title): a point for \(name).",
                      comment: "Two players: the winning hand, the losing one, then who gets the point")
    }
}

extension HandsScore {
    /// Two people's head-to-head tally (D96), by their pair of names in either order: wins each, never mixed with the
    /// person's score against the companion.
    struct Duel: Codable, Sendable, Equatable {
        var wins: [String: Int] = [:]
    }

    static let duelsKey = "companion.handsDuels"

    func duel(_ players: [String], winner: Int) async {
        var all = (try? await kvStore?.get(Self.duelsKey, as: [String: Duel].self)) ?? [:]
        let pair = players.sorted().joined(separator: " · ")
        all[pair, default: Duel()].wins[players[winner], default: 0] += 1
        try? await kvStore?.set(Self.duelsKey, all)
    }
}
