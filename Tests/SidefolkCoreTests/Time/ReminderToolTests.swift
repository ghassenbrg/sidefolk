import Foundation
import Testing
@testable import SidefolkCore

@Suite struct ReminderToolTests {
    /// The tools registered in a real executor, so Guard, the audit log and Undo are all in play.
    func setup() async throws -> (SchedulerEnv, ToolExecutor) {
        let t = try await SchedulerEnv()
        let calendar = t.calendar
        t.env.registry.register(ReminderTools.make(scheduler: t.scheduler, parser: { TimeTest.parser(calendar) }))
        return (t, t.env.executor)
    }

    func ok(_ outcome: ToolOutcome) throws -> ToolResult {
        guard case .ok(let r) = outcome.status else { throw TestFailure(String(describing: outcome.status)) }
        return r
    }

    struct TestFailure: Error { let message: String; init(_ m: String) { message = m } }

    @Test func specsAreLowRiskTimeTools() async throws {
        let (t, _) = try await setup()
        let specs = Dictionary(uniqueKeysWithValues: t.env.registry.specs.map { ($0.name, $0) })
        #expect(Set(specs.keys) == ["reminders.create", "reminders.list", "reminders.cancel", "reminders.complete", "reminders.snooze"])
        for spec in specs.values {
            #expect(spec.risk == .low)
            #expect(spec.capabilities == [.time])
            #expect(spec.category == .time)
        }
        #expect(specs["reminders.create"]?.mutates == true)
        #expect(specs["reminders.create"]?.external == true)
        #expect(specs["reminders.list"]?.mutates == false)
        #expect(specs["reminders.list"]?.external == true)
        #expect(specs["reminders.create"]?.inputSchema["required"] == ["title", "when"])
    }

    @Test func createsFromAPhrase() async throws {
        let (t, run) = try await setup()
        let outcome = await run.execute(name: "reminders.create",
                                        input: ["title": "Send the document", "when": "tomorrow morning"], caller: .agent(runId: "r1"))
        let result = try ok(outcome)
        let card = try #require(result.card)
        #expect(card.kind == .reminder)
        #expect(card.title == "Send the document")
        #expect(card.subtitle == "Tomorrow 09:00")
        #expect(result.text.contains("Thu 23 Oct 2025 09:00"))
        #expect(outcome.activity.undoAvailable)

        let saved = try #require(await t.scheduler.upcoming().first)
        #expect(saved.title == "Send the document")
        #expect(saved.fireAt == t.date(2025, 10, 23, 9))
        #expect(saved.source == "user:agent")   // a clean turn acts for the user (SECURITY T3)
        #expect(saved.level == .attention)
        #expect(card.refId == saved.id)
        #expect(result.text.contains(saved.id))
    }

    @Test func createsFromISO() async throws {
        let (t, run) = try await setup()
        let result = try ok(await run.execute(name: "reminders.create",
                                              input: ["title": "Launch", "when": "2025-12-01T09:30:00Z", "level": "critical", "notes": "Be ready"],
                                              caller: .user))
        #expect(result.card?.subtitle == "1 Dec 09:30")
        let saved = try #require(await t.scheduler.upcoming().first)
        #expect(saved.fireAt == t.date(2025, 12, 1, 9, 30))
        #expect(saved.level == .critical)
        #expect(saved.notes == "Be ready")
    }

    @Test func aRepeatInTheWhenPhrase() async throws {
        let (t, run) = try await setup()
        let result = try ok(await run.execute(name: "reminders.create",
                                              input: ["title": "Standup", "when": "every weekday at 9"], caller: .user))
        #expect(result.card?.subtitle == "Tomorrow 09:00 · every weekday")
        let saved = try #require(await t.scheduler.upcoming().first)
        #expect(saved.recurrence == Recurrence(frequency: .weekdays))
    }

    @Test func anExplicitRecurrenceObject() async throws {
        let (t, run) = try await setup()
        let input: JSONValue = [
            "title": "Gym", "when": "tomorrow at 7am",
            "recurrence": ["frequency": "weekly", "weekdays": ["mon", 3, "friday"], "interval": 1, "until": "2025-12-31"],
        ]
        let result = try ok(await run.execute(name: "reminders.create", input: input, caller: .user))
        let saved = try #require(await t.scheduler.upcoming().first)
        #expect(saved.recurrence?.frequency == .weekly)
        #expect(saved.recurrence?.weekdays == [1, 3, 5])
        // Tomorrow is Thursday, so the first Monday/Wednesday/Friday is Friday.
        #expect(saved.fireAt == t.date(2025, 10, 24, 7))
        #expect(saved.recurrence?.until == t.date(2025, 12, 31, 23, 59).addingTimeInterval(59))
        #expect(result.card?.subtitle == "Fri 07:00 · every Mon, Wed, Fri")
    }

