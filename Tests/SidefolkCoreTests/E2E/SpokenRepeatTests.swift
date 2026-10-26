import Foundation
import Testing
@testable import SidefolkCore

/// Voice (D34) meets repeating reminders down to the minute (D35) and approval modes (D37): what the talk key
/// hears goes through the same pipeline as typing, and a repeat said aloud ends where it was said to.
@Suite struct SpokenRepeatTests {
    /// The local path the Ask panel takes for a transcript the parser understands, on a full runtime.
    struct Local {
        let runtime: SidefolkRuntime
        let runner: LocalIntentRunner
        let clock: ManualClock

        init() async throws {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("sf-e2e-\(UUID().uuidString.prefix(8))", isDirectory: true)
            clock = ManualClock(TestEnv.referenceDate)
            runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: clock)
            runner = LocalIntentRunner(runtime: runtime)
        }

        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: TestEnv.referenceDate)!
        }
    }

    /// Dictation writes times its own way: "6 PM", "6 p.m.", "6pm".
    @Test(arguments: ["Remind me every 30 minutes until 6pm to stretch.", "remind me every 30 minutes until 6 PM to stretch",
                      "Remind me to stretch every 30 minutes until 6 p.m."])
    func aRepeatSaidAloudEndsWhereItWasSaid(heard: String) async throws {
        let w = try await Local()
        let transcript = try #require(VoicePolicy.usableTranscript(heard))
        let parsed = try #require(await w.runner.parse(transcript), "“\(heard)” should not need AI")
        #expect(parsed.hint.contains("until 18:00"), "\(parsed.hint)")
        guard case .card(let card, _, true) = await w.runner.run(parsed.intent) else { Issue.record("expected an undoable card"); return }
        #expect(card.title == "Stretch")

        let reminder = try #require(await w.runtime.scheduler.upcoming().first)
        #expect(reminder.fireAt == w.at(10, 30))
        #expect(reminder.recurrence?.frequency == .minutely && reminder.recurrence?.interval == 30)
        #expect(reminder.recurrence?.until == w.at(18), "the hint promised an end; the reminder must keep it")
        #expect(reminder.source == "user")

        // Through the day: it fires every half hour, and the last one is at 18:00.
        await w.runtime.scheduler.start()
        var fired: [Date] = []
        for step in 1...20 {
            w.clock.set(w.at(10).addingTimeInterval(Double(step) * 1800))
            await w.runtime.scheduler.tick()
            if let r = try await w.runtime.reminderStore.reminder(id: reminder.id), let last = r.lastFiredAt, last != fired.last { fired.append(last) }
        }
        #expect(fired.first == w.at(10, 30))
        #expect(fired.last == w.at(18))
        #expect(fired.count == 16)
        #expect(await w.runtime.scheduler.upcoming().isEmpty, "the series is over")
        await w.runtime.scheduler.stop()
    }

    /// "Every month on the 31st" said in November fires on the 30th, then must come back to the 31st. The local path
    /// lost the series' day, so the rent reminder drifted to the 30th (or the 28th, said in February) for good.
    @Test func aMonthlyDayKeepsItsDayFromTheLocalPath() async throws {
        let start = Calendar.current.date(from: DateComponents(year: 2025, month: 11, day: 5, hour: 10))!
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sf-e2e-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let clock = ManualClock(start)
        let runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: clock)
        let runner = LocalIntentRunner(runtime: runtime)
        let parsed = try #require(await runner.parse("remind me every month on the 31st to pay rent"))
        _ = await runner.run(parsed.intent)
        let first = try #require(await runtime.scheduler.upcoming().first)
        #expect(Calendar.current.component(.day, from: first.fireAt) == 30)
        await runtime.scheduler.start()
        clock.set(first.fireAt.addingTimeInterval(60))
        await runtime.scheduler.tick()
        let next = try #require(await runtime.scheduler.upcoming().first)
        #expect(Calendar.current.dateComponents([.month, .day], from: next.fireAt) == DateComponents(month: 12, day: 31))
        await runtime.scheduler.stop()
    }

    /// The same request through the AI, in Auto mode: the reminder needs no card, the medium-risk watch runs
    /// without one too (clean turn), and the answer's first sentence is what gets said.
    @Test func aSpokenRequestThroughTheAIInAutoMode() async throws {
        let world = try await World([
            .perform { request in
                #expect(request.system.contains("# Spoken request"), "the prompt asks for a first sentence that stands alone")
                return .calling([
                    ToolCall(id: "c1", name: "reminders_create", input: ["title": "Stretch", "when": "every 30 minutes until 6pm"]),
                    ToolCall(id: "c2", name: "watch_create", input: ["kind": "url_change", "target": "https://status.example.com"]),
                ])
            },
            .turn(.reply("I'll remind you to stretch every half hour until six. I'm also watching the status page at https://status.example.com.")),
        ], mode: .auto)
        world.watchWeb.say("<p>All systems normal</p>")
        let person = Person(world.env)
        let events = await world.ask("every half hour until six remind me to stretch and watch the status page", spoken: true)
        person.leave()

        #expect(person.seen.isEmpty, "nothing in this request needed a card in Auto")
        let reply = try #require(events.replyText)
        #expect(SpokenLine.answer(reply, appLanguage: "en") == "I'll remind you to stretch every half hour until six.")

        let reminder = try #require(await world.scheduler.upcoming().first)
        #expect(reminder.recurrence?.until == TimeTest.date(2025, 10, 22, 18))
        #expect(reminder.source == "user:agent")
        let decisions = Dictionary(try await world.activity().map { ($0.tool, $0.decision) }, uniquingKeysWith: { a, _ in a })
        #expect(decisions["reminders.create"] == .auto)
        #expect(decisions["watch.create"] == .autoMode, "Activity says Auto answered for the person")

        let thread = try #require(await world.runtime.activeThreadId)
        let asked = try #require(try await ExchangeStore(world.env.db).recent(threadId: thread).first)
        #expect(asked.meta?["spoken"] == true, "kept as text, marked spoken; no audio")
        await world.engine.stop()
    }
}
