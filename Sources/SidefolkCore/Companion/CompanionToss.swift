import Foundation

/// A hand in rock, paper, scissors.
public enum Hand: String, CaseIterable, Sendable, Codable {
    case rock, paper, scissors

    /// The hand this one beats.
    public var beats: Hand {
        switch self {
        case .rock: .scissors
        case .paper: .rock
        case .scissors: .paper
        }
    }

    /// "Rock", in the app's language.
    public var title: String {
        switch self {
        case .rock: String(localized: "hand.rock", defaultValue: "Rock", comment: "Rock, paper, scissors: the rock")
        case .paper: String(localized: "hand.paper", defaultValue: "Paper", comment: "Rock, paper, scissors: the paper")
        case .scissors: String(localized: "hand.scissors", defaultValue: "Scissors", comment: "Rock, paper, scissors: the scissors")
        }
    }
}

/// What came up when the companion flipped, rolled or played a hand (D44, amended): drawn in core with the system's
/// generator, so the result is real and the model can only repeat it, then played on the desktop by the app.
public enum Toss: Sendable, Equatable {
    /// One entry per coin: true is heads. `call` is what the person called for a single coin, if they did (D75).
    case coins([Bool], call: Bool? = nil)
    /// Each die's face, and what is added to their sum (the +1 of 2d6+1).
    case dice(sides: Int, rolls: [Int], modifier: Int)
    /// The person's hand, and the companion's.
    case hands(person: Hand, companion: Hand)

    public static let maxCoins = 5
    public static let maxDice = 10
    public static let sidesRange = 2...100
    public static let modifierRange = -100...100

    /// What the caption and the card say: "Heads!", "It's 4!", "4 + 2 = 6", "Paper beats rock: you win!".
    public var result: String {
        switch self {
        case .coins(let flips, _):
            guard flips.count > 1 else {
                return flips.first == true ? String(localized: "Heads!", comment: "A coin landed on heads")
                    : String(localized: "Tails!", comment: "A coin landed on tails")
            }
            return Wording.list(flips.map { $0 ? String(localized: "coin.heads.word", defaultValue: "heads", comment: "One coin in a list of several: “heads, tails and heads”")
                : String(localized: "coin.tails.word", defaultValue: "tails", comment: "One coin in a list of several: “heads, tails and heads”") }).capitalizedFirst
        case .dice(_, let rolls, let modifier):
            if rolls.count == 1, modifier == 0 {
                return String(localized: "It's \(Self.number(rolls[0]))!", comment: "The face one die landed on: “It's 4!”")
            }
            return Self.sum(rolls, modifier, Self.number)
        case .hands(let person, let companion):
            return Self.verdict(person, companion)
        }
    }

    /// Whether the person's call was right, when they called one coin.
    public var called: Bool? {
        guard case .coins(let flips, let call?) = self, flips.count == 1 else { return nil }
        return call == flips[0]
    }

    /// The same, in English for the model.
    var forModel: String {
        switch self {
        case .coins(let flips, let call):
            let faces = flips.map { $0 ? "heads" : "tails" }
            guard flips.count > 1 else {
                guard let call else { return faces[0] }
                return "\(faces[0]); the user called \(call ? "heads" : "tails") and was \(call == flips[0] ? "right" : "wrong")"
            }
            let heads = flips.filter { $0 }.count
            return "\(faces.joined(separator: ", ")) (\(heads) heads, \(flips.count - heads) tails)"
        case .dice(let sides, let rolls, let modifier):
            let total = rolls.count == 1 && modifier == 0 ? "\(rolls[0])" : Self.sum(rolls, modifier) { "\($0)" }
            return "\(Self.notation(count: rolls.count, sides: sides, modifier: modifier)): \(total)"
        case .hands(let person, let companion):
            let outcome = person == companion ? "a draw" : person.beats == companion ? "the user wins" : "you win"
            return "the user played \(person.rawValue) and you played \(companion.rawValue): \(outcome)"
        }
    }

