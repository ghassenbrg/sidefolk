import Foundation
import Synchronization

/// How sentences are compared (D93, D100): lowercased, their last punctuation gone, accents off Latin letters (so "mas
/// dificil" is "más difícil"), other scripts' digits as 0–9, and no spaces (Korean and Japanese are spaced either way).
public enum CommandText {
    public static func key(_ text: String) -> String {
        let trimmed = digits(text.lowercased()).trimmingCharacters(in: CharacterSet(charactersIn: " !.?？！。؟,،"))
        return latinFolded(trimmed).filter { !$0.isWhitespace }
    }

    /// Accents off Latin letters only: folding everything would turn Japanese が into か.
    public static func latinFolded(_ text: String) -> String {
        String(text.map { ch -> Character in
            guard let s = ch.unicodeScalars.first, s.value >= 0xC0, s.value < 0x250 else { return ch }
            return String(ch).folding(options: .diacriticInsensitive, locale: nil).first ?? ch
        })
    }

    /// Arabic-Indic and Persian digits as 0–9, so "١٠ أسئلة" counts ten.
    public static func digits(_ text: String) -> String {
        String(text.unicodeScalars.map { s -> Character in
            switch s.value {
            case 0x660...0x669: Character(UnicodeScalar(s.value - 0x660 + 0x30)!)
            case 0x6F0...0x6F9: Character(UnicodeScalar(s.value - 0x6F0 + 0x30)!)
            case 0xFF10...0xFF19: Character(UnicodeScalar(s.value - 0xFF10 + 0x30)!)
            default: Character(s)
            }
        })
    }

    /// Written without spaces between words (kana and Han): a word of it stands anywhere, not only between spaces.
    static func isUnspaced(_ text: String) -> Bool { text.unicodeScalars.contains { (0x3040...0x9FFF).contains($0.value) } }
}

/// Everything an extension's commands are built from, in all its languages at once (D100): a person may speak any of
/// them whatever the app's language is.
public struct CommandVocabulary: Sendable {
    public var words: [String: [String]]
    public var choices: [String: [String: [String]]]
    public var parts: [String: [ExtensionManifest.PartMeta]]
    public var carry: CommandCarry
    /// A command's sentences in each language it has them in, by its `name`.
    var translationsByLanguage: [String: [String: ExtensionStrings.CommandWords]]

    var translations: [String: [ExtensionStrings.CommandWords]] { translationsByLanguage.mapValues { Array($0.values) } }

    /// Parts already compiled. Many commands name the same parts, and a part holds its phrases in every language; a regular expression
    /// takes ICU a millisecond or more, so compiling each once is what keeps a large extension from costing seconds.
    private let compiledParts = CompiledParts()

    private final class CompiledParts: Sendable {
        let parts = Mutex<[String: CommandPart]>([:])
    }

    init(words: [String: [String]] = [:]) {
        self.words = words
        choices = [:]
        parts = [:]
        carry = CommandCarry()
        translationsByLanguage = [:]
    }

    /// The part of this name, compiled once for this vocabulary.
    func compiledPart(_ name: String) -> CommandPart? {
        if let known = compiledParts.parts.withLock({ $0[name] }) { return known }
        guard let metas = parts[name] else { return nil }
        // The same phrase in several languages ("{level:level}") is one phrase.
        let phrases = Set(metas.flatMap(\.say)).compactMap { CommandPhrase($0, vocabulary: self) }.sorted { $0.length > $1.length }
        guard !phrases.isEmpty else { return nil }
        let part = CommandPart(name: name, phrases: phrases, fixed: metas.first?.input ?? [:], isFree: phrases.contains { $0.slots.contains { $0.isFree } })
        compiledParts.parts.withLock { $0[name] = part }
        return part
    }

