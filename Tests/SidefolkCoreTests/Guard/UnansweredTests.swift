import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// "If I don't answer" (D37): a card nobody answers never holds a run forever.
@Suite struct UnansweredTests {
    /// A minute lasts 10 ms here, so the default "skip after 10 minutes" passes in a tenth of a second.
    static let minute: TimeInterval = 0.01

    func env(_ rule: UnansweredRule = UnansweredRule(), mode: GuardMode = .askOncePerKind) async throws -> TestEnv {
        let env = try TestEnv(minute: Self.minute)
        try await env.permissions.setPolicy(GuardPolicy(mode: mode, unanswered: rule))
        return env
    }

    @Test func aStepNobodyAnswersIsSkippedAndKept() async throws {
        let env = try await env()
        env.registry.register(ProbeTool(name: "files.move", risk: .medium, capabilities: [.filesWrite]))
        let out = await env.executor.execute(name: "files.move", input: ["x": "a.pdf"], caller: .agent(runId: "r"))

        guard case .unanswered(stop: false) = out.status else { Issue.record("expected a skipped step, got \(out.status)"); return }
        #expect(out.modelText.contains("the user didn't answer in time, so this step was skipped"))
        #expect(out.modelText.contains("Carry on with the rest of the request"))
        let logged = try await env.activity.recent()[0]
        #expect(logged.decision == .skipped)
        #expect(logged.error == "You didn't answer in time, so this step was skipped.")
        let kept = await env.executor.skipped.list()
        #expect(kept.count == 1)
        #expect(kept[0].request.tool == "files.move" && kept[0].request.summary == "Probe a.pdf" && !kept[0].stoppedTask)
    }

    @Test func theStopSettingEndsTheTask() async throws {
        let env = try await env(UnansweredRule(action: .stop, minutes: 5))
        env.registry.register(ProbeTool(risk: .high))
        let out = await env.executor.execute(name: "test.probe", input: [:], caller: .agent(runId: "r"))
        guard case .unanswered(stop: true) = out.status else { Issue.record("expected a stop, got \(out.status)"); return }
        #expect(out.modelText.contains("the task is stopping"))
        #expect(await env.executor.skipped.list().first?.stoppedTask == true)
    }

    @Test func waitsPerCaller() {
        let policy = GuardPolicy(unanswered: UnansweredRule(action: .skip, minutes: 10))
        let own = ToolExecutor.wait(for: .agent(runId: "r"), policy: policy, present: false, minute: 60)
        #expect(own.seconds == 600 && own.whenTimeIsUp == .skip)
        // Everyone else keeps two minutes and "no" (SECURITY T1), and so does a card for someone who is there.
        for caller in [Caller.user, .routine(id: "x"), .external(client: "x"), .extension(id: "x")] {
            let other = ToolExecutor.wait(for: caller, policy: policy, present: false, minute: 60)
            #expect(other.seconds == 120 && other.whenTimeIsUp == nil)
        }
        let present = ToolExecutor.wait(for: .agent(runId: "r"), policy: policy, present: true, minute: 60)
        #expect(present.seconds == 120 && present.whenTimeIsUp == nil)
        // "Keep waiting" waits a day, then stops the task.
        let waiting = ToolExecutor.wait(for: .agent(runId: "r"), policy: GuardPolicy(unanswered: UnansweredRule(action: .keepWaiting)),
                                        present: false, minute: 60)
        #expect(waiting.seconds == 86_400 && waiting.whenTimeIsUp == .stop)
    }

    @Test func otherAgentsStillHearNo() async throws {
        let env = try await env()
        env.registry.register(ProbeTool(risk: .medium))
        let out = await env.executor.execute(name: "test.probe", input: [:], caller: .external(client: "codex"), tainted: true,
                                             approvalTimeout: 0.05)
        guard case .denied(let why) = out.status else { Issue.record("expected denied"); return }
        #expect(why.contains("too long"))
        #expect(await env.executor.skipped.list().isEmpty)
    }

