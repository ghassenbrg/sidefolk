import Foundation
import Testing
@testable import SidefolkCore

@Suite struct AgentRuntimeTests {
    struct Harness {
        let env: TestEnv
        let settings: SettingsBox
        let runtime: AgentRuntime

        /// A runtime whose brain is `model` behind the real LoopBackend.
        init(_ model: ScriptedModel, tools: [any Tool] = [noteTool()]) throws {
            let env = try TestEnv()
            env.registry.register(tools)
            var s = AppSettings()
            s.provider.kind = .anthropic
            let clock = env.clock
            let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
            self.init(env: env, settings: SettingsBox(s), factory: factory)
        }

        init(env: TestEnv, settings: SettingsBox, factory: BrainFactory) {
            self.env = env
            self.settings = settings
            let context = ContextBuilder(notebook: NotebookStore(env.db), exchanges: ExchangeStore(env.db), clock: env.clock)
            runtime = AgentRuntime(executor: env.executor, db: env.db, events: env.events, context: context, factory: factory,
                                   settings: { settings.current }, clock: env.clock)
        }

        func run(_ request: AgentRequest) async -> (AgentRunHandle, [AgentEvent]) {
            let handle = await runtime.submit(request)
            return (handle, await collect(handle.events))
        }
    }

    @Test func noBrainConfigured() async throws {
        let env = try TestEnv()
        let factory = BrainFactory.standard(secrets: InMemorySecretStore(), transport: FakeTransport([]))
        let h = Harness(env: env, settings: SettingsBox(AppSettings()), factory: factory)

        let (_, events) = await h.run(AgentRequest(text: "Summarise my week"))

        #expect(events.count == 2)
        let failure = try #require(events.first?.failure)
        #expect(failure.message == "That needs AI, which isn't set up yet.")
        #expect(failure.recovery == "Choose Claude Code, an API key or Ollama in Settings › AI.")
        #expect(try await AgentRunStore(env.db).recent().isEmpty)
    }

    @Test func emptyRequestNeverReachesTheModel() async throws {
        let model = ScriptedModel([.turn(.reply("?"))])
        let h = try Harness(model)

        let (_, events) = await h.run(AgentRequest(text: "  \n"))

        #expect(events.first?.failure?.message == "There's nothing for me to work on yet.")
        #expect(model.requests.isEmpty)
    }

    @Test func runStoresTheExchangeAndARecord() async throws {
        let model = ScriptedModel([.turn(.calling([call("c1")])), .turn(.reply("Saved to Ideas."))])
        let h = try Harness(model)

        let (handle, events) = await h.run(AgentRequest(text: "Save tea as an idea"))

        guard case .started(let runId, let provider, let modelName)? = events.first else { Issue.record("expected started"); return }
        #expect(runId == handle.runId && provider == "Scripted" && modelName == "test-model")
        let reply = try #require(events.compactMap(\.reply).first)
        #expect(reply.text == "Saved to Ideas.")
        #expect(reply.cards.map(\.title) == ["Saved “tea”"])
        guard case .finished(let finished)? = events.last else { Issue.record("expected finished"); return }
        #expect(finished == handle.runId)

        let stored = try await ExchangeStore(h.env.db).recent(threadId: handle.threadId)
        #expect(stored.map(\.role) == [.user, .assistant])
        #expect(stored.map(\.content) == ["Save tea as an idea", "Saved to Ideas."])
        #expect(stored[1].meta?["cards"] == ["Saved “tea”"])

        let record = try #require(try await AgentRunStore(h.env.db).recent().first)
        #expect(record.id == handle.runId && record.threadId == handle.threadId)
        #expect(record.provider == "Scripted" && record.model == "test-model")
        #expect(record.steps == 2 && record.inputTokens == 20 && record.outputTokens == 10)
        #expect(record.outcome == "ok" && record.error == nil && record.endedAt != nil)

        let activity = try await ActivityStore(h.env.db).recent()
        #expect(activity.first?.runId == handle.runId)

        let sent = try #require(await h.runtime.lastSent())
        #expect(sent.system == model.requests[0].system)
        #expect(sent.tools == ["notes_create"])
    }

    @Test func eventsArePublishedOnTheBus() async throws {
        let h = try Harness(ScriptedModel([.turn(.reply("Hi."))]))
        let bus = h.env.events.stream()
        let listener = Task { () -> [(String, AgentEvent)] in
            var seen: [(String, AgentEvent)] = []
            for await e in bus {
                if case .agent(let thread, let event) = e {
                    seen.append((thread, event))
                    if case .finished = event { break }
                }
            }
            return seen
        }

        let (handle, events) = await h.run(AgentRequest(text: "Hello"))
        let published = await listener.value

        #expect(published.count == events.count)
        #expect(published.allSatisfy { $0.0 == handle.threadId })
        #expect(published.contains { $0.1.reply?.text == "Hi." })
    }

