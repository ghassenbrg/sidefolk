/// What the character holds while working, chosen by the running tool's category.
public enum CharacterProp: String, CaseIterable, Sendable {
    case none, notepad, clock, binoculars, folder, globe, laptop, card, book, bell
}

/// The companion states of docs/PRODUCT.md §8. The app picks one by priority; the view shows it.
public enum CharacterState: Equatable, Sendable {
    case idle, sleeping, listening, thinking, working(CharacterProp), waiting, success, error, alert, dragging, celebrating

    /// Every state once, with each working prop, in contact-sheet order.
    public static var gallery: [CharacterState] {
        [.idle, .sleeping, .listening, .thinking, .waiting, .success, .error, .alert, .dragging, .celebrating]
            + CharacterProp.allCases.map { .working($0) }
    }

    public var name: String {
        switch self {
        case .idle: "idle"
        case .sleeping: "sleeping"
        case .listening: "listening"
        case .thinking: "thinking"
        case .working(let prop): prop == .none ? "working" : "working · \(prop.rawValue)"
        case .waiting: "waiting"
        case .success: "success"
        case .error: "error"
        case .alert: "alert"
        case .dragging: "dragging"
        case .celebrating: "celebrating"
        }
    }
}

/// One-shot moves layered over the current state.
public enum CharacterGesture: Sendable {
    case wave, hop, nod, shake, lookAround, blink
}

/// Small ambient markers beside the character.
public enum CharacterBadge: Hashable, Sendable {
    case watching, busy, count(Int)
}

extension CharacterProp {
    /// What the character is doing with this prop, for VoiceOver.
    var activity: String {
        switch self {
        case .none: "working"
        case .notepad: "writing a note"
        case .clock: "keeping time"
        case .binoculars: "watching for something"
        case .folder: "working with files"
        case .globe: "looking something up on the web"
        case .laptop: "working with an agent"
        case .card: "preparing a card"
        case .book: "reading"
        case .bell: "ringing a reminder"
        }
    }
}
