import Foundation

/// Something Settings › Extensions lists that can be searched and filtered: an installed extension or MCP
/// server, or a built-in this Mac can't run.
public protocol ExtensionListEntry {
    /// Switched on and running its tools. A built-in that can't run counts as off.
    var isOn: Bool { get }
    /// What a search reads, the friendliest first (its name, description, tools…): `hit(in:)` names the first match.
    var searchTexts: [String] { get }
}

/// What Settings › Extensions shows of what is installed (D39): some words to look for, and which state to show.
/// With many extensions the list needs both. Every word must appear in something the row says or holds (its name,
/// description, a tool, a permission, the request to try), ignoring case, accents and width, so "zip" finds
/// Archives by its tools, "meteo" finds Météo and "internet" finds what can reach it.
public struct ExtensionListQuery: Sendable, Hashable {
    public enum Show: String, CaseIterable, Sendable { case all, on, off }

    public var text: String
    public var show: Show

    public init(text: String = "", show: Show = .all) {
        self.text = text
        self.show = show
    }

    /// The words looked for, folded; quotes and other punctuation around a word don't count.
    public var words: [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { Self.fold(String($0).trimmingCharacters(in: .punctuationCharacters)) }
            .filter { !$0.isEmpty }
    }

    public var isSearching: Bool { !words.isEmpty }

    /// Anything left out: words to look for, or one state only.
    public var isNarrowed: Bool { isSearching || show != .all }

    /// True when every word appears in one of `texts` (each word may be in a different one).
    public func matches(_ texts: [String]) -> Bool {
        let words = self.words
        guard !words.isEmpty else { return true }
        let folded = texts.map(Self.fold)
        return words.allSatisfy { word in folded.contains { $0.contains(word) } }
    }

    public func shows(isOn: Bool) -> Bool {
        switch show {
        case .all: true
        case .on: isOn
        case .off: !isOn
        }
    }

    public func includes(_ entry: some ExtensionListEntry) -> Bool {
        shows(isOn: entry.isOn) && matches(entry.searchTexts)
    }

    public func filter<E: ExtensionListEntry>(_ entries: [E]) -> [E] { entries.filter(includes) }

    /// The first of `texts` holding one of the words: why a row matched when its name and description don't say.
    public func hit(in texts: [String]) -> String? {
        let words = self.words
        guard !words.isEmpty else { return nil }
        return texts.first { text in
            let folded = Self.fold(text)
            return words.contains { folded.contains($0) }
        }
    }

    /// How many entries match the words in each state, whichever state is shown: the filter's segments say where
    /// the matches are ("On 0, Off 2" while searching for something switched off).
    public struct Counts: Sendable, Hashable {
        public var all = 0
        public var on = 0
        public var off = 0

        public init(all: Int = 0, on: Int = 0, off: Int = 0) {
            self.all = all
            self.on = on
            self.off = off
        }

        public subscript(show: Show) -> Int {
            switch show {
            case .all: all
            case .on: on
            case .off: off
            }
        }

        public static func + (a: Counts, b: Counts) -> Counts { Counts(all: a.all + b.all, on: a.on + b.on, off: a.off + b.off) }
    }

    public func counts(_ entries: [some ExtensionListEntry]) -> Counts {
        var counts = Counts()
        for entry in entries where matches(entry.searchTexts) {
            counts.all += 1
            if entry.isOn { counts.on += 1 } else { counts.off += 1 }
        }
        return counts
    }

    /// What a search reads for an installed extension: its name and description, its tools by title and by name, what
    /// its watchers watch, what it may do, who wrote it, its id and, for an MCP server, the command it runs. "No access
    /// to your files or the internet" is left out: a search for "internet" looks for what can reach it.
    public static func texts(for info: ExtensionInfo) -> [String] {
        [info.name, info.description ?? ""]
            + info.tools.map(\.title) + info.watchers.flatMap { [$0.title, $0.description] }
            + info.summary.lines.filter { $0.kind != .none }.map(\.text)
            + [info.author, info.version, info.id, info.command].compactMap { $0 }
            + info.tools.map(\.name)
    }

    /// Case, accents and full-width letters don't matter; with no locale, so the same words match in every language.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
