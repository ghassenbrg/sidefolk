import Foundation
import Testing
@testable import SidefolkCore

/// Random sentences in the syntax D35 added ("every 30 minutes until 6pm", "tell me the CPU every 10 s for an hour",
/// "notify me", "until I stop it"), mixed with reminder, quiet and stop words. The parser runs on every keystroke for
/// the hint line, so it must never crash, and whatever it claims must be usable as is: a reminder in the future
/// with no time words in its title and a repeat that starts before it ends, a report the tool would accept.
/// Seeded, so a failure names an input that reproduces.
@Suite struct NewSyntaxFuzzTests {
    static let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")
    static let nows = [TimeTest.wednesday10, TimeTest.date(2025, 10, 22, 17, 45), TimeTest.date(2025, 10, 22, 23, 50),
                       TimeTest.date(2025, 12, 31, 23, 30), TimeTest.date(2028, 2, 29, 8)]

    static let leads = ["remind me", "set a reminder", "please remind me", "hey pip, remind me", "tell me", "show me", "", "notify me of",
                        "can you remind me", "reminder:", "urgent: remind me", "stop telling me", "quiet", "go quiet"]
    static let pieces = [
        "every", "each", "every other", "30", "15", "2", "90", "10s", "minute", "minutes", "min", "hour", "hours", "half hour", "seconds",
        "second", "until", "till", "6pm", "18:00", "6", "9am", "10:30", "midnight", "friday", "tomorrow", "for", "an hour", "the next 30 minutes",
        "to", "stretch", "drink water", "the cpu", "cpu usage", "my battery", "free disk", "the temperature in Fukuoka", "weather in Paris",
        "notify me", "I stop it", "forever", "between", "from", "9", "and", "5", "at", "on", "weekday", "monday", "the 1st", "of every month",
        "in", "20 min", "yesterday", "later", "important", "99999999999999999999", "0", "-1", "once a minute", "s", "h", "m",
    ]

    static let fillers = ["stretch", "drink water", "check the oven", "call mom", "log time", "stand up"]
    static let units = ["minute", "minutes", "min", "hour", "hours", "seconds", "s", "m", "h"]
    static let ends = ["6pm", "18:00", "6", "9am", "10:30", "midnight", "friday", "tomorrow", "I stop it", "noon", "5:30pm", "next week"]
    static let subjects = ["the cpu", "cpu usage", "my battery", "free disk space", "the memory", "the temperature in Fukuoka",
                           "humidity in new york", "the weather in Paris, France", "network speed"]

