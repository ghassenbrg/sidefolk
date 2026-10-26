import Foundation
import Testing
@testable import SidefolkCore

/// Inputs that crashed Sidefolk before the 0.1.0 review: `Int(_:)` traps on a Double past Int.max and Int
/// arithmetic traps on overflow, so a number typed, sent by another agent or stored in a row took the app down.
@Suite struct CrashRegressionTests {
    /// The hint line parses on every keystroke: typing a long number must not crash the app.
    @Test(arguments: [
        "remind me on dec 99999999999999999999 to pay",
        "remind me on the 99999999999999999999th to pay",
        "remind me in 99999999999999999999 days to pay",
        "remind me in 99999999999999999999 weeks to pay",
        "remind me every 99999999999999999999 days to pay",
        "remind me at 99999999999999999999:00 to pay",
        "every 9999999999999999999999999999999 hours tell me the cpu",
        "quiet for 99999999999999999999 years",
    ])
    func hugeNumbersTypedNeverCrash(text: String) {
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")
        _ = parser.parse(text, now: TimeTest.wednesday10)
    }

    @Test func aReportFasterThanAToolAcceptsIsLeftToTheAI() {
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")
        #expect(parser.parse("every 1000 hours tell me the cpu", now: TimeTest.wednesday10) == nil)
    }

    /// Another agent's `reminders.create` with a giant interval crashed the app at once (weekly) or when the
    /// reminder fired, and then at every launch, since the row stays.
    @Test(arguments: Recurrence.Frequency.allCases)
    func anotherAgentCantSendAGiantInterval(frequency: Recurrence.Frequency) async throws {
        let t = try await SchedulerEnv()
        let calendar = t.calendar
        t.env.registry.register(ReminderTools.make(scheduler: t.scheduler, parser: { TimeTest.parser(calendar) }))
        let out = await t.env.executor.execute(
            name: "reminders.create",
            input: ["title": "x", "when": "tomorrow 9am",
                    "recurrence": ["frequency": .string(frequency.rawValue), "interval": 9_000_000_000_000_000_000]],
            caller: .external(client: "agent"))
        guard case .failed(let error) = out.status else { Issue.record("expected a refusal, got \(out.status)"); return }
        #expect(error.message.contains("must be at most 1000"))
        #expect(try await t.store.all().isEmpty)
    }

    /// A row saved with a giant interval (by an older version, or by hand) still schedules without trapping.
    @Test(arguments: Recurrence.Frequency.allCases)
    func aStoredGiantIntervalNeverTraps(frequency: Recurrence.Frequency) throws {
        let json = #"{"frequency":"\#(frequency.rawValue)","interval":9000000000000000000,"weekdays":[]}"#
        let rule = try JSONDecoder().decode(Recurrence.self, from: Data(json.utf8))
        let anchor = TimeTest.wednesday10
        _ = RecurrenceMath.nextOccurrence(after: anchor.addingTimeInterval(86_400 * 400), recurrence: rule, anchor: anchor, calendar: TimeTest.utc)
        #expect(Recurrence(frequency: frequency, interval: .max).interval == Recurrence.maxInterval)
    }

    /// An extension's schema can carry any bound; saying it back must not trap.
    @Test func aGiantBoundInAnExtensionSchemaIsSaidSafely() {
        let schema = Schema.object(["n": ["type": "number", "maximum": 1e300]])
        #expect(InputSchema.problem(schema, ["n": 1e301]) == "“n” must be at most 1e+300.")
    }
}
