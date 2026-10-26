import Foundation

/// A pattern searched for anywhere in a text (unlike `IntentPattern`, which must match all of it).
struct Scan: Sendable {
    private let regex: NSRegularExpression

    init(_ pattern: String) {
        // Literals in this module; a typo is a programmer error caught by the tests.
        regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    func found(in s: String) -> Bool { regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    func firstRange(in s: String) -> Range<String.Index>? {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)).flatMap { Range($0.range, in: s) }
    }

    func replacing(in s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Replaces every match with whatever `transform` makes of its capture groups (group 0 is the whole match).
    func replacing(in s: String, _ transform: ([String]) -> String) -> String {
        var out = ""
        var cursor = s.startIndex
        for m in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s) else { continue }
            let groups = (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
            out += s[cursor..<whole.lowerBound] + transform(groups)
            cursor = whole.upperBound
        }
        return out + s[cursor...]
    }

    /// The text of the capture groups of the first match (group 0 is the whole match).
    func groups(in s: String) -> [String]? {
        guard let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }
}

/// What the reminder parser does around the time words, so that a reminder is either exactly right or left to the
/// AI (docs/DECISIONS.md D4): urgency, words for a time that cannot be used, words the time parser does not know,
/// and time words that would otherwise end up inside the title.
extension IntentParser {
    // MARK: Urgency

