import Foundation

/// How a scene's words and names are read: every text is the extension's, cleaned and clipped here.
enum SceneReading {
    /// One line of at most so many characters.
    static func line(_ j: JSONValue?, _ characters: Int) -> String? { ExtensionPage.text(j, characters) }

    /// Text that may hold a line break or two, cleaned and capped.
    static func long(_ j: JSONValue?, _ characters: Int) -> String? {
        guard let raw = j?.stringValue else { return nil }
        let text = ExtensionText.clip(ExtensionText.shown(raw).replacingOccurrences(of: "\t", with: " "), characters)
        return text.isEmpty ? nil : text
    }

    /// A small name the extension chose (an area, a timer, a key): lowercase letters, digits, `_` and `-`.
    static func token(_ j: JSONValue?) -> String? {
        guard let s = j?.stringValue, s.range(of: #"^[a-z0-9][a-z0-9_-]{0,39}$"#, options: .regularExpression) != nil else { return nil }
        return s
    }
}

/// What a scene's end meant for the person, for the one row in History (D99, D78: a loss is never the danger red).
public enum SceneOutcome: String, Sendable, Hashable, CaseIterable {
    case win, loss, draw
}