    public init(manifest m: ExtensionManifest, strings: ExtensionStrings?) {
        words = m.words
        choices = m.choices
        parts = m.parts.mapValues { [$0] }
        var carryMeta = [m.carry]
        translationsByLanguage = [:]
        for (language, table) in strings?.tables ?? [:] {
            for (list, byValue) in table.choices {
                for (value, spoken) in byValue { choices[list, default: [:]][value, default: []] += spoken }
            }
            for (part, say) in table.parts {
                // A translated part means what the English one does: same fixed arguments.
                parts[part, default: []].append(ExtensionManifest.PartMeta(say: say, input: m.parts[part]?.input))
            }
            if let carry = table.carry { carryMeta.append(carry) }
            for (command, words) in table.commands { translationsByLanguage[command, default: [:]][language] = words }
        }
        carry = CommandCarry(carryMeta)
    }
}

/// The words that only carry a sentence, as one extension declares them (D100): what is left once they are out must be
/// exactly a command's name, or the sentence goes to the AI.
public struct CommandCarry: Sendable {
    let words: Set<String>
    let lead: Set<String>
    let leadInside: [String]
    let inside: [String]
    let endings: [String]
    /// Words that carry only this sentence: the companion's own name, which the extension can't know ("play marbles with mochi").
    var also: Set<String> = []

    init(_ metas: [ExtensionManifest.CarryMeta] = []) {
        let all = metas.flatMap(\.words) + metas.flatMap(\.lead)
        words = Set(all.map { CommandText.latinFolded($0.lowercased()) })
        let leads = metas.flatMap(\.lead).map { $0.lowercased() }
        lead = Set(leads.filter { !CommandText.isUnspaced($0) })
        leadInside = leads.filter(CommandText.isUnspaced)
        inside = Array(Set(metas.flatMap(\.inside))).sorted { $0.count > $1.count }
        endings = Array(Set(metas.flatMap(\.endings))).sorted { $0.count > $1.count }
    }

    /// Whether the sentence says a name is meant.
    func leads(_ text: String) -> Bool {
        let said = text.lowercased()
        let spoken = Set(said.split { $0.isWhitespace || ",.!?".contains($0) }.map(String.init))
        return !spoken.isDisjoint(with: lead) || leadInside.contains { said.contains($0) }
    }

    /// The words left once the carrying ones are out, joined without spaces.
    func residual(_ text: String) -> String {
        var t = CommandText.latinFolded(text.lowercased())
        for mark in [",", ".", "!", "?", "？", "！", "。", "、", "؟", "،", ";", ":", "-", "–", "\"", "“", "”", "«", "»"] {
            t = t.replacingOccurrences(of: mark, with: " ")
        }
        let kept = t.split(whereSeparator: \.isWhitespace).map(String.init).compactMap { word -> String? in
            // Elided articles: "l'ultimo", "all'ultimo", "d'animaux".
            var w = word
            if let quote = w.firstIndex(of: "'"), w.distance(from: w.startIndex, to: quote) <= 4, w.index(after: quote) < w.endIndex,
               !words.contains(w) {
                w = String(w[w.index(after: quote)...])
            }
            if words.contains(w) || also.contains(w) { return nil }
            for ending in endings where w.count > ending.count + 1 && w.hasSuffix(ending) {
                w = String(w.dropLast(ending.count))
                break
            }
            return w
        }
        var joined = kept.joined()
        for piece in inside where joined.contains(piece) { joined = joined.replacingOccurrences(of: piece, with: "") }
        return joined
    }

    /// Free words without carrying ones at their ends ("space with" is "space").
    func trimmed(_ raw: String) -> String? {
        var said = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        func carries(_ word: String) -> Bool {
            let folded = CommandText.latinFolded(word.lowercased())
            return words.contains(folded) || also.contains(folded)
        }
        while let w = said.last, carries(w) { said.removeLast() }
        while let w = said.first, carries(w) { said.removeFirst() }
        let kept = said.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        return kept.isEmpty ? nil : kept
    }
}

/// A part of a sentence, compiled: found wherever it stands, its slots read, and taken out.
struct CommandPart: Sendable {
    let name: String
    let phrases: [CommandPhrase]
    let fixed: [String: JSONValue]
    /// Holds a slot of free words: looked for only when the name doesn't stand without it.
    let isFree: Bool