    /// "urgent: remind me ...", "urgently remind me ...", "important reminder: ..." in front of the command.
    static let urgentLead = Scan(#"^(?:(?:urgent|important)(?:ly)?\s*[:,!\-–—]+\s*|(?:urgently|importantly)\s+|(?:an?\s+)?(?:urgent|important)\s+(?=reminder\b))"#)
    /// "remind me urgently to ...", "remind me (important) ...", "remind me urgent: ..." right after the command.
    static let urgentRestLead = Scan(#"^(?:(?:urgent|important)\s*[:,\-–—]+\s*|(?:urgently|importantly)\b[\s,:\-]*|[\(\[]\s*(?:urgent|important)\s*[\)\]]\s*)"#)
    /// "... (important)", "..., it's urgent", "... urgently" at the end.
    static let urgentTail = Scan(#"(?:\s*[\(\[]\s*(?:urgent|important)\s*[\)\]]|\s*[,\-–—:]\s*(?:(?:it'?s|this\s+is|very|really)\s+)*(?:urgent|important)|\s+(?:urgently|importantly))\s*$"#)

    /// Removes an urgency marker at the start and/or the end; says whether there was one.
    static func stripUrgency(_ s: String, lead: Scan, tail: Scan? = nil) -> (text: String, important: Bool) {
        var text = s
        var important = false
        if let r = lead.firstRange(in: text) { text.removeSubrange(r); important = true }
        if let tail, let r = tail.firstRange(in: text) { text.removeSubrange(r); important = true }
        return (text.trimmingCharacters(in: .whitespaces), important)
    }

    // MARK: Times that cannot be used

    private static let pastWords = #"yesterday|the\s+day\s+before\s+yesterday|last\s+night|last\s+(?:week|month|year|weekend|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|(?:\d+|an?|one|two|three|a\s+few|a\s+couple\s+of)\s+(?:seconds?|minutes?|hours?|days?|weeks?|months?|years?)\s+ago|earlier\s+today"#
    private static let vagueWords = #"later(?:\s+(?:today|tonight|this\s+(?:morning|afternoon|evening|week|weekend)))?|sometime|some\s*time|someday|eventually|soon|whenever|at\s+some\s+point"#
    private static let unusable: [(start: Scan, end: Scan, past: Bool)] = [
        (Scan(#"^(?:(?:on|at|for|by)\s+)?(\#(pastWords))\b[\s,:;\-]*"#), Scan(#"[\s,:;\-]*\b(?:(?:on|at|for|by)\s+)?(\#(pastWords))$"#), true),
        (Scan(#"^(?:(?:on|at|for|by)\s+)?(\#(vagueWords))\b[\s,:;\-]*"#), Scan(#"[\s,:;\-]*\b(?:(?:on|at|for|by)\s+)?(\#(vagueWords))$"#), false),
    ]
    private static let clock = Scan(#"(?:\b(?:at|on|by)\s+)?\b(\d{1,3}):(\d{2})\b(?:\s*(am|pm)\b)?"#)

    /// A word or number that names a time nobody can use at the start or end of the reminder text ("yesterday",
    /// "later", "25:00"): the text without it, and why it was no use. The reminder is then asked about, with a clean title.
    func unusableTime(in rest: String) -> (rest: String, reason: String)? {
        for pattern in Self.unusable {
            for scan in [pattern.start, pattern.end] {
                guard let range = scan.firstRange(in: rest), let g = scan.groups(in: rest), g.count > 1, !g[1].isEmpty else { continue }
                var text = rest
                text.removeSubrange(range)
                let phrase = g[1].lowercased().split(separator: " ").joined(separator: " ")
                let reason: String
                if pattern.past {
                    reason = phrase == "yesterday" ? String(localized: "Yesterday has passed.")
                        : phrase.hasSuffix("ago") ? String(localized: "That time has passed.")
                        : String(localized: "\(phrase.capitalizedFirst) has passed.")
                } else {
                    reason = String(localized: "\(phrase.capitalizedFirst) isn't a time.")
                }
                return (text.trimmingCharacters(in: .whitespaces), reason)
            }
        }
        if let range = Self.clock.firstRange(in: rest), let g = Self.clock.groups(in: rest), let h = Int(g[1]), let m = Int(g[2]) {
            let meridiem = !g[3].isEmpty
            if h > (meridiem ? 12 : 23) || m > 59 || (meridiem && h == 0) {
                var text = rest
                text.removeSubrange(range)
                let typed = "\(g[1]):\(g[2])\(meridiem ? " " + g[3].lowercased() : "")"
                return (text.trimmingCharacters(in: .whitespaces), String(localized: "\(typed) isn't a time."))
            }
        }
        return nil
    }

    // MARK: Ways of writing a time that the time parser does not read

    private static let hedge = Scan(#"\b(in|at|by|within|around)\s+(?:about|around|roughly|approximately|circa)\s+"#)
    private static let ish = Scan(#"\b(\d{1,2}(?::\d{2})?)\s*ish\b"#)
    private static let dotted = Scan(#"\b(\d{1,2})\.(\d{2})\s*(am|pm)\b"#)
    private static let frenchHM = Scan(#"(?<!\bin\s)(?<!\bfor\s)(?<!\bwithin\s)(?<![\d:.])\b(\d{1,2})h(\d{2})\b"#)
    private static let frenchH = Scan(#"\b(at\s+)(\d{1,2})h\b"#)
    private static let halfQuarter = Scan(#"\b(?:a\s+)?(half|quarter)\s+(past|to)\s+(\d{1,2})\b"#)
    private static let twelveNoon = Scan(#"\b12\s+(noon|midnight)\b"#)
    private static let timeSuffix = Scan(#"\b(\d+\s+(?:seconds?|minutes?|mins?|hours?|hrs?|days?|weeks?))['’]?s?\s+time\b"#)
    private static let fortnight = Scan(#"\b(in|within)\s+(?:a|one)\s+fortnight\b"#)
    private static let spelledNumber = Scan(
        #"(?<=\b(?:in|within|after|for)\s)((?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[\s-]+(?:one|two|three|four|five|six|seven|eight|nine))?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen)(?=\s+(?:seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)\b)"#)
    private static let ordinalOfEveryMonth = Scan(#"\b(?:on\s+)?the\s+(\d{1,2}(?:st|nd|rd|th)|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|fifteenth|twentieth)\s+of\s+(?:every|each)\s+month\b"#)

    private static let numberValues: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let ordinalValues: [String: String] = [
        "first": "1st", "second": "2nd", "third": "3rd", "fourth": "4th", "fifth": "5th", "sixth": "6th", "seventh": "7th", "eighth": "8th",
        "ninth": "9th", "tenth": "10th", "fifteenth": "15th", "twentieth": "20th",
    ]

    /// Rewrites the common ways of writing a time that `WhenParser` does not read into ones it does: "9h30", "5.30pm",
    /// "half past 3", "in about 5 minutes", "12 noon", "in forty five minutes", "the 15th of every month". What the
    /// rewrite does not cover is caught later (`looksLikeATime`) and left to the AI.
    static func rewriteTimeWords(_ text: String) -> String {
        var s = text
        s = ordinalOfEveryMonth.replacing(in: s) { g in "every month on the " + (ordinalValues[g[1].lowercased()] ?? g[1]) }
        s = hedge.replacing(in: s, with: "$1 ")
        s = ish.replacing(in: s, with: "$1")
        s = dotted.replacing(in: s, with: "$1:$2$3")
        s = frenchHM.replacing(in: s, with: "$1:$2")
        s = frenchH.replacing(in: s, with: "$1$2:00")
        s = halfQuarter.replacing(in: s) { g in
            guard let n = Int(g[3]), (1...12).contains(n) else { return g[0] }
            let toNext = g[2].lowercased() == "to"
            let minutes = g[1].lowercased() == "half" ? 30 : (toNext ? 45 : 15)
            var hour = toNext ? n - 1 : n
            if hour == 0 { hour = 12 }
            return String(format: "%d:%02d", hour, minutes)
        }
        s = twelveNoon.replacing(in: s, with: "$1")
        s = timeSuffix.replacing(in: s, with: "$1")
        s = fortnight.replacing(in: s, with: "$1 2 weeks")
        s = spelledNumber.replacing(in: s) { g in
            let words = g[1].lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
            return String(words.compactMap { numberValues[$0] }.reduce(0, +))
        }
        return s
    }

    /// A time typed as the answer to "when?": reads the same spellings a reminder sentence does ("9h30", "half past 3",
    /// "in about 5 minutes"). Check `remaining` is empty to know the whole answer was a time.
    public func parseTime(_ text: String, now: Date) -> WhenResult? { when.parse(Self.rewriteTimeWords(text), now: now) }

    // MARK: Time words the parser did not understand

    private static let numWord = #"(?:\d+(?:\.\d+)?|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty|sixty)"#
    private static let unit = #"(?:seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?|fortnights?)"#
    /// A number written in digits or words (not "a" / "an").
    private static let count = #"(?:\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty|sixty)"#
    private static let stillATime: [Scan] = [
        // "in about 5 minutes", "in a couple of hours", "within forty five minutes"
        Scan(#"\b(?:in|within)\s+(?:about\s+|around\s+|roughly\s+)?(?:\#(numWord)[\s-]+){1,3}\#(unit)\b"#),
        Scan(#"\b(?:in|within)\s+(?:a\s+)?(?:few|couple(?:\s+of)?|bit)\b"#),
        // "for the next 30 minutes" (a span, not a task's length like "read for 20 minutes")
        Scan(#"\bthe\s+next\s+(?:\#(numWord)[\s-]+){1,3}\#(unit)\b"#),
        // "half past 3", "a quarter to 6", "ten to five", "20 past 4"
        Scan(#"\b(?:half|quarter)\s+(?:past|to)\b"#),
        Scan(#"\b(?:\d+|five|ten|twenty|twenty-five)\s+(?:to|past)\s+(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#),
        // "at 9.30", "at about 9"
        Scan(#"\bat\s+\d{1,2}[.:]\d{2}\b"#),
        Scan(#"\b(?:at|by|around|until|till)\s+(?:about|around)\b"#),
        // "next week", "this weekend", "coming month"
        Scan(#"\b(?:next|this|last|coming)\s+(?:week|month|year|weekend|fortnight|quarter)\b"#),
        // A repeat the parser could not use: "every 10 minutes until 9am" when 9am has passed, "every 10 seconds"
        Scan(#"\b(?:every|each)\s+(?:other\s+|\#(count)\s*)?\#(unit)\b"#),
        // "the 5th", "12/11"
        Scan(#"\b\d{1,2}(?:st|nd|rd|th)\b"#),
        Scan(#"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#),
    ]

    /// Whether text with no time the parser could read still seems to contain one, written in a way it does not know.
    /// Better the AI than a reminder that asks "when?" about a time that was given.
    static func looksLikeATime(_ text: String) -> Bool { stillATime.contains { $0.found(in: text) } }

    // MARK: Time words left in the title

    private static let titleShapes: [Scan] = [
        // A dangling preposition or schedule word at the front: "on 2025-12-01" took its date and left "on".
        Scan(#"^(?:at|on|by|around|until|till|within|every|each|of|except)\b"#),
        Scan(#"^(?:roughly|approximately|ish\b|h\d{0,2}\b|['’])"#),
        // "and" / "or" joining two times ("at 8am and 8pm") or a time left alone at an end
        Scan(#"(?:^|\s)(?:and|or)$"#),
        Scan(#"^(?:and|or)\b"#),
        Scan(#"\b(?:or|and|to|at|on|by|until|till|from|after|before|past)\s+\d[\w:.]*$"#),
        // "1 week", "3 days" left at an end of the title
        // ("read for 20 minutes" is a title, not a time: only a count with nothing in front of it counts)
        Scan(#"(?<!\bfor\s)(?<!\b(?:every|each|last|past|next|this)\s)\b(?:\#(count))\s+\#(unit)$"#),
        Scan(#"^(?:\#(count))\s+\#(unit)\b"#),
        // A span the repeat didn't absorb: "every 30 minutes for an hour to stretch" left "for an hour".
        Scan(#"^(?:for\s+(?:the\s+next\s+)?|the\s+next\s+)(?:an?|\#(count))\s+\#(unit)\b"#),
        // A repeat said another way: "once a minute".
        Scan(#"\bonce\s+(?:a|an|per|every)\s+(?:second|minute|hour|day|week|month|year)\b"#),
        // A window of hours: "every 30 minutes between 9 and 5", "from 9 to 5", "9-5".
        Scan(#"\b(?:between|from)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s*(?:and|to|-|–)\s*\d"#),
        // A weekday or part of day left at an end ("wed fri at 8am", "evening to plan")
        Scan(#"^(?:mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday|morning|afternoon|evening|night|tonight|noon|midnight|weekend)\b"#),
        Scan(#"\b(?:morning|afternoon|evening|tonight|noon|midnight)$"#),
        // "ten to five", "half past"
        Scan(#"^(?:half|quarter|\d+|five|ten|twenty)\s+(?:to|past)\b"#),
        // schedule words that were not absorbed
        Scan(#"\b(?:every|each|except)\b"#),
        // an ordinal day or "first monday" left over
        Scan(#"\b\d{1,2}(?:st|nd|rd|th)\b"#),
        Scan(#"\b(?:first|second|third|fourth|fifth|last)\s+(?:of\b|mon|tue|wed|thu|fri|sat|sun)"#),
        Scan(#"\bof\s+(?:the|next|this|every|each)\s+(?:month|year|week)\b"#),
        Scan(#"^(?:next|this|last|coming)\s+(?:week|month|year|weekend|fortnight)\b"#),
    ]
    /// "1 week from tomorrow", "3 days after monday": the time parser drops the offset and keeps the day.
    private static let offsetFromDay = Scan(#"\b(?:\#(numWord))\s+\#(unit)\s+(?:after|from|before)\b"#)

    /// Whether the title that is left (`title`, and `left` before it was tidied) still has time words in it, or the text
    /// has a construct the time parser gets wrong.
    static func leavesTimeWords(title: String, left: String, rest: String) -> Bool {
        offsetFromDay.found(in: rest) || [title, left].contains { text in titleShapes.contains { $0.found(in: text) } }
    }
}