    @Test func rejectsTimesInThePastAndNonsense() async throws {
        let (t, run) = try await setup()
        let past = await run.execute(name: "reminders.create", input: ["title": "x", "when": "2024-01-01T10:00:00Z"], caller: .user)
        guard case .failed(let pastError) = past.status else { throw TestFailure("expected failure") }
        #expect(pastError.message.contains("in the past"))
        #expect(pastError.changedNothing)

        let gone = await run.execute(name: "reminders.create", input: ["title": "x", "when": "this morning"], caller: .user)
        guard case .failed(let goneError) = gone.status else { throw TestFailure("expected failure") }
        #expect(goneError.message.contains("already passed"))
        #expect(goneError.recovery?.contains("Thu 23 Oct 2025 09:00") == true)

        let nonsense = await run.execute(name: "reminders.create", input: ["title": "x", "when": "whenever you like"], caller: .user)
        guard case .failed(let nonsenseError) = nonsense.status else { throw TestFailure("expected failure") }
        #expect(nonsenseError.message.contains("couldn't read"))
        #expect(nonsenseError.recovery?.contains("tomorrow") == true)

        #expect(await t.scheduler.upcoming().isEmpty)
    }

    @Test func missingFieldsFail() async throws {
        let (_, run) = try await setup()
        let noWhen = await run.execute(name: "reminders.create", input: ["title": "x"], caller: .user)
        guard case .failed(let e) = noWhen.status else { throw TestFailure("expected failure") }
        #expect(e.message.contains("when"))
    }

    @Test func undoCancelsTheReminder() async throws {
        let (t, run) = try await setup()
        let outcome = await run.execute(name: "reminders.create", input: ["title": "Oops", "when": "in an hour"], caller: .user)
        #expect(try await run.undo.undo(outcome.activity.id) == "Cancel reminder")
        #expect(await t.scheduler.upcoming().isEmpty)
        let saved = try #require(try await t.store.all().first)
        #expect(saved.state == .cancelled)
    }

