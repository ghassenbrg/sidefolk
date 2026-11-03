import Foundation
import Testing
@testable import SidefolkCore

/// "What's due this week", "what do I have tomorrow": reads by day, on a fixed clock.
@Suite struct ReadsByDateTests {
    let runtime: SidefolkRuntime
    let clock = ManualClock(TestEnv.referenceDate)

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-dates-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: clock)
    }

    func text(_ tool: String, _ input: JSONValue) async -> (text: String, ok: Bool) {
        let outcome = await runtime.executor.execute(name: tool, input: input, caller: .agent(runId: "r"))
        return (outcome.promptText, outcome.isOK)
    }

    func save(_ title: String, due: String?) async {
        var input: [String: JSONValue] = ["text": .string(title), "kind": "task"]
        if let due { input["due"] = .string(due) }
        #expect(await text("notes.save", .object(input)).ok)
    }

    @Test func tasksDueInAWindowComeSoonestFirst() async {
        await save("Later", due: "in 10 days")
        await save("Soon", due: "in 2 days")
        await save("Whenever", due: nil)
        let soon = await text("notes.list", ["due_before": "in 3 days"])
        #expect(soon.ok, "\(soon.text)")
        #expect(soon.text.contains("Soon") && !soon.text.contains("Later") && !soon.text.contains("Whenever"))
        #expect(soon.text.contains("soonest due first"))
        let both = await text("notes.list", ["due_after": "today"])
        #expect(both.ok, "\(both.text)")
        let soonAt = both.text.range(of: "Soon")?.lowerBound, laterAt = both.text.range(of: "Later")?.lowerBound
        #expect(soonAt != nil && laterAt != nil && soonAt! < laterAt!, "\(both.text)")
        #expect(!both.text.contains("Whenever"))
        let everything = await text("notes.list", [:])
        #expect(everything.text.contains("Whenever"), "with no window, as before")
    }

    @Test func aWordThatIsntADateIsSaid() async {
        let bad = await text("notes.list", ["due_before": "whenever"])
        #expect(!bad.ok)
        #expect(bad.text.contains("couldn't read"))
        let backwards = await text("reminders.list", ["from": "in 3 days", "to": "tomorrow"])
        #expect(!backwards.ok)
    }

    @Test func remindersKeepToTheirWindow() async throws {
        _ = try await runtime.scheduler.create(title: "Soon", at: clock.now.addingTimeInterval(3600), source: "user")
        _ = try await runtime.scheduler.create(title: "Next week", at: clock.now.addingTimeInterval(7 * 86400), source: "user")
        let list = await text("reminders.list", ["to": "in 2 days"])
        #expect(list.text.contains("Soon") && !list.text.contains("Next week"))
        let later = await text("reminders.list", ["from": "in 2 days"])
        #expect(!later.text.contains("Soon") && later.text.contains("Next week"))
    }

    @Test func theAgendaLooksAtAnotherDay() async throws {
        _ = try await runtime.scheduler.create(title: "Today's", at: clock.now.addingTimeInterval(60), source: "user")
        let tomorrow = try #require(Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: clock.now))
        _ = try await runtime.scheduler.create(title: "Tomorrow's", at: tomorrow, source: "user")
        await save("Due tomorrow", due: "tomorrow")
        await save("Not due", due: nil)
        let plate = await text("agenda.today", ["day": "tomorrow"])
        #expect(plate.ok, "\(plate.text)")
        #expect(plate.text.contains("Tomorrow's") && plate.text.contains("Due tomorrow"))
        #expect(!plate.text.contains("Today's") && !plate.text.contains("Not due"))
        let today = await text("agenda.today", [:])
        #expect(today.text.contains("Today's") && today.text.contains("Not due"), "today is as it was")
        #expect(await text("agenda.today", ["day": "today"]).text == today.text)
    }
}
