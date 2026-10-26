import Foundation
import Testing
@testable import SidefolkCore

/// Apple Notes (D38) meets "If I don't answer" (D37): the copy is asked about after the run read a note, the
/// person is away, the step is skipped and the run finishes; back at the Mac, "Run it now" does exactly that copy.
@Suite struct AwayNotesCopyTests {
    static func handle(_ n: Int) -> String { AppleNotes.handle(for: NotesFixture.id(n)) }

    @Test func aSkippedCopyRunsLaterExactlyAsAsked() async throws {
        let copy = ToolCall(id: "c2", name: "applenotes_copy",
                            input: ["notes": [["id": .string(Self.handle(1)), "collection": "Cooking"],
                                              ["id": .string(Self.handle(4)), "collection": "Cooking"]]])
        let world = try await World([
            .turn(.calling([ToolCall(id: "c1", name: "applenotes_list", input: ["folder": "Recipes"])])),
            .turn(.calling([copy])),
            .perform { request in
                guard case .toolResults(let results)? = request.messages.last else { throw UserFacingError("expected a tool result") }
                #expect(results[0].content.contains("the user didn't answer in time, so this step was skipped"))
                return .reply("I didn't copy your recipes: you weren't there to say yes. The copy is waiting in Now.")
            },
        ], mode: .auto, unanswered: UnansweredRule(action: .skip, minutes: 10), minute: 0.01)

        // Eleven minutes pass while the copy's card waits.
        let away = Away(world.env, for: 11 * 60)
        let events = await world.ask("copy my Apple Notes recipes into a Cooking collection")
        away.back()

        #expect(events.compactMap(\.failure).isEmpty)
        #expect(events.replyText?.hasPrefix("I didn't copy your recipes") == true)
        let card = try #require(away.missed)
        #expect(card.tool == "applenotes.copy" && card.tainted, "Auto listed without a card, then asked once a note had been read")
        #expect(try await world.notebook.items().isEmpty, "nothing was copied while the person was away")

        // Back at the Mac: the step is in Now with the card's own words, and one click runs it.
        let step = try #require(await world.executor.skipped.list().first)
        #expect(step.request.summary == card.summary)
        let person = Person(world.env, answer: .deny)
        let outcome = try #require(await world.executor.runSkipped(id: step.id))
        person.leave()
        #expect(outcome.isOK, "\(outcome.status)")
        #expect(person.seen.isEmpty, "the click in Now was the answer: no second card")

        let items = try await world.notebook.items()
        #expect(Set(items.map(\.title)) == ["Pasta carbonara", "Sourdough"])
        #expect(items.allSatisfy { $0.source == "app:notes" })
        #expect(try await world.notebook.findCollection(named: "Cooking") != nil)
        // Activity tells the story: listed by Auto, skipped, then allowed by the click.
        let copies = try await world.activity().filter { $0.tool == "applenotes.copy" }.map(\.decision)
        #expect(copies == [.allowed, .skipped])
        #expect(await world.executor.skipped.list().isEmpty)
        // Nothing in Notes changed.
        #expect(!world.notes.calls.contains("notes.remove"))
    }

    /// The person turned Notes off (capability `mac.apps`) while they were away: "Run it now" still goes
    /// through Guard, and the copy doesn't happen.
    @Test func runItNowRespectsWhatChangedMeanwhile() async throws {
        let world = try await World([
            .turn(.calling([ToolCall(id: "c1", name: "applenotes_copy",
                                     input: ["notes": [["id": .string(Self.handle(4)), "collection": "Cooking"]]])])),
            .turn(.reply("Skipped.")),
        ], unanswered: UnansweredRule(action: .skip, minutes: 2), minute: 0.01)
        let away = Away(world.env, for: 3 * 60)
        _ = await world.ask("copy my sourdough note")
        away.back()
        let step = try #require(await world.executor.skipped.list().first)

        try await world.env.permissions.setPolicy(GuardPolicy(disabled: [.macApps]))
        let outcome = try #require(await world.executor.runSkipped(id: step.id))
        guard case .denied(let why) = outcome.status else { Issue.record("expected a refusal, got \(outcome.status)"); return }
        #expect(why.contains("turned off"))
        #expect(try await world.notebook.items().isEmpty)
    }
}
