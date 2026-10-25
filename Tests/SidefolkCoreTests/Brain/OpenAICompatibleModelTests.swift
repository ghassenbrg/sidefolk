import Foundation
import Testing
@testable import SidefolkCore

@Suite struct OpenAICompatibleModelTests {
    @Test func requestBodyGolden() throws {
        var conversation = AnthropicModelTests.conversation
        conversation.append(.toolResults([ToolResultMessage(callId: "toolu_2", name: "x", content: "Failed: no.", isError: true)]))
        let request = TurnRequest(model: "gpt-4o-mini", system: "You are Sidefolk.", messages: conversation,
                                  tools: [AnthropicModelTests.reminderSpec], maxOutputTokens: 8192, timeBudget: 100)
        let expected = try JSONValue.parse("""
            {
              "model": "gpt-4o-mini",
              "stream": false,
              "messages": [
                {"role": "system", "content": "You are Sidefolk."},
                {"role": "user", "content": "Remind me tomorrow morning to send the doc"},
                {"role": "assistant", "content": "On it.", "tool_calls": [
                  {"id": "toolu_1", "type": "function",
                   "function": {"name": "reminders_create", "arguments": "{\\"title\\":\\"Send the doc\\",\\"when\\":\\"tomorrow morning\\"}"}}
                ]},
                {"role": "tool", "tool_call_id": "toolu_1", "content": "Reminder set for 09:00."},
                {"role": "tool", "tool_call_id": "toolu_2", "content": "Failed: no."}
              ],
              "tools": [{
                "type": "function",
                "function": {
                  "name": "reminders_create",
                  "description": "Remind the user at a time.",
                  "parameters": {
                    "type": "object",
                    "properties": {
                      "title": {"type": "string", "description": "What"},
                      "when": {"type": "string", "description": "When, in the user's words"}
                    },
                    "required": ["title", "when"],
                    "additionalProperties": false
                  }
                }
              }]
            }
            """)
        #expect(OpenAICompatibleModel.requestBody(request) == expected)
    }

    @Test func assistantTurnWithOnlyToolCallsHasNullContent() {
        let body = OpenAICompatibleModel.requestBody(TurnRequest(model: "m", system: "", messages: [
            .user("hi"), .modelTurn(.calling([ToolCall(id: "c", name: "t", input: [:])])),
        ], tools: [], maxOutputTokens: 1, timeBudget: 1))
        let messages = body["messages"]?.arrayValue ?? []
        #expect(messages.count == 2)
        #expect(messages[1]["content"] == .null)
        #expect(body["tools"] == nil)
    }

    @Test func parsesStringObjectAndBrokenArguments() throws {
        let body = """
            {"choices": [{"index": 0, "finish_reason": "tool_calls", "message": {"role": "assistant", "content": null, "tool_calls": [
              {"id": "call_a", "type": "function", "function": {"name": "notes_create", "arguments": "{\\"x\\": \\"tea\\"}"}},
              {"type": "function", "function": {"name": "notes_create", "arguments": {"x": "coffee"}}},
              {"id": "call_c", "type": "function", "function": {"name": "notes_create", "arguments": "{x: broken"}},
              {"id": "call_d", "type": "function", "function": {"name": "time_now", "arguments": ""}}
            ]}}]}
            """
        let turn = try OpenAICompatibleModel.parse(Data(body.utf8), provider: "OpenAI")
        #expect(turn.stop == .toolUse)
        #expect(turn.text == "")
        #expect(turn.usage == .zero)
        #expect(turn.toolCalls.map(\.id) == ["call_a", "call_1", "call_c", "call_d"])
        #expect(turn.toolCalls[0].input == ["x": "tea"])
        #expect(turn.toolCalls[1].input == ["x": "coffee"])
        #expect(turn.toolCalls[2].invalidArguments == "{x: broken")
        #expect(turn.toolCalls[3].input == .object([:]) && turn.toolCalls[3].invalidArguments == nil)
    }

    @Test func ollamaStyleAnswer() throws {
        let body = """
            {"choices": [{"finish_reason": "stop", "message": {"role": "assistant",
              "content": "<think>The user wants a greeting.</think>\\n\\nHello there.",
              "tool_calls": [{"id": "call_1", "function": {"name": "time_now", "arguments": "{}"}}]}}],
             "usage": {"prompt_tokens": 50, "completion_tokens": 7}}
            """
        let turn = try OpenAICompatibleModel.parse(Data(body.utf8), provider: "Ollama")
        #expect(turn.text == "Hello there.")
        #expect(turn.stop == .toolUse)
        #expect(turn.usage == TokenUsage(input: 50, output: 7))
    }

