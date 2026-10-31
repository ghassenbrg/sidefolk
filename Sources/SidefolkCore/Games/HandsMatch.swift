import Foundation
import Synchronization

/// Rock, paper, scissors as a best of three in the Play panel (D75), Sidefolk's own game on the same board model as
/// an extension's. Fairness stays core's (D44): the companion's hand is drawn with the system's generator as each round
/// begins, before the person picks, and kept sealed (its card in the header) until both show; nothing reads the
/// person's hand to choose it. Now and then it bluffs before a round ("I'm going rock…"), naming a hand drawn apart
/// from the one it holds, so the bluff is true about a third of the time, as a real one would be.
public final class HandsMatch: GameProvider {
    public let info = GameInfo.handsMatch
    /// Rounds to win the match.
    public static let toWin = 2

    /// Where the match stands; public for the UI snapshots, which draw each moment of it.
    public struct State: Sendable {
        var round = 1
        var you = 0
        var companion = 0
        /// The last throw, while its result shows.
        var last: (you: Hand, companion: Hand)?
        /// The companion's hand for the round under way, drawn when it began and sealed until the person picks.
        var sealed: Hand?
        var over: Bool { you >= HandsMatch.toWin || companion >= HandsMatch.toWin }

        public init(round: Int = 1, you: Int = 0, companion: Int = 0, last: (you: Hand, companion: Hand)? = nil, sealed: Hand? = nil) {
            self.round = round
            self.you = you
            self.companion = companion
            self.last = last
            self.sealed = sealed
        }
    }

    private let state = Mutex(State())
    private let score: HandsScore
    private let companionName: String
    /// A whole number in the range: the system's generator, or a script in tests.
    private let random: @Sendable (ClosedRange<Int>) -> Int

    init(score: HandsScore, companionName: String, random: @escaping @Sendable (ClosedRange<Int>) -> Int = { Int.random(in: $0) }) {
        self.score = score
        self.companionName = companionName
        self.random = random
    }

    /// The match the app plays, its score added to the one kept since D44.
    public convenience init(db: AppDatabase?, companionName: String) {
        self.init(score: HandsScore(kv: db.map(KVStore.init)), companionName: companionName)
    }

    public func start(_ setup: GameSetup) async throws -> GameBoard {
        let sealed = draw()
        let s = state.withLock { s -> State in
            s = State(sealed: sealed)
            return s
        }
        return board(s, cue: GameCue(move: .ready, line: .hello, look: .panel))
    }

    /// The companion's hand for a round: uniform, from the system's generator (a script in tests), never looking at
    /// the person's.
    private func draw() -> Hand { Hand.allCases[random(0...2)] }

    /// The hand the companion holds for the round under way, sealed (tests check it is fixed before the move).
    var sealedHand: Hand? { state.withLock { $0.sealed } }

    public func move(_ move: GameMove) async throws -> GameBoard {
        switch move {
        case .answer(let i) where Hand.allCases.indices.contains(i):
            guard let mine = state.withLock({ $0.last == nil && !$0.over ? $0.sealed : nil }) else { return current() }
            let you = Hand.allCases[i]
            _ = await score.record(person: you, companion: mine)
            let s = state.withLock { s -> State in
                s.last = (you, mine)
                s.sealed = nil
                if you.beats == mine { s.you += 1 } else if mine.beats == you { s.companion += 1 }
                return s
            }
            return board(s, cue: reaction(s, you: you, mine: mine))
        case .button("next"):
            guard state.withLock({ $0.last != nil && !$0.over }) else { return current() }
            let sealed = draw()
            // A bluff now and then, before the count: a wink and a hand named at random, apart from the one it holds.
            let bluff: Hand? = random(0...2) == 0 ? Hand.allCases[random(0...2)] : nil
            let s = state.withLock { s -> State in
                s.last = nil
                s.round += 1
                s.sealed = sealed
                return s
            }
            var next = board(s, cue: bluff == nil ? GameCue(move: .ready, look: .panel) : GameCue(move: .tease, look: .you))
            next.said = bluff.map(Self.bluff)
            return next
        case .button("again"):
            return try await start(GameSetup())
        default:
            return current()
        }
    }

