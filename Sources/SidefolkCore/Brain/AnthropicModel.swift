import Foundation

/// Claude through the Anthropic Messages API (`POST /v1/messages`, tool use, no streaming).
public struct AnthropicModel: TurnModel {
    public static let defaultModel = "claude-opus-5-5"
    public static let apiVersion = "2023-06-01"
    static let baseURL = URL(string: "https://\(ProviderKeys.anthropicHost)/v1")!

    public let providerName = "Anthropic"
    private let apiKey: Secret
    private let http: ProviderHTTP

    public init(apiKey: Secret, transport: any HTTPTransport = URLSessionTransport(), retry: RetryPolicy = .standard) {
        self.apiKey = apiKey
        http = ProviderHTTP(transport: transport, retry: retry, provider: "Anthropic", local: false)
    }

    public func respond(to request: TurnRequest) async throws -> ModelTurn {
        let body = Data(Self.requestBody(request).jsonString.utf8)
        let post = HTTPRequest(method: "POST", url: Self.baseURL.appendingPathComponent("messages"), headers: headers(),
                               body: body, timeout: min(max(request.timeBudget, 5), 120))
        let response = try await http.send(post, timeBudget: request.timeBudget)
        guard response.status == 200 else { throw Self.error(for: response, model: request.model) }
        return try Self.parse(response.body)
    }

    /// `GET /v1/models/{model}`: free, and proves the key, the network and the model name at once.
    public func check(model: String) async -> Result<String, UserFacingError> {
        let name = model.isEmpty ? Self.defaultModel : model
        let path = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._"))) ?? name
        let get = HTTPRequest(method: "GET", url: Self.baseURL.appendingPathComponent("models/\(path)"), headers: headers(), timeout: 15)
        do {
            let response = try await http.send(get, timeBudget: 20)
            guard response.status == 200 else { return .failure(Self.error(for: response, model: name)) }
            let json = try? JSONValue.parse(response.body)
            let display = json?.string("display_name") ?? name
            return .success("Connected to Anthropic. \(display) is ready.")
        } catch let e as UserFacingError {
            return .failure(e)
        } catch {
            return .failure(UserFacingError("The check was stopped."))
        }
    }

    private func headers() -> [String: String] {
        ["x-api-key": apiKey.reveal(), "anthropic-version": Self.apiVersion, "content-type": "application/json",
         "accept": "application/json"]
    }

    // MARK: Wire format

