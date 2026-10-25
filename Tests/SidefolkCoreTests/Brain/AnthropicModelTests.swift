import Foundation
import Testing
@testable import SidefolkCore

@Suite struct AnthropicModelTests {
    static let reminderSpec = ToolSpec(
        name: "reminders.create", title: "Create reminder", description: "Remind the user at a time.",
        inputSchema: Schema.object(["title": Schema.string("What"), "when": Schema.string("When, in the user's words")],
                                   required: ["title", "when"]),
        risk: .low, capabilities: [.time], category: .time, mutates: true)

    static let conversation: [TurnMessage] = [
        .user("Remind me tomorrow morning to send the doc"),
        .modelTurn(ModelTurn(text: "On it.", toolCalls: [
            ToolCall(id: "toolu_1", name: "reminders_create", input: ["title": "Send the doc", "when": "tomorrow morning"]),
        ], stop: .toolUse)),
        .toolResults([
            ToolResultMessage(callId: "toolu_1", name: "reminders_create", content: "Reminder set for 09:00.", isError: false),
        ]),
    ]

    @Test func requestBodyGolden() throws {
        let request = TurnRequest(model: "claude-opus-5-5", system: "You are Sidefolk.", messages: Self.conversation,
                                  tools: [Self.reminderSpec], maxOutputTokens: 8192, timeBudget: 100)
        let expected = try JSONValue.parse("""
            {
              "model": "claude-opus-5-5",
              "max_tokens": 8192,
              "system": "You are Sidefolk.",
              "messages": [
                {"role": "user", "content": "Remind me tomorrow morning to send the doc"},
                {"role": "assistant", "content": [
                  {"type": "text", "text": "On it."},
                  {"type": "tool_use", "id": "toolu_1", "name": "reminders_create",
                   "input": {"title": "Send the doc", "when": "tomorrow morning"}}
                ]},
                {"role": "user", "content": [
                  {"type": "tool_result", "tool_use_id": "toolu_1", "content": "Reminder set for 09:00."}
                ]}
              ],
              "tools": [{
                "name": "reminders_create",
                "description": "Remind the user at a time.",
                "input_schema": {
                  "type": "object",
                  "properties": {
                    "title": {"type": "string", "description": "What"},
                    "when": {"type": "string", "description": "When, in the user's words"}
                  },
                  "required": ["title", "when"],
                  "additionalProperties": false
                },
                "cache_control": {"type": "ephemeral"}
              }]
            }
            """)
        #expect(AnthropicModel.requestBody(request) == expected)
    }

    @Test func failedToolResultsAreMarked() {
        let message = AnthropicModel.message(.toolResults([ToolResultMessage(callId: "t", name: "x", content: "Failed: no.", isError: true)]))
        #expect(message == ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t", "content": "Failed: no.", "is_error": true]]])
    }

    static let toolUseResponse = """
        {"id": "msg_1", "type": "message", "role": "assistant", "model": "claude-opus-5-5",
         "content": [
           {"type": "thinking", "thinking": "", "signature": "sig-abc"},
           {"type": "text", "text": "Setting that up."},
           {"type": "tool_use", "id": "toolu_9", "name": "reminders_create", "input": {"title": "Call mom", "when": "at 5pm"}}
         ],
         "stop_reason": "tool_use",
         "usage": {"input_tokens": 120, "cache_creation_input_tokens": 30, "cache_read_input_tokens": 50, "output_tokens": 40}}
        """

    @Test func sendsTheRightRequestAndParsesToolUse() async throws {
        let transport = FakeTransport([FakeTransport.json(200, Self.toolUseResponse)])
        let model = AnthropicModel(apiKey: Secret("sk-ant-test-key"), transport: transport, retry: DelayRecorder().policy)

        let turn = try await model.respond(to: TurnRequest(model: "claude-opus-5-5", system: "S", messages: [.user("hi")], tools: [],
                                                           maxOutputTokens: 1024, timeBudget: 60))

        let sent = try #require(transport.requests.first)
        #expect(sent.method == "POST")
        #expect(sent.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(sent.headers["x-api-key"] == "sk-ant-test-key")
        #expect(sent.headers["anthropic-version"] == "2023-06-01")
        #expect(!sent.description.contains("sk-ant"))
        #expect(turn.text == "Setting that up.")
        #expect(turn.stop == .toolUse)
        #expect(turn.toolCalls == [ToolCall(id: "toolu_9", name: "reminders_create", input: ["title": "Call mom", "when": "at 5pm"])])
        #expect(turn.usage == TokenUsage(input: 200, output: 40))

        // The thinking block goes back unchanged in the next request of the run.
        let next = AnthropicModel.message(.modelTurn(turn))
        #expect(next["content"]?.arrayValue?.first?["signature"] == "sig-abc")
        #expect(next["content"]?.arrayValue?.count == 3)
    }

