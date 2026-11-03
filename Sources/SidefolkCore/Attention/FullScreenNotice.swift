import Foundation

/// When the person keeps the companion off full-screen apps (D138), what happens while they're in one and something needs them.
public enum FullScreenNotice: String, Codable, Sendable, CaseIterable {
    /// It comes to that space, says it, and goes back once it's answered or left alone for a while.
    case companion
    /// A notification through the Mac, from Sidefolk: the least in the way that still reaches them.
    case menuBar
    /// Nothing until they leave: it waits in the count.
    case silent

    /// How something is shown right now.
    public enum Route: Sendable, Equatable {
        case asUsual
        /// The companion visits the full-screen space for it.
        case visit
        /// A notification now; the card or slip waits until they leave.
        case notify
        /// It waits until they leave.
        case wait
    }

    /// `whisper`: it needs nothing from them, so it isn't worth interrupting for, whichever they chose.
    public static func route(hidesOverFullScreen: Bool, inFullScreen: Bool, notice: FullScreenNotice, whisper: Bool) -> Route {
        guard hidesOverFullScreen, inFullScreen else { return .asUsual }
        if whisper { return .wait }
        return switch notice {
        case .companion: .visit
        case .menuBar: .notify
        case .silent: .wait
        }
    }
}
