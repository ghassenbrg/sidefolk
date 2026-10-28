import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Coins, dice and rock, paper, scissors (D44, amended): understood without AI, drawn for real in core, and told to the
/// app to play on the desktop.
@Suite struct IntentChanceTests {
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    func chance(_ text: String) -> ChanceIntent? {
        if case .chance(let c)? = parser.parse(text, now: TimeTest.wednesday10)?.intent { return c }
        return nil
    }

    // MARK: Words

    @Test func coinsDiceAndHandsInPlainWords() {
        let cases: [(String, ChanceIntent)] = [
            ("flip a coin", ChanceIntent(.coin)), ("Pip, toss a coin for me", ChanceIntent(.coin)), ("heads or tails?", ChanceIntent(.coin)),
            ("coin flip", ChanceIntent(.coin)), ("flip 3 coins", ChanceIntent(.coin, count: 3)), ("toss two coins", ChanceIntent(.coin, count: 2)),
            ("roll a die", ChanceIntent(.dice)), ("roll a dice", ChanceIntent(.dice)), ("roll the die", ChanceIntent(.dice)),
            ("roll the dice", ChanceIntent(.dice, count: 2)), ("roll dice", ChanceIntent(.dice, count: 2)),
            ("roll 3 dice", ChanceIntent(.dice, count: 3)), ("roll two d20s", ChanceIntent(.dice, count: 2, sides: 20)),
            ("roll a d20", ChanceIntent(.dice, sides: 20)), ("roll 2d6+1", ChanceIntent(.dice, count: 2, modifier: 1)),
            ("roll 3d8 - 2", ChanceIntent(.dice, count: 3, sides: 8, modifier: -2)), ("roll d100", ChanceIntent(.dice, sides: 100)),
            ("roll a 12-sided die", ChanceIntent(.dice, sides: 12)),
            ("rock paper scissors", ChanceIntent(.rockPaperScissors)), ("let's play rock, paper, scissors!", ChanceIntent(.rockPaperScissors)),
            ("rock", ChanceIntent(.rockPaperScissors, hand: .rock)), ("I choose paper", ChanceIntent(.rockPaperScissors, hand: .paper)),
            ("rock paper scissors: scissors", ChanceIntent(.rockPaperScissors, hand: .scissors)),
            ("I'll go with rock", ChanceIntent(.rockPaperScissors, hand: .rock)),
        ]
        for (text, expected) in cases { #expect(chance(text) == expected, "\(text)") }
        #expect(parser.parse("flip a coin", now: TimeTest.wednesday10)?.hint == "Flip a coin · no AI")
        #expect(parser.parse("roll 2d6+1", now: TimeTest.wednesday10)?.hint == "Roll 2d6+1 · no AI")
        #expect(parser.parse("roll a die", now: TimeTest.wednesday10)?.hint == "Roll a die · no AI")
        #expect(parser.parse("paper", now: TimeTest.wednesday10)?.hint == "Rock, paper, scissors: Paper · no AI")
    }

    @Test func otherSentencesAreNotChance() {
        for text in ["flip a coin to decide where we eat", "rock music", "roll back the last commit", "paper towels", "heads up",
                     "rock paper scissors is a silly game", "flip 20 coins", "roll 50 dice", "roll a d1", "what are the odds of heads?"] {
            #expect(chance(text) == nil, "\(text)")
        }
        // A trick stays a trick, and a list stays a list.
        if case .companion(.flip)? = parser.parse("do a flip", now: TimeTest.wednesday10)?.intent {} else { Issue.record("a flip is a trick") }
        if case .note? = parser.parse("add dice to my shopping list", now: TimeTest.wednesday10)?.intent {} else {
            Issue.record("dice on a shopping list is a note")
        }
    }

    // MARK: The tool

    /// Draws the numbers a test gives, in order.
    final class Script: Sendable {
        let values: Mutex<[Int]>
        init(_ values: [Int]) { self.values = Mutex(values) }
        func next(_ range: ClosedRange<Int>) -> Int {
            values.withLock { v in
                let n = v.removeFirst()
                #expect(range.contains(n), "\(n) is outside \(range)")
                return n
            }
        }
    }

    func env(_ script: [Int], score: HandsScore? = nil) throws -> TestEnv {
        let env = try TestEnv()
        let random = Script(script)
        env.registry.register(CompanionTossTool(events: env.events, score: score ?? HandsScore(kv: KVStore(env.db)), random: random.next))
        return env
    }

    func play(_ env: TestEnv, _ input: JSONValue) async -> (ToolOutcome, Toss?) {
        let stream = env.events.stream()
        let outcome = await env.executor.execute(name: "companion.toss", input: input, caller: .agent(runId: "r1"))
        let heard = await withTaskGroup(of: Toss?.self) { group in
            group.addTask {
                for await event in stream { if case .toss(let t) = event { return t } }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(outcome.isOK ? 5 : 0.2))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return (outcome, heard)
    }

    func result(_ outcome: ToolOutcome) throws -> ToolResult {
        guard case .ok(let r) = outcome.status else {
            Issue.record("expected success, got \(outcome.status)")
            throw CancellationError()
        }
        return r
    }

    @Test func aCoinIsFlippedOnTheDesktopAndTheModelHearsTheTruth() async throws {
        let (outcome, toss) = await play(try env([1]), ["kind": "coin"])
        let r = try result(outcome)
        #expect(toss == .coins([true]))
        #expect(r.card?.kind == .chance && r.card?.title == "Heads!" && r.card?.subtitle == "A coin flip")
        #expect(r.text == "Flipped on the user's desktop, where they saw it: heads. Say it in a few words.")
        #expect(outcome.activity.decision == .auto, "a coin needs nobody's approval")

        let (three, _) = await play(try env([0, 1, 0]), ["kind": "coin", "count": 3])
        let r3 = try result(three)
        #expect(r3.card?.title == "Tails, heads, tails")
        #expect(r3.text.contains("tails, heads, tails (1 heads, 2 tails)"))
    }

    @Test func diceAddUpWithTheirModifier() async throws {
        let (outcome, toss) = await play(try env([4, 2]), ["kind": "dice", "count": 2, "modifier": 1])
        let r = try result(outcome)
        #expect(toss == .dice(sides: 6, rolls: [4, 2], modifier: 1))
        #expect(r.card?.title == "4 + 2 + 1 = 7" && r.card?.subtitle == "2d6+1")
        #expect(r.text.contains("2d6+1: 4 + 2 + 1 = 7"))

        let (d20, _) = await play(try env([17]), ["kind": "dice", "sides": 20])
        #expect(try result(d20).card?.title == "It's 17!")
        #expect(try result(d20).text.contains("d20: 17"))
        #expect(Toss.dice(sides: 6, rolls: [3, 5], modifier: -2).result == "3 + 5 − 2 = 6")
    }

    @Test func rockPaperScissorsKeepsTheScoreAcrossRestarts() async throws {
        let first = try env([1])
        // Paper (index 1) against rock: the companion wins.
        let (outcome, toss) = await play(first, ["kind": "rock_paper_scissors", "hand": "rock"])
        let r = try result(outcome)
        #expect(toss == .hands(person: .rock, companion: .paper))
        #expect(r.card?.title == "Paper beats rock: I win!")
        #expect(r.card?.subtitle == "You 0 · Me 1 · Draws 0")
        #expect(r.text.contains("the user played rock and you played paper: you win") && r.text.contains("Score this far: the user 0, you 1, draws 0"))

        // A new score over the same database (the app restarted) carries on from the tool's.
        let kv = KVStore(first.db)
        _ = await HandsScore(kv: kv).record(person: .scissors, companion: .paper)
        #expect(await HandsScore(kv: kv).record(person: .rock, companion: .rock) == HandsScore.Score(person: 1, companion: 1, draws: 1))

        #expect(Toss.hands(person: .scissors, companion: .paper).result == "Scissors beat paper: you win!")
        #expect(Toss.hands(person: .paper, companion: .paper).result == "We both played paper: a draw!")
        for person in Hand.allCases {
            #expect(person.beats != person && person.beats.beats != person, "each hand beats exactly one other")
        }
    }

    @Test func whatCannotBeDrawnIsRefused() async throws {
        for input: JSONValue in [["kind": "coin", "count": 6], ["kind": "dice", "sides": 1], ["kind": "dice", "count": 11],
                                 ["kind": "rock_paper_scissors"], ["kind": "lottery"]] {
            let (outcome, toss) = await play(try env([1, 1, 1]), input)
            #expect(!outcome.isOK, "\(input)")
            #expect(toss == nil, "nothing plays on the desktop for \(input)")
        }
    }
}
