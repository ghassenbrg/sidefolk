import Foundation

/// Any server speaking OpenAI's `POST {base}/chat/completions` with function tools: OpenAI, Ollama
/// (`http://localhost:11434/v1`, no key), LM Studio, OpenRouter.
public struct OpenAICompatibleModel: TurnModel {
    public let providerName: String
    public let baseURL: URL
    private let apiKey: Secret?
    private let http: ProviderHTTP

    /// Throws when the address is unusable, including plain `http://` to anything but this Mac.
    public init(baseURL: String, apiKey: Secret?, transport: any HTTPTransport = URLSessionTransport(),
                retry: RetryPolicy = .standard) throws(UserFacingError) {
        let url = try Self.validate(baseURL: baseURL)
        self.baseURL = url
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
        providerName = Self.displayName(for: url)
        http = ProviderHTTP(transport: transport, retry: retry, provider: providerName, local: Self.isLoopback(url.host))
    }

    public func respond(to request: TurnRequest) async throws -> ModelTurn {
        let body = Data(Self.requestBody(request).jsonString.utf8)
        let post = HTTPRequest(method: "POST", url: baseURL.appendingPathComponent("chat/completions"), headers: headers(),
                               body: body, timeout: min(max(request.timeBudget, 5), 120))
        let response = try await http.send(post, timeBudget: request.timeBudget)
        guard response.status == 200 else { throw error(for: response, model: request.model) }
        return try Self.parse(response.body, provider: providerName)
    }

    /// `GET {base}/models`: costs nothing and tells whether the model is there.
    public func check(model: String) async -> Result<String, UserFacingError> {
        let get = HTTPRequest(method: "GET", url: baseURL.appendingPathComponent("models"), headers: headers(), timeout: 15)
        do {
            let response = try await http.send(get, timeBudget: 20)
            guard response.status == 200 else { return .failure(error(for: response, model: model)) }
            let json = try? JSONDecoder().decode(JSONValue.self, from: response.body)
            let ids = (json?["data"]?.arrayValue ?? json?["models"]?.arrayValue ?? []).compactMap { $0.string("id") ?? $0.string("name") }
            guard !model.isEmpty else { return .success("Connected to \(providerName).") }
            guard Self.lists(model, in: ids) else {
                let some = ids.prefix(5).joined(separator: ", ")
                return .failure(UserFacingError("\(providerName) is reachable, but it doesn't have “\(model)”.",
                                                recovery: some.isEmpty ? "Check the model name in Settings › AI." : "Available: \(some)."))
            }
            return .success("Connected to \(providerName). \(model) is ready.")
        } catch let e as UserFacingError {
            return .failure(e)
        } catch {
            return .failure(UserFacingError("The check was stopped."))
        }
    }

    private func headers() -> [String: String] {
        var h = ["content-type": "application/json", "accept": "application/json"]
        if let apiKey { h["authorization"] = "Bearer \(apiKey.reveal())" }
        return h
    }

    // MARK: Addresses

    static func validate(baseURL raw: String) throws(UserFacingError) -> URL {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else {
            throw UserFacingError("I need the address of your AI service.",
                                  recovery: "Add it in Settings › AI (for Ollama: http://localhost:11434/v1).")
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else {
            throw UserFacingError("“\(raw.clipped(80))” isn't an address I can use.",
                                  recovery: "Use a full address like https://api.openai.com/v1 or http://localhost:11434/v1.")
        }
        guard scheme == "https" || isLoopback(host) else {
            throw UserFacingError("I only talk to AI services over https, except on this Mac.",
                                  recovery: "Use an https:// address, or http://localhost for Ollama and LM Studio.")
        }
        return url
    }

    static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
        return host == "localhost" || host == "::1" || host.hasPrefix("127.")
    }

    static func displayName(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        if host == "api.openai.com" { return "OpenAI" }
        if host.hasSuffix("openrouter.ai") { return "OpenRouter" }
        if isLoopback(host) {
            switch url.port {
            case 11434: return "Ollama"
            case 1234: return "LM Studio"
            default: return "your local AI server"
            }
        }
        return host
    }

    /// Ollama reports "llama3.1:latest" for a model the user calls "llama3.1".
    static func lists(_ model: String, in ids: [String]) -> Bool {
        ids.contains { $0 == model || $0 == "\(model):latest" || ($0.hasPrefix("\(model):") && !model.contains(":")) }
    }

    // MARK: Wire format

    static func requestBody(_ r: TurnRequest) -> JSONValue {
        var messages: [JSONValue] = []
        if !r.system.isEmpty { messages.append(["role": "system", "content": .string(r.system)]) }
        for m in r.messages {
            switch m {
            case .user(let text):
                messages.append(["role": "user", "content": .string(text)])
            case .assistant(let text):
                messages.append(["role": "assistant", "content": .string(text)])
            case .modelTurn(let turn):
                var message: [String: JSONValue] = ["role": "assistant", "content": turn.text.isEmpty ? .null : .string(turn.text)]
                if !turn.toolCalls.isEmpty {
                    message["tool_calls"] = .array(turn.toolCalls.map { call in
                        ["id": .string(call.id), "type": "function",
                         "function": ["name": .string(call.name), "arguments": .string(call.input.jsonString)]]
                    })
                }
                messages.append(.object(message))
            case .toolResults(let results):
                for r in results {
                    messages.append(["role": "tool", "tool_call_id": .string(r.callId), "content": .string(r.content)])
                }
            }
        }
        // No token limit: OpenAI's newer models reject `max_tokens`, and local servers differ on
        // `max_completion_tokens`. The run's deadline bounds the cost instead.
        var body: [String: JSONValue] = ["model": .string(r.model), "messages": .array(messages), "stream": false]
        if !r.tools.isEmpty {
            body["tools"] = .array(r.tools.map { spec in
                ["type": "function", "function": [
                    "name": .string(spec.modelName),
                    "description": .string(spec.description.isEmpty ? spec.title : spec.description),
                    "parameters": spec.inputSchema,
                ]]
            })
        }
        return .object(body)
    }

