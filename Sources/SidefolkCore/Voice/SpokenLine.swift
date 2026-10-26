import Foundation
import NaturalLanguage

/// The one short line the companion says aloud (D34): it passes the one-breath test, and never reads
/// a URL, a path or code. Everything else stays on the screen, where it is shown as well.
public enum SpokenLine {
    /// About one breath.
    public static let maxWords = 24
    /// Languages written without spaces get a character budget instead.
    static let maxCharacters = 60

    /// Said when nothing in the answer can be read out (only a link or code).
    public static var onScreen: String {
        String(localized: "It's on the screen.", comment: "Said aloud when the answer is only a link or code")
    }

    /// An AI answer: the count and first item of a list, otherwise its first sentence that still says
    /// something once links, paths and code are taken out.
    /// - Parameter appLanguage: the language the app's own words are in ("en", "fr").
    public static func answer(_ text: String, appLanguage: String = Bundle.main.preferredLocalizations.first ?? "en") -> String {
        let plain = text.replacingOccurrences(of: "```[\\s\\S]*?(```|$)", with: "\n", options: .regularExpression)
        let lines = plain.components(separatedBy: .newlines)
        let items = lines.compactMap(listItem)
        if items.count >= 2 {
            if speaks(text, appLanguage) { return list(count: items.count, first: items[0]) }
            // "3 things. First:" would be in the app's language, not the answer's: its own lead-in, or its first item.
            let lead = lines.prefix { listItem($0) == nil }.joined(separator: "\n")
            return first(in: lead) ?? first(in: items[0]) ?? onScreen
        }
        return first(in: lines.joined(separator: "\n")) ?? onScreen
    }

    /// The first sentence that still says something once made speakable (links go first: their
    /// "?" and "." would end a sentence).
    private static func first(in text: String) -> String? {
        for sentence in Sentences.split(speakable(text)) {
            let spoken = speakable(sentence)
            if says(spoken) { return clipped(spoken) }
        }
        return nil
    }

    /// Whether `text` is written in `language` (when that can be told).
    private static func speaks(_ text: String, _ language: String) -> Bool {
        guard let detected = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue else { return true }
        func code(_ id: String) -> Substring { id.prefix { $0 != "-" && $0 != "_" } }
        return code(detected) == code(language)
    }

    /// What a result card says: what happened, and when for a reminder ("Stretch, today 17:00.").
    public static func card(_ card: ResultCard) -> String {
        var parts = [card.title]
        if card.kind == .reminder, let when = card.subtitle { parts.append(when) }
        let spoken = speakable(parts.joined(separator: ", "))
        return says(spoken) ? clipped(spoken) : onScreen
    }

    /// Several results: how many, and the first.
    public static func list(title: String, cards: [ResultCard]) -> String {
        guard let first = cards.first else { return line(title) }
        return cards.count == 1 ? card(first) : list(count: cards.count, first: first.title)
    }

    /// Any other line (a question back, an error): its first sentence, made speakable.
    public static func line(_ text: String) -> String {
        answer(text)
    }

    static func list(count: Int, first: String) -> String {
        let item = speakable(first)
        guard says(item) else { return onScreen }
        return clipped(String(localized: "\(count) things. First: \(item)", comment: "Said aloud for a list: how many, then the first one"))
    }

    // MARK: Making text speakable

    /// Links become their site, paths their last name, code disappears; markdown marks go.
    static func speakable(_ text: String) -> String {
        var s = unmark(text)
        // [label](https://…) reads as its label.
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "`[^`]*`", with: " ", options: .regularExpression)
        s = replace(in: s, pattern: "\\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\\s<>()\"']+") { site(of: $0) }
        s = replace(in: s, pattern: "\\b(www\\.)?([a-zA-Z0-9-]+\\.)+[a-zA-Z]{2,}/[^\\s<>()\"']*") { site(of: "https://" + $0) }
        s = replace(in: s, pattern: "(?<![\\w])(~|\\.{1,2})?/[^\\s,;:!?)\"']*") { name(of: $0) }
        // Lines stay lines (a line without a full stop still ends a sentence).
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " ([.,;:!?])", with: "$1", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:")))
    }

    /// "example.com" for any link to it.
    private static func site(of link: String) -> String {
        let trimmed = link.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        guard let host = URL(string: trimmed)?.host, !host.isEmpty else { return " " }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "Invoices" for ~/Downloads/Invoices, "notes" for /tmp/notes.txt.
    private static func name(of path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?/"))
        let last = (trimmed as NSString).lastPathComponent
        let bare = (last as NSString).deletingPathExtension
        return bare.isEmpty || bare == "~" ? " " : bare
    }

    private static func unmark(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "(\\*\\*|__|~~)", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s{0,3}(#{1,6}|>)\\s*", with: "", options: .regularExpression)
        // *emphasis* (a lone asterisk between words is left alone).
        return s.replacingOccurrences(of: "(?<![\\w*])\\*([^*\\n]+)\\*(?![\\w*])", with: "$1", options: .regularExpression)
    }

    /// The text of a bulleted or numbered line, if it is one.
    private static func listItem(_ line: String) -> String? {
        let pattern = "^\\s*([-*•]|\\d{1,2}[.)])\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 2), in: line) else { return nil }
        let item = String(line[range]).trimmingCharacters(in: .whitespaces)
        return item.isEmpty ? nil : item
    }

    private static func replace(in text: String, pattern: String, with transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }

    /// Something worth saying: two words, or a few letters in a script written without spaces (a
    /// site's name alone is not an answer).
    private static func says(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).filter { $0.contains { $0.isLetter || $0.isNumber } }.count
        let unspaced = text.unicodeScalars.filter { $0.properties.isIdeographic || (0x3040...0x30FF).contains($0.value)
            || (0x0E00...0x0E7F).contains($0.value) }.count
        return words >= 2 || unspaced >= 2
    }

    /// One breath: up to `maxWords`, cut at a comma or semicolon when there is one late enough.
    static func clipped(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        if words.count <= 1 {
            guard text.count > maxCharacters else { return text }
            let head = text.prefix(maxCharacters)
            if let pause = head.lastIndex(where: { "、，,;".contains($0) }), head.distance(from: head.startIndex, to: pause) > 10 {
                return String(head[..<pause]) + "。"
            }
            return String(head)
        }
        guard words.count > maxWords else { return text }
        let kept = words.prefix(maxWords)
        if let pause = kept.lastIndex(where: { $0.hasSuffix(",") || $0.hasSuffix(";") || $0.hasSuffix(":") }), pause >= 4 {
            return String(kept[...pause].joined(separator: " ").dropLast()) + "."
        }
        return kept.joined(separator: " ") + "…"
    }
}
