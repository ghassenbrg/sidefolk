import Foundation
import Testing
@testable import SidefolkCore

/// The founder's Gemini setup: model "models/gemini-2.5-flash" picked from Gemini's own list passed
/// the old "Test" (a /models lookup) and failed in real use with "no AI service at that address".
@Suite struct GeminiCompatibilityTests {
    static let base = ProviderPreset.gemini.baseURL
    static let answer = #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"ok"}}],"usage":{"prompt_tokens":5,"completion_tokens":1}}"#

    @Test func requestsUseThePlainModelName() async throws {
        let transport = FakeTransport([FakeTransport.json(200, Self.answer)])
        let model = try OpenAICompatibleModel(baseURL: Self.base, apiKey: Secret("g-1"), name: "Google Gemini", transport: transport)
        var request = AnthropicModelTests.simpleRequest
        request.model = "models/gemini-2.5-flash"
        _ = try await model.respond(to: request)
        let sent = try #require(transport.requests.first)
        #expect(sent.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        let body = try JSONValue.parse(try #require(sent.body))
        #expect(body.string("model") == "gemini-2.5-flash")
        #expect(OpenAICompatibleModel.wireName("openai/gpt-oss-120b") == "openai/gpt-oss-120b", "other prefixes are names")
    }

    @Test func checkMatchesEitherForm() async throws {
        let list = #"{"object":"list","data":[{"id":"models/gemini-2.5-flash","object":"model"}]}"#
        let transport = FakeTransport([FakeTransport.json(200, list), FakeTransport.json(200, list)])
        let model = try OpenAICompatibleModel(baseURL: Self.base, apiKey: Secret("g-1"), name: "Google Gemini", transport: transport)
        #expect(await model.check(model: "models/gemini-2.5-flash") == .success("Connected to Google Gemini. gemini-2.5-flash is ready."))
        #expect(await model.check(model: "gemini-2.5-flash") == .success("Connected to Google Gemini. gemini-2.5-flash is ready."))
    }

    /// Gemini wraps errors in an array. A 404 from the provider about the model is a model problem,
    /// not a wrong address; a bare 404 page still is.
    @Test func errorsInGeminisShapeAreRead() async throws {
        let notFound = #"[{"error":{"code":404,"message":"models/gemini-9 is not found for API version v1main, or is not supported for generateContent.","status":"NOT_FOUND"}}]"#
        let (type, message) = ProviderHTTP.errorMessage(Data(notFound.utf8))
        #expect(type == "NOT_FOUND")
        #expect(message?.hasPrefix("models/gemini-9 is not found") == true)

        func failure(_ status: Int, _ body: String) async throws -> UserFacingError? {
            let model = try OpenAICompatibleModel(baseURL: Self.base, apiKey: Secret("g-1"), name: "Google Gemini",
                                                  transport: FakeTransport([FakeTransport.json(status, body)]), retry: RetryPolicy(maxRetries: 0))
            var request = AnthropicModelTests.simpleRequest
            request.model = "gemini-9"
            return await #expect(throws: UserFacingError.self) { try await model.respond(to: request) }
        }
        #expect(try await failure(404, notFound)?.message == "Google Gemini doesn't have the model “gemini-9”. Nothing was changed.")
        #expect(try await failure(404, #"[{"error":{"code":404,"message":"Requested entity was not found.","status":"NOT_FOUND"}}]"#)?
            .message == "Google Gemini doesn't have the model “gemini-9”. Nothing was changed.")
        #expect(try await failure(404, "<html><title>404 Not Found</title></html>")?.message
                == "I couldn't find an AI service at that address. Nothing was changed.")
        #expect(try await failure(400, #"[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}]"#)?
            .detail?.contains("API key not valid") == true)
    }
}

/// "Test" in Settings › AI sends one tiny real request through the same path as real use, so a
/// passing test means a question will work.
@Suite struct ProviderTestTests {
    @Test func testSendsOneRealRequestWithTheModelAsUsed() async throws {
        let env = try TestEnv()
        let secrets = InMemorySecretStore()
        try ProviderKeys(store: secrets).save(Secret("g-1"), account: ProviderPreset.gemini.keyAccount, host: "generativelanguage.googleapis.com")
        let list = #"{"data":[{"id":"models/gemini-2.5-flash"}]}"#
        let transport = FakeTransport([FakeTransport.json(200, list), FakeTransport.json(200, GeminiCompatibilityTests.answer)])
        var settings = AppSettings()
        settings.provider.kind = .openAICompatible
        settings.provider.preset = .gemini
        settings.provider.model = "models/gemini-2.5-flash"
        let factory = BrainFactory.standard(secrets: secrets, transport: transport, retry: RetryPolicy(maxRetries: 0), clock: env.clock)
        let box = SettingsBox(settings)
        let runtime = AgentRuntime(executor: env.executor, db: env.db, events: env.events,
                                   context: ContextBuilder(notebook: NotebookStore(env.db), exchanges: ExchangeStore(env.db), clock: env.clock),
                                   factory: factory, settings: { box.current }, clock: env.clock)

        let result = await runtime.testProvider()
        #expect(try result.get().hasPrefix("Google Gemini answered “ok”"))
        #expect(try result.get().hasSuffix("using gemini-2.5-flash."))
        #expect(transport.requests.map(\.method) == ["GET", "POST"], "the free check, then one chat request")
        let body = try JSONValue.parse(try #require(transport.requests.last?.body))
        #expect(body.string("model") == "gemini-2.5-flash")
        #expect(body["tools"] == nil, "no tools: nothing can be done by a test")
        #expect(try await AgentRunStore(env.db).recent().isEmpty, "a test isn't a run")

        // A failing request fails the test, worded as real use would be.
        let broken = FakeTransport([FakeTransport.json(200, list),
                                    FakeTransport.json(404, #"[{"error":{"code":404,"message":"Requested entity was not found.","status":"NOT_FOUND"}}]"#)])
        let failing = AgentRuntime(executor: env.executor, db: env.db, events: env.events,
                                   context: ContextBuilder(notebook: NotebookStore(env.db), exchanges: ExchangeStore(env.db), clock: env.clock),
                                   factory: BrainFactory.standard(secrets: secrets, transport: broken, retry: RetryPolicy(maxRetries: 0), clock: env.clock),
                                   settings: { box.current }, clock: env.clock)
        guard case .failure(let error) = await failing.testProvider() else { Issue.record("expected failure"); return }
        #expect(error.message == "Google Gemini doesn't have the model “gemini-2.5-flash”. Nothing was changed.")
    }

    @Test func eachProviderKeepsItsOwnModels() {
        var provider = ProviderSettings()
        provider.switchProvider(to: .openAICompatible, preset: .ollama)
        #expect(provider.model == "")
        provider.model = "gemma3:4b"
        provider.switchProvider(to: .openAICompatible, preset: .gemini)
        #expect(provider.model == "", "never an Ollama model in a Gemini setup")
        provider.model = "gemini-2.5-flash"
        provider.smartModel = "gemini-2.5-pro"
        provider.switchProvider(to: .claudeCode)
        #expect(provider.model == "sonnet")
        #expect(provider.smartModel == "")
        provider.switchProvider(to: .openAICompatible, preset: .gemini)
        #expect(provider.model == "gemini-2.5-flash")
        #expect(provider.smartModel == "gemini-2.5-pro")
        provider.switchProvider(to: .openAICompatible, preset: .ollama)
        #expect(provider.model == "gemma3:4b")
        #expect(provider.memoryKey == "openAICompatible.ollama")
    }
}
