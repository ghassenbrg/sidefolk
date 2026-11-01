import Foundation

/// What a person may say about the game they open (D93): "trivia about space, 10 questions", "guess a number between 1
/// and 1000", "you guess my number up to 500". Sidefolk passes them to the game in `game.start`'s `options` beside
/// its own (`tone`, `sneaky`, `companion`), and the game uses those it knows; nothing else about the person goes.
/// Each value is checked here, whoever asked (the person's words or the AI through `games.open`).
public struct GameSlots: Sendable, Hashable {
    /// Who guesses in a number game: `mine` the person guesses the companion's number, `yours` the companion guesses
    /// theirs (Playtime's Higher or Lower's own words).
    public enum Mode: String, Sendable, Hashable, CaseIterable { case mine, yours }

    /// A quiz's subject in the person's words ("space", "the Roman empire").
    public var topic: String?
    /// How many questions or rounds.
    public var count: Int?
    /// A number game's range.
    public var min: Int?
    public var max: Int?
    public var mode: Mode?

    public init(topic: String? = nil, count: Int? = nil, min: Int? = nil, max: Int? = nil, mode: Mode? = nil) {
        self.topic = topic
        self.count = count
        self.min = min
        self.max = max
        self.mode = mode
    }

    public static let maxTopic = 40
    public static let counts = 1...50
    public static let range = 0...1_000_000

    public var isEmpty: Bool { self == GameSlots() }

    /// From `games.open`'s input, each value checked: a topic of plain words, a count and a range in bounds, a range
    /// whose low end is below its high one (a lone `max` counts up from 1).
    public init(_ input: JSONValue) {
        if let t = input.string("topic") {
            let words = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !words.isEmpty, words.count <= Self.maxTopic, words.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                topic = ExtensionText.line(words, characters: Self.maxTopic)
            }
        }
        if let n = input["count"]?.intValue, Self.counts.contains(n) { count = n }
        let low = input["min"]?.intValue, high = input["max"]?.intValue
        if let high, Self.range.contains(high), (low ?? 1) < high, Self.range.contains(low ?? 1) {
            min = low ?? 1
            max = high
        }
        mode = input.string("mode").flatMap(Mode.init(rawValue:))
    }

    /// As `game.start`'s options take them, and `games.open`'s input.
    public var options: [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        if let topic { out["topic"] = .string(topic) }
        if let count { out["count"] = .number(Double(count)) }
        if let min, let max {
            out["min"] = .number(Double(min))
            out["max"] = .number(Double(max))
        }
        if let mode { out["mode"] = .string(mode.rawValue) }
        return out
    }
}