    @Test func runItNowAnswersTheSameQuestion() async throws {
        let env = try await env()
        let counter = CallCounter()
        env.registry.register(noteTool(name: "files.move", risk: .medium, capabilities: [.filesWrite], counter: counter))
        _ = await env.executor.execute(name: "files.move", input: ["x": "a.pdf"], caller: .agent(runId: "r"))
        let step = try #require(await env.executor.skipped.list().first)

        // The click in Now is the answer: no second card.
        let cards = Mutex(0)
        let stream = env.events.stream()
        let listener = Task { for await e in stream { if case .approvalRequested = e { cards.withLock { $0 += 1 } } } }
        let out = try #require(await env.executor.runSkipped(id: step.id))
        listener.cancel()

        #expect(out.isOK)
        #expect(counter.value == 1)
        #expect(cards.withLock { $0 } == 0)
        #expect(try await env.activity.recent()[0].decision == .allowed)
        #expect(await env.executor.skipped.list().isEmpty)
        #expect(await env.executor.runSkipped(id: step.id) == nil)
    }

    @Test func runItNowStillGoesThroughGuard() async throws {
        let env = try await env()
        env.registry.register(ProbeTool(name: "files.move", risk: .medium, capabilities: [.filesWrite]))
        _ = await env.executor.execute(name: "files.move", input: [:], caller: .agent(runId: "r"))
        let step = try #require(await env.executor.skipped.list().first)
        try await env.permissions.setPolicy(GuardPolicy(disabled: [.filesWrite]))
        let out = try #require(await env.executor.runSkipped(id: step.id))
        guard case .denied = out.status else { Issue.record("a capability turned off since must still block it"); return }
    }

    @Test func stepsAreKeptForADayAtMost() async throws {
        let env = try await env()
        env.registry.register(ProbeTool(risk: .medium))
        _ = await env.executor.execute(name: "test.probe", input: [:], caller: .agent(runId: "r"))
        let step = try #require(await env.executor.skipped.list().first)
        env.clock.advance(SkippedSteps.lifetime)
        #expect(await env.executor.skipped.list().isEmpty)
        #expect(await env.executor.runSkipped(id: step.id) == nil)
    }

    // MARK: A whole run, with a scripted model

    func harness(_ model: ScriptedModel, rule: UnansweredRule, tool: ProbeTool) async throws -> AgentRuntimeTests.Harness {
        let env = try await env(rule)
        env.registry.register(tool)
        var s = AppSettings()
        s.provider.kind = .anthropic
        let clock = env.clock
        let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
        return AgentRuntimeTests.Harness(env: env, settings: SettingsBox(s), factory: factory)
    }

    /// Moves the test clock while a card waits, as if the person were away that long.
    func passTime(_ seconds: TimeInterval, whileWaitingIn env: TestEnv) -> Task<Void, Never> {
        let stream = env.events.stream()
        let clock = env.clock
        return Task {
            for await e in stream { if case .approvalRequested = e { clock.advance(seconds); return } }
        }
    }

    @Test func aSkippedStepLetsTheRunCarryOn() async throws {
        let model = ScriptedModel([
            .turn(.calling([call("c1", "files_move", "invoices")])),
            .perform { request in
                guard case .toolResults(let results)? = request.messages.last else { throw UserFacingError("expected a tool result") }
                #expect(results[0].content.contains("the user didn't answer in time, so this step was skipped"))
                #expect(results[0].isError)
                return .reply("I didn't move the invoices: you weren't there to say yes. It's waiting in Now.")
            },
        ])
        let h = try await harness(model, rule: UnansweredRule(action: .skip, minutes: 10),
                                  tool: noteTool(name: "files.move", risk: .medium, capabilities: [.filesWrite]))
        // Eleven minutes pass while the card waits; the run's own two minutes must not count them.
        let away = passTime(11 * 60, whileWaitingIn: h.env)
        let (_, events) = await h.run(AgentRequest(text: "Move my invoices"))
        away.cancel()

        #expect(events.compactMap(\.failure).isEmpty)
        #expect(events.compactMap(\.reply).first?.text == "I didn't move the invoices: you weren't there to say yes. It's waiting in Now.")
        #expect(model.requests.count == 2)
        #expect(await h.env.executor.skipped.list().map(\.request.tool) == ["files.move"])
        #expect(try await AgentRunStore(h.env.db).recent().first?.outcome == "ok")
    }