    static func parse(_ data: Data, provider: String) throws(UserFacingError) -> ModelTurn {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data), let choice = json["choices"]?.arrayValue?.first,
              let message = choice["message"]
        else {
            throw UserFacingError("\(provider) sent an answer I couldn't read. Nothing was changed.", recovery: "Try again in a moment.",
                                  detail: "unreadable response")
        }
        var calls: [ToolCall] = []
        for (index, raw) in (message["tool_calls"]?.arrayValue ?? []).enumerated() {
            let function = raw["function"] ?? raw
            let name = function["name"]?.stringValue ?? ""
            let id = raw.string("id") ?? "call_\(index)"
            switch function["arguments"] {
            case .string(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    calls.append(ToolCall(id: id, name: name, input: .object([:])))
                } else if let parsed = try? JSONValue.parse(trimmed), parsed.objectValue != nil {
                    calls.append(ToolCall(id: id, name: name, input: parsed))
                } else {
                    calls.append(ToolCall(id: id, name: name, input: .object([:]), invalidArguments: text.clipped(200)))
                }
            case .object(let object):
                calls.append(ToolCall(id: id, name: name, input: .object(object)))
            case nil, .null?:
                calls.append(ToolCall(id: id, name: name, input: .object([:])))
            case let other?:
                calls.append(ToolCall(id: id, name: name, input: .object([:]), invalidArguments: other.jsonString.clipped(200)))
            }
        }
        let stop: TurnStop
        switch choice["finish_reason"]?.stringValue {
        case "length": stop = .maxTokens
        case "content_filter": stop = .refusal
        case "tool_calls", "function_call": stop = .toolUse
        case "stop", nil: stop = calls.isEmpty ? .end : .toolUse
        case let other?: stop = calls.isEmpty ? .other(other) : .toolUse
        }
        let usage = json["usage"]
        return ModelTurn(text: stripReasoning(text(of: message["content"])), toolCalls: calls, stop: stop,
                         usage: TokenUsage(input: usage?["prompt_tokens"]?.intValue ?? 0,
                                           output: usage?["completion_tokens"]?.intValue ?? 0))
    }

    /// `content` is a string, null, or (some servers) an array of `{type: text, text}` parts.
    static func text(of content: JSONValue?) -> String {
        switch content {
        case .string(let s)?: return s
        case .array(let parts)?: return parts.compactMap { $0["text"]?.stringValue }.joined()
        default: return ""
        }
    }

    /// Local reasoning models (DeepSeek-R1, Qwen3 via Ollama) put their thinking in `<think>` tags.
    static func stripReasoning(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func error(for response: HTTPResponse, model: String) -> UserFacingError {
        let detail = ProviderHTTP.detail(response)
        let (type, message) = ProviderHTTP.errorMessage(response.body)
        let lower = ((message ?? "") + " " + (type ?? "")).lowercased()
        let name = providerName
        switch response.status {
        case 401, 403:
            if apiKey == nil {
                return UserFacingError("\(name) needs an API key. Nothing was changed.", recovery: "Add one in Settings › AI.", detail: detail)
            }
            return UserFacingError("\(name) rejected your API key. Nothing was changed.",
                                   recovery: "Check the key in Settings › AI, or paste a new one.", detail: detail)
        case 404 where lower.contains("model"):
            return UserFacingError("\(name) doesn't have the model “\(model)”. Nothing was changed.",
                                   recovery: name == "Ollama" ? "Run “ollama pull \(model)”, or choose another model in Settings › AI."
                                       : "Choose another model in Settings › AI.", detail: detail)
        case 404:
            return UserFacingError("I couldn't find an AI service at that address. Nothing was changed.",
                                   recovery: "Check the address in Settings › AI (it usually ends in /v1).", detail: detail)
        case 413:
            return AnthropicModel.contextTooLong(detail)
        case 400 where lower.contains("does not support tools") || lower.contains("tool use is not supported"):
            return UserFacingError("The model “\(model)” can't use tools, so I can't act with it. Nothing was changed.",
                                   recovery: "Choose a model that supports tool calling in Settings › AI.", detail: detail)
        case 400 where lower.contains("context_length") || lower.contains("context length") || lower.contains("maximum context")
            || lower.contains("too many tokens"):
            return AnthropicModel.contextTooLong(detail)
        case 429 where lower.contains("insufficient_quota") || lower.contains("credit"):
            return UserFacingError("Your \(name) account is out of credit. Nothing was changed.",
                                   recovery: "Check your plan with \(name), or switch provider in Settings › AI.", detail: detail)
        case 429:
            return UserFacingError("\(name) is limiting how fast I can ask right now. Nothing was changed.",
                                   recovery: "Wait a minute and try again.", detail: detail)
        case 500...:
            return UserFacingError("\(name) had a problem answering. Nothing was changed.", recovery: "Try again in a moment.",
                                   detail: detail)
        default:
            return UserFacingError("\(name) couldn't accept that request. Nothing was changed.",
                                   recovery: "Check the model and address in Settings › AI.", detail: detail)
        }
    }
}