    /// A shuffled bag of words: catches crashes and confident misreads of odd input.
    static func bag(_ rng: inout Seeded) -> String {
        let n = Int.random(in: 1...8, using: &rng)
        let words = (0..<n).map { _ in pieces.randomElement(using: &rng)! }
        return ([leads.randomElement(using: &rng)!] + words).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The shapes people type, with the parts in different orders.
    static func shaped(_ rng: inout Seeded) -> String {
        let every = "every \([1, 2, 5, 10, 15, 30, 45, 90].randomElement(using: &rng)!) \(units.randomElement(using: &rng)!)"
        let until = Bool.random(using: &rng) ? "until \(ends.randomElement(using: &rng)!)" : ""
        if Bool.random(using: &rng) {
            let what = "to " + fillers.randomElement(using: &rng)!
            let order = [["remind me", every, until, what], ["remind me", what, every, until], ["remind me", every, what, until]]
            return order.randomElement(using: &rng)!.filter { !$0.isEmpty }.joined(separator: " ")
        }
        let subject = subjects.randomElement(using: &rng)!
        let extra = ["", "notify me", "for an hour", "for the next 30 minutes"].randomElement(using: &rng)!
        let order = [[every, "tell me", subject, until, extra], ["tell me", subject, every, until, extra], ["show", subject, every, extra, until]]
        return order.randomElement(using: &rng)!.filter { !$0.isEmpty }.joined(separator: " ")
    }

    @Test func realisticSentencesAreRightOrLeftToTheAI() {
        expectNoProblems(seed: 0x51DE_F01C, make: Self.shaped, titles: true)
    }

    /// Word salad may become an odd title, but never a crash, a time in the past or a repeat or report that can't run.
    @Test func wordSaladNeverCrashesOrClaimsSomethingUnusable() {
        expectNoProblems(seed: 0xF022_5A1D, make: Self.bag, titles: false)
    }

    func expectNoProblems(seed: UInt64, make: (inout Seeded) -> String, titles: Bool) {
        var rng = Seeded(seed: seed)
        var problems: [String] = []
        for _ in 0..<12_000 {
            let text = make(&rng)
            let now = Self.nows.randomElement(using: &rng)!
            guard let parsed = Self.parser.parse(text, now: now, knownCollections: ["Work"]) else { continue }
            if let why = Self.problem(parsed, now: now, titles: titles) { problems.append("“\(text)” at \(TimeTest.show(now)): \(why)") }
            if problems.count >= 20 { break }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// What makes a claimed intent unusable; nil when it is fine.
    static func problem(_ parsed: ParsedIntent, now: Date, titles: Bool) -> String? {
        guard parsed.hint.hasSuffix("no AI") else { return "hint “\(parsed.hint)”" }
        switch parsed.intent {
        case .remind(let title, let when, let rule, _, let anchor):
            if when <= now { return "fires in the past (\(TimeTest.show(when)))" }
            if title.isEmpty { return "no title" }
            if titles, Self.timeWords.found(in: title) { return "time words in the title “\(title)”" }
            guard let rule else { return nil }
            if !(1...Recurrence.maxInterval).contains(rule.interval) { return "interval \(rule.interval)" }
            if let until = rule.until, until < when { return "ends (\(TimeTest.show(until))) before it starts" }
            if let anchor, anchor > when { return "the series starts (\(TimeTest.show(anchor))) after its first fire" }
            let first = RecurrenceMath.nextOccurrence(after: when.addingTimeInterval(-1), recurrence: rule, anchor: anchor ?? when,
                                                      calendar: TimeTest.utc)
            if first != when { return "first fire \(TimeTest.show(first)) isn't \(TimeTest.show(when))" }
        case .report(let r):
            if !(r.everySeconds > 0 && r.everySeconds <= WatchLimits.maxInterval) { return "every \(r.everySeconds) s" }
            if r.untilStopped && r.until != nil { return "both an end and until stopped" }
            if let until = r.until {
                // As `Report.end` reads it when the tool runs.
                guard let end = Self.parser.when.parse(until, now: now) ?? Self.parser.when.parse("in " + until, now: now),
                      end.date > now, end.recurrence == nil else { return "end “\(until)” the tool can't read" }
            }
        case .quiet(let until):
            if let until, until <= now { return "quiet until the past" }
        default:
            break
        }
        return nil
    }

    static let timeWords = Scan(#"\b(?:every|each|until|till|forever)\b|(?<!\bfor\s)\b\d+\s*(?:minutes?|mins?|hours?|hrs?|seconds?)\b|\b(?:between|from)\s+\d"#)

    @Test(arguments: [
        "remind me every 30 minutes for an hour to stretch",
        "remind me every 30 minutes between 9 and 5 to stretch",
        "remind me every hour from 9 to 5 to drink water",
        "remind me every 30 minutes to stretch until friday",
        "remind me to stand up every 2 minutes until I stop it",
        "set a reminder for the next 30 minutes",
    ]) func whatARepeatCantHoldGoesToTheAI(text: String) {
        #expect(Self.parser.parse(text, now: TimeTest.wednesday10) == nil)
    }

    @Test func aTitleMayStillSayUntilWhenNothingRepeats() {
        let parsed = Self.parser.parse("remind me tomorrow at 9 to wait until the parcel arrives", now: TimeTest.wednesday10)
        #expect(parsed?.intent == .remind(title: "Wait until the parcel arrives", when: TimeTest.date(2025, 10, 23, 9), recurrence: nil))
    }
}

/// SplitMix64: the same numbers on every run and machine.
struct Seeded: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