    @Test func ollamaWithoutKeyGoesToLocalhost() async throws {
        let transport = FakeTransport([FakeTransport.json(200, #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Hi"}}]}"#)])
        let model = try OpenAICompatibleModel(baseURL: "http://localhost:11434/v1/", apiKey: nil, transport: transport,
                                              retry: DelayRecorder().policy)

        let turn = try await model.respond(to: AnthropicModelTests.simpleRequest)

        #expect(model.providerName == "Ollama")
        #expect(turn.text == "Hi")
        let sent = try #require(transport.requests.first)
        #expect(sent.url.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(sent.headers["authorization"] == nil)
    }

    @Test func bearerKeyIsSentToHTTPSOnly() async throws {
        let transport = FakeTransport([FakeTransport.json(200, #"{"choices":[{"message":{"content":"Hi"}}]}"#)])
        let model = try OpenAICompatibleModel(baseURL: "https://openrouter.ai/api/v1", apiKey: Secret("sk-or-123"), transport: transport,
                                              retry: DelayRecorder().policy)
        _ = try await model.respond(to: AnthropicModelTests.simpleRequest)
        #expect(model.providerName == "OpenRouter")
        #expect(transport.requests.first?.headers["authorization"] == "Bearer sk-or-123")

        #expect(throws: UserFacingError.self) { _ = try OpenAICompatibleModel(baseURL: "http://192.168.1.20:11434/v1", apiKey: nil) }
        #expect(throws: UserFacingError.self) { _ = try OpenAICompatibleModel(baseURL: "http://example.com/v1", apiKey: Secret("k")) }
        #expect(throws: UserFacingError.self) { _ = try OpenAICompatibleModel(baseURL: "https://user:pw@example.com/v1", apiKey: nil) }
        #expect(throws: UserFacingError.self) { _ = try OpenAICompatibleModel(baseURL: "ftp://example.com", apiKey: nil) }
        #expect(throws: UserFacingError.self) { _ = try OpenAICompatibleModel(baseURL: "  ", apiKey: nil) }
        #expect(try OpenAICompatibleModel(baseURL: "http://127.0.0.1:1234/v1", apiKey: nil).providerName == "LM Studio")
    }

    @Test func errorsAreWordedForPeople() async throws {
        func failure(_ status: Int, _ body: String, key: Secret? = Secret("k"), base: String = "https://api.openai.com/v1") async throws
            -> UserFacingError? {
            let model = try OpenAICompatibleModel(baseURL: base, apiKey: key, transport: FakeTransport([FakeTransport.json(status, body)]),
                                                  retry: RetryPolicy(maxRetries: 0))
            return await #expect(throws: UserFacingError.self) { try await model.respond(to: AnthropicModelTests.simpleRequest) }
        }
        #expect(try await failure(401, #"{"error":{"message":"Incorrect API key","type":"invalid_request_error","code":"invalid_api_key"}}"#)?
            .message == "OpenAI rejected your API key. Nothing was changed.")
        #expect(try await failure(401, #"{"error":"unauthorized"}"#, key: nil)?.message == "OpenAI needs an API key. Nothing was changed.")
        #expect(try await failure(404, #"{"error":{"message":"model \"llama9\" not found, try pulling it first"}}"#,
                                  base: "http://localhost:11434/v1")?.recovery?.contains("ollama pull") == true)
        #expect(try await failure(400, #"{"error":{"message":"registry.ollama.ai/library/gemma:2b does not support tools"}}"#,
                                  base: "http://localhost:11434/v1")?.message.contains("can't use tools") == true)
        #expect(try await failure(400, #"{"error":{"message":"This model's maximum context length is 128000 tokens","code":"context_length_exceeded"}}"#)?
            .message == "That was more than the model can read at once. Nothing was changed.")
        #expect(try await failure(429, #"{"error":{"message":"You exceeded your current quota","code":"insufficient_quota"}}"#)?
            .message == "Your OpenAI account is out of credit. Nothing was changed.")
    }

    @Test func localServerNotRunning() async throws {
        let model = try OpenAICompatibleModel(baseURL: "http://localhost:11434/v1", apiKey: nil,
                                              transport: FakeTransport([.failure(URLError(.cannotConnectToHost))]))
        let error = await #expect(throws: UserFacingError.self) { try await model.respond(to: AnthropicModelTests.simpleRequest) }
        #expect(error?.message == "I couldn't reach Ollama on this Mac. Nothing was changed.")
        #expect(error?.recovery == "Make sure Ollama is running, and check the address in Settings › AI.")
    }

    @Test func checkListsModels() async throws {
        let list = #"{"object":"list","data":[{"id":"llama3.1:latest","object":"model"},{"id":"qwen3:8b","object":"model"}]}"#
        let transport = FakeTransport([FakeTransport.json(200, list), FakeTransport.json(200, list)])
        let model = try OpenAICompatibleModel(baseURL: "http://localhost:11434/v1", apiKey: nil, transport: transport)

        #expect(await model.check(model: "llama3.1") == .success("Connected to Ollama. llama3.1 is ready."))
        guard case .failure(let e) = await model.check(model: "mistral") else { Issue.record("expected failure"); return }
        #expect(e.message == "Ollama is reachable, but it doesn't have “mistral”.")
        #expect(e.recovery == "Available: llama3.1:latest, qwen3:8b.")
        #expect(transport.requests[0].url.absoluteString == "http://localhost:11434/v1/models")
    }
}
