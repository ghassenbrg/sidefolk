import Foundation
import Testing
@testable import SidefolkCore

/// Reasoning effort per model slot (D36): only levels a provider and model take are offered or
/// sent, "Default" sends nothing, and each provider remembers its own.
@Suite struct EffortSupportTests {
    func levels(_ kind: ProviderKind, _ model: String, preset: ProviderPreset = .custom, claude: [ReasoningEffort] = [],
                codex: [ModelOption] = []) -> [ReasoningEffort] {
        var p = ProviderSettings()
        p.kind = kind
        p.preset = preset
        p.model = model
        return EffortSupport.levels(p, thinkHarder: false, claudeCLI: claude, codexModels: codex)
    }

    @Test func anthropicByModel() {
        let all: [ReasoningEffort] = [.low, .medium, .high, .xhigh, .max]
        #expect(levels(.anthropic, "") == all, "Sidefolk's default model")
        #expect(levels(.anthropic, "claude-opus-5-5") == all)
        #expect(levels(.anthropic, "claude-sonnet-5-5") == all)
        #expect(levels(.anthropic, "claude-haiku-5-5") == all)
        #expect(levels(.anthropic, "claude-fable-5-1") == all)
        #expect(levels(.anthropic, "claude-opus-4-7") == all)
        #expect(levels(.anthropic, "claude-opus-4-6") == [.low, .medium, .high, .max])
        #expect(levels(.anthropic, "claude-sonnet-4-6") == [.low, .medium, .high, .max])
        #expect(levels(.anthropic, "claude-opus-4-5-20251101") == [.low, .medium, .high])
        #expect(levels(.anthropic, "claude-sonnet-4-5") == [])
        #expect(levels(.anthropic, "claude-haiku-4-5") == [])
        #expect(levels(.anthropic, "claude-sonnet-4-20250514") == [], "a date isn't a minor version")
        #expect(levels(.anthropic, "claude-3-7-sonnet-latest") == [])
        #expect(levels(.anthropic, "my-proxy-model") == [], "no guess for a model Sidefolk can't place")
    }

    @Test func claudeCodeTakesWhatTheCLIListsAndTheModelTakes() {
        let cli: [ReasoningEffort] = [.low, .medium, .high, .xhigh, .max]
        #expect(levels(.claudeCode, "sonnet", claude: cli) == cli)
        #expect(levels(.claudeCode, "", claude: cli) == cli, "its default model")
        #expect(levels(.claudeCode, "claude-opus-4-6", claude: cli) == [.low, .medium, .high, .max])
        #expect(levels(.claudeCode, "claude-sonnet-4-5", claude: cli) == [])
        #expect(levels(.claudeCode, "opus", claude: []) == [], "a CLI without --effort offers nothing")
    }

    @Test func codexFollowsItsCatalog() {
        let catalog = [ModelOption(id: "gpt-6-luna", efforts: [.low, .medium, .high, .xhigh, .max]),
                       ModelOption(id: "gpt-5.5", efforts: [.low, .medium, .high, .xhigh])]
        #expect(levels(.codex, "gpt-6-luna", codex: catalog) == [.low, .medium, .high, .xhigh, .max])
        #expect(levels(.codex, "gpt-5.5", codex: catalog) == [.low, .medium, .high, .xhigh])
        #expect(levels(.codex, "", codex: catalog) == [.low, .medium, .high, .xhigh], "what every model shares")
        #expect(levels(.codex, "my-own-model", codex: catalog) == [.low, .medium, .high, .xhigh])
        #expect(levels(.codex, "gpt-6-luna") == [.low, .medium, .high], "no catalog: the three every reasoning model took")
    }

