import Foundation

/// Whether the companion is on the desktop. The person's last Show or Hide (menu bar, Pocket, shortcut) stands until
/// they change "Where it lives"; before that, and after, the setting decides. Settings are written all the time (a
/// checked update, a theme, a skipped version), and each write re-applies the companion: without this, the person's Hide
/// came back on the next write, and a Show from a menu-bar-only Mac vanished on it while the menu still said "Hide".
public struct CompanionVisibility: Sendable, Equatable {
    public struct Decision: Sendable, Equatable {
        public var visible: Bool
        /// How it lives while shown. A companion the person asked for is out, not tucked away or a menu bar icon only.
        public var presence: PresenceMode
    }

    private struct Choice: Sendable, Equatable {
        var visible: Bool
        var under: PresenceMode
    }

    private var choice: Choice?

    public init() {}

    /// The person's Show or Hide, made while the setting was `presence`.
    public mutating func choose(visible: Bool, under presence: PresenceMode) {
        choice = Choice(visible: visible, under: presence)
    }

    public func decide(presence: PresenceMode) -> Decision {
        guard let choice, choice.under == presence else {
            return Decision(visible: presence != .menuBarOnly, presence: presence)
        }
        return Decision(visible: choice.visible, presence: .always)
    }
}
