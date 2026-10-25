import Foundation

/// One tool call the model asked for.
public struct ToolCall: Sendable, Hashable {
    public var id: String
    /// The model-facing name (`notes_create`); `BrainToolbox` accepts it as is.
    public var name: String
    public var input: JSONValue
    /// Set when the model sent arguments that are not a JSON object. The loop answers with an error
    /// instead of running the tool, so a garbled call never reaches Guard with guessed arguments.
    public var invalidArguments: String?

    public init(id: String, name: String, input: JSONValue, invalidArguments: String? = nil) {
        self.id = id
        self.name = name
        self.input = input
        self.invalidArguments = invalidArguments
    }
}

public struct TokenUsage: Sendable, Hashable {
    public var input: Int
    public var output: Int
    public init(input: Int = 0, output: Int = 0) {
        self.input = input
        self.output = output
    }
    public static let zero = TokenUsage()
}

/// Why the model stopped this turn, in provider-neutral terms.
public enum TurnStop: Sendable, Hashable {
    /// A finished answer.
    case end
    /// It wants tools run before it continues.
    case toolUse
    /// The output limit cut it off; any tool call in the turn may be truncated.
    case maxTokens
    /// The provider declined to answer.
    case refusal
    case other(String)
}

/// What the model said in one turn.
public struct ModelTurn: Sendable {
    public var text: String
    public var toolCalls: [ToolCall]
    public var stop: TurnStop
    public var usage: TokenUsage
    /// The provider's own encoding of this assistant turn, replayed unchanged in the next request of
    /// the same run. Anthropic thinking blocks are bound to the conversation and must round-trip.
    public var replay: JSONValue?

    public init(text: String, toolCalls: [ToolCall] = [], stop: TurnStop, usage: TokenUsage = .zero, replay: JSONValue? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.stop = stop
        self.usage = usage
        self.replay = replay
    }
}

/// The answer to one tool call, as the model will read it.
public struct ToolResultMessage: Sendable, Hashable {
    public var callId: String
    public var name: String
    public var content: String
    public var isError: Bool

    public init(callId: String, name: String, content: String, isError: Bool) {
        self.callId = callId
        self.name = name
        self.content = content
        self.isError = isError
    }
}

/// The conversation a `TurnModel` sees. Earlier exchanges are plain text; turns produced during the
/// current run keep their tool calls (and provider replay data) so the transcript stays append-only.
public enum TurnMessage: Sendable {
    case user(String)
    case assistant(String)
    case modelTurn(ModelTurn)
    case toolResults([ToolResultMessage])
}

public struct TurnRequest: Sendable {
    public var model: String
    public var system: String
    public var messages: [TurnMessage]
    public var tools: [ToolSpec]
    public var maxOutputTokens: Int
    /// Seconds left in the run. Adapters never sleep for a retry past it.
    public var timeBudget: TimeInterval

    public init(model: String, system: String, messages: [TurnMessage], tools: [ToolSpec], maxOutputTokens: Int,
                timeBudget: TimeInterval) {
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
        self.maxOutputTokens = maxOutputTokens
        self.timeBudget = timeBudget
    }
}

/// A chat model that answers one turn at a time. Adapters translate to a provider's wire format and
/// throw only `UserFacingError` (already worded for people) or `CancellationError`.
public protocol TurnModel: Sendable {
    /// "Anthropic", "OpenAI", "Ollama"...
    var providerName: String { get }
    func respond(to request: TurnRequest) async throws -> ModelTurn
    /// The cheapest call that proves the provider is reachable, the key works and the model exists.
    func check(model: String) async -> Result<String, UserFacingError>
}
