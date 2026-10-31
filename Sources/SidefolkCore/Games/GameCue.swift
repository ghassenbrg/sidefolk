import Foundation

/// How a game asks the companion to react (D75): a move, an effect, a prop, a line, a sound and where to look, each
/// named from a fixed list. A game can name a mood, never drive the rig, move the window, open a bubble or say words of
/// its own: a `line` is a key, and Sidefolk says one of its own written lines for it in the person's language.
public struct GameCue: Sendable, Hashable {
    public var move: Move?
    public var effect: Effect?
    public var prop: Prop?
    public var line: Line?
    public var sound: GameSound?
    public var look: Look?

    public init(move: Move? = nil, effect: Effect? = nil, prop: Prop? = nil, line: Line? = nil, sound: GameSound? = nil, look: Look? = nil) {
        self.move = move
        self.effect = effect
        self.prop = prop
        self.line = line
        self.sound = sound
        self.look = look
    }

    public enum Move: String, Sendable, Hashable, CaseIterable {
        case think, cheer, celebrate, sulk, bow, nod, shrug, giggle, wince, gasp, tease, sweat, dizzy, ready, shuffle, hop, spin, wave, dance
        /// Short versions for fast games (Copy Me): `accent:wave`.
        case accentWave = "accent:wave", accentHop = "accent:hop", accentSpin = "accent:spin", accentBow = "accent:bow"
    }

    public enum Effect: String, Sendable, Hashable, CaseIterable {
        case confetti, sparkles, hearts, question, exclaim, sweat, stars, frost, flame

        /// What Reduce Motion drops: things that fall, spin or drift across.
        public var moves: Bool { self == .confetti || self == .stars || self == .frost }
    }

    public enum Prop: Sendable, Hashable {
        case balloons(Int)
        case hat, crown, magnifier, cards, sealedCard, gem
        /// Puts away what it holds.
        case none

        static func parse(_ text: String) -> Prop? {
            switch text {
            case "hat": .hat
            case "crown": .crown
            case "magnifier": .magnifier
            case "cards": .cards
            case "sealed_card": .sealedCard
            case "gem": .gem
            case "none": Prop.none
            default:
                // balloons(7)
                text.wholeMatch(of: /balloons\((\d)\)/).flatMap { Int($0.1) }.flatMap { (1...9).contains($0) ? .balloons($0) : nil }
            }
        }
    }

    /// Keys for Sidefolk's own lines (`GameLines`); never text.
    public enum Line: String, Sendable, Hashable, CaseIterable {
        case hello, yourTurn = "your_turn", myTurn = "my_turn", thinking, closeOne = "close_one", youWin = "you_win", iWin = "i_win", draw,
             record, streak, encourage, tease, caughtCheating = "caught_cheating", hintIntro = "hint_intro", bye
    }

    public enum Look: Sendable, Hashable {
        case panel, you, away
        case cell(row: Int, column: Int)
    }

    /// Reads `{move, effect, prop, line, sound, look}`: a value off its list is dropped, the rest kept.
    public static func parse(_ j: JSONValue) -> GameCue? {
        guard j.objectValue != nil else { return nil }
        var cue = GameCue()
        cue.move = j["move"]?.stringValue.flatMap(Move.init(rawValue:))
        cue.effect = j["effect"]?.stringValue.flatMap(Effect.init(rawValue:))
        cue.prop = j["prop"]?.stringValue.flatMap(Prop.parse)
        cue.line = j["line"]?.stringValue.flatMap(Line.init(rawValue:))
        cue.sound = j["sound"]?.stringValue.flatMap(GameSound.init(rawValue:))
        if let look = j["look"] {
            if let a = look.arrayValue, a.count == 2, let r = a[0].intValue, let c = a[1].intValue, (0..<8).contains(r), (0..<8).contains(c) {
                cue.look = .cell(row: r, column: c)
            } else {
                cue.look = switch look.stringValue {
                case "panel": .panel
                case "you": .you
                case "away": .away
                default: nil
                }
            }
        }
        return cue == GameCue() ? nil : cue
    }
}

/// The app's game sounds (D75). Extensions only name them; Sidefolk owns and plays them, at a fixed volume.
public enum GameSound: String, Sendable, Hashable, CaseIterable {
    case tap, flip, rattle, pop, ding, boop, tick, whoosh, stamp, shuffle, snap, cork, fanfare, trombone
}

/// How often cues may act (D75), so a game can't make the companion flail or chatter: a move every 0.8 s at most, a
/// newer one replacing one still waiting; a line every 2 s; four sounds a second. Pure timing, so it is tested
/// without a clock; the app asks it before acting on each part of a cue.
public struct CueLimiter: Sendable {
    public static let moveGap: TimeInterval = 0.8
    public static let lineGap: TimeInterval = 2
    public static let soundsPerSecond = 4

    private var lastMove: Date?
    private var lastLine: Date?
    private var sounds: [Date] = []
    /// A move that came too soon, played when its turn comes (a newer one takes its place).
    public private(set) var waitingMove: GameCue.Move?

    public init() {}

    public enum MoveVerdict: Equatable, Sendable {
        case now
        /// Play it after this many seconds, unless another move replaces it.
        case after(TimeInterval)
    }

    public mutating func move(_ move: GameCue.Move, at now: Date) -> MoveVerdict {
        if let last = lastMove, now.timeIntervalSince(last) < Self.moveGap {
            waitingMove = move
            return .after(Self.moveGap - now.timeIntervalSince(last))
        }
        lastMove = now
        waitingMove = nil
        return .now
    }

    /// The waiting move, if it is still the one to play; marks it played.
    public mutating func takeWaiting(_ move: GameCue.Move, at now: Date) -> Bool {
        guard waitingMove == move else { return false }
        waitingMove = nil
        lastMove = now
        return true
    }

    public mutating func line(at now: Date) -> Bool {
        if let last = lastLine, now.timeIntervalSince(last) < Self.lineGap { return false }
        lastLine = now
        return true
    }

    public mutating func sound(at now: Date) -> Bool {
        sounds = sounds.filter { now.timeIntervalSince($0) < 1 }
        guard sounds.count < Self.soundsPerSecond else { return false }
        sounds.append(now)
        return true
    }
}
