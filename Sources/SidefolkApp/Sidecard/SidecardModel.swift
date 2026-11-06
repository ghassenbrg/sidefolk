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
    /// The held cards are out of the shoulder (true) or folding back into it, and the way to it from the stack's foot
    /// (D84's arc); no way with Reduce Motion, so they simply stand.
    var stackOut = true
    var fanFrom: CGSize?
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
    /// The card in front took the keyboard from its shortcut (D84): which answer has the focus and where it stands among
    /// the held cards. Nil while the card only shows, which is almost always.
    var keys: CardKeys?
    /// The held card the keyboard is on while the stack is fanned from the shortcut.
    var stackFocus: String?
    /// Bumped when Return met a firm card, so the ⌘↩ hint says so once more.
    var keysNudge = 0
    /// The companion speaking for itself: its face and name.
    var face: NSImage?
    var companionName = "Sidefolk"

    /// How far each source may interrupt (D88), for the card's "Fewer like this".
    var interruptions = Interruptions()

    var respond: ((AttentionItem, String?) -> Void)?
    /// The card's ⋯ asked for fewer notices like it: its source goes to this level.
    var lowerSource: ((AttentionItem, InterruptSource, InterruptLevel) -> Void)?
    /// A whisper clicked: it grows into a card in place.
    var grow: (() -> Void)?
    /// The card changed its height (its message opened or closed): the window fits it again.
    var refit: (() -> Void)?
    /// The stack clicked: Ask opens on top of it.
    var openStack: (() -> Void)?

    /// The share of the whisper's time left, 1 to 0, at `now`.
    func timeLeft(at now: Date) -> Double {
        if let pausedLeft { return pausedLeft / whisperSeconds }
        guard let deadline else { return 1 }
        return max(0, deadline.timeIntervalSince(now)) / whisperSeconds
    }
}
