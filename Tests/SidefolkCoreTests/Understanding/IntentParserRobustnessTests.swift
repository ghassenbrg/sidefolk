import Foundation
import Testing
@testable import SidefolkCore

/// The parser runs on every keystroke to show the hint line, so it must be fast and never crash on odd input.
@Suite struct IntentParserRobustnessTests {
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")
    let now = TimeTest.wednesday10

    @Test func oddInputNeverCrashes() {
        let pieces = ["remind me", "tomorrow", "at", "5", "to", "every", "note:", "💡", "\n", "\t", "\"", "(", "tell me when", "https://", ".", "?", "—",
                      "in", "20", "min", "watch", "find", "quiet", "until", "2025-13-45", "99:99", "0", "-1", "ß", "İ", "٣", "of", "the", "31st", "feb"]
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<3000 {
            let n = Int.random(in: 1...7, using: &rng)
            let text = (0..<n).map { _ in pieces.randomElement(using: &rng)! }.joined(separator: Bool.random(using: &rng) ? " " : "")
            _ = parser.parse(text, now: now, knownCollections: ["Work"])
            _ = parser.when.parse(text, now: now)
        }
    }

    @Test func typingOneLetterAtATimeStaysCheap() {
        let text = "remind me every weekday at 9 to do the standup notes and send the document to the whole team please"
        let start = Date()
        for end in text.indices {
            _ = parser.parse(String(text[...end]), now: now, knownCollections: ["Work", "Sidefolk", "Groceries"])
        }
        let perKeystroke = Date().timeIntervalSince(start) / Double(text.count)
        // A keystroke must not be noticeable; this leaves a wide margin for slow CI machines.
        #expect(perKeystroke < 0.01, "\(perKeystroke * 1000) ms per keystroke")
    }

    @Test func parsingIsDeterministic() {
        let text = "remind me in 20 min to call mom"
        let first = parser.parse(text, now: now)
        for _ in 0..<20 { #expect(parser.parse(text, now: now) == first) }
    }

    @Test func partialTypingNeverClaimsTooMuch() {
        // While the user is still typing, only complete commands are claimed.
        #expect(parser.parse("rem", now: now) == nil)
        #expect(parser.parse("remind", now: now) == nil)
        #expect(parser.parse("remind me", now: now) == nil)
        #expect(parser.parse("remind me t", now: now)?.intent == .needsTime(title: "T"))
        #expect(parser.parse("not", now: now) == nil)
        #expect(parser.parse("note", now: now) == nil)
        #expect(parser.parse("note:", now: now) == nil)
        #expect(parser.parse("note: a", now: now) != nil)
        #expect(parser.parse("wat", now: now) == nil)
        #expect(parser.parse("watch", now: now) == nil)
        #expect(parser.parse("watch exa", now: now) == nil)
        #expect(parser.parse("tell me when", now: now) == nil)
    }
}
