import Foundation

extension AttentionItem {
    /// Sources whose cards Return may answer (D84): the person's own reminders and commands, the morning brief,
    /// what waited while they were away, and Sidefolk speaking for itself. Everything else, another app's or an agent
    /// session's question, an extension's notice, `sidefolk notify` from any script, what a watched page said, needs
    /// ⌘Return or a click, so a Return typed for something else can never answer it.
    public static let calmSources: Set<String> = ["reminder", "brief", "job", "summary", "user", "addons", "update", "onboarding", "companion"]

    /// Return answers this card when it has the keyboard; otherwise only ⌘Return does.
    public var takesReturn: Bool { Self.calmSources.contains(source) }
}

/// The keyboard on the card beside the companion (D84): which answer has the focus, what the keys do, and which held
/// card ↑/↓ brings to the front. It only decides; the desktop shows the focus and answers.
public struct CardKeys: Sendable, Equatable {
    public enum Key: Sendable, Equatable {
        case enter(command: Bool)
        case escape
        case left, right
        case tab(back: Bool)
        case up, down
    }

    public enum Outcome: Sendable, Equatable {
        /// Press this answer (its id, as the card lists it).
        case press(String)
        /// Esc: the card goes back to the stack (or away, when nothing holds it).
        case putAway
        /// Bring this held card to the front.
        case show(String)
        /// The focus moved to another answer.
        case moved
        /// Return on a firm card: only ⌘Return answers it.
        case needsCommand
        case ignored
    }

    /// The card's answers in reading order, leading to trailing: what the card shows, the main one last.
    public var answers: [String]
    public var focused: Int
    public var takesReturn: Bool
    /// The held cards, oldest first, and the one in front (nil when it isn't among them, as onboarding's lines).
    public var deck: [String]
    public var current: String?
    /// ←/→ follow the screen: in right-to-left languages the row is mirrored, so ← moves toward the trailing end.
    public var rightToLeft: Bool

    public init(answers: [String], main: String?, takesReturn: Bool, deck: [String] = [], current: String? = nil, rightToLeft: Bool = false) {
        self.answers = answers
        focused = main.flatMap { answers.firstIndex(of: $0) } ?? max(0, answers.count - 1)
        self.takesReturn = takesReturn
        self.deck = deck
        self.current = current
        self.rightToLeft = rightToLeft
    }

    public var focusedAnswer: String? { answers.indices.contains(focused) ? answers[focused] : nil }

    /// "2 of 4": where the card in front stands among the held ones, when there is more than one.
    public var position: (index: Int, count: Int)? {
        guard deck.count > 1, let current, let i = deck.firstIndex(of: current) else { return nil }
        return (i + 1, deck.count)
    }

    public mutating func press(_ key: Key) -> Outcome {
        switch key {
        case .enter(let command):
            guard let answer = focusedAnswer else { return .ignored }
            return command || takesReturn ? .press(answer) : .needsCommand
        case .escape:
            return .putAway
        case .left:
            return move(rightToLeft ? 1 : -1, wrap: false)
        case .right:
            return move(rightToLeft ? -1 : 1, wrap: false)
        case .tab(let back):
            return move(back ? -1 : 1, wrap: true)
        case .up, .down:
            // Up goes to the older cards, as the stack lists them above the newer ones.
            guard let current, let i = deck.firstIndex(of: current) else { return .ignored }
            let next = i + (key == .up ? -1 : 1)
            guard deck.indices.contains(next) else { return .ignored }
            return .show(deck[next])
        }
    }

    private mutating func move(_ step: Int, wrap: Bool) -> Outcome {
        guard answers.count > 1 else { return .ignored }
        var next = focused + step
        if wrap { next = (next + answers.count) % answers.count }
        guard answers.indices.contains(next) else { return .ignored }
        focused = next
        return .moved
    }
}
