import Foundation

/// A whole-text, case-insensitive pattern with named groups. The intent parser is a list of these,
/// tried in a fixed order; anything that matches none of them is left to the AI.
struct Pattern: Sendable {
    private let regex: NSRegularExpression

    init(_ pattern: String) {
        // The patterns are literals in this module; a typo is a programmer error caught by the tests.
        regex = try! NSRegularExpression(pattern: "^(?:" + pattern + ")$", options: [.caseInsensitive])
    }

    func match(_ text: String) -> Captures? {
        let whole = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, options: [], range: whole) else { return nil }
        return Captures(text: text, match: m)
    }
}

struct Captures {
    let text: String
    let match: NSTextCheckingResult

    /// The trimmed text of a named group, or nil when it did not take part or is empty.
    subscript(name: String) -> String? {
        let r = match.range(withName: name)
        guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

extension String {
    /// Upper-cases the first letter only ("send the document" -> "Send the document").
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// Removes one pair of surrounding quotes.
    var unquoted: String {
        let t = trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, let a = t.first, let b = t.last else { return t }
        let pairs: [Character: Character] = ["\"": "\"", "'": "'", "\u{201C}": "\u{201D}", "`": "`"]
        return pairs[a] == b ? String(t.dropFirst().dropLast()) : t
    }
}
