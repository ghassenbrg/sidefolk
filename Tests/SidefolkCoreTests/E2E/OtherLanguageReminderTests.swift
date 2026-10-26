import Foundation
import Testing
@testable import SidefolkCore

/// Languages (D28) meet reminders through the AI: the local parser is English only, so a French request goes to the
/// model, which may pass the time in French first. The tool must steer it to a form it reads, the reminder keeps the
/// person's words, and editing it later (Home › Now) keeps what made it theirs.
@Suite struct OtherLanguageReminderTests {
    @Test func aFrenchReminderThroughTheAIThenEdited() async throws {
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")
        let asked = "Rappelle-moi demain à 9h d'appeler maman, toutes les semaines"
        #expect(parser.parse(asked, now: TimeTest.wednesday10) == nil, "not English: left to the AI, never half-read")

        let world = try await World([
            .turn(.calling([ToolCall(id: "c1", name: "reminders_create",
                                     input: ["title": "Appeler maman", "when": "demain à 9h, toutes les semaines"])])),
            .perform { request in
                guard case .toolResults(let results)? = request.messages.last else { throw UserFacingError("expected a tool result") }
                #expect(results[0].isError)
                #expect(results[0].content.contains("ISO date"), "the error says what the tool does read")
                return .calling([ToolCall(id: "c2", name: "reminders_create",
                                          input: ["title": "Appeler maman", "when": "2025-10-23T09:00:00",
                                                  "recurrence": ["frequency": "weekly"]])])
            },
            .turn(.reply("C'est noté : je te rappellerai d'appeler maman demain à 9 h, puis chaque semaine.")),
        ])
        let events = await world.ask(asked)
        #expect(events.compactMap(\.failure).isEmpty)
        #expect(events.replyText?.hasPrefix("C'est noté") == true)

        let made = try #require(await world.scheduler.upcoming().first)
        #expect(made.title == "Appeler maman")
        #expect(made.fireAt == TimeTest.date(2025, 10, 23, 9))
        #expect(made.recurrence?.frequency == .weekly)
        #expect(made.source == "user:agent")
        #expect(try await world.activity().map(\.decision) == [.auto, .failed], "the failed try is in Activity too")

        // Home › Now: the person moves it to 10:00 and fixes the title.
        let before = try await world.scheduler.edit(id: made.id, title: "Appeler maman 📞", fireAt: TimeTest.date(2025, 10, 23, 10),
                                                    recurrence: .some(made.recurrence))
        #expect(before == made, "edit hands back how it was, for Undo")
        let edited = try #require(await world.scheduler.upcoming().first)
        #expect(edited.title == "Appeler maman 📞")
        #expect(edited.fireAt == TimeTest.date(2025, 10, 23, 10))
        #expect(edited.recurrence?.frequency == .weekly)
        #expect(edited.source == made.source && edited.level == made.level)

        // It fires at the new time, then next week at 10:00.
        await world.scheduler.start()
        world.clock.set(TimeTest.date(2025, 10, 23, 10))
        await world.scheduler.tick()
        let after = try #require(await world.scheduler.upcoming().first)
        #expect(after.fireAt == TimeTest.date(2025, 10, 30, 10))
        let notice = try #require(try await AttentionStore(world.env.db).recent().first { $0.refId == made.id })
        #expect(notice.title == "Appeler maman 📞")
        await world.scheduler.stop()
    }

    /// The ways models write a time when told to use ISO 8601.
    @Test(arguments: [
        ("2025-10-23T09:00:00", 9), ("2025-10-23T09:00", 9), ("2025-10-23T09:00:00Z", 9), ("2025-10-23T11:00:00+02:00", 9),
        ("2025-10-23 09:00", 9), ("2025-10-23T09:00:00.000Z", 9),
    ])
    func isoTimesModelsSend(when: String, hourUTC: Int) async throws {
        let world = try await World([])
        let out = await world.executor.execute(name: "reminders.create", input: ["title": "x", "when": .string(when)], caller: .agent(runId: "r"))
        #expect(out.isOK, "“\(when)”: \(out.status)")
        #expect(await world.scheduler.upcoming().first?.fireAt == TimeTest.date(2025, 10, 23, hourUTC), "“\(when)”")
    }
}
