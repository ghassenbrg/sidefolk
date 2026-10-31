import Foundation

/// The light at the companion's feet (D84, Lantern): what is going on, readable from across the room before a word is
/// read. One state at a time, by what matters most to the person; the app draws it as the light pool and the mark on
/// the companion's shoulder.
public enum DesktopLight: Sendable, Equatable {
    /// Nothing to say: no light.
    case idle
    /// Something runs for the person (a tool, the AI thinking, the microphone listening): the light breathes.
    case working
    /// Things wait for an answer, folded into the count on the shoulder: steady amber.
    case waiting(Int)
    /// A card is out asking now: one amber pulse, then steady, with the count.
    case alert(Int)
    /// Something just failed: a still red light, for as long as the companion looks sorry about it.
    case failed
    /// Focus: a dim grey light, Focus's half circle on the shoulder, or how many wait (held whispers too) in grey.
    case focus(Int)
    /// Quiet mode: no light, a moon on the shoulder; what waits is told when it ends.
    case quiet(Int)

    /// - Parameters:
    ///   - waiting: what waits on the person: open notices that need an answer, and approvals.
    ///   - cardOut: a card (not a whisper) is out beside the companion right now.
    ///   - held: whispers Focus holds until it ends.
    public static func of(pose: CompanionPose, waiting: Int, cardOut: Bool, quiet: Bool, focus: Bool = false, held: Int = 0) -> DesktopLight {
        if quiet { return .quiet(waiting) }
        if focus { return .focus(waiting + held) }
        if pose == .error { return .failed }
        if waiting > 0 { return cardOut ? .alert(waiting) : .waiting(waiting) }
        switch pose {
        case .working, .thinking, .hearing: return .working
        case .alert: return cardOut ? .alert(0) : .idle
        default: return .idle
        }
    }

    /// How many wait, for the shoulder's count (0 when it shows none).
    public var count: Int {
        switch self {
        case .waiting(let n), .alert(let n), .focus(let n), .quiet(let n): n
        default: 0
        }
    }
}