    public func end(_ reason: GameEndReason) async {}

    private func current() -> GameBoard { board(state.withLock { $0 }, cue: nil) }

    /// After a throw: a round is a small moment, the match a big one.
    private func reaction(_ s: State, you: Hand, mine: Hand) -> GameCue {
        if s.over {
            return s.you > s.companion ? GameCue(move: .bow, effect: .confetti, line: .youWin, sound: .fanfare)
                : GameCue(move: .celebrate, prop: .crown, line: .iWin, sound: .fanfare)
        }
        if you == mine { return GameCue(move: .shrug, line: .draw, sound: .boop) }
        return you.beats == mine ? GameCue(move: .gasp, sound: .snap) : GameCue(move: .giggle, line: .tease, sound: .snap)
    }

    public func board(_ s: State, cue: GameCue?) -> GameBoard {
        var parts: [GameBoard.Part] = [.score(GameBoard.Score(you: s.you, companion: s.companion, streak: nil, best: nil, rounds: Self.toWin,
                                                              companionPicked: s.sealed != nil))]
        let tiles = Hand.allCases.map { hand -> GameBoard.Answers.Tile in
            var state = GameBoard.Answers.State.none
            if let last = s.last {
                // The person's hand shows how it went; the companion's carries its face; the third steps back.
                state = hand == last.you ? (last.you.beats == last.companion ? .right : last.companion.beats == last.you ? .wrong : .picked)
                    : hand == last.companion ? .none : .faded
            }
            return GameBoard.Answers.Tile(label: hand.title, state: state, companion: s.last?.companion == hand, art: GameArt(rawValue: hand.rawValue))
        }
        if let last = s.last {
            parts.append(.reveal(.hands(you: last.you, companion: last.companion)))
            parts.append(.prompt(GameBoard.Prompt(text: Toss.hands(person: last.you, companion: last.companion).result,
                                                  eyebrow: Self.roundTitle(s.round), chip: nil)))
        } else {
            parts.append(.prompt(GameBoard.Prompt(text: String(localized: "Rock, paper or scissors?", comment: "The best of three asks for the person's hand"),
                                                  eyebrow: Self.roundTitle(s.round), chip: nil)))
        }
        parts.append(.answers(GameBoard.Answers(tiles: tiles, layout: .row, locked: s.last != nil)))
        if s.over {
            let won = s.you > s.companion
            parts.append(.result(GameBoard.Result(
                figure: "\(Toss.number(s.you)) – \(Toss.number(s.companion))",
                line: won ? String(localized: "You win the match!", comment: "The end of rock, paper, scissors: the person won")
                    : String(localized: "\(companionName) wins the match.", comment: "The end of rock, paper, scissors: the companion (named) won"),
                ribbon: nil, tone: won ? .good : .bad, facts: [],
                actions: [GameBoard.Button(label: String(localized: "Rematch", comment: "A button: play the best of three again"), move: "again",
                                           style: .primary, symbol: "arrow.clockwise", key: nil, disabled: false)])))
        } else if s.last != nil {
            parts.append(.button(GameBoard.Button(label: String(localized: "Next round", comment: "A button in rock, paper, scissors"), move: "next",
                                                  style: .primary, symbol: "arrow.right", key: nil, disabled: false)))
        }
        var board = GameBoard(parts: parts, cue: cue, over: s.over)
        board.keepOnePrimary()
        return board
    }

    static func roundTitle(_ round: Int) -> String {
        String(localized: "Round \(round)", comment: "Rock, paper, scissors: which round of the best of three")
    }

    static func bluff(_ hand: Hand) -> String {
        switch hand {
        case .rock: String(localized: "I'm going rock…", comment: "The companion bluffs before a round of rock, paper, scissors")
        case .paper: String(localized: "I'm going paper…", comment: "The companion bluffs before a round of rock, paper, scissors")
        case .scissors: String(localized: "I'm going scissors…", comment: "The companion bluffs before a round of rock, paper, scissors")
        }
    }
}
