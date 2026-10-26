import Foundation
import Testing
@testable import SidefolkCore

@Suite struct ProviderSettingsDecodingTests {
    /// Settings saved before Codex and presets existed (D26) keep working: the provider isn't reset,
    /// and the preset comes from the address.
    @Test func olderSettingsKeepTheirProvider() throws {
        let stored = #"{"companionName":"Pip","provider":{"kind":"openAICompatible","model":"llama3.1","smartModel":"","baseURL":"http://localhost:11434/v1","claudePath":""},"historyDays":3}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(stored.utf8))
        #expect(settings.companionName == "Pip")
        #expect(settings.historyDays == 3)
        #expect(settings.provider.kind == .openAICompatible)
        #expect(settings.provider.model == "llama3.1")
        #expect(settings.provider.preset == .ollama)
        #expect(settings.provider.codexPath == "")
        #expect(settings.provider.resolvedBaseURL == "http://localhost:11434/v1")

        let claude = #"{"provider":{"kind":"claudeCode","model":"sonnet"}}"#
        let partial = try JSONDecoder().decode(AppSettings.self, from: Data(claude.utf8))
        #expect(partial.provider.kind == .claudeCode)
        #expect(partial.provider.model == "sonnet")
        #expect(partial.provider.preset == .custom)
    }

    @Test func newSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.provider.kind = .codex
        settings.provider.preset = .groq
        settings.provider.codexPath = "/opt/codex"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        // A kind from a newer Sidefolk falls back to no AI rather than losing every other setting.
        let future = #"{"companionName":"Pip","provider":{"kind":"telepathy","model":"x"}}"#
        let read = try JSONDecoder().decode(AppSettings.self, from: Data(future.utf8))
        #expect(read.companionName == "Pip")
        #expect(read.provider.kind == .none)
        #expect(read.provider.model == "x")
    }

    @Test func addressesMatchTheirPreset() {
        #expect(ProviderPreset.matching(baseURL: "https://api.openai.com/v1") == .openAI)
        #expect(ProviderPreset.matching(baseURL: "https://openrouter.ai/api/v1/") == .openRouter)
        #expect(ProviderPreset.matching(baseURL: "https://generativelanguage.googleapis.com/v1beta/openai") == .gemini)
        #expect(ProviderPreset.matching(baseURL: "http://127.0.0.1:1234/v1") == .lmStudio)
        #expect(ProviderPreset.matching(baseURL: "https://proxy.example.com/v1") == .custom)
        #expect(ProviderPreset.matching(baseURL: "") == .custom)
        for preset in ProviderPreset.allCases where preset != .custom {
            #expect(ProviderPreset.matching(baseURL: preset.baseURL) == preset, "\(preset)")
            #expect((try? OpenAICompatibleModel.validate(baseURL: preset.baseURL)) != nil)
        }
        for preset in ProviderPreset.apiKeyPresets {
            #expect(preset.keyNeed == .required && preset.keyPage?.scheme == "https" && !preset.suggestedModels.isEmpty, "\(preset)")
        }
    }
}

@Suite struct PresetKeyTests {
    @Test func eachPresetHasItsOwnKeyBoundToItsHost() throws {
        let store = InMemorySecretStore()
        let keys = ProviderKeys(store: store)
        try keys.save(Secret("gsk-1"), account: ProviderPreset.groq.keyAccount, host: "api.groq.com")
        try keys.save(Secret("sk-oa"), account: ProviderPreset.openAI.keyAccount, host: "api.openai.com")
        #expect(try keys.key(for: .groq, host: "api.groq.com") == Secret("gsk-1"))
        #expect(try keys.key(for: .openAI, host: "api.openai.com") == Secret("sk-oa"))
        #expect(try keys.key(for: .mistral, host: "api.mistral.ai") == nil)
        #expect(throws: UserFacingError.self) { _ = try keys.key(for: .groq, host: "evil.example.com") }
        #expect(Set(SecretKey.providerKeys).isSuperset(of: ProviderPreset.allCases.map(\.keyAccount)), "Delete all data finds every key")
    }

    /// Before presets, every OpenAI-compatible key lived in OpenAI's account, bound to its host. It
    /// still works for that host, and only that host.
    @Test func olderKeysStillWorkForTheirHost() throws {
        let store = InMemorySecretStore()
        let keys = ProviderKeys(store: store)
        try keys.save(Secret("sk-or-legacy"), account: SecretKey.openAIAPIKey, host: "openrouter.ai")
        #expect(try keys.key(for: .openRouter, host: "openrouter.ai") == Secret("sk-or-legacy"))
        #expect(try keys.key(for: .groq, host: "api.groq.com") == nil)
        #expect(throws: UserFacingError.self) { _ = try keys.key(for: .openAI, host: "api.openai.com") }

        try keys.remove(preset: .openRouter, host: "openrouter.ai")
        #expect(try keys.key(for: .openRouter, host: "openrouter.ai") == nil)
        #expect(try store.get(SecretKey.openAIAPIKey) == nil, "removing the key in use removes the older copy")
    }
}