    @Test func openAIByModelFamily() {
        #expect(levels(.openAICompatible, "gpt-5-mini", preset: .openAI) == [.minimal, .low, .medium, .high])
        #expect(levels(.openAICompatible, "gpt-5-2025-08-07", preset: .openAI) == [.minimal, .low, .medium, .high])
        #expect(levels(.openAICompatible, "gpt-5.1", preset: .openAI) == [.off, .low, .medium, .high])
        #expect(levels(.openAICompatible, "gpt-5.5", preset: .openAI) == [.off, .low, .medium, .high, .xhigh])
        #expect(levels(.openAICompatible, "gpt-6-luna", preset: .openAI) == [.low, .medium, .high, .xhigh, .max])
        #expect(levels(.openAICompatible, "o4-mini", preset: .openAI) == [.low, .medium, .high])
        #expect(levels(.openAICompatible, "gpt-4.1-mini", preset: .openAI) == [])
        #expect(levels(.openAICompatible, "gpt-5-chat-latest", preset: .openAI) == [])
    }

    @Test func otherServices() {
        #expect(levels(.openAICompatible, "gemini-2.5-flash", preset: .gemini) == [.off, .minimal, .low, .medium, .high])
        #expect(levels(.openAICompatible, "gemini-2.5-pro", preset: .gemini) == [.minimal, .low, .medium, .high], "Pro can't stop thinking")
        #expect(levels(.openAICompatible, "gemini-flash-latest", preset: .gemini) == [.minimal, .low, .medium, .high])
        #expect(levels(.openAICompatible, "gemini-3-pro-preview", preset: .gemini) == [.minimal, .low, .medium, .high])
        #expect(levels(.openAICompatible, "gemini-2.0-flash", preset: .gemini) == [])
        #expect(levels(.openAICompatible, "mistral-small-latest", preset: .mistral) == [.off, .high])
        #expect(levels(.openAICompatible, "mistral-medium-3-5", preset: .mistral) == [.off, .high])
        #expect(levels(.openAICompatible, "mistral-medium-3-1", preset: .mistral) == [])
        #expect(levels(.openAICompatible, "zai-glm-5-3", preset: .mistral) == [.low, .high, .max])
        #expect(levels(.openAICompatible, "openai/gpt-oss-120b", preset: .groq) == [.low, .medium, .high])
        #expect(levels(.openAICompatible, "llama-3.3-70b-versatile", preset: .groq) == [])
        #expect(levels(.openAICompatible, "grok-3-mini", preset: .xai) == [.low, .high])
        #expect(levels(.openAICompatible, "grok-4.7", preset: .xai) == [.low, .medium, .high, .xhigh])
        #expect(levels(.openAICompatible, "grok-4.5", preset: .xai) == [.low, .medium, .high])
        #expect(levels(.openAICompatible, "grok-4", preset: .xai) == [])
        #expect(levels(.openAICompatible, "grok-4.20-multi-agent", preset: .xai) == [], "there the setting is an agent count")
        #expect(levels(.openAICompatible, "anthropic/claude-opus-5-5", preset: .openRouter) == ReasoningEffort.allCases)
        #expect(levels(.openAICompatible, "openrouter/auto", preset: .openRouter) == [])
        for preset in [ProviderPreset.deepSeek, .ollama, .lmStudio, .custom] {
            #expect(levels(.openAICompatible, "deepseek-reasoner", preset: preset) == [], "\(preset)")
        }
    }

    @Test func thinkHarderUsesItsOwnModelOrTheMainOne() {
        var p = ProviderSettings()
        p.kind = .anthropic
        p.model = "claude-sonnet-4-5"
        #expect(EffortSupport.levels(p, thinkHarder: true) == [], "an empty Think harder uses the main model")
        p.smartModel = "claude-opus-5-5"
        #expect(EffortSupport.levels(p, thinkHarder: true) == [.low, .medium, .high, .xhigh, .max])
    }
}