    @Test func theStopSettingEndsTheRun() async throws {
        let model = ScriptedModel([.turn(.calling([call("c1", "files_move", "invoices")])), .turn(.reply("never asked"))])
        let h = try await harness(model, rule: UnansweredRule(action: .stop, minutes: 10),
                                  tool: noteTool(name: "files.move", risk: .medium, capabilities: [.filesWrite]))
        let (_, events) = await h.run(AgentRequest(text: "Move my invoices"))

        let failure = try #require(events.compactMap(\.failure).first)
        #expect(failure.message == "I stopped: you didn't answer in time. Nothing was changed.")
        #expect(failure.recovery == "The step I asked about is in Now, where you can still run it.")
        #expect(model.requests.count == 1)
        #expect(try await AgentRunStore(h.env.db).recent().first?.outcome == "unanswered")
        #expect(await h.env.executor.skipped.list().first?.stoppedTask == true)
    }

    @Test func theDeadlineWaitsWhileACardDoes() async throws {
        let env = try await env(UnansweredRule(action: .keepWaiting))
        env.registry.register(ProbeTool(risk: .medium))
        let box = toolbox(env)
        let base = env.clock.now.addingTimeInterval(120)
        #expect(box.deadline(from: base) == base)

        let stream = env.events.stream()
        let call = Task { await box.call("test.probe", input: [:]) }
        var request: ApprovalRequest?
        for await e in stream { if case .approvalRequested(let r) = e { request = r; break } }
        #expect(box.deadline(from: base) == nil)
        env.clock.advance(300)
        await env.broker.resolve(id: try #require(request).id, decision: .allowOnce)
        _ = await call.value
        #expect(box.deadline(from: base) == base.addingTimeInterval(300))
    }

    // MARK: Nothing is silent

    @Test func activityOffersTheSameUndo() async throws {
        let env = try await env(mode: .fullAccess)
        let undone = CallCounter()
        env.registry.register(ProbeTool(risk: .high, result: { _ in
            ToolResult(text: "Trashed.", undo: UndoAction(label: "Put back 2 files") { undone.bump() })
        }))
        let out = await env.executor.execute(name: "test.probe", input: [:], caller: .agent(runId: "r"))
        #expect(out.isOK && out.activity.undoAvailable)
        let row = try #require(try await env.activity.recent()[0].id)
        #expect(await env.executor.undo.undoableRows() == [row])
        #expect(try await env.executor.undo.undo(row: row) == "Put back 2 files")
        #expect(undone.value == 1)
        #expect(await env.executor.undo.undoableRows().isEmpty)
        #expect(try await env.executor.undo.undo(row: row) == nil)
    }

    @Test func actsWithoutAskingAreRecordedAsSuch() async throws {
        for (mode, tag) in [(GuardMode.auto, ActivityEntry.Decision.autoMode), (.fullAccess, .fullAccess)] {
            let env = try await env(mode: mode)
            env.registry.register(ProbeTool(risk: .medium))
            let stream = env.events.stream()
            let finished = Task { () -> ToolActivity? in
                for await e in stream { if case .toolFinished(let a, _) = e { return a } }
                return nil
            }
            let out = await env.executor.execute(name: "test.probe", input: [:], caller: .agent(runId: "r"))
            #expect(out.isOK)
            #expect(out.activity.actedWithoutAsking)
            #expect(await finished.value?.decision == tag)
            #expect(try await env.activity.recent()[0].decision == tag)
        }
    }
}
