import Foundation
import Testing
@testable import SidefolkCore

/// Playing with the companion (D44) in plain words, right away and without AI; anything longer is left alone.
@Suite struct IntentPlayTests {
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    func act(_ text: String) -> CompanionAct? {
        if case .companion(let act)? = parser.parse(text, now: TimeTest.wednesday10)?.intent { return act }
        return nil
    }

    @Test func tricksAndGamesInPlainWords() {
        let cases: [(String, CompanionAct)] = [
            ("dance!", .dance), ("Pip, do a little dance", .dance), ("can you dance for me?", .dance), ("let's dance", .dance),
            ("wave", .wave), ("wave at me", .wave), ("take a bow", .bow), ("do a flip", .flip), ("backflip", .flip),
            ("jump", .hop), ("celebrate with me!", .cheer), ("nod", .nod), ("laugh", .giggle), ("do a trick", .trick),
            ("show me a trick please", .trick), ("make me laugh", .trick), ("do something funny", .trick),
            ("let's play catch", .catchMe), ("catch me if you can", .catchMe), ("play tag with me", .catchMe),
            ("breathe with me", .breathe), ("let's do a breathing exercise", .breathe), ("help me relax", .breathe),
            ("I need to calm down", .breathe),
        ]
        for (text, expected) in cases { #expect(act(text) == expected, "\(text)") }
        #expect(parser.parse("dance", now: TimeTest.wednesday10)?.hint == "A little dance · no AI")
        #expect(parser.parse("let's play catch", now: TimeTest.wednesday10)?.hint == "Catch me! · no AI")
    }

    @Test func longerSentencesAreNotTricks() {
        for text in ["dance music for the party", "wave goodbye to Friday's meeting", "how do I do a backflip on a trampoline?",
                     "remind me to dance at 5pm", "find my notes about breathing", "why do people laugh?", "play some music",
                     "breathe deeply is good advice"] {
            #expect(act(text) == nil, "\(text)")
        }
        // A reminder about dancing stays a reminder.
        if case .remind? = parser.parse("remind me to dance at 5pm", now: TimeTest.wednesday10)?.intent {} else {
            Issue.record("a reminder about dancing should stay a reminder")
        }
    }

    @Test func thePlayToolTellsTheApp() async throws {
        let env = try TestEnv()
        env.registry.register(CompanionPlayTool(events: env.events))
        let stream = env.events.stream()
        let outcome = await env.executor.execute(name: "companion.play", input: ["act": "catch_me"], caller: .user)
        #expect(outcome.isOK, "\(outcome.status)")
        let heard = await withTaskGroup(of: CompanionAct?.self) { group in
            group.addTask {
                for await event in stream { if case .companion(let act) = event { return act } }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #expect(heard == .catchMe)
        let bad = await env.executor.execute(name: "companion.play", input: ["act": "explode"], caller: .user)
        #expect(!bad.isOK)
    }
}