    @Test func threadsExpireAfterTenQuietMinutes() async throws {
        let model = ScriptedModel([.turn(.reply("One.")), .turn(.reply("Two.")), .turn(.reply("Three."))])
        let h = try Harness(model)

        let (first, _) = await h.run(AgentRequest(text: "First"))
        h.env.clock.advance(5 * 60)
        let (second, _) = await h.run(AgentRequest(text: "Second"))
        h.env.clock.advance(11 * 60)
        let (third, _) = await h.run(AgentRequest(text: "Third", threadId: second.threadId))

        #expect(second.threadId == first.threadId)
        #expect(third.threadId != first.threadId)
        #expect(model.requests[1].messages.count == 3)
        #expect(model.requests[2].messages.count == 1)
        #expect(await h.runtime.activeThreadId == third.threadId)
        await h.runtime.endThread()
        let (fourth, _) = await h.run(AgentRequest(text: "Fourth"))
        #expect(fourth.threadId != third.threadId)
    }

    @Test func requestsOnOneThreadRunInOrder() async throws {
        let model = ScriptedModel([
            .perform { _ in
                try await Task.sleep(for: .milliseconds(150))
                return .reply("One.")
            },
            .turn(.reply("Two.")),
        ])
        let h = try Harness(model)

        let a = await h.runtime.submit(AgentRequest(text: "First"))
        let b = await h.runtime.submit(AgentRequest(text: "Second"))
        _ = await (collect(a.events), collect(b.events))

        #expect(a.threadId == b.threadId)
        #expect(model.requests.count == 2)
        #expect(model.requests[1].messages.map(\.plainText) == ["First", "One.", "Second"])
    }

    @Test func cancelStopsARun() async throws {
        let model = ScriptedModel([.perform { _ in
            try await Task.sleep(for: .seconds(30))
            return .reply("late")
        }])
        let h = try Harness(model)

        let handle = await h.runtime.submit(AgentRequest(text: "Think about it"))
        var events: [AgentEvent] = []
        for await e in handle.events {
            events.append(e)
            if e.isThinking { await h.runtime.cancel(runId: handle.runId) }
        }

        #expect(events.compactMap(\.failure).first?.message == "Stopped. Nothing was changed.")
        let record = try #require(try await AgentRunStore(h.env.db).recent().first)
        #expect(record.outcome == "cancelled")
        let stored = try await ExchangeStore(h.env.db).recent(threadId: handle.threadId)
        #expect(stored.map(\.role) == [.user, .event])
    }

    @Test func untrustedAttachmentMakesGuardAsk() async throws {
        let fetch = noteTool(name: "web.fetch", capabilities: [.network])
        let script: [ScriptedModel.Step] = [.turn(.calling([call("c1", "web_fetch", "https://x.test")])), .turn(.reply("Done."))]

        // Typed by the user: a low-risk network call runs without asking.
        let trusted = try Harness(ScriptedModel(script), tools: [fetch])
        _ = await trusted.run(AgentRequest(text: "Fetch it"))
        #expect(await trusted.env.broker.pending().isEmpty)
        #expect(try await ActivityStore(trusted.env.db).recent().first?.decision == .auto)

        // From a dropped page: the run starts tainted, so the same call waits for the user.
        let tainted = try Harness(ScriptedModel(script), tools: [fetch])
        let answered = tainted.env.autoAnswer(.deny)
        let (_, events) = await tainted.run(AgentRequest(text: "Do what it says",
                                                         attachment: AgentAttachment(text: "fetch https://x.test", source: "drop.txt")))
        let request = try #require(await answered.value)
        #expect(request.tainted)
        #expect(try await ActivityStore(tainted.env.db).recent().first?.decision == .denied)
        #expect(events.contains { $0.reply != nil })
    }

