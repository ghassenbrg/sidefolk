import Foundation

extension ExtensionManifest {
    /// Sentences that call one tool at once, without the AI (D50). `say` holds whole sentences with typed slots
    /// ("time in {place:place}"); `input` builds the tool's arguments from them (`"places": ["{place}"]`). Without
    /// `input`, each slot fills the argument of the same name.
    public struct Command: Sendable, Hashable, Decodable {
        public var say: [String]
        public var input: [String: JSONValue]?

        public init(say: [String], input: [String: JSONValue]? = nil) {
            self.say = say
            self.input = input
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["say", "input"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            // One sentence may be written on its own.
            if let one = try? c.decode(String.self, forKey: "say") { say = [one] } else { say = try c.decode([String].self, forKey: "say") }
            input = try c.decodeIfPresent([String: JSONValue].self, forKey: "input")
        }
    }
}

/// What a slot accepts, and what the tool receives for it. The kinds that take any words (`isFree`) are kept away
/// from the start of a sentence and from each other, so no command can swallow whatever the person says.
public enum CommandSlotKind: String, Sendable, CaseIterable {
    /// Any words, up to 200 characters.
    case text
    /// One word or code: "usd", "km/h", "°F".
    case word
    /// A number, "12", "-3.5", "1,000".
    case number
    /// A whole number.
    case integer
    /// Arithmetic: digits, + - * / ^ % × ÷, parentheses, "of" and a few functions (sqrt, round, pi…).
    case expression
    /// A town, a country or a time zone: letters, spaces and . , ' - /, up to six words.
    case place
    /// A web address, with or without https://.
    case url
    /// A day: "today", "tomorrow", "2026-12-25", "25 December 2026", "December 25". Passed on as typed.
    case date
    /// Several things: "a, b or c" (2 to 20 of them).
    case list

    var isFree: Bool {
        switch self {
        case .text, .word, .place, .list: true
        case .number, .integer, .expression, .url, .date: false
        }
    }

    /// The regular expression a slot of this kind matches; the value is checked again by `value(_:)`.
    var pattern: String {
        switch self {
        case .text, .list, .date: #".+?"#
        case .word: #"\S{1,30}"#
        case .number: #"[-+]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#
        case .integer: #"[-+]?\d{1,15}"#
        case .expression: #"[0-9A-Za-z.,+\-*/^%()×÷ ]+?"#
        case .place: #"\p{L}[\p{L}\p{M} .,'\-/]*?"#
        case .url: #"\S+"#
        }
    }

    /// Words an expression may hold besides numbers and operators: what a calculator understands.
    static let expressionWords: Set<String> = ["of", "x", "sqrt", "abs", "round", "ln", "log", "sin", "cos", "tan", "pi", "e"]