    static func requestBody(_ r: TurnRequest) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(r.model),
            "max_tokens": .number(Double(r.maxOutputTokens)),
            "messages": .array(r.messages.map(message)),
        ]
        if !r.system.isEmpty { body["system"] = .string(r.system) }
        if !r.tools.isEmpty {
            body["tools"] = .array(r.tools.enumerated().map { index, spec in
                var tool: [String: JSONValue] = [
                    "name": .string(spec.modelName),
                    "description": .string(spec.description.isEmpty ? spec.title : spec.description),
                    "input_schema": spec.inputSchema,
                ]
                // The tool list is the stable prefix of every request (it renders before the system
                // prompt), so caching it saves most of the repeated input across loop steps and runs.
                if index == r.tools.count - 1 { tool["cache_control"] = ["type": "ephemeral"] }
                return .object(tool)
            })
        }
        return .object(body)
    }

    static func message(_ m: TurnMessage) -> JSONValue {
        switch m {
        case .user(let text):
            return ["role": "user", "content": .string(text)]
        case .assistant(let text):
            return ["role": "assistant", "content": .string(text)]
        case .modelTurn(let turn):
            if let replay = turn.replay { return ["role": "assistant", "content": replay] }
            var blocks: [JSONValue] = []
            if !turn.text.isEmpty { blocks.append(["type": "text", "text": .string(turn.text)]) }
            for call in turn.toolCalls {
                blocks.append(["type": "tool_use", "id": .string(call.id), "name": .string(call.name), "input": call.input])
            }
            return ["role": "assistant", "content": .array(blocks)]
        case .toolResults(let results):
            return ["role": "user", "content": .array(results.map { r in
                var block: [String: JSONValue] = ["type": "tool_result", "tool_use_id": .string(r.callId), "content": .string(r.content)]
                if r.isError { block["is_error"] = true }
                return .object(block)
            })]
        }
    }

    static func parse(_ data: Data) throws(UserFacingError) -> ModelTurn {
        guard let json = try? JSONValue.parse(data), let content = json["content"]?.arrayValue else {
            throw UserFacingError("Anthropic sent an answer I couldn't read. Nothing was changed.", recovery: "Try again in a moment.",
                                  detail: "unreadable response")
        }
        var texts: [String] = []
        var calls: [ToolCall] = []
        for (index, block) in content.enumerated() {
            switch block["type"]?.stringValue {
            case "text":
                if let t = block["text"]?.stringValue { texts.append(t) }
            case "tool_use":
                let input = block["input"] ?? .object([:])
                calls.append(ToolCall(id: block.string("id") ?? "toolu_\(index)", name: block["name"]?.stringValue ?? "",
                                      input: input, invalidArguments: input.objectValue == nil ? input.jsonString.clipped(200) : nil))
            default:
                break // thinking and redacted_thinking travel in `replay` only
            }
        }
        let stop: TurnStop
        switch json["stop_reason"]?.stringValue {
        case "end_turn", "stop_sequence", nil: stop = .end
        case "tool_use": stop = .toolUse
        case "max_tokens", "model_context_window_exceeded": stop = .maxTokens
        case "refusal": stop = .refusal
        case let other?: stop = .other(other)
        }
        let usage = json["usage"]
        let input = (usage?["input_tokens"]?.intValue ?? 0) + (usage?["cache_creation_input_tokens"]?.intValue ?? 0)
            + (usage?["cache_read_input_tokens"]?.intValue ?? 0)
        return ModelTurn(text: texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines), toolCalls: calls,
                         stop: stop, usage: TokenUsage(input: input, output: usage?["output_tokens"]?.intValue ?? 0),
                         replay: .array(content))
    }

    static func error(for response: HTTPResponse, model: String) -> UserFacingError {
        let detail = ProviderHTTP.detail(response)
        let lower = (ProviderHTTP.errorMessage(response.body).message ?? "").lowercased()
        switch response.status {
        case 401:
            return UserFacingError("Your Anthropic API key was rejected. Nothing was changed.",
                                   recovery: "Check the key in Settings › AI, or paste a new one.", detail: detail)
        case 402:
            return UserFacingError("Anthropic turned the request down for a billing reason. Nothing was changed.",
                                   recovery: "Check your plan and credits in the Anthropic Console.", detail: detail)
        case 403:
            return UserFacingError("Your Anthropic key isn't allowed to do that. Nothing was changed.",
                                   recovery: "Check your workspace access in the Anthropic Console.", detail: detail)
        case 404:
            return UserFacingError("Anthropic doesn't offer the model “\(model)” to your account. Nothing was changed.",
                                   recovery: "Choose another model in Settings › AI.", detail: detail)
        case 413:
            return contextTooLong(detail)
        case 400 where lower.contains("prompt is too long") || lower.contains("context window") || lower.contains("too many tokens"):
            return contextTooLong(detail)
        case 429:
            return UserFacingError("Anthropic is limiting how fast I can ask right now. Nothing was changed.",
                                   recovery: "Wait a minute and try again.", detail: detail)
        case 529:
            return UserFacingError("Claude is overloaded right now. Nothing was changed.", recovery: "Try again in a moment.", detail: detail)
        case 500...:
            return UserFacingError("Anthropic had a problem answering. Nothing was changed.", recovery: "Try again in a moment.",
                                   detail: detail)
        default:
            return UserFacingError("Anthropic couldn't accept that request. Nothing was changed.",
                                   recovery: "Try rephrasing it. If it keeps happening, check the model in Settings › AI.", detail: detail)
        }
    }

    static func contextTooLong(_ detail: String) -> UserFacingError {
        UserFacingError("That was more than the model can read at once. Nothing was changed.",
                        recovery: "Try a shorter request, or start a fresh conversation.", detail: detail)
    }
}
