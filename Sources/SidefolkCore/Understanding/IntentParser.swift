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
/// - Reminders start with "remind me", "reminder", "set a reminder" ("ping me", "nudge me", "tell me to" and
///   "remember to" also count when a time is given). "tomorrow at 10 dentist" and "tell me a joke in 5 minutes" are not
///   reminders. A reminder without a usable time becomes `.needsTime` so the app can ask when. "Urgent" and "important"
///   make a reminder that interrupts quiet mode.
/// - The contract for everything time-related is "exactly right, or left to the AI": a time the parser cannot read
///   fully is never half-used (docs/DECISIONS.md D4), and time words never end up in a title.
/// - Text saved as a note is kept exactly as typed: its punctuation, "thanks", line breaks and indentation.
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

    /// - Parameters:
    ///   - knownCollections: names of the user's notebook collections, so "ideas for Sidefolk" can tell a collection from a search word.
    ///   - watching: what is being watched or reported, so "stop the Fukuoka temperature" can name one.
    public func parse(_ text: String, now: Date, knownCollections: [String] = [], watching: [WatchName] = []) -> ParsedIntent? {
        guard let p = prepare(text) else { return nil }
        let ctx = Context(now: now, known: knownCollections, watching: watching)
        return quiet(p.command, ctx) ?? conversation(p.command) ?? play(p.command) ?? stopWatch(p.command, ctx) ?? report(p.command, ctx) ?? watch(p.command, ctx)
            ?? remind(p.command, ctx) ?? note(p.typed, ctx) ?? find(p.command, ctx)
    }

    struct Context {
        let now: Date
        let known: [String]
        var watching: [WatchName] = []
    }

    // MARK: Cleaning the text

    private static let leadIns = [
        "i would like you to", "i'd like you to", "i need you to", "i want you to", "go ahead and", "could you", "would you", "can you",
        "will you", "could u", "can u", "please", "kindly", "hello", "okay", "hey", "pls", "plz", "just", "also", "yo", "ok", "hi", "so",
    ]
    private static let closers = ["please", "pls", "plz"]
    /// ", thanks!" after a command is politeness; "say thank you" is a task and keeps its words.
    private static let thanks = Scan(#"\s*[,.;!\-–—]\s*(?:thanks|thank you|thx|ty)[\s.!?]*$"#)

    /// The text as the command patterns see it, and as the person typed it.
    struct Prepared {
        /// Single-spaced, without trailing punctuation or polite closers.
        let command: String
        /// Without the polite lead-in only: line breaks, indentation, punctuation and "thanks" as typed. Notes are saved from this.
        let typed: String
    }

    func prepare(_ raw: String) -> Prepared? {
        var t = raw.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        let typed = Self.tidy(t)

        var command = typed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let r = Self.thanks.firstRange(in: command) { command.removeSubrange(r) }
        changed = true
        while changed {
            changed = false
            command = command.trimmingCharacters(in: CharacterSet(charactersIn: " .!?,;"))
            let lower = command.lowercased()
            for closer in Self.closers where lower.hasSuffix(" " + closer) {
                command = String(command.dropLast(closer.count + 1))
                changed = true
            }
        }
        command = Self.fixRemindTypo(command)
        guard !command.isEmpty, !typed.isEmpty else { return nil }
        return Prepared(command: command, typed: typed)
    }

    /// Line breaks as "\n", runs of spaces inside a line collapsed, indentation and blank lines kept.
    static func tidy(_ s: String) -> String {
        let lines = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                let words = line.dropFirst(indent.count).split(whereSeparator: { $0 == " " || $0 == "\t" })
                return words.isEmpty ? "" : String(indent) + words.joined(separator: " ")
            }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func endsWord(_ s: String, at count: Int) -> Bool {
        guard s.count > count else { return false }
        let next = s[s.index(s.startIndex, offsetBy: count)]
        return next.isWhitespace || next == "," || next == ":"
    }

    private static func dropLead(_ s: String, count: Int) -> String {
        String(s.dropFirst(count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:-").union(.whitespacesAndNewlines))
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
        #"(?:(?<strong>(?:set|create|add|make|schedule|new)\s+(?:me\s+)?(?:an?\s+|another\s+|the\s+)?(?:(?:urgent|important)\s+)?reminder(?:\s+for\s+me)?|remind\s+(?:me|myself)|reminder(?=\s*[:\-–—]|\s+(?:to|about|for|that)\s))|(?<weak>(?:ping|nudge|alert|notify)\s+me|tell\s+me\s+to|remember))(?:\s*[:,\-–—]\s*|\s+)(?<rest>.+)"#
    )
    /// "every few minutes" is no schedule, and seconds are finer than a reminder repeats (a minute at least).
    private static let tooFineOrVague = Scan(#"\bevery\s+(?:few\s+(?:minutes?|mins?|seconds?|secs?)\b|(?:other\s+|\d+\s*)?(?:seconds?|secs?)\b|\d+s\b)"#)
    private static let weekendWord = Scan(#"\bweekend\b"#)
    private static let repeatEnd = Scan(#"\b(?:until|till|til|forever|indefinitely)\b"#)
    private static let nightWord = Scan(#"\b(?:tonight|night|evening)\b"#)

    private func remind(_ command: String, _ ctx: Context) -> ParsedIntent? {
        let (t, leadingUrgency) = Self.stripUrgency(command, lead: Self.urgentLead)
        guard let c = Self.remindLead.match(t), var rest = c["rest"] else { return nil }
        var important = leadingUrgency
        let strong = c["strong"] != nil
        if let lead = c["strong"]?.lowercased(), lead.contains("urgent") || lead.contains("important") { important = true }
        if !strong {
            // "remember that ..." is a note; "remember to ..." is a reminder only with a time.
            guard c["weak"]?.lowercased() != "remember" || rest.lowercased().hasPrefix("to ") else { return nil }
        }
        if rest.lowercased().hasPrefix("for ") { rest = String(rest.dropFirst(4)) }
        // Better left to the AI than to ask "when?" about a time that was given, or to round it.
        if Self.tooFineOrVague.found(in: rest) { return nil }
        let urgency = Self.stripUrgency(rest, lead: Self.urgentRestLead, tail: Self.urgentTail)
        rest = urgency.text
        important = important || urgency.important

        // "yesterday", "later", "25:00": a time was said, but it cannot be used. Ask again, without those words in the title.
        let unusable = unusableTime(in: rest)
        if let unusable { rest = unusable.rest }
        rest = Self.rewriteTimeWords(rest)

        guard let found = when.parse(rest, now: ctx.now) else {
            // A time written in a way the parser does not know is the AI's to read; asking "when?" about a time that was given is worse.
            guard !Self.looksLikeATime(rest) else { return nil }
            let title = Self.cleanTitle(rest)
            guard !title.isEmpty, strong else { return nil }
            return ask(title: title, reason: unusable?.reason, important: important)
        }
        // Two statements about when ("yesterday ... at 5") are not for guessing.
        guard unusable == nil else { return nil }
        let title = Self.cleanTitle(found.remaining)
        guard !title.isEmpty, !Self.leavesTimeWords(title: title, left: found.remaining, rest: rest) else { return nil }
        // "every 30 minutes to stretch until friday": an end the repeat didn't take is not part of the title.
        if found.recurrence != nil, Self.repeatEnd.found(in: title) { return nil }
        // "this weekend" on a weekend rolls over a whole week; the person meant now.
        if Self.weekendWord.found(in: found.matched), (6...7).contains(TimeFormat.isoWeekday(of: ctx.now, calendar: when.calendar)) { return nil }

        guard found.confidence != .low, !(found.isExplicitInstant && found.date <= ctx.now) else {
            // The words said "remind me" but the time is already over: ask when.
            guard strong else { return nil }
            return ask(title: title, reason: String(localized: "\(found.matched.capitalizedFirst) has passed."), important: important)
        }
        var date = found.date
        // "tonight at 12" is the midnight that ends tonight, not noon.
        if Self.nightWord.found(in: found.matched), when.calendar.component(.hour, from: date) == 12,
           when.calendar.component(.minute, from: date) == 0, let midnight = when.calendar.date(byAdding: .hour, value: 12, to: date) {
            date = midnight
        }
        var parts = [String(localized: "Reminder"), TimeFormat.when(date, now: ctx.now, calendar: when.calendar)]
        if let rule = found.recurrence { parts.append(TimeFormat.recurrence(rule, now: ctx.now, calendar: when.calendar)) }
        if important { parts.append(String(localized: "important")) }
        // The series' own start, only where it changes what comes after the first fire (a clamped 31st).
        let anchor = found.recurrence.flatMap { rule in
            RecurrenceMath.nextOccurrence(after: date, recurrence: rule, anchor: found.anchor, calendar: when.calendar)
                == RecurrenceMath.nextOccurrence(after: date, recurrence: rule, anchor: date, calendar: when.calendar) ? nil : found.anchor
        }
        return ParsedIntent(intent: .remind(title: title, when: date, recurrence: found.recurrence, important: important, anchor: anchor),
                            hint: ParsedIntent.hint(parts.joined(separator: " · ")))
    }

    private func ask(title: String, reason: String?, important: Bool) -> ParsedIntent {
        ParsedIntent(intent: .needsTime(title: title, reason: reason, important: important),
                     hint: ParsedIntent.hint(String(localized: "Reminder"), String(localized: "I'll ask when")))
    }

    private static let titleLeads: Set<String> = ["to", "that", "about", "of", "for", "me"]
    private static let danglingPrepositions: Set<String> = ["on", "at", "in", "by", "for", "from", "until", "till", "around", "of"]

    /// "to send the document" -> "Send the document". A preposition the time parser left behind ("on to renew") goes too.
    static func cleanTitle(_ s: String) -> String {
        var words = s.split(separator: " ").map(String.init)
        func bare(_ w: String) -> String { w.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        while let first = words.first {
            if titleLeads.contains(bare(first)) { words.removeFirst(); continue }
            if danglingPrepositions.contains(bare(first)), words.count > 1, titleLeads.contains(bare(words[1])) { words.removeFirst(); continue }
            break
        }
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
            return ParsedIntent(intent: .quietOff, hint: ParsedIntent.hint(String(localized: "Quiet off")))
        }
        for pattern in Self.quietOn {
            guard let c = pattern.match(t) else { continue }
            guard let prep = c["prep"]?.lowercased(), let rest = c["rest"] else {
                return ParsedIntent(intent: .quiet(until: nil), hint: ParsedIntent.hint(String(localized: "Quiet until you turn it off")))
            }
            guard let end = quietEnd(prep: prep, rest: rest, ctx) else { return nil }
            let label = when.calendar.isDate(end, inSameDayAs: ctx.now)
                ? TimeFormat.clock(end, calendar: when.calendar) : TimeFormat.when(end, now: ctx.now, calendar: when.calendar)
            return ParsedIntent(intent: .quiet(until: end), hint: ParsedIntent.hint(String(localized: "Quiet until \(label)")))
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
