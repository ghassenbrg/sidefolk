import Foundation

/// Talking by clicking the microphone (D232): one click turns it on, the person's second click or Return sends. Only the
/// person's own click on the button starts it: nothing else in the app has a way in (T64). Anything else that ends it,
/// the minute running out, the panel closing, the person leaving Sidefolk, the Mac sleeping or locking, stops the
/// microphone and leaves what was heard in the Say field, unsent: sending is the person's to do.
public struct VoiceToggle: Sendable, Equatable {
    public enum Event: Sendable, Equatable {
        /// The microphone button, clicked by the person; `replyPlaying` when a spoken answer is still being said.
        case click(replyPlaying: Bool)
        case returnKey
        case escape
        case timeUp
        case panelClosed
        case leftSidefolk
        case sleptOrLocked
    }

    public enum Action: Sendable, Equatable {
        case none
        /// The answer being said stops; the microphone stays off until the next click.
        case silence
        case listen
        case send
        /// Esc: the microphone stops and nothing is kept.
        case cancel
        /// The microphone stops; what was heard waits in the field for the person to send or clear.
        case stopKeepingWords
    }

    /// The longest one click listens.
    public static let limit: Duration = .seconds(60)

    public private(set) var listening = false

    public init() {}

    public mutating func handle(_ event: Event) -> Action {
        guard listening else {
            guard case .click(let replyPlaying) = event else { return .none }
            if replyPlaying { return .silence }
            listening = true
            return .listen
        }
        listening = false
        switch event {
        case .click, .returnKey: return .send
        case .escape: return .cancel
        case .timeUp, .panelClosed, .leftSidefolk, .sleptOrLocked: return .stopKeepingWords
        }
    }

    /// Talking ended some other way (the talk key, a failure): the next click starts afresh.
    public mutating func reset() { listening = false }
}
