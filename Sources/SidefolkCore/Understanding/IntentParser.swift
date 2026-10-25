import Foundation

/// Understands plain language without a model (docs/DECISIONS.md D4): reminders, notes and lists,
/// things to remember, watches, quiet mode and searching the notebook. It is deliberately
/// conservative: it only claims text it is sure about, and returns nil for questions and requests
/// that need reasoning, which the app then sends to the AI.
///
/// Rules:
/// - Every pattern is anchored at the start of the text, after polite lead-ins ("please", "hey",
///   "can you", "could you", a companion name followed by a comma) are removed. A sentence that merely
///   contains the word "remind" or "note" somewhere is not a command.
/// - Reminders start with "remind me", "reminder", "set a reminder" ("ping me", "nudge me" and
///   "remember to" also count when a time is given). "tomorrow at 10 dentist" is not a reminder.
///   A reminder without a usable time becomes `.needsTime` so the app can ask when.
/// - Notes start with "note:", "idea:", "task:", "todo", "save this idea to X:", "add X to my Y list",
///   "jot down", "remember that". "remember that I ..." is a fact about the user; other facts are notes.
/// - Watches start with "watch", "tell me when", "let me know when", "remind me when".
/// - Searches are "find X", "search for X", "what ideas did I save for X", "show my tasks".
public struct IntentParser: Sendable {
    public let when: WhenParser
    /// The user's home folder, for "Downloads" and "~/...".
    let home: String
    /// Names the companion answers to, removed when they start a sentence ("hey pip, ...").
    let names: [String]

    public init(when: WhenParser, home: String = NSHomeDirectory(), companionNames: [String] = ["sidefolk", "pip"]) {
        self.when = when
        self.home = home
        names = companionNames.map { $0.lowercased() }
    }

    public init(calendar: Calendar = .autoupdatingCurrent, morningHour: Int = 9, afternoonHour: Int = 14, eveningHour: Int = 18,
                home: String = NSHomeDirectory()) {
        self.init(when: WhenParser(calendar: calendar, morningHour: morningHour, afternoonHour: afternoonHour, eveningHour: eveningHour), home: home)
    }

    /// - Parameter knownCollections: names of the user's notebook collections, so "ideas for Sidefolk" can tell a collection from a search word.
    public func parse(_ text: String, now: Date, knownCollections: [String] = []) -> ParsedIntent? {
        guard let t = prepare(text) else { return nil }
        let ctx = Context(now: now, known: knownCollections)
        return quiet(t, ctx) ?? watch(t, ctx) ?? remind(t, ctx) ?? note(t, ctx) ?? find(t, ctx)
    }

    struct Context {
        let now: Date
        let known: [String]
    }

    // MARK: Cleaning the text

    private static let leadIns = [
        "i would like you to", "i'd like you to", "i need you to", "i want you to", "go ahead and", "could you", "would you", "can you",
        "will you", "could u", "can u", "please", "kindly", "hello", "okay", "hey", "pls", "plz", "just", "also", "yo", "ok", "hi", "so",
    ]
    private static let closers = ["please", "pls", "plz", "thanks", "thank you", "thx", "ty"]

    func prepare(_ raw: String) -> String? {
        var t = raw.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
        t = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !t.isEmpty, t.count <= 2000, !t.hasPrefix("/") else { return nil }

        var changed = true
        while changed {
            changed = false
            let lower = t.lowercased()
            for lead in Self.leadIns where lower.hasPrefix(lead) && Self.endsWord(lower, at: lead.count) {
                t = Self.dropLead(t, count: lead.count)
                changed = true
                break
            }
            if !changed, let name = names.first(where: { n in
                guard lower.hasPrefix(n), let next = lower.dropFirst(n.count).first else { return false }
                return next == "," || next == ":"
            }) {
                t = Self.dropLead(t, count: name.count)
                changed = true
            }
        }

        changed = true
        while changed {
            changed = false
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .!?,;"))
            let lower = t.lowercased()
            for closer in Self.closers where lower.hasSuffix(" " + closer) {
                t = String(t.dropLast(closer.count + 1))
                changed = true
            }
        }
        t = Self.fixRemindTypo(t)
        return t.isEmpty ? nil : t
    }

    private static func endsWord(_ s: String, at count: Int) -> Bool {
        guard s.count > count else { return false }
        let next = s[s.index(s.startIndex, offsetBy: count)]
        return next == " " || next == "," || next == ":"
    }