    @Test func listsUpcomingReminders() async throws {
        let (t, run) = try await setup()
        let empty = try ok(await run.execute(name: "reminders.list", input: .object([:]), caller: .user))
        #expect(empty.text == "You have no reminders.")
        #expect(empty.card?.title == "No upcoming reminders")

        let a = try await t.scheduler.create(title: "Later", at: t.date(2025, 10, 24, 9))
        let b = try await t.scheduler.create(title: "Sooner", at: t.date(2025, 10, 22, 15), recurrence: Recurrence(frequency: .daily))
        let result = try ok(await run.execute(name: "reminders.list", input: .object([:]), caller: .external(client: "claude-code")))
        let lines = result.text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == "\(b.id) · Sooner · Today 15:00 · every day")
        #expect(lines[1] == "\(a.id) · Later · Fri 09:00")
        #expect(result.card?.title == "2 upcoming reminders")
    }

    @Test func listCanIncludeFinishedOnes() async throws {
        let (t, run) = try await setup()
        let r = try await t.scheduler.create(title: "Done thing", at: t.date(2025, 10, 22, 11))
        try await t.scheduler.complete(id: r.id)
        let without = try ok(await run.execute(name: "reminders.list", input: .object([:]), caller: .user))
        #expect(!without.text.contains("Done thing"))
        let with = try ok(await run.execute(name: "reminders.list", input: ["include_done": true], caller: .user))
        #expect(with.text.contains("Done thing"))
        #expect(with.text.contains("done"))
    }

    @Test func cancelByIdAndUndo() async throws {
        let (t, run) = try await setup()
        let r = try await t.scheduler.create(title: "Maybe", at: t.date(2025, 10, 22, 15))
        let outcome = await run.execute(name: "reminders.cancel", input: ["id": .string(r.id)], caller: .user)
        let result = try ok(outcome)
        #expect(result.text == "Cancelled “Maybe”.")
        #expect(await t.reminder(r.id)?.state == .cancelled)
        _ = try await run.undo.undo(outcome.activity.id)
        #expect(await t.reminder(r.id)?.state == .scheduled)

        let again = try ok(await run.execute(name: "reminders.cancel", input: ["id": .string(String(r.id.prefix(10)))], caller: .user))
        #expect(again.card?.title == "Maybe")
        let twice = try ok(await run.execute(name: "reminders.cancel", input: ["id": .string(r.id)], caller: .user))
        #expect(twice.text.contains("already cancelled"))
    }

    @Test func unknownIdsAreReportedClearly() async throws {
        let (_, run) = try await setup()
        for name in ["reminders.cancel", "reminders.complete"] {
            let outcome = await run.execute(name: name, input: ["id": "does-not-exist"], caller: .user)
            guard case .failed(let e) = outcome.status else { throw TestFailure("expected failure") }
            #expect(e.message.contains("couldn't find"))
        }
    }

    @Test func completeMarksDone() async throws {
        let (t, run) = try await setup()
        let r = try await t.scheduler.create(title: "Pay", at: t.date(2025, 10, 22, 15))
        let outcome = await run.execute(name: "reminders.complete", input: ["id": .string(r.id)], caller: .user)
        #expect(try ok(outcome).card?.subtitle == "Done")
        #expect(await t.reminder(r.id)?.state == .done)
        _ = try await run.undo.undo(outcome.activity.id)
        #expect(await t.reminder(r.id)?.state == .scheduled)
    }

    @Test func completingARepeatKeepsItRepeating() async throws {
        let (t, run) = try await setup()
        let r = try await t.scheduler.create(title: "Standup", at: t.date(2025, 10, 23, 9), recurrence: Recurrence(frequency: .daily))
        let result = try ok(await run.execute(name: "reminders.complete", input: ["id": .string(r.id)], caller: .user))
        #expect(await t.reminder(r.id)?.state == .scheduled)
        #expect(result.card?.subtitle == "Done for now")
        #expect(result.text.contains("remind you again"))
    }

    @Test func snoozeAcceptsPhrasesAndBareDurations() async throws {
        let (t, run) = try await setup()
        let r = try await t.scheduler.create(title: "Stretch", at: t.date(2025, 10, 22, 10, 30))
        let outcome = await run.execute(name: "reminders.snooze", input: ["id": .string(r.id), "when": "10 minutes"], caller: .user)
        let result = try ok(outcome)
        #expect(result.card?.subtitle == "Snoozed to Today 10:10")
        let snoozed = try #require(await t.reminder(r.id))
        #expect(snoozed.state == .snoozed)
        #expect(snoozed.snoozedUntil == t.date(2025, 10, 22, 10, 10))

        _ = try await run.undo.undo(outcome.activity.id)
        #expect(await t.reminder(r.id)?.state == .scheduled)

        let tomorrow = try ok(await run.execute(name: "reminders.snooze", input: ["id": .string(r.id), "when": "tomorrow morning"], caller: .user))
        #expect(tomorrow.card?.subtitle == "Snoozed to Tomorrow 09:00")
    }

    @Test func snoozeRefusesFinishedReminders() async throws {
        let (t, run) = try await setup()
        let r = try await t.scheduler.create(title: "Gone", at: t.date(2025, 10, 22, 15))
        try await t.scheduler.cancel(id: r.id)
        let outcome = await run.execute(name: "reminders.snooze", input: ["id": .string(r.id), "when": "in an hour"], caller: .user)
        guard case .failed(let e) = outcome.status else { throw TestFailure("expected failure") }
        #expect(e.message.contains("cancelled"))
    }

    @Test func theAuditLogRecordsTheCalls() async throws {
        let (t, run) = try await setup()
        _ = await run.execute(name: "reminders.create", input: ["title": "Logged", "when": "in 5 minutes"], caller: .external(client: "codex"))
        let entries = try await t.env.activity.recent()
        let entry = try #require(entries.first)
        #expect(entry.tool == "reminders.create")
        #expect(entry.risk == "low")
        #expect(entry.decision == .auto)
        #expect(entry.summary.contains("Logged"))
        let saved = try #require(await t.scheduler.upcoming().first)
        #expect(saved.source == "external:codex")
    }

    @Test func morningHourFollowsSettings() async throws {
        let t = try await SchedulerEnv()
        let calendar = t.calendar
        let settings = t.settings
        t.env.registry.register(ReminderTools.make(scheduler: t.scheduler, settings: settings, calendar: calendar))
        await settings.update { $0.morningHour = 7 }
        _ = await t.env.executor.execute(name: "reminders.create", input: ["title": "Early", "when": "tomorrow"], caller: .user)
        #expect(await t.scheduler.upcoming().first?.fireAt == t.date(2025, 10, 23, 7))
    }
}