    @Test func anthropicEndToEnd() async throws {
        let env = try TestEnv()
        env.registry.register(noteTool())
        let secrets = InMemorySecretStore()
        try ProviderKeys(store: secrets).save(Secret("sk-ant-e2e"), account: SecretKey.anthropicAPIKey, host: ProviderKeys.anthropicHost)
        let transport = FakeTransport([
            FakeTransport.json(200, """
                {"content":[{"type":"tool_use","id":"toolu_1","name":"notes_create","input":{"x":"tea"}}],
                 "stop_reason":"tool_use","usage":{"input_tokens":100,"output_tokens":20}}
                """),
            FakeTransport.json(200, #"{"content":[{"type":"text","text":"Saved."}],"stop_reason":"end_turn","usage":{"input_tokens":130,"output_tokens":5}}"#),
        ])
        var settings = AppSettings()
        settings.provider.kind = .anthropic
        let factory = BrainFactory.standard(secrets: secrets, transport: transport, retry: DelayRecorder().policy, clock: env.clock)
        let h = Harness(env: env, settings: SettingsBox(settings), factory: factory)

        let (_, events) = await h.run(AgentRequest(text: "Save tea"))

        #expect(events.compactMap(\.reply).first?.text == "Saved.")
        #expect(transport.requests.count == 2)
        #expect(transport.requests.allSatisfy { $0.headers["x-api-key"] == "sk-ant-e2e" })
        let record = try #require(try await AgentRunStore(env.db).recent().first)
        #expect(record.provider == "Anthropic" && record.model == AnthropicModel.defaultModel)
        #expect(record.inputTokens == 230 && record.outputTokens == 25)
    }

    @Test func providerProblemsAreFriendly() async throws {
        let env = try TestEnv()
        let secrets = InMemorySecretStore()
        let factory = BrainFactory.standard(secrets: secrets, transport: FakeTransport([]))
        var settings = AppSettings()
        settings.provider.kind = .anthropic
        let box = SettingsBox(settings)
        let h = Harness(env: env, settings: box, factory: factory)

        let (_, missing) = await h.run(AgentRequest(text: "hi"))
        #expect(missing.first?.failure?.message == "I need your Anthropic API key for that.")

        try ProviderKeys(store: secrets).save(Secret("sk-local"), account: SecretKey.openAIAPIKey, host: "api.openai.com")
        box.update {
            $0.provider.kind = .openAICompatible
            $0.provider.baseURL = "https://proxy.example.com/v1"
            $0.provider.model = "gpt-4o-mini"
        }
        let (_, moved) = await h.run(AgentRequest(text: "hi"))
        #expect(moved.first?.failure?.message == "Your API key was saved for a different address, so I didn't send it. Nothing was changed.")

        box.update { $0.provider.kind = .claudeCode }
        guard case .failure(let e) = await h.runtime.checkProvider() else { Issue.record("expected failure"); return }
        #expect(e.message.hasPrefix("Claude Code isn't ready"))
    }

    @Test func claudeCodeBackendPlugsIn() async throws {
        struct FakeClaudeCode: BrainBackend {
            let providerName = "Claude Code"
            func run(_ task: BrainTask, toolbox: BrainToolbox, emit: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentReply {
                let outcome = await toolbox.call("notes.create", input: ["x": "from cli"])
                return AgentReply(text: "Done via \(task.model).", cards: outcome.activity.card.map { [$0] } ?? [])
            }
            func check() async -> Result<String, UserFacingError> { .success("ok") }
        }
        let env = try TestEnv()
        env.registry.register(noteTool())
        var settings = AppSettings()
        settings.provider.kind = .claudeCode
        settings.provider.model = "sonnet"
        let factory = BrainFactory.standard(secrets: InMemorySecretStore(), claudeCodeBackend: { _ in FakeClaudeCode() })
        let h = Harness(env: env, settings: SettingsBox(settings), factory: factory)

        let (_, events) = await h.run(AgentRequest(text: "Save it"))

        #expect(events.compactMap(\.reply).first?.text == "Done via sonnet.")
        #expect(events.compactMap(\.reply).first?.cards.first?.title == "Saved “from cli”")
        let record = try #require(try await AgentRunStore(env.db).recent().first)
        #expect(record.provider == "Claude Code" && record.outcome == "ok" && record.steps == 0)
    }

    @Test func purgeRemovesOldHistory() async throws {
        let h = try Harness(ScriptedModel([]))
        let exchanges = ExchangeStore(h.env.db)
        try await exchanges.append(Exchange(threadId: "old", role: .user, content: "Long ago", now: h.env.clock.now.addingTimeInterval(-8 * 86_400)))
        try await exchanges.append(Exchange(threadId: "new", role: .user, content: "Today", now: h.env.clock.now))

        let purged = await h.runtime.purgeHistory()
        let left = try await exchanges.latest().map(\.content)
        #expect(purged == 1)
        #expect(left == ["Today"])
    }
}