    private static func dropLead(_ s: String, count: Int) -> String {
        String(s.dropFirst(count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:-"))
    }

    /// "remnd me", "remindme", "reminde me" -> "remind me".
    private static func fixRemindTypo(_ t: String) -> String {
        let words = t.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 2, words[1].lowercased() == "me", words[0].lowercased() != "remind",
              words[0].count >= 5, words[0].allSatisfy(\.isLetter),
              WhenLexicon.editDistance(Array(words[0].lowercased()), Array("remind"), limit: 1) <= 1 else { return t }
        return "remind " + t.dropFirst(words[0].count).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Reminders

    private static let remindLead = IntentPattern(
        #"(?:(?<strong>(?:set|create|add|make|schedule|new)\s+(?:me\s+)?(?:a\s+|another\s+|the\s+)?reminder(?:\s+for\s+me)?|remind\s+(?:me|myself)|reminder(?=\s*[:\-–—]|\s+(?:to|about|for|that)\s))|(?<weak>(?:ping|nudge|alert|notify|tell)\s+me|remember))(?:\s*[:,\-–—]\s*|\s+)(?<rest>.+)"#
    )

    private func remind(_ t: String, _ ctx: Context) -> ParsedIntent? {
        guard let c = Self.remindLead.match(t), var rest = c["rest"] else { return nil }
        let strong = c["strong"] != nil
        if !strong {
            // "remember that ..." is a note; "remember to ..." is a reminder only with a time.
            guard c["weak"]?.lowercased() != "remember" || rest.lowercased().hasPrefix("to ") else { return nil }
        }
        if rest.lowercased().hasPrefix("for ") { rest = String(rest.dropFirst(4)) }
        // "every 30 minutes" is a schedule a Recurrence cannot hold (its smallest step is an hour):
        // better left to the AI than to ask "when?" about a time that was given.
        if rest.range(of: #"\bevery\s+(?:other\s+|few\s+|\d+\s+)?(?:minutes?|mins?|seconds?|secs?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }

        let found = when.parse(rest, now: ctx.now)
        let title = Self.cleanTitle(found?.remaining ?? rest)
        guard !title.isEmpty else { return nil }

        guard let found, found.confidence != .low, !(found.isExplicitInstant && found.date <= ctx.now) else {
            // The words said "remind me" but the time is missing or already over: ask when.
            guard strong else { return nil }
            return ParsedIntent(intent: .needsTime(title: title), hint: "Reminder · I'll ask when · no AI")
        }
        var hint = "Reminder · \(TimeFormat.when(found.date, now: ctx.now, calendar: when.calendar))"
        if let rule = found.recurrence { hint += " · \(TimeFormat.recurrence(rule))" }
        return ParsedIntent(intent: .remind(title: title, when: found.date, recurrence: found.recurrence), hint: hint + " · no AI")
    }

    private static let titleLeads: Set<String> = ["to", "that", "about", "of", "for", "me"]

    /// "to send the document" -> "Send the document".
    static func cleanTitle(_ s: String) -> String {
        var words = s.split(separator: " ").map(String.init)
        while let first = words.first, titleLeads.contains(first.lowercased().trimmingCharacters(in: .punctuationCharacters)) { words.removeFirst() }
        var title = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-\u{2013}\u{2014}.!?"))
        while let last = title.split(separator: " ").last.map(String.init), ["please", "pls", "plz"].contains(last.lowercased()) {
            title = String(title.dropLast(last.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        }
        return title.unquoted.capitalizedFirst
    }

    // MARK: Quiet mode

    private static let quietName = #"(?:quiet(?:\s+mode)?|silent\s+mode|dnd|do\s+not\s+disturb|don't\s+disturb(?:\s+me)?|focus\s+mode)"#
    private static let quietOff: [IntentPattern] = [
        IntentPattern(#"(?:turn|switch|set)\s+"# + quietName + #"\s+off"#),
        IntentPattern(#"(?:turn|switch)\s+off\s+"# + quietName),
        IntentPattern(#"(?:stop|end|disable|cancel|exit|leave|finish)\s+"# + quietName),
        IntentPattern(quietName + #"\s+(?:off|stop|end|over|done)"#),
    ]
    private static let quietOn: [IntentPattern] = [
        IntentPattern(#"(?:go|be|stay|keep)\s+(?:quiet|silent)(?:\s+(?<prep>for|until|till|til)\s+(?<rest>.+))?"#),
        IntentPattern(#"(?:(?:turn|switch|set)\s+(?:on\s+)?|enable\s+|start\s+|activate\s+)?"# + quietName
            + #"(?:\s+on)?(?:\s+(?<prep>for|until|till|til)\s+(?<rest>.+))?"#),
    ]

    private func quiet(_ t: String, _ ctx: Context) -> ParsedIntent? {
        if Self.quietOff.contains(where: { $0.match(t) != nil }) {
            return ParsedIntent(intent: .quietOff, hint: "Quiet off · no AI")
        }
        for pattern in Self.quietOn {
            guard let c = pattern.match(t) else { continue }
            guard let prep = c["prep"]?.lowercased(), let rest = c["rest"] else {
                return ParsedIntent(intent: .quiet(until: nil), hint: "Quiet until you turn it off · no AI")
            }
            guard let end = quietEnd(prep: prep, rest: rest, ctx) else { return nil }
            let label = when.calendar.isDate(end, inSameDayAs: ctx.now)
                ? TimeFormat.clock(end, calendar: when.calendar) : TimeFormat.when(end, now: ctx.now, calendar: when.calendar)
            return ParsedIntent(intent: .quiet(until: end), hint: "Quiet until \(label) · no AI")
        }
        return nil
    }

    /// "for 1 hour" / "until 3pm" as a moment; nil when the words are not exactly a time.
    private func quietEnd(prep: String, rest: String, _ ctx: Context) -> Date? {
        var phrase = rest
        if prep == "for" {
            for lead in ["the next ", "the following ", "next ", "about ", "around ", "another "] where phrase.lowercased().hasPrefix(lead) {
                phrase = String(phrase.dropFirst(lead.count))
            }
            phrase = "in " + phrase
        } else if phrase.count <= 2, Int(phrase) != nil {
            phrase = "at " + phrase
        }
        guard let r = when.parse(phrase, now: ctx.now), r.remaining.isEmpty, r.recurrence == nil,
              r.confidence != .low, r.date > ctx.now else { return nil }
        return r.date
    }
}
