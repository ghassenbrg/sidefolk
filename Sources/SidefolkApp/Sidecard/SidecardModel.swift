import AppKit
import SidefolkCore

/// What the Sidecard shows above the companion right now (D84): one moment at a time, in the size its importance
/// asks for. Ask is its largest size and lives in the Ask panel; this is the whisper, the card and the stack.
@MainActor @Observable
final class SidecardModel {
    enum Shape: Equatable {
        /// One line for six seconds, a thin line along its foot running out the time.
        case whisper
        /// A title, a few lines and up to three actions; it stays until answered, or folds into the stack.
        case card
        /// What waits, fanned: the top three, the newest in front.
        case stack
    }

    var item: AttentionItem?
    var shape: Shape = .whisper
    /// The held cards the stack fans out, newest last.
    var stack: [AttentionItem] = []
    /// How many wait in all, for the stack's "+n more".
    var waiting = 0
    /// When the whisper goes, and how long it was given; nil while the pointer holds it.
    var deadline: Date?
    var whisperSeconds: TimeInterval = AttentionPolicy.gentleSeconds
    /// Time left when the pointer came, kept while it stays.
    var pausedLeft: TimeInterval?
    var hovering = false
    /// Where the tail meets the card along its bottom edge, 0 to 1 in reading order; nil when it sits below.
    var tailAt: CGFloat? = 0.5
    /// The agent sessions Sidefolk follows, by id, so a session's notice says whose it is.
    var sessions: [String: AgentSession] = [:]
    /// The companion speaking for itself: its face and name.
    var face: NSImage?
    var companionName = "Sidefolk"

    var respond: ((AttentionItem, String?) -> Void)?
    /// A whisper clicked: it grows into a card in place.
    var grow: (() -> Void)?
    /// The stack clicked: Ask opens on top of it.
    var openStack: (() -> Void)?

    /// The share of the whisper's time left, 1 to 0, at `now`.
    func timeLeft(at now: Date) -> Double {
        if let pausedLeft { return pausedLeft / whisperSeconds }
        guard let deadline else { return 1 }
        return max(0, deadline.timeIntervalSince(now)) / whisperSeconds
    }
}