@Suite struct EffortSettingsTests {
    @Test func eachProviderRemembersItsEfforts() {
        var p = ProviderSettings()
        p.switchProvider(to: .codex)
        #expect(p.effort == "")
        #expect(p.smartEffort == "high", "Think harder on Codex asked for high before efforts could be chosen")
        p.model = "gpt-6-luna"
        p.effort = "xhigh"
        p.smartModel = "gpt-6.1-sol"
        p.switchProvider(to: .anthropic)
        #expect(p.effort == "" && p.smartEffort == "", "Default elsewhere")
        p.effort = "max"
        p.switchProvider(to: .codex)
        #expect(p.model == "gpt-6-luna" && p.effort == "xhigh" && p.smartModel == "gpt-6.1-sol" && p.smartEffort == "high")
        p.smartEffort = ""
        p.switchProvider(to: .anthropic)
        #expect(p.effort == "max")
        p.switchProvider(to: .codex)
        #expect(p.smartEffort == "", "a chosen Default stays Default")
    }

    @Test func settingsSavedBeforeEffortsKeepWhatThinkHarderDid() throws {
        let codex = #"{"provider":{"kind":"codex","model":"gpt-5.5","modelMemory":{"anthropic":{"model":"claude-opus-5","smartModel":""}}}}"#
        var read = try JSONDecoder().decode(AppSettings.self, from: Data(codex.utf8)).provider
        #expect(read.effort == "")
        #expect(read.smartEffort == "high")
        read.switchProvider(to: .anthropic)
        #expect(read.model == "claude-opus-5" && read.effort == "" && read.smartEffort == "")

        let claude = #"{"provider":{"kind":"claudeCode","model":"sonnet"}}"#
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(claude.utf8)).provider.smartEffort == "")
        let memory = #"{"provider":{"kind":"anthropic","modelMemory":{"codex":{"model":"gpt-5.5","smartModel":""}}}}"#
        var back = try JSONDecoder().decode(AppSettings.self, from: Data(memory.utf8)).provider
        back.switchProvider(to: .codex)
        #expect(back.smartEffort == "high")
    }

    @Test func defaultRoundTripsAsDefault() throws {
        var settings = AppSettings()
        settings.provider.switchProvider(to: .codex)
        settings.provider.smartEffort = ""
        settings.provider.effort = "xhigh"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.provider.smartEffort == "")
        #expect(decoded.provider.requestedEffort(thinkHarder: false) == .xhigh)
        #expect(decoded.provider.requestedEffort(thinkHarder: true) == nil)
    }
}

/// What actually goes over the wire, through the same path as a question.
@Suite struct EffortWireTests {
    static let anthropicAnswer = #"{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":5,"output_tokens":1}}"#

    func runtime(_ env: TestEnv, _ settings: AppSettings, _ transport: FakeTransport, secrets: InMemorySecretStore) -> AgentRuntime {
        let box = SettingsBox(settings)
        return AgentRuntime(executor: env.executor, db: env.db, events: env.events,
                            context: ContextBuilder(notebook: NotebookStore(env.db), exchanges: ExchangeStore(env.db), clock: env.clock),
                            factory: BrainFactory.standard(secrets: secrets, transport: transport, retry: RetryPolicy(maxRetries: 0),
                                                           clock: env.clock),
                            settings: { box.current }, clock: env.clock)
    }