@Suite struct ModelCatalogTests {
    @Test func readsOpenAIStyleLists() {
        let body = Data(#"{"object":"list","data":[{"id":"gpt-4.1-mini"},{"id":"text-embedding-3-small"},{"id":"whisper-1"},{"id":"gpt-5-mini"},{"id":"tts-1"},{"id":"gpt-5"},{"id":"omni-moderation-latest"},{"id":"gpt-image-1"},{"id":"o3"}]}"#.utf8)
        let ids = ModelCatalog.ordered(ModelCatalog.parseOpenAI(body), preset: .openAI).map(\.id)
        #expect(ids == ["gpt-5-mini", "gpt-4.1-mini", "gpt-5", "o3"], "suggestions first, models that can't answer left out")

        let gemini = Data(#"{"object":"list","data":[{"id":"models/gemini-2.5-flash","object":"model"},{"id":"models/gemini-flash-latest"},{"id":"models/text-embedding-004"}]}"#.utf8)
        #expect(ModelCatalog.ordered(ModelCatalog.parseOpenAI(gemini), preset: .gemini).map(\.id) == ["gemini-flash-latest", "gemini-2.5-flash"])
    }

    /// Recorded from Ollama 0.40 (trimmed): capabilities say which models can call tools, and a
    /// remote host means the model runs in Ollama's cloud, not on this Mac.
    @Test func readsOllamaTags() {
        let body = Data(#"{"models":[{"name":"glm-5.2:cloud","model":"glm-5.2:cloud","remote_model":"glm-5.2","remote_host":"https://ollama.com:443","details":{"family":"glm"},"capabilities":["completion","tools","thinking"]},{"name":"gemma3:4b","model":"gemma3:4b","details":{"family":"gemma3"},"capabilities":["completion","vision"]},{"name":"qwen3:8b","details":{},"capabilities":["completion","tools"]},{"name":"llama3.1:latest","details":{}}]}"#.utf8)
        let models = ModelCatalog.parseOllama(body)
        #expect(models.map(\.id) == ["glm-5.2:cloud", "gemma3:4b", "qwen3:8b", "llama3.1:latest"])
        #expect(models[0] == ModelOption(id: "glm-5.2:cloud", usesTools: true, cloud: true))
        #expect(models[1].usesTools == false)
        #expect(models[3].usesTools == nil, "older Ollama: unknown")
        #expect(ModelCatalog.defaultLocalModel(models) == "qwen3:8b", "a local model that can use tools beats a cloud one")
        #expect(ModelCatalog.ollamaTags(URL(string: "http://localhost:11434/v1")!).absoluteString == "http://localhost:11434/api/tags")
    }

    @Test func listingSendsTheKeyOnlyWhenThereIsOne() async throws {
        let transport = FakeTransport([FakeTransport.json(200, #"{"data":[{"id":"llama-3.3-70b-versatile"},{"id":"whisper-large-v3"}]}"#),
                                       FakeTransport.json(401, #"{"error":{"message":"Invalid API Key"}}"#)])
        let listed = try await ModelCatalog.list(.groq, baseURL: ProviderPreset.groq.baseURL, key: Secret("gsk-1"), transport: transport).get()
        #expect(listed.map(\.id) == ["llama-3.3-70b-versatile"])
        #expect(transport.requests.first?.url.absoluteString == "https://api.groq.com/openai/v1/models")
        #expect(transport.requests.first?.headers["authorization"] == "Bearer gsk-1")

        guard case .failure(let error) = await ModelCatalog.list(.groq, baseURL: ProviderPreset.groq.baseURL, key: Secret("bad"),
                                                                transport: transport) else { Issue.record("401"); return }
        #expect(error.message == "Groq didn't accept the key.")

        let open = FakeTransport([FakeTransport.json(200, #"{"data":[{"id":"openrouter/auto"}]}"#)])
        _ = await ModelCatalog.list(.openRouter, baseURL: ProviderPreset.openRouter.baseURL, key: nil, transport: open)
        #expect(open.requests.first?.headers["authorization"] == nil)
    }

    @Test func picksDefaultsFromWhatTheProviderOffers() {
        #expect(ProviderPreset.openAI.defaultModel(available: nil) == "gpt-5-mini")
        #expect(ProviderPreset.openAI.defaultModel(available: ["gpt-4.1-mini", "o3"]) == "gpt-4.1-mini")
        #expect(ProviderPreset.openAI.defaultModel(available: ["o3"]) == nil, "nothing we know: the user picks")
        #expect(ProviderPreset.deepSeek.defaultSmartModel(available: ["deepseek-chat", "deepseek-reasoner"]) == "deepseek-reasoner")
        #expect(ProviderPreset.ollama.defaultModel(available: nil) == nil)
    }

    @Test func localServerStates() async {
        let running = FakeTransport([FakeTransport.json(200, #"{"models":[{"name":"qwen3:8b","capabilities":["tools"]}]}"#)])
        #expect(await LocalServers.probe(.ollama, transport: running, installed: true) == .running(models: [ModelOption(id: "qwen3:8b", usesTools: true)]))
        #expect(running.requests.first?.url.absoluteString == "http://localhost:11434/api/tags")
        #expect(await LocalServers.probe(.lmStudio, transport: FakeTransport([.failure(URLError(.cannotConnectToHost))]), installed: true)
                == .installedNotRunning)
        #expect(await LocalServers.probe(.lmStudio, transport: FakeTransport([.failure(URLError(.cannotConnectToHost))]), installed: false)
                == .notInstalled)
        #expect(LocalServers.isInstalled(.ollama, home: "/Users/x", exists: { $0 == "/Applications/Ollama.app" }))
        #expect(!LocalServers.isInstalled(.lmStudio, home: "/Users/x", exists: { _ in false }))
    }
}

@Suite struct PresetFactoryTests {
    @Test func presetsUseTheirAddressKeyAndSuggestedModel() async throws {
        let secrets = InMemorySecretStore()
        let transport = FakeTransport([FakeTransport.json(200, #"{"data":[{"id":"mistral-small-latest"}]}"#)])
        let factory = BrainFactory.standard(secrets: secrets, transport: transport)
        var provider = ProviderSettings()
        provider.kind = .openAICompatible
        provider.preset = .mistral
        provider.baseURL = "https://ignored.example.com/v1"

        #expect(throws: UserFacingError.self) { _ = try factory.make(provider, thinkHarder: false) }
        do {
            _ = try factory.make(provider, thinkHarder: false)
        } catch {
            #expect(error.message == "I need your Mistral API key for that. Nothing was changed.")
        }

        try ProviderKeys(store: secrets).save(Secret("mk-1"), account: ProviderPreset.mistral.keyAccount, host: "api.mistral.ai")
        let choice = try factory.make(provider, thinkHarder: false)
        #expect(choice.model == "mistral-small-latest")
        #expect(choice.backend.providerName == "Mistral")
        #expect(try factory.make(provider, thinkHarder: true).model == "mistral-large-latest")
        _ = await choice.backend.check()
        #expect(transport.requests.first?.url.absoluteString == "https://api.mistral.ai/v1/models")
        #expect(transport.requests.first?.headers["authorization"] == "Bearer mk-1")

        provider.model = "mistral-medium-latest"
        #expect(try factory.make(provider, thinkHarder: true).model == "mistral-medium-latest", "a chosen model beats suggestions")
    }

    @Test func localPresetsNeedNoKeyButAModel() throws {
        let factory = BrainFactory.standard(secrets: InMemorySecretStore(), transport: FakeTransport([]))
        var provider = ProviderSettings()
        provider.kind = .openAICompatible
        provider.preset = .ollama
        do {
            _ = try factory.make(provider, thinkHarder: false)
            Issue.record("expected an error")
        } catch {
            #expect(error.message == "I need to know which Ollama model to use.")
        }
        provider.model = "qwen3:8b"
        #expect(try factory.make(provider, thinkHarder: false).backend.providerName == "Ollama")
    }

    @Test func codexBackendPlugsIn() throws {
        struct Fake: BrainBackend {
            let providerName = "Codex"
            func run(_ task: BrainTask, toolbox: BrainToolbox, emit: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentReply {
                AgentReply(text: "ok", cards: [])
            }
            func check() async -> Result<String, UserFacingError> { .success("ok") }
        }
        let factory = BrainFactory.standard(secrets: InMemorySecretStore(), codexBackend: { _ in Fake() })
        var provider = ProviderSettings()
        provider.switchProvider(to: .codex)
        let harder = try factory.make(provider, thinkHarder: true)
        #expect(harder.model == "", "Codex's default model")
        #expect(harder.effort == .high, "Think harder starts where it always was")
        #expect(try factory.make(provider, thinkHarder: false).effort == nil)
        let none = BrainFactory.standard(secrets: InMemorySecretStore())
        #expect(throws: UserFacingError.self) { _ = try none.make(provider, thinkHarder: false) }
    }
}