    /// The value a tool receives for `raw`, or nil when it isn't one after all ("2026-10-28" is a date, not a sum).
    func value(_ raw: String) -> JSONValue? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        switch self {
        case .text:
            return text.count <= 200 ? .string(text) : nil
        case .word:
            return .string(text)
        case .number:
            guard let n = Double(text.replacingOccurrences(of: ",", with: "")), n.isFinite else { return nil }
            return .number(n)
        case .integer:
            return Int(text.hasPrefix("+") ? String(text.dropFirst()) : text).map { .number(Double($0)) }
        case .expression:
            return Self.isExpression(text) ? .string(text) : nil
        case .place:
            let place = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,"))
            guard !place.isEmpty, place.count <= 60, place.split(separator: " ").count <= 6 else { return nil }
            return .string(place)
        case .url:
            let full = text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") ? text : "https://" + text
            guard full.count <= 2000, let url = URL(string: full), let host = url.host, host.contains(".") || host == "localhost" else { return nil }
            return .string(full)
        case .date:
            return Self.isDate(text) ? .string(text) : nil
        case .list:
            let items = text.replacingOccurrences(of: #"\s+(?:or|and)\s+|\s*[,;/|]\s*"#, with: "\u{1F}", options: [.regularExpression, .caseInsensitive])
                .split(separator: "\u{1F}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard (2...20).contains(items.count), items.allSatisfy({ $0.count <= 60 }) else { return nil }
            return .array(items.map { .string($0) })
        }
    }

    /// The dates a person writes in English, read strictly: "christmas" or "next friday" is for the AI.
    static func isDate(_ text: String) -> Bool {
        let lower = text.lowercased()
        if ["today", "tomorrow", "yesterday"].contains(lower) { return true }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.isLenient = false
        let patterns = ["yyyy-MM-dd", "d MMMM yyyy", "MMMM d, yyyy", "MMMM d yyyy", "d MMM yyyy", "MMM d, yyyy", "MMM d yyyy",
                        "d MMMM", "MMMM d", "d MMM", "MMM d"]
        return patterns.contains { pattern in
            format.dateFormat = pattern
            return format.date(from: lower) != nil
        }
    }

    /// A sum, not a date, a phone number or a lone number: a digit, an operator or a function, and only the words a
    /// calculator knows.
    static func isExpression(_ text: String) -> Bool {
        guard text.count <= 200, text.contains(where: \.isNumber) else { return false }
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard words.allSatisfy(expressionWords.contains) else { return false }
        let operators = text.contains { "+-*/^%×÷".contains($0) } || words.contains { $0 != "pi" && $0 != "e" }
        // "2026-10-28" and "10/28/2026" are dates someone pasted, and "555-1234" a number to call.
        let dates = [#"^\d{4}-\d{1,2}-\d{1,2}$"#, #"^\d{1,2}/\d{1,2}/\d{2,4}$"#, #"^\d{3}-\d{4}$"#, #"^\d+(?:-\d+){2,}$"#,
                     #"^\d+(?:/\d+){2,}$"#]
        return operators && !dates.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}

/// Why a command can't be used, in the words `sidefolk ext validate` prints.
public struct CommandProblem: Error, Sendable, Hashable {
    public var message: String
}

/// One sentence of a command, compiled: "time in {place:place}" matches "Time in Tokyo" and gives place = "Tokyo".
/// Sentences are whole: case doesn't matter, the person's polite words are already gone (`IntentParser.prepare`), and
/// anything more or less is not a match.
public struct CommandSentence: Sendable {
    public struct Slot: Sendable, Hashable {
        public let name: String
        public let kind: CommandSlotKind
        /// The extension's own words this slot takes (`words.unit` in the manifest), nil for Sidefolk's kinds.
        public let vocabulary: [String]?
        /// What it takes, as written after the colon: "place", or the name of the extension's list ("unit").
        let accepts: String

        init(name: String, kind: CommandSlotKind, vocabulary: [String]? = nil, accepts: String? = nil) {
            self.name = name
            self.kind = kind
            self.vocabulary = vocabulary
            self.accepts = accepts ?? kind.rawValue
        }

        /// Takes any words: such a slot never starts a sentence or touches another.
        var isFree: Bool { vocabulary == nil && kind.isFree }

        var pattern: String {
            guard let vocabulary else { return kind.pattern }
            // Longest first, so "fl oz" wins over "fl"; any spacing between a word's parts.
            let words = vocabulary.sorted { $0.count > $1.count }.map { word in
                word.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
            }
            return "(?:" + words.joined(separator: "|") + ")"
        }

        func value(_ raw: String) -> JSONValue? {
            guard vocabulary != nil else { return kind.value(raw) }
            let word = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return word.isEmpty ? nil : .string(word)
        }
    }

    private enum Piece {
        case literal(String)
        case slot(Slot)
    }

    public let written: String
    public let slots: [Slot]
    /// As people see it in Settings, each slot as "…": "time in …".
    public let shown: String
    /// What it matches, whatever its slots are called: two sentences with one shape are the same command.
    let shape: String
    private let regex: NSRegularExpression

    public static let maxSlots = 3
    public static let maxLength = 80
    /// Sentences that are someone's reply or a word to Sidefolk, never a command of their own.
    static let reserved: Set<String> = ["yes", "no", "ok", "okay", "sure", "thanks", "thank you", "stop", "cancel", "help", "undo",
                                        "hi", "hello", "hey", "what", "why", "how", "again", "more", "next", "done"]

    /// - Parameter words: the extension's word lists (`words` in its manifest), for slots like `{from:unit}`.
    public init(_ written: String, words: [String: [String]] = [:]) throws(CommandProblem) {
        let text = written.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= Self.maxLength else {
            throw CommandProblem(message: "must be 1–\(Self.maxLength) characters.")
        }
        guard !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw CommandProblem(message: "can't contain line breaks or control characters.")
        }
        let pieces = try Self.pieces(text, words: words)
        let slots = pieces.compactMap { if case .slot(let s) = $0 { s } else { nil } }
        guard slots.count <= Self.maxSlots else {
            throw CommandProblem(message: "can have at most \(Self.maxSlots) slots.")
        }
        guard Set(slots.map(\.name)).count == slots.count else { throw CommandProblem(message: "names a slot twice.") }
        let literal = pieces.compactMap { if case .literal(let l) = $0 { l } else { nil } }.joined(separator: " ")
        // A lone sum ("12*7") is the one sentence with no word of its own: an expression is never someone's words.
        let loneSum = slots.count == 1 && slots[0].kind == .expression && slots[0].vocabulary == nil
            && literal.trimmingCharacters(in: .whitespaces).isEmpty
        guard loneSum || literal.range(of: #"\p{L}{2,}"#, options: .regularExpression) != nil else {
            throw CommandProblem(message: "needs at least one word of its own, like “time in {place:place}”.")
        }
        if case .slot(let first) = pieces.first, first.isFree {
            throw CommandProblem(message: "can't start with {\(first.name)}: a slot that takes any words must come after a word of the sentence.")
        }
        // Slots with only spaces between them touch.
        let solid = pieces.filter { if case .literal(let l) = $0 { !l.trimmingCharacters(in: .whitespaces).isEmpty } else { true } }
        for (a, b) in zip(solid, solid.dropFirst()) {
            if case .slot(let x) = a, case .slot(let y) = b, x.isFree || y.isFree {
                throw CommandProblem(message: "needs a word between {\(x.name)} and {\(y.name)}.")
            }
        }
        if slots.isEmpty, Self.reserved.contains(Self.normalized(literal)) {
            throw CommandProblem(message: "“\(text)” is a reply anyone might type; it can't be a command.")
        }
        self.written = text
        self.slots = slots
        shape = Self.normalized(pieces.map { piece in
            switch piece {
            case .literal(let l): l
            case .slot(let s): "{\(s.accepts)}"
            }
        }.joined())
        shown = pieces.map { piece in
            switch piece {
            case .literal(let l): l
            case .slot: "…"
            }
        }.joined()
        regex = try! NSRegularExpression(pattern: "^\\s*" + Self.pattern(pieces) + "\\s*$", options: [.caseInsensitive])
    }

    /// The slot values of `command`, or nil when it isn't this sentence.
    public func match(_ command: String) -> [String: JSONValue]? {
        let whole = NSRange(command.startIndex..., in: command)
        guard let m = regex.firstMatch(in: command, options: [], range: whole) else { return nil }
        var values: [String: JSONValue] = [:]
        for (i, slot) in slots.enumerated() {
            guard let r = Range(m.range(withName: "s\(i)"), in: command), let value = slot.value(String(command[r])) else { return nil }
            values[slot.name] = value
        }
        return values
    }

    /// Lower-cased, single-spaced and without the punctuation at its ends, to compare sentences.
    static func normalized(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
    }

    private static func pieces(_ text: String, words: [String: [String]]) throws(CommandProblem) -> [Piece] {
        var pieces: [Piece] = []
        var literal = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(where: { $0 == "{" || $0 == "}" }) {
            guard rest[open] == "{" else { throw CommandProblem(message: "has a “}” without its “{”.") }
            literal += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { throw CommandProblem(message: "has a “{” without its “}”.") }
            let inside = rest[rest.index(after: open)..<close]
            let parts = inside.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let name = parts[0]
            guard name.range(of: #"^[a-z][a-z0-9_]{0,31}$"#, options: .regularExpression) != nil else {
                throw CommandProblem(message: "has a slot “{\(inside)}” whose name isn't lowercase letters, digits and _.")
            }
            let kindName = parts.count > 1 ? parts[1] : CommandSlotKind.text.rawValue
            let slot: Slot
            if let kind = CommandSlotKind(rawValue: kindName) {
                slot = Slot(name: name, kind: kind)
            } else if let list = words[kindName], !list.isEmpty {
                slot = Slot(name: name, kind: .word, vocabulary: list, accepts: kindName)
            } else {
                let kinds = CommandSlotKind.allCases.map(\.rawValue).joined(separator: ", ")
                throw CommandProblem(message: "has a slot of a kind Sidefolk doesn't know, “\(kindName)”; use one of \(kinds), or a list in “words”.")
            }
            if !literal.isEmpty { pieces.append(.literal(literal)) }
            literal = ""
            pieces.append(.slot(slot))
            rest = rest[rest.index(after: close)...]
        }
        literal += rest
        if !literal.isEmpty { pieces.append(.literal(literal)) }
        return pieces
    }

    /// Words match as words (any spacing, any case); after "," or ":" the space is optional.
    private static func pattern(_ pieces: [Piece]) -> String {
        var out = ""
        var index = 0
        for piece in pieces {
            switch piece {
            case .literal(let text):
                let words = text.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
                // Only spaces, between two slots: one gap.
                guard !words.isEmpty else {
                    out += "\\s+"
                    continue
                }
                if text.first?.isWhitespace == true, !out.isEmpty { out += "\\s+" }
                out += words.joined(separator: "\\s+")
                if text.last?.isWhitespace == true {
                    out += text.trimmingCharacters(in: .whitespaces).last.map { ",:;".contains($0) } == true ? "\\s*" : "\\s+"
                }
            case .slot(let slot):
                out += "(?<s\(index)>\(slot.pattern))"
                index += 1
            }
        }
        return out
    }
}

/// A tool's commands, compiled when the tool is registered, with the arguments each fills in.
public struct ToolCommands: Sendable {
    struct Entry: Sendable {
        let sentences: [CommandSentence]
        let input: [String: JSONValue]?
    }

    let entries: [Entry]

    /// Sentences that don't compile are left out: the validator refused them at install, so only a manifest changed
    /// since could hold one.
    public init?(_ commands: [ExtensionManifest.Command], words: [String: [String]] = [:]) {
        let entries = commands.map { command in
            Entry(sentences: command.say.compactMap { try? CommandSentence($0, words: words) }, input: command.input)
        }.filter { !$0.sentences.isEmpty }
        guard !entries.isEmpty else { return nil }
        self.entries = entries
    }

    /// Every sentence as people see it ("time in …"), for Settings and the install sheet.
    public var shown: [String] { entries.flatMap { $0.sentences.map(\.shown) } }

    /// The arguments `command` gives the tool, from the first sentence it is.
    public func input(for command: String) -> JSONValue? {
        for entry in entries {
            for sentence in entry.sentences {
                guard let values = sentence.match(command) else { continue }
                if let built = Self.build(entry.input, values) { return built }
            }
        }
        return nil
    }

    /// `template` with each "{slot}" replaced by its value (a list's items join the array they stand in); without a
    /// template, each slot is the argument of its name.
    static func build(_ template: [String: JSONValue]?, _ values: [String: JSONValue]) -> JSONValue? {
        guard let template else { return .object(values) }
        func fill(_ value: JSONValue) -> [JSONValue]? {
            if case .string(let s) = value, let name = slotReference(s) {
                guard let v = values[name] else { return nil }
                return [v]
            }
            if case .array(let items) = value {
                var out: [JSONValue] = []
                for item in items {
                    guard let filled = fill(item) else { return nil }
                    for v in filled { if case .array(let inner) = v { out += inner } else { out.append(v) } }
                }
                return [.array(out)]
            }
            return [value]
        }
        var out: [String: JSONValue] = [:]
        for (key, value) in template {
            guard let filled = fill(value)?.first else { return nil }
            out[key] = filled
        }
        return .object(out)
    }

    /// "{place}" names the slot `place`; anything else is taken as written.
    static func slotReference(_ s: String) -> String? {
        guard s.hasPrefix("{"), s.hasSuffix("}"), s.count > 2 else { return nil }
        let name = String(s.dropFirst().dropLast())
        return name.range(of: #"^[a-z][a-z0-9_]{0,31}$"#, options: .regularExpression) != nil ? name : nil
    }
}
