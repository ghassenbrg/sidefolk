import Foundation

/// "every 10 seconds tell me the CPU usage", "temperature in Fukuoka every minute", "show my battery every 5
/// minutes", and "stop telling me the CPU". Like the rest of the parser, it claims a sentence only when every word
/// is accounted for: an interval, one thing to report, and words that only say "tell me".
extension IntentParser {
    // MARK: Words

    /// "every 10 seconds", "every 10s", "every minute", "each hour", "every other minute", "every half hour", "once a minute".
    private static let interval = Scan(
        #"\b(?:(?:every|each)\s+(?:(\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty|sixty|other)\s*)?(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)|(?:every|each)\s+(half)\s+(?:an\s+)?hour|once\s+(?:a|an|per|every)\s+(second|minute|hour))\b"#)
    private static let untilStopped = Scan(
        #"\b(?:until|till|til)\s+(?:i\s+(?:stop|cancel|end|say\s+(?:stop|so))(?:\s+(?:it|you|this|that))?|(?:it'?s\s+)?stopped|further\s+notice)\b|\b(?:forever|indefinitely|non-?stop)\b"#)
    /// "for an hour", "for the next 30 minutes".
    private static let forSpan = Scan(#"\bfor\s+(?:the\s+next\s+)?((?:\d+|an?|one|two|three|ten|twenty|thirty)\s+(?:minutes?|mins?|hours?|hrs?))\b"#)
    private static let untilWord = Scan(#"\b(?:until|till|til)\s+"#)
    private static let notifyWords = Scan(#"\b(?:(?:send|give)\s+me\s+)?(?:a\s+|with\s+a\s+)?notifications?\b|\bnotify\s+me\b(?:\s+(?:of|about|with))?"#)

    /// Words that only say "tell me" or "what it is now" around the thing reported.
    private static let fillers: Set<String> = [
        "tell", "me", "show", "give", "report", "check", "watch", "monitor", "display", "send", "let", "know", "post", "update", "keep",
        "what", "what's", "whats", "how", "much", "many", "is", "are", "it", "its", "it's", "now", "right", "currently", "current", "at",
        "the", "my", "a", "an", "of", "and", "then", "on", "usage", "use", "used", "level", "value", "values", "percentage", "percent",
        "status", "reading", "readings", "please", "updates", "me,", "this", "mac", "mac's", "computer", "computer's", "here", "there",
        "be", "will", "you", "can", "could", "would", "with", "about", "for", "to", "in", "like", "outside", "today", "live", "load",
        "free", "left", "remaining", "available",
    ]

    /// Every way of naming a metric, longest first so "cpu usage" wins over "cpu".
    static let metricWords: [(phrase: String, metric: Metric)] = [
        ("internet speed", .network), ("network speed", .network), ("download speed", .network), ("upload speed", .network),
        ("network traffic", .network), ("disk space", .disk), ("free space", .disk), ("free disk", .disk), ("drive space", .disk),
        ("storage space", .disk), ("battery charge", .battery), ("cpu", .cpu), ("processor", .cpu), ("memory", .memory), ("ram", .memory),
        ("battery", .battery), ("charge", .battery), ("disk", .disk), ("storage", .disk), ("network", .network), ("bandwidth", .network),
    ]

    static let weatherWords: [(phrase: String, quantity: WeatherQuantity)] = [
        ("feels like", .feelsLike), ("wind speed", .wind), ("temperature", .temperature), ("temp", .temperature),
        ("humidity", .humidity), ("wind", .wind), ("precipitation", .precipitation), ("rain", .precipitation),
        ("weather", .conditions), ("conditions", .conditions), ("degrees", .temperature),
    ]

    // MARK: Reports

    func report(_ command: String, _ ctx: Context) -> ParsedIntent? {
        var text = " " + Self.fixEverySlip(command.lowercased().replacingOccurrences(of: "’", with: "'")) + " "
        guard let seconds = Self.seconds(in: text), let found = Self.interval.firstRange(in: text) else { return nil }
        text.replaceSubrange(found, with: " ")
        guard !Self.interval.found(in: text) else { return nil }   // two intervals: not for guessing

        var report = ReportIntent(source: .metric(.cpu), everySeconds: seconds)
        if let r = Self.untilStopped.firstRange(in: text) {
            report.untilStopped = true
            text.replaceSubrange(r, with: " ")
        }
        if let g = Self.forSpan.groups(in: text), let r = Self.forSpan.firstRange(in: text) {
            report.until = "in " + g[1]
            text.replaceSubrange(r, with: " ")
        } else if let r = Self.untilWord.firstRange(in: text) {
            guard let (phrase, end) = untilPhrase(text[r.upperBound...], ctx) else { return nil }
            report.until = phrase
            text.replaceSubrange(r.lowerBound..<end, with: " ")
        }
        // "for an hour until I stop it": two ends are not for guessing.
        guard !(report.untilStopped && report.until != nil) else { return nil }
        if let r = Self.notifyWords.firstRange(in: text) {
            report.notify = true
            text.replaceSubrange(r, with: " ")
        }
        guard let source = subject(text, original: command) else { return placeNeeded(text) }
        report.source = source
        return ParsedIntent(intent: .report(report), hint: hint(report, ctx))
    }

    /// "evey 10s", "evry minute", "ever 5 seconds": a slip in "every" right before how often, the one word every
    /// report has. Anywhere else the word is left as typed.
    static func fixEverySlip(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for i in words.indices.dropLast() where words[i] != "every" && (4...6).contains(words[i].count) && words[i].allSatisfy(\.isLetter) {
            let next = words[i + 1]
            let saysHowOften = next.first?.isNumber == true || WhenLexicon.numberWords[next] != nil
                || ["other", "half", "second", "sec", "minute", "min", "hour"].contains { next.hasPrefix($0) }
            guard saysHowOften, WhenLexicon.editDistance(Array(words[i]), Array("every"), limit: 1) <= 1 else { continue }
            words[i] = "every"
        }
        return words.joined(separator: " ")
    }

    /// What is reported, when it is the only thing the words name.
    private func subject(_ text: String, original: String) -> ReportIntent.Source? {
        var rest = text
        var metric: Metric?
        for (phrase, m) in Self.metricWords {
            guard let r = rest.range(of: " \(phrase) ") ?? rest.range(of: " \(phrase)'s ") else { continue }
            guard metric == nil || metric == m else { return nil }
            metric = m
            rest.replaceSubrange(r, with: " ")
        }
        var quantity: WeatherQuantity?
        for (phrase, q) in Self.weatherWords {
            guard let r = rest.range(of: " \(phrase) ") else { continue }
            if quantity == nil || quantity == .conditions { quantity = q } else if q != .conditions, q != quantity { return nil }
            rest.replaceSubrange(r, with: " ")
        }
        if let metric {
            guard quantity == nil, Self.onlyFillers(rest) else { return nil }
            return .metric(metric)
        }
        guard let quantity else { return nil }
        if let place = Self.place(in: rest, original: original) { return .weather(place: place, quantity: quantity) }
        // Nothing but the quantity and "tell me" words: where the person is, when they share it (D48).
        guard let here, Self.onlyFillers(rest) else { return nil }
        return .weather(place: here, quantity: quantity)
    }

    /// "temperature every 10 minutes" with no place named and none known: ask which, rather than leave it to a guess.
    private func placeNeeded(_ text: String) -> ParsedIntent? {
        guard here == nil, !Self.metricWords.contains(where: { text.contains(" \($0.phrase) ") }) else { return nil }
        var rest = text
        var quantity: WeatherQuantity?
        for (phrase, q) in Self.weatherWords {
            guard let r = rest.range(of: " \(phrase) ") else { continue }
            if quantity == nil || quantity == .conditions { quantity = q } else if q != .conditions, q != quantity { return nil }
            rest.replaceSubrange(r, with: " ")
        }
        guard let quantity, Self.onlyFillers(rest) else { return nil }
        return ParsedIntent(intent: .needsPlace(quantity), hint: ParsedIntent.hint(String(localized: "Needs a place")))
    }

    /// "in Fukuoka", "for paris, france", "at new york": the words after the preposition, as typed, when nothing but
    /// "tell me" words is left around them. "the Fukuoka temperature" works too (the place before the quantity).
    private static func place(in rest: String, original: String) -> String? {
        let words = rest.split(separator: " ").map(String.init)
        var candidate: [String] = []
        var others: [String] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            if ["in", "at", "for"].contains(w), candidate.isEmpty, i + 1 < words.count, !fillers.contains(words[i + 1]) {
                var j = i + 1
                while j < words.count, !fillers.contains(words[j]) || words[j].hasSuffix(","), candidate.count < 4 {
                    candidate.append(words[j]); j += 1
                }
                i = j
                continue
            }
            if !fillers.contains(w) { others.append(w) }
            i += 1
        }
        if candidate.isEmpty, (1...3).contains(others.count) { candidate = others; others = [] }
        guard !candidate.isEmpty, others.isEmpty else { return nil }
        let typed = candidate.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,'s"))
        // The person's own capitals: "Fukuoka", "New York".
        let shown = original.range(of: typed, options: .caseInsensitive).map { String(original[$0]) } ?? typed.capitalized
        guard let clean = WeatherProbe.cleanPlace(shown) else { return nil }
        return clean.prefix(1).uppercased() + clean.dropFirst()
    }

    private static func onlyFillers(_ text: String) -> Bool {
        text.split(separator: " ").allSatisfy { fillers.contains(String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",.!?"))) }
    }

    /// Seconds between readings, from the interval words.
    static func seconds(in text: String) -> TimeInterval? {
        guard let g = interval.groups(in: text) else { return nil }
        if !g[3].isEmpty { return 1800 }
        let unit = !g[4].isEmpty ? g[4] : g[2]
        let count: Double
        switch g[1] {
        case "": count = 1
        case "other": count = 2
        default: count = Double(g[1]) ?? WhenLexicon.numberWords[g[1]] ?? 0
        }
        guard count > 0 else { return nil }
        let seconds: TimeInterval
        switch unit.first {
        case "s": seconds = count
        case "m": seconds = count * 60
        default: seconds = count * 3600
        }
        // What `watch.report` would refuse is the AI's to explain; and a huge number must not reach the hint's wording.
        return seconds <= WatchLimits.maxInterval ? seconds : nil
    }

    /// "until 6pm" in the middle of a sentence: the longest run of words after "until" that is a time and nothing else.
    private func untilPhrase(_ after: Substring, _ ctx: Context) -> (String, String.Index)? {
        let words = after.split(separator: " ", omittingEmptySubsequences: true)
        for n in stride(from: min(4, words.count), through: 1, by: -1) {
            let phrase = words[0..<n].joined(separator: " ")
            guard let found = when.parse(phrase, now: ctx.now), found.remaining.isEmpty, found.recurrence == nil,
                  found.confidence != .low, found.date > ctx.now else { continue }
            return (phrase, words[n - 1].endIndex)
        }
        return nil
    }

    private func hint(_ r: ReportIntent, _ ctx: Context) -> String {
        let what: String
        let fastest: TimeInterval
        switch r.source {
        case .metric(let m): (what, fastest) = (m.title, ReportFloors.metric)
        case .weather(let place, let quantity): (what, fastest) = (quantity.title(place), ReportFloors.web)
        }
        // How often it will really read: a faster request is raised (D35), and the hint must not promise more.
        var parts = [String(localized: "Show \(what) every \(WatchWords.every(max(r.everySeconds, fastest)))")]
        if r.untilStopped {
            parts.append(String(localized: "until you stop it"))
        } else if let until = r.until, let end = when.parse(until, now: ctx.now)?.date {
            parts.append(String(localized: "until \(TimeFormat.moment(end, now: ctx.now, calendar: when.calendar))"))
        }
        return ParsedIntent.hint(parts.joined(separator: " · "))
    }

    // MARK: Stopping

    /// "stop telling me the CPU": a lead that is only about telling or watching, whatever follows.
    private static let stopStrong = IntentPattern(
        #"(?:stop|quit|no\s+more)\s+(?:telling\s+me|showing(?:\s+me)?|reporting|watching|checking|tracking|monitoring|displaying|updating\s+me\s+on)(?:\s+(?:about|on))?(?:\s+(?<what>.+))?"#)
    /// "stop the Fukuoka temperature", "cancel the CPU report", "turn off the battery readout": only for a watcher that exists.
    private static let stopWeak = IntentPattern(#"(?:stop|cancel|end|remove|turn\s+off|switch\s+off|kill)\s+(?<what>.+)"#)
    private static let stopFillers: Set<String> = [
        "the", "my", "a", "that", "this", "those", "these", "report", "reports", "readout", "readouts", "reading", "readings", "updates",
        "update", "live", "value", "pill", "watch", "watcher", "watching", "please", "usage", "use", "level", "of", "for", "in", "at",
        "on", "about", "me", "it", "now", "one", "every", "minute", "minutes", "seconds", "second", "hour", "hours", "s", "telling", "showing",
    ]

    func stopWatch(_ command: String, _ ctx: Context) -> ParsedIntent? {
        let strong = Self.stopStrong.match(command)
        guard let c = strong ?? Self.stopWeak.match(command) else { return nil }
        let words = Set((c["what"] ?? "").lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." })
            .map(String.init).filter { !Self.stopFillers.contains($0) && !$0.allSatisfy(\.isNumber) })
        var matches: [WatchName]
        if words.isEmpty {
            // "stop telling me": fine when there is exactly one report to mean.
            let reports = ctx.watching.filter(\.isReport)
            guard strong != nil, reports.count == 1 else { return nil }
            matches = reports
        } else {
            matches = ctx.watching.filter { words.isSubset(of: $0.words) }
            // Several watchers fit and only some are live values: the person who says "telling me" means those.
            if matches.count > 1, strong != nil, matches.contains(where: \.isReport) { matches = matches.filter(\.isReport) }
        }
        guard !matches.isEmpty || strong != nil else { return nil }
        let hint: String
        switch matches.count {
        case 0: hint = ParsedIntent.hint(String(localized: "Stop"), String(localized: "nothing like that is running"))
        case 1: hint = ParsedIntent.hint(String(localized: "Stop \(matches[0].title)"))
        default: hint = ParsedIntent.hint(String(localized: "Stop"), String(localized: "\(matches.count) matches. Which one?"))
        }
        return ParsedIntent(intent: .stopWatch(ids: matches.map(\.id), words: c["what"] ?? ""), hint: hint)
    }
}

/// A watcher the person may name when stopping it, with every word that names it.
public struct WatchName: Sendable, Equatable {
    public var id: String
    public var title: String
    public var isReport: Bool
    /// Lower-cased: the title's words, and words for what it reads ("cpu", "processor"; "fukuoka", "temperature").
    public var words: Set<String>

    public init(_ w: Watcher) {
        id = w.id
        title = w.title
        isReport = w.mode == .report
        var words = Set(w.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." }).map(String.init))
        if let metric = w.config.string("metric") {
            words.insert(metric)
            words.formUnion(IntentParser.metricWords.filter { $0.metric.rawValue == metric }.flatMap { $0.phrase.split(separator: " ").map(String.init) })
        }
        if let quantity = w.config.string("quantity") {
            words.formUnion(IntentParser.weatherWords.filter { $0.quantity.rawValue == quantity }.flatMap { $0.phrase.split(separator: " ").map(String.init) })
            words.insert("weather")
        }
        for key in ["place", "url", "path", "name", "command"] {
            guard let value = w.config.string(key)?.lowercased() else { continue }
            words.formUnion(value.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." }).map(String.init))
            if key == "url", let host = URL(string: value)?.host { words.insert(host); words.formUnion(host.split(separator: ".").map(String.init)) }
        }
        self.words = words
    }
}