    func lastBody(_ transport: FakeTransport) throws -> JSONValue {
        try JSONValue.parse(try #require(transport.requests.last?.body))
    }

    @Test func anthropicSendsOutputConfigEffort() async throws {
        let env = try TestEnv()
        let secrets = InMemorySecretStore()
        try ProviderKeys(store: secrets).save(Secret("sk-ant"), account: SecretKey.anthropicAPIKey, host: ProviderKeys.anthropicHost)
        var settings = AppSettings()
        settings.provider.switchProvider(to: .anthropic)
        settings.provider.model = "claude-opus-5-5"
        settings.provider.effort = "xhigh"
        settings.provider.smartModel = "claude-sonnet-4-5"
        settings.provider.smartEffort = "max"
        let transport = FakeTransport([FakeTransport.json(200, #"{"id":"claude-opus-5-5"}"#), FakeTransport.json(200, Self.anthropicAnswer),
                                       FakeTransport.json(200, Self.anthropicAnswer)])
        let agent = runtime(env, settings, transport, secrets: secrets)

        _ = try await agent.testProvider().get()
        let body = try lastBody(transport)
        #expect(body["output_config"] == ["effort": "xhigh"])
        #expect(body["max_tokens"] == 16_000, "the top efforts think at length")
        #expect(body["thinking"] == nil, "thinking keeps the model's own default")

        // Sonnet 4.5 rejects effort: Think harder sends none, rather than a request that fails.
        _ = await collect(agent.handle(AgentRequest(text: "Plan my week", thinkHarder: true)))
        let harder = try lastBody(transport)
        #expect(harder.string("model") == "claude-sonnet-4-5")
        #expect(harder["output_config"] == nil)
    }

    @Test func openAICompatibleSendsReasoningEffort() async throws {
        let env = try TestEnv()
        let secrets = InMemorySecretStore()
        try ProviderKeys(store: secrets).save(Secret("sk-oa"), account: ProviderPreset.openAI.keyAccount, host: "api.openai.com")
        var settings = AppSettings()
        settings.provider.switchProvider(to: .openAICompatible, preset: .openAI)
        settings.provider.model = "gpt-5.5"
        settings.provider.effort = "none"
        let list = #"{"data":[{"id":"gpt-5.5"}]}"#
        let transport = FakeTransport([FakeTransport.json(200, list), FakeTransport.json(200, GeminiCompatibilityTests.answer),
                                       FakeTransport.json(200, list), FakeTransport.json(200, GeminiCompatibilityTests.answer)])
        _ = try await runtime(env, settings, transport, secrets: secrets).testProvider().get()
        #expect(try lastBody(transport)["reasoning_effort"] == "none")

        settings.provider.effort = ""
        _ = try await runtime(env, settings, transport, secrets: secrets).testProvider().get()
        #expect(try lastBody(transport)["reasoning_effort"] == nil, "Default sends nothing")
    }

    @Test func openRouterSendsItsReasoningObject() async throws {
        let env = try TestEnv()
        let secrets = InMemorySecretStore()
        try ProviderKeys(store: secrets).save(Secret("sk-or"), account: ProviderPreset.openRouter.keyAccount, host: "openrouter.ai")
        var settings = AppSettings()
        settings.provider.switchProvider(to: .openAICompatible, preset: .openRouter)
        settings.provider.model = "openai/gpt-6-luna"
        settings.provider.effort = "high"
        let transport = FakeTransport([FakeTransport.json(200, #"{"data":[{"id":"openai/gpt-6-luna"}]}"#),
                                       FakeTransport.json(200, GeminiCompatibilityTests.answer)])
        _ = try await runtime(env, settings, transport, secrets: secrets).testProvider().get()
        let body = try lastBody(transport)
        #expect(body["reasoning"] == ["effort": "high"])
        #expect(body["reasoning_effort"] == nil)
    }

    @Test func aLevelTheModelDoesntTakeIsNeverSent() async throws {
        let env = try TestEnv()
        var settings = AppSettings()
        settings.provider.switchProvider(to: .openAICompatible, preset: .ollama)
        settings.provider.model = "qwen3:8b"
        settings.provider.effort = "high"
        let transport = FakeTransport([FakeTransport.json(200, #"{"data":[{"id":"qwen3:8b"}]}"#),
                                       FakeTransport.json(200, GeminiCompatibilityTests.answer)])
        _ = try await runtime(env, settings, transport, secrets: InMemorySecretStore()).testProvider().get()
        #expect(try lastBody(transport)["reasoning_effort"] == nil, "Ollama has no effort control")
    }
}