    @Test func stopReasonsMap() throws {
        func stop(_ reason: String) throws -> TurnStop {
            try AnthropicModel.parse(Data(#"{"content": [], "stop_reason": "\#(reason)"}"#.utf8)).stop
        }
        #expect(try stop("end_turn") == .end)
        #expect(try stop("max_tokens") == .maxTokens)
        #expect(try stop("refusal") == .refusal)
        #expect(try stop("pause_turn") == .other("pause_turn"))
    }

    @Test func rejectedKey() async throws {
        let transport = FakeTransport([FakeTransport.json(401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)])
        let model = AnthropicModel(apiKey: Secret("bad"), transport: transport, retry: DelayRecorder().policy)

        let error = await #expect(throws: UserFacingError.self) { try await model.respond(to: Self.simpleRequest) }

        #expect(error?.message == "Your Anthropic API key was rejected. Nothing was changed.")
        #expect(error?.recovery == "Check the key in Settings › AI, or paste a new one.")
        #expect(error?.changedNothing == true)
        #expect(error?.detail?.contains("authentication_error") == true)
        #expect(transport.requests.count == 1)
    }

    @Test func rateLimitIsRetriedTwiceThenExplained() async throws {
        let limited = FakeTransport.json(429, #"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#)
        let transport = FakeTransport([limited, limited, limited])
        let delays = DelayRecorder()
        let model = AnthropicModel(apiKey: Secret("k"), transport: transport, retry: delays.policy)

        let error = await #expect(throws: UserFacingError.self) { try await model.respond(to: Self.simpleRequest) }

        #expect(transport.requests.count == 3)
        #expect(delays.recorded == [0.8, 1.6])
        #expect(error?.message == "Anthropic is limiting how fast I can ask right now. Nothing was changed.")
    }

    @Test func overloadedThenRecoversHonouringRetryAfter() async throws {
        let overloaded = FakeTransport.json(529, #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
                                            headers: ["Retry-After": "3"])
        let ok = FakeTransport.json(200, #"{"content":[{"type":"text","text":"Hi"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}"#)
        let transport = FakeTransport([overloaded, ok])
        let delays = DelayRecorder()
        let model = AnthropicModel(apiKey: Secret("k"), transport: transport, retry: delays.policy)

        let turn = try await model.respond(to: Self.simpleRequest)

        #expect(turn.text == "Hi")
        #expect(delays.recorded == [3])
    }

    @Test func overloadedWithoutTimeLeftIsNotRetried() async throws {
        let overloaded = FakeTransport.json(529, #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
                                            headers: ["retry-after": "8"])
        let transport = FakeTransport([overloaded, overloaded])
        let model = AnthropicModel(apiKey: Secret("k"), transport: transport, retry: DelayRecorder().policy)
        var request = Self.simpleRequest
        request.timeBudget = 5

        let error = await #expect(throws: UserFacingError.self) { try await model.respond(to: request) }

        #expect(transport.requests.count == 1)
        #expect(error?.message == "Claude is overloaded right now. Nothing was changed.")
    }

    @Test func offline() async throws {
        let transport = FakeTransport([.failure(URLError(.notConnectedToInternet))])
        let model = AnthropicModel(apiKey: Secret("k"), transport: transport, retry: DelayRecorder().policy)

        let error = await #expect(throws: UserFacingError.self) { try await model.respond(to: Self.simpleRequest) }

        #expect(error?.message == "I couldn't reach Anthropic. Nothing was changed.")
        #expect(error?.recovery == "Check your internet connection, or switch provider in Settings › AI.")
    }

    @Test func contextTooLong() async throws {
        let transport = FakeTransport([FakeTransport.json(400, #"{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long: 1200000 tokens > 1000000 maximum"}}"#)])
        let model = AnthropicModel(apiKey: Secret("k"), transport: transport, retry: DelayRecorder().policy)

        let error = await #expect(throws: UserFacingError.self) { try await model.respond(to: Self.simpleRequest) }

        #expect(error?.message == "That was more than the model can read at once. Nothing was changed.")
    }

    @Test func checkUsesTheModelsEndpoint() async throws {
        let transport = FakeTransport([
            FakeTransport.json(200, #"{"id":"claude-haiku-5-5","display_name":"Claude Haiku 5.5","type":"model"}"#),
            FakeTransport.json(404, #"{"type":"error","error":{"type":"not_found_error","message":"model: claude-nope"}}"#),
        ])
        let model = AnthropicModel(apiKey: Secret("k"), transport: transport, retry: DelayRecorder().policy)

        #expect(await model.check(model: "claude-haiku-5-5") == .success("Connected to Anthropic. Claude Haiku 5.5 is ready."))
        guard case .failure(let e) = await model.check(model: "claude-nope") else { Issue.record("expected failure"); return }
        #expect(e.message == "Anthropic doesn't offer the model “claude-nope” to your account. Nothing was changed.")
        #expect(transport.requests[0].method == "GET")
        #expect(transport.requests[0].url.absoluteString == "https://api.anthropic.com/v1/models/claude-haiku-5-5")
    }

    static let simpleRequest = TurnRequest(model: "claude-opus-5-5", system: "S", messages: [.user("hi")], tools: [],
                                           maxOutputTokens: 1024, timeBudget: 60)
}
