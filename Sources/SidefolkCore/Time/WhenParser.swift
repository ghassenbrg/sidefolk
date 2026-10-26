import Foundation

/// What `WhenParser` understood.
public struct WhenResult: Sendable, Equatable {
    public enum Confidence: Int, Sendable, Comparable {
        /// The time cannot be used as is (it already passed, or only a later one is available); the caller should ask.
        case low
        /// A reasonable assumption was made (am or pm guessed, rolled over to next week).
        case medium
        case high

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// The (first) moment. For `low` confidence it is the next opportunity, offered as a suggestion.
    public var date: Date
    /// Start of the repeating series; equals `date` unless a month or year had to be clamped. Persist it with the reminder.
    public var anchor: Date
    public var recurrence: Recurrence?
    /// The words that were understood as the time, as written.
    public var matched: String
    /// Where they are in the input (one range, or two when the date and the time were apart).
    public var ranges: [Range<String.Index>]
    /// The input without the time words, tidied ("call Karim at 5" -> "call Karim").
    public var remaining: String
    public var confidence: Confidence
    /// A clock time or part of the day was given (otherwise the morning hour was assumed).
    public var hasTime: Bool
    /// Written as an ISO 8601 date: it may be in the past, and callers should reject that.
    public var isExplicitInstant: Bool

    /// From the first matched word to the last.
    public var range: Range<String.Index> { ranges[0].lowerBound..<ranges[ranges.count - 1].upperBound }
}

/// Deterministic English time phrases to dates, no AI involved. Handles offsets ("in 20 min"),
/// clock times ("at 5", "17:30", "5:30pm", "noon"), days ("tomorrow", "friday", "next monday",
/// "on 12 nov"), parts of the day ("tomorrow evening"), ISO 8601 and repeats ("every weekday at 9").
///
/// Rules worth knowing:
/// - A date without a time means the morning hour.
/// - Bare hours: 1-7 mean the afternoon, 8-11 the morning (the evening if the morning is over), 12 is noon.
/// - Anything relative rolls forward, never into the past. Asking for a part of today that is over
///   ("this morning" at 10:00, "on oct 22" at noon) returns `.low` confidence so the caller can ask.
/// - `12/11` is never guessed: only month names and ISO dates are dates.
public struct WhenParser: Sendable {
    public let calendar: Calendar
    public let morningHour: Int
    public let afternoonHour: Int
    public let eveningHour: Int

    public init(calendar: Calendar = .autoupdatingCurrent, morningHour: Int = 9, afternoonHour: Int = 14, eveningHour: Int = 18) {
        self.calendar = calendar
        self.morningHour = morningHour
        self.afternoonHour = afternoonHour
        self.eveningHour = eveningHour
    }

    public init(calendar: Calendar = .autoupdatingCurrent, settings: AppSettings) {
        self.init(calendar: calendar, morningHour: settings.morningHour, afternoonHour: settings.afternoonHour, eveningHour: settings.eveningHour)
    }

    /// The most useful time phrase in `text`, or nil when there is none.
    ///
    /// When several phrases are present, one at the start or end of the text wins over one in the
    /// middle (titles often contain day names), and a date at one end is joined with a time at the other
    /// ("tomorrow ... call Karim at 5").
    public func parse(_ text: String, now: Date) -> WhenResult? {
        let tokens = WhenTokenizer.tokenize(text)
        guard !tokens.isEmpty else { return nil }
        let scanner = WhenScanner(tokens: tokens)
        let groups = phrases(scanner.atoms(), tokens)
        guard !groups.isEmpty else { return nil }

        let first = groups.first { $0.start <= scanner.firstContent }
        let last = groups.last { $0.end > scanner.lastContent }
        var candidates: [(WhenAtom, [Range<Int>])] = []
        if let first, let last, first.start != last.start, let both = first.merged(with: last) {
            candidates.append((both, [first.start..<first.end, last.start..<last.end]))
        }
        if let first { candidates.append((first, [first.start..<first.end])) }
        if let last { candidates.append((last, [last.start..<last.end])) }
        for g in groups { candidates.append((g, [g.start..<g.end])) }

        let resolver = WhenResolver(calendar: calendar, now: now, morning: morningHour, afternoon: afternoonHour, evening: eveningHour)
        for (atom, spans) in candidates {
            guard let outcome = resolver.resolve(atom) else { continue }
            let ranges = spans.map { tokens[$0.lowerBound].range.lowerBound..<tokens[$0.upperBound - 1].range.upperBound }
            return WhenResult(
                date: outcome.date, anchor: outcome.anchor, recurrence: outcome.recurrence,
                matched: ranges.map { String(text[$0]) }.joined(separator: " "), ranges: ranges,
                remaining: Self.remaining(text, removing: ranges), confidence: outcome.confidence,
                hasTime: outcome.hasTime, isExplicitInstant: outcome.exact
            )
        }
        return nil
    }

    // MARK: Phrases

    private static let connectors: Set<String> = ["on", "at", "the", "of"]

    /// Joins neighbouring atoms that fit together ("friday" + "at 3pm") into phrases.
    private func phrases(_ atoms: [WhenAtom], _ tokens: [WhenToken]) -> [WhenAtom] {
        func onlyConnectors(from a: Int, to b: Int) -> Bool {
            tokens[a..<b].allSatisfy { t in
                switch t.kind {
                case .word: Self.connectors.contains(t.text)
                case .punct: [",", "-", "\u{2013}", "\u{2014}", "@"].contains(t.text)
                default: false
                }
            }
        }
        var out: [WhenAtom] = []
        var current: WhenAtom?
        for atom in atoms {
            if let c = current, onlyConnectors(from: c.end, to: atom.start), let joined = c.merged(with: atom) {
                current = joined
            } else {
                if let c = current { out.append(c) }
                current = atom
            }
        }
        if let current { out.append(current) }
        return out
    }

    // MARK: Leftover text

    private static let dangling: Set<String> = ["on", "at", "in", "by", "for", "from", "until", "till", "around", "every", "each", "this", "next", "of"]

    static func remaining(_ text: String, removing ranges: [Range<String.Index>]) -> String {
        var s = text
        for r in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            // Take the space before the phrase with it so punctuation after it stays attached to the previous word.
            var range = r
            while range.lowerBound > s.startIndex, s[s.index(before: range.lowerBound)].isWhitespace {
                range = s.index(before: range.lowerBound)..<range.upperBound
            }
            s.removeSubrange(range)
        }
        let edge = CharacterSet(charactersIn: ",;:-\u{2013}\u{2014} ")
        var words = s.split(whereSeparator: \.isWhitespace).map(String.init)
        func trimmed(_ w: String) -> String { w.trimmingCharacters(in: edge) }
        words = words.filter { !trimmed($0).isEmpty }
        while let last = words.last, dangling.contains(trimmed(last).lowercased()) { words.removeLast() }
        guard !words.isEmpty else { return "" }
        words[0] = String(words[0].drop { edge.contains($0.unicodeScalars.first!) })
        words[words.count - 1] = words[words.count - 1].trimmingCharacters(in: CharacterSet(charactersIn: ",;:-\u{2013}\u{2014}"))
        return words.joined(separator: " ")
    }
}
