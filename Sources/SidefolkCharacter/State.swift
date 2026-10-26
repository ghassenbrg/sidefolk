import Foundation

/// What the character holds while working, chosen by the running tool's category.
public enum CharacterProp: String, CaseIterable, Sendable {
    case none, notepad, clock, binoculars, folder, globe, laptop, card, book, bell
}

/// The companion states of docs/PRODUCT.md §8. The app picks one by priority; the view shows it.
public enum CharacterState: Equatable, Sendable {
    case idle, sleeping, listening, thinking, working(CharacterProp), waiting, success, error, alert, dragging, celebrating
    /// The microphone is on (the talk key is held): ears up, eyes wide, waves beside the head (D34).
    case hearing

    /// Every state once, with each working prop, in contact-sheet order.
    public static var gallery: [CharacterState] {
        [.idle, .sleeping, .listening, .hearing, .thinking, .waiting, .success, .error, .alert, .dragging, .celebrating]
            + CharacterProp.allCases.map { .working($0) }
    }

    public var name: String {
        switch self {
        case .idle: "idle"
        case .sleeping: "sleeping"
        case .listening: "listening"
        case .hearing: "hearing"
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
    /// What `name` is doing with this prop, for VoiceOver, in the app's language.
    func activity(_ name: String) -> String {
        switch self {
        case .none: String(localized: "\(name) is working")
        case .notepad: String(localized: "\(name) is writing a note")
        case .clock: String(localized: "\(name) is keeping time")
        case .binoculars: String(localized: "\(name) is watching for something")
        case .folder: String(localized: "\(name) is working with files")
        case .globe: String(localized: "\(name) is looking something up on the web")
        case .laptop: String(localized: "\(name) is working with an agent")
        case .card: String(localized: "\(name) is preparing a card")
        case .book: String(localized: "\(name) is reading")
        case .bell: String(localized: "\(name) is ringing a reminder")
        }
    }
}