    /// "2d6+1", "d20": dice as players write them, in every language.
    public static func notation(count: Int, sides: Int, modifier: Int) -> String {
        "\(count == 1 ? "" : String(count))d\(sides)" + (modifier == 0 ? "" : modifier > 0 ? "+\(modifier)" : "\(modifier)")
    }

    /// "4 + 2 + 1 = 7", "4 + 2 − 1 = 5".
    public static func sum(_ rolls: [Int], _ modifier: Int, _ format: (Int) -> String) -> String {
        var parts = rolls.map(format).joined(separator: " + ")
        if modifier != 0 { parts += modifier > 0 ? " + \(format(modifier))" : " − \(format(-modifier))" }
        return parts + " = " + format(rolls.reduce(0, +) + modifier)
    }

    /// A die's face or a sum as the person's language writes numbers.
    public static func number(_ n: Int) -> String { n.formatted(.number.grouping(.never).locale(Wording.locale)) }

    /// Each pair in a whole sentence of its own, so every language can say it its way.
    private static func verdict(_ person: Hand, _ companion: Hand) -> String {
        switch (person, companion) {
        case (.rock, .scissors): String(localized: "Rock beats scissors: you win!")
        case (.scissors, .rock): String(localized: "Rock beats scissors: I win!", comment: "The companion speaks")
        case (.paper, .rock): String(localized: "Paper beats rock: you win!")
        case (.rock, .paper): String(localized: "Paper beats rock: I win!", comment: "The companion speaks")
        case (.scissors, .paper): String(localized: "Scissors beat paper: you win!")
        case (.paper, .scissors): String(localized: "Scissors beat paper: I win!", comment: "The companion speaks")
        case (.rock, _): String(localized: "We both played rock: a draw!")
        case (.paper, _): String(localized: "We both played paper: a draw!")
        case (.scissors, _): String(localized: "We both played scissors: a draw!")
        }
    }
}

/// Rock, paper, scissors over time, kept with the data so the score survives a restart (and stays in memory
/// where there is no database).
actor HandsScore {
    struct Score: Codable, Sendable, Equatable {
        var person = 0
        var companion = 0
        var draws = 0
    }

    static let key = "companion.handsScore"
    private let kv: KVStore?
    private var kept = Score()

    init(kv: KVStore? = nil) { self.kv = kv }

    /// Adds one round and returns the score after it.
    func record(person: Hand, companion: Hand) async -> Score {
        var score = (try? await kv?.get(Self.key, as: Score.self)) ?? kept
        if person == companion { score.draws += 1 } else if person.beats == companion { score.person += 1 } else { score.companion += 1 }
        kept = score
        try? await kv?.set(Self.key, score)
        return score
    }
}

/// `companion.toss`: the companion flips coins, rolls dice or plays a hand on the desktop. The draw happens here,
/// through the executor like every action, so the AI and the person's own words reach the same real chance; the
/// app only shows it (`AppEvent.toss`).
struct CompanionTossTool: Tool {
    let events: EventBus
    let score: HandsScore
    /// A whole number in the range, at random: the system's generator, or a script in tests.
    let random: @Sendable (ClosedRange<Int>) -> Int

    init(events: EventBus, score: HandsScore = HandsScore(), random: @escaping @Sendable (ClosedRange<Int>) -> Int = { Int.random(in: $0) }) {
        self.events = events
        self.score = score
        self.random = random
    }

    let spec = ToolSpec(
        name: "companion.toss", title: String(localized: "Flip a coin, roll dice or play a hand"),
        description: """
            Your companion flips coins, rolls dice or plays rock, paper, scissors on the user's desktop, where they watch it \
            happen. The result is truly random and comes back to you: say it as it came, never make one up. Use it whenever \
            the user wants a coin flip, a dice roll (count, sides and modifier, as in 2d6+1 or d20) or a round of rock, paper, \
            scissors (pass the user's hand; if they didn't say it, ask for it first).
            """,
        inputSchema: Schema.object([
            "kind": Schema.string("What to do.", enum: ["coin", "dice", "rock_paper_scissors"]),
            "count": Schema.integer("coin: how many coins (1 to 5). dice: how many dice (1 to 10). 1 if not given.", minimum: 1, maximum: 10),
            "sides": Schema.integer("dice: sides on each die; 6 if not given, 20 for a d20.", minimum: 2, maximum: 100),
            "modifier": Schema.integer("dice: added to the sum, like the +1 of 2d6+1.", minimum: -100, maximum: 100),
            "hand": Schema.string("rock_paper_scissors: the user's hand.", enum: Hand.allCases.map(\.rawValue)),
            "call": Schema.string("coin: what the user called for one coin, if they did.", enum: ["heads", "tails"]),
        ], required: ["kind"]),
        risk: .low, capabilities: [.system], category: .system, mutates: false)