    /// Takes the first phrase found out of `text`, and what it says.
    func take(from text: inout String, carry: CommandCarry) -> [String: JSONValue]? {
        for phrase in phrases {
            guard let values = phrase.take(from: &text, carry: carry) else { continue }
            return values.merging(fixed) { own, _ in own }
        }
        return nil
    }
}

/// One way of saying a part. Unlike a whole sentence it stands anywhere, between spaces or punctuation (anywhere at all in
/// languages written without spaces).
struct CommandPhrase: Sendable {
    let slots: [CommandSentence.Slot]
    let length: Int
    private let regex: NSRegularExpression

    init?(_ written: String, vocabulary v: CommandVocabulary) {
        let text = written.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= CommandSentence.maxLength else { return nil }
        // Slots and the words between them; compiled by hand, because a phrase's edges differ from a sentence's.
        var pattern = ""
        var slots: [CommandSentence.Slot] = []
        var rest = Substring(text)
        var endsInSlot = false
        while let open = rest.firstIndex(of: "{") {
            guard let close = rest[open...].firstIndex(of: "}"),
                  let slot = try? CommandSentence("xx {\(rest[rest.index(after: open)..<close])}", words: v.words, choices: v.choices).slots.first else { return nil }
            let literal = rest[..<open]
            pattern += Self.literal(literal, afterSlot: endsInSlot)
            pattern += "(?<s\(slots.count)>\(Self.slotPattern(slot, last: rest[rest.index(after: close)...].allSatisfy(\.isWhitespace))))"
            slots.append(slot)
            endsInSlot = true
            rest = rest[rest.index(after: close)...]
        }
        pattern += Self.literal(rest, afterSlot: endsInSlot)
        let first = text.first.map(String.init) ?? "", last = text.last.map(String.init) ?? ""
        // A word's edge, in languages with spaces; a vocabulary's words carry their own, and a number only needs not to be
        // part of a longer one.
        let opens = text.hasPrefix("{") ? (slots.first?.vocabulary == nil ? #"(?<![\p{N}.,])"# : "") : CommandText.isUnspaced(first) ? "" : #"(?<![\p{L}\p{N}'])"#
        let closes = text.hasSuffix("}") ? (slots.last?.vocabulary == nil ? #"(?![\p{N}])"# : "") : CommandText.isUnspaced(last) ? "" : #"(?![\p{L}\p{N}])"#
        guard let regex = try? NSRegularExpression(pattern: opens + pattern + closes, options: [.caseInsensitive]) else { return nil }
        self.regex = regex
        self.slots = slots
        length = text.count
    }

    private static func literal(_ text: Substring, afterSlot: Bool) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty else { return text.isEmpty ? "" : #"\s+"# }
        var out = words.joined(separator: #"\s+"#)
        // A number's unit may touch it ("10questions", "10問"); words before a slot keep their space.
        if afterSlot, text.first?.isWhitespace == true { out = #"\s*"# + out }
        if text.last?.isWhitespace == true { out += #"\s+"# }
        return out
    }

    private static func slotPattern(_ slot: CommandSentence.Slot, last: Bool) -> String {
        guard let vocabulary = slot.vocabulary else {
            // Free words stop at a comma: "a quiz about space, hard".
            if slot.kind == .text { return last ? #"[^,،、]+"# : #"[^,،、]+?"# }
            return slot.kind.pattern
        }
        return "(?:" + vocabulary.sorted { $0.count > $1.count }.map { word -> String in
            let escaped = word.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s+"#)
            return CommandText.isUnspaced(word) ? escaped : #"(?<![\p{L}\p{N}'])"# + escaped + #"(?![\p{L}\p{N}])"#
        }.joined(separator: "|") + ")"
    }

    func take(from text: inout String, carry: CommandCarry) -> [String: JSONValue]? {
        let whole = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: whole), let found = Range(m.range, in: text) else { return nil }
        var values: [String: JSONValue] = [:]
        for (i, slot) in slots.enumerated() {
            guard let r = Range(m.range(withName: "s\(i)"), in: text) else { return nil }
            var raw = String(text[r])
            if slot.kind == .text, slot.vocabulary == nil {
                guard let kept = carry.trimmed(raw) else { return nil }
                raw = kept
            }
            guard let value = slot.value(raw) else { return nil }
            values[slot.name] = value
        }
        // Two numbers in one phrase are a range, read low to high: "between 1000 and 1" isn't one.
        if slots.count == 2, case .number(let low)? = values[slots[0].name], case .number(let high)? = values[slots[1].name], low >= high { return nil }
        text.replaceSubrange(found, with: " ")
        return values
    }
}

/// A command said by its name with parts around it, in any order (D100): "a quiz about space, hard, 10 questions",
/// "jouons au morpion difficile", "guess a number between 1 and 1000". Conservative like the rest of the parser (D4):
/// once the parts and the carrying words are out, what remains must be exactly its name, and a bare name counts only with a
/// word that says it is meant or a part, so another extension's command keeps it. Its whole sentences (`say`) may have the same
/// parts around them: what remains is then compared as the sentence is, carrying words and all, so it stays as strict as saying it alone.
struct CommandFrame: Sendable {
    let names: Set<String>
    let parts: [CommandPart]
    let carry: CommandCarry
    /// Its whole sentences, for when parts stand around one: without a slot by `CommandText.key`, with one compiled.
    let wholeSentences: Set<String>
    let slottedSentences: [CommandSentence]

    init?(_ command: ExtensionManifest.Command, vocabulary v: CommandVocabulary, sentences: [CommandSentence] = []) {
        let translated = command.name.flatMap { v.translations[$0] }?.flatMap(\.names) ?? []
        carry = v.carry
        let carry = v.carry
        names = Set((command.names + translated).map { carry.residual($0) }.filter { !$0.isEmpty })
        let compiled = command.with.compactMap(v.compiledPart)
        wholeSentences = compiled.isEmpty ? [] : Set(sentences.filter(\.slots.isEmpty).map { CommandText.key($0.written) })
        slottedSentences = compiled.isEmpty ? [] : sentences.filter { !$0.slots.isEmpty }
        guard !names.isEmpty || !wholeSentences.isEmpty || !slottedSentences.isEmpty else { return nil }
        // Numbers and enums come out first, free words last: "a quiz about space, hard" must not take "hard" as the topic.
        parts = compiled.filter { !$0.isFree } + compiled.filter(\.isFree)
    }

    /// What the sentence says around the name, or nil when it isn't this command. `companion`: its names just now, which only carry a sentence.
    func match(_ command: String, companion: Set<String> = []) -> [String: JSONValue]? {
        var carry = carry
        carry.also = companion
        let meant = carry.leads(command)
        var text = " " + command.replacingOccurrences(of: "’", with: "'") + " "
        var values: [String: JSONValue] = [:]
        var tookPart = false
        for part in parts where !part.isFree {
            guard let found = part.take(from: &text, carry: carry) else { continue }
            // The same thing said twice ("easy … hard") is unclear: the AI's to read.
            var again = text
            if part.take(from: &again, carry: carry) != nil { return nil }
            values.merge(found) { own, _ in own }
            tookPart = true
        }
        func ends(_ text: String) -> [String: JSONValue]? {
            if names.contains(carry.residual(text)), meant || tookPart { return [:] }
            guard tookPart else { return nil }
            // What joined the sentence to the part goes with the part: "spin the wheel; red".
            let said = text.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;:!-–—"))
            if wholeSentences.contains(CommandText.key(said)) { return [:] }
            return slottedSentences.lazy.compactMap { $0.match(said) }.first
        }
        if let rest = ends(text) { return values.merging(rest) { own, _ in own } }
        for part in parts where part.isFree {
            guard let found = part.take(from: &text, carry: carry) else { continue }
            values.merge(found) { own, _ in own }
            tookPart = true
            if let rest = ends(text) { return values.merging(rest) { own, _ in own } }
        }
        return nil
    }
}
