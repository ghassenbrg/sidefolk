import Foundation

/// Finding a setting by what it says (D84): every word typed must start a word of the row's title, detail or section,
/// ignoring case, accents and widths, so "quiet" finds "Quiet hours" and "quietly", and "notif" finds "notifications".
/// Titles that match rank first. Pure, so the Settings window and the tests agree.
public enum SettingsSearch {
    public struct Entry: Sendable, Equatable {
        public var id: String
        public var title: String
        public var detail: String
        public var section: String

        public init(id: String, title: String, detail: String = "", section: String = "") {
            self.id = id
            self.title = title
            self.detail = detail
            self.section = section
        }
    }

    /// The entries `query` finds, best first; the order of `entries` breaks ties. An empty query finds nothing.
    public static func find(_ query: String, in entries: [Entry]) -> [Entry] {
        let words = Self.words(query)
        guard !words.isEmpty else { return [] }
        return entries.enumerated().compactMap { index, entry -> (Int, Int, Entry)? in
            let title = Self.words(entry.title), rest = Self.words(entry.detail) + Self.words(entry.section)
            let whole = fold(entry.title + " " + entry.detail + " " + entry.section)
            var score = 0
            for word in words {
                if title.contains(where: { $0.hasPrefix(word) }) { score += 2 } else if rest.contains(where: { $0.hasPrefix(word) }) {
                    score += 1
                } else if Self.unspaced(word), whole.contains(word) {
                    // Japanese, Chinese and Korean words aren't always split where a person would type them.
                    score += 1
                } else { return nil }
            }
            return (score, index, entry)
        }
        .sorted { ($0.0, -$0.1) > ($1.0, -$1.1) }
        .map(\.2)
    }

    /// The ranges of `text` the words of `query` match, for highlighting.
    public static func matches(of query: String, in text: String) -> [Range<String.Index>] {
        let words = Self.words(query)
        guard !words.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { word, range, _, _ in
            guard let word else { return }
            let folded = fold(word)
            guard let match = words.filter({ folded.hasPrefix($0) }).max(by: { $0.count < $1.count }) else { return }
            // The matched prefix in the original text: as many characters as the folded word's prefix.
            let end = text.index(range.lowerBound, offsetBy: min(match.count, text.distance(from: range.lowerBound, to: range.upperBound)))
            found.append(range.lowerBound..<end)
        }
        return found
    }

    /// Written without spaces between words (CJK and after): matched anywhere, not only at a word's start.
    static func unspaced(_ word: String) -> Bool { word.unicodeScalars.contains { $0.value >= 0x2E80 } }

    static func words(_ text: String) -> [String] {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { word, _, _, _ in
            if let word { words.append(fold(word)) }
        }
        return words
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