    func summary(for input: JSONValue) -> String {
        let count = input["count"]?.intValue ?? 1
        switch input.string("kind") {
        case "coin": return count > 1 ? String(localized: "Flip \(count) coins") : String(localized: "Flip a coin")
        case "dice":
            let sides = input["sides"]?.intValue ?? 6
            let modifier = input["modifier"]?.intValue ?? 0
            return count == 1 && sides == 6 && modifier == 0 ? String(localized: "Roll a die")
                : String(localized: "Roll \(Toss.notation(count: count, sides: sides, modifier: modifier))", comment: "Rolling dice written as players do: “Roll 2d6”")
        default: return String(localized: "Rock, paper, scissors")
        }
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let count = input["count"]?.intValue ?? 1
        let toss: Toss
        let subtitle: String
        switch input.string("kind") {
        case "coin":
            guard (1...Toss.maxCoins).contains(count) else {
                throw ToolError.invalidInput(String(localized: "Flip between 1 and \(Toss.maxCoins) coins at a time."))
            }
            let call = count == 1 ? input.string("call").flatMap { ["heads": true, "tails": false][$0.lowercased()] } : nil
            toss = .coins((0..<count).map { _ in random(0...1) == 1 }, call: call)
            subtitle = count == 1 ? String(localized: "A coin flip") : String(localized: "\(count) coins")
        case "dice":
            let sides = input["sides"]?.intValue ?? 6, modifier = input["modifier"]?.intValue ?? 0
            guard (1...Toss.maxDice).contains(count) else {
                throw ToolError.invalidInput(String(localized: "Roll between 1 and \(Toss.maxDice) dice at a time."))
            }
            guard Toss.sidesRange.contains(sides), Toss.modifierRange.contains(modifier) else {
                throw ToolError.invalidInput(String(localized: "Dice have 2 to 100 sides, and the number added is at most 100."))
            }
            toss = .dice(sides: sides, rolls: (0..<count).map { _ in random(1...sides) }, modifier: modifier)
            subtitle = Toss.notation(count: count, sides: sides, modifier: modifier)
        case "rock_paper_scissors":
            guard let hand = input.string("hand").flatMap({ Hand(rawValue: $0.lowercased()) }) else {
                throw ToolError.invalidInput(String(localized: "Tell me the user's hand: rock, paper or scissors."))
            }
            let mine = Hand.allCases[random(0...2)]
            toss = .hands(person: hand, companion: mine)
            let s = await score.record(person: hand, companion: mine)
            let tally = String(localized: "You \(s.person) · Me \(s.companion) · Draws \(s.draws)", comment: "The rock, paper, scissors score, said by the companion")
            events.publish(.toss(toss))
            return ToolResult(
                text: "Played on the user's desktop, where they saw it: \(toss.forModel). Score this far: the user \(s.person), "
                    + "you \(s.companion), draws \(s.draws). Say it in a few words.",
                card: ResultCard(kind: .chance, title: toss.result, subtitle: tally))
        default:
            throw ToolError.invalidInput(String(localized: "“kind” must be coin, dice or rock_paper_scissors."))
        }
        events.publish(.toss(toss))
        let verb = if case .coins = toss { "Flipped" } else { "Rolled" }
        return ToolResult(text: "\(verb) on the user's desktop, where they saw it: \(toss.forModel). Say it in a few words.",
                          card: ResultCard(kind: .chance, title: toss.result, subtitle: subtitle))
    }
}
