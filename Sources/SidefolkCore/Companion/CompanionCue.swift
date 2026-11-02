import Foundation

/// How a surface may ask the companion to react (D75, D99): a move, an effect or a prop, each named from a fixed list. It can name a
/// mood, never drive the rig, move the window, open a bubble or say words.
public enum CompanionCue {
    public enum Move: String, Sendable, Hashable, CaseIterable {
        case think, cheer, celebrate, sulk, bow, nod, shrug, giggle, wince, gasp, tease, sweat, dizzy, ready, shuffle, hop, spin, wave, dance
        /// Short versions for fast choreography: `accent:wave`.
        case accentWave = "accent:wave", accentHop = "accent:hop", accentSpin = "accent:spin", accentBow = "accent:bow"

        var isAccent: Bool { rawValue.hasPrefix("accent:") }
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
}

/// How often reactions may act (D75), so a surface can't make the companion flail: a move every 0.8 s at most, a newer one
/// replacing one still waiting; four sounds a second. Pure timing, so it is tested without a clock.
public struct CueLimiter: Sendable {
    public static let moveGap: TimeInterval = 0.8
    public static let soundsPerSecond = 4
    /// The short moves made for fast choreography (`accent:*`) go at the sounds' pace: a sequence being shown is the point, not a mood.
    public static let accentGap: TimeInterval = 1 / Double(soundsPerSecond)

    private var lastMove: Date?
    private var lastAccent: Date?
    private var sounds: [Date] = []
    /// A move that came too soon, played when its turn comes (a newer one takes its place).
    public private(set) var waitingMove: CompanionCue.Move?

    public init() {}

    public enum MoveVerdict: Equatable, Sendable {
        case now
        /// Play it after this many seconds, unless another move replaces it.
        case after(TimeInterval)
    }

    public mutating func move(_ move: CompanionCue.Move, at now: Date) -> MoveVerdict {
        if move.isAccent {
            if let last = lastAccent, now.timeIntervalSince(last) < Self.accentGap {
                waitingMove = move
                return .after(Self.accentGap - now.timeIntervalSince(last))
            }
            lastAccent = now
            waitingMove = nil
            return .now
        }
        if let last = lastMove, now.timeIntervalSince(last) < Self.moveGap {
            waitingMove = move
            return .after(Self.moveGap - now.timeIntervalSince(last))
        }
        lastMove = now
        waitingMove = nil
        return .now
    }

    /// The waiting move, if it is still the one to play; marks it played.
    public mutating func takeWaiting(_ move: CompanionCue.Move, at now: Date) -> Bool {
        guard waitingMove == move else { return false }
        waitingMove = nil
        if move.isAccent { lastAccent = now } else { lastMove = now }
        return true
    }

    public mutating func sound(at now: Date) -> Bool {
        sounds = sounds.filter { now.timeIntervalSince($0) < 1 }
        guard sounds.count < Self.soundsPerSecond else { return false }
        sounds.append(now)
        return true
    }
}
