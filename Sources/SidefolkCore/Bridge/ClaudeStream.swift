import Foundation

/// The parts of Claude Code's `--output-format stream-json` the brain backend acts on.
public enum ClaudeStreamEvent: Sendable, Equatable {
    /// `{"type":"system","subtype":"init", "tools": [...], "mcp_servers": [...]}`: what the CLI loaded.
    case initialized(ClaudeInit)
    /// An assistant message: its text blocks joined, and the tools it calls.
    case assistant(text: String, toolUses: [ClaudeToolUse])
    case result(ClaudeResult)
    case other
}

public struct ClaudeInit: Sendable, Equatable {
    public var tools: [String]
    public var mcpServers: [ClaudeMCPServer]
    public var model: String?
}

public struct ClaudeMCPServer: Sendable, Equatable {
    public var name: String
    public var status: String
}

public struct ClaudeToolUse: Sendable, Equatable {
    public var name: String
    public var input: JSONValue
}

public struct ClaudeResult: Sendable, Equatable {
    public var text: String
    public var isError: Bool
    public var subtype: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var turns: Int?
}

public enum ClaudeStream {
    public static func parse(_ line: String) -> ClaudeStreamEvent {
        guard let json = try? JSONValue.parse(line) else { return .other }
        switch json.string("type") {
        case "system" where json.string("subtype") == "init":
            let tools = (json["tools"]?.arrayValue ?? []).compactMap(\.stringValue)
            let servers = (json["mcp_servers"]?.arrayValue ?? []).compactMap { s -> ClaudeMCPServer? in
                guard let name = s.string("name") else { return nil }
                return ClaudeMCPServer(name: name, status: s.string("status") ?? "unknown")
            }
            return .initialized(ClaudeInit(tools: tools, mcpServers: servers, model: json.string("model")))
        case "assistant":
            var texts: [String] = []
            var uses: [ClaudeToolUse] = []
            for block in json["message"]?["content"]?.arrayValue ?? [] {
                switch block.string("type") {
                case "text": if let t = block["text"]?.stringValue { texts.append(t) }
                case "tool_use": uses.append(ClaudeToolUse(name: block.string("name") ?? "?", input: block["input"] ?? .object([:])))
                default: break
                }
            }
            return .assistant(text: texts.joined(), toolUses: uses)
        case "result":
            let usage = json["usage"] ?? .object([:])
            let input = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                .compactMap { usage[$0]?.intValue }.reduce(0, +)
            let isError = json["is_error"]?.boolValue ?? (json.string("subtype") != "success")
            let text = json["result"]?.stringValue
                ?? (json["errors"]?.arrayValue ?? []).compactMap(\.stringValue).joined(separator: " ")
            return .result(ClaudeResult(text: text, isError: isError, subtype: json.string("subtype") ?? "unknown",
                                        inputTokens: input, outputTokens: usage["output_tokens"]?.intValue ?? 0,
                                        turns: json["num_turns"]?.intValue))
        default:
            return .other
        }
    }

    /// The brain may only have Sidefolk's tools from Sidefolk's own MCP server (T7). Anything else
    /// means user, project or managed configuration leaked into the run.
    public static func isolationProblem(_ i: ClaudeInit) -> String? {
        if let tool = i.tools.first(where: { !$0.hasPrefix("mcp__sidefolk__") }) {
            return "Claude Code loaded a tool Sidefolk didn't give it (\(tool.clipped(60)))."
        }
        if let server = i.mcpServers.first(where: { $0.name != "sidefolk" }) {
            return "Claude Code loaded an MCP server Sidefolk didn't give it (\(server.name.clipped(60)))."
        }
        return nil
    }

    /// Plain-language errors for the ways a Claude Code run fails.
    static func userFacingError(message: String, stderr: String) -> UserFacingError {
        let text = (message + "\n" + stderr).lowercased()
        let detail = Redactor.redact(message.isEmpty ? stderr : message).clipped(300)
        if ["not logged in", "/login", "invalid api key", "oauth token", "authentication", "unauthorized"].contains(where: text.contains) {
            return UserFacingError("Claude Code isn't signed in.", recovery: "Open Terminal, run claude and sign in, then try again.",
                                   detail: detail)
        }
        if ["usage limit", "rate limit", "rate_limit", "limit reached", "hit your limit", "429", "overloaded"].contains(where: text.contains) {
            return UserFacingError("Claude's usage limit is reached for now.", recovery: "Try again later or switch provider in Settings › AI.",
                                   detail: detail)
        }
        if ["enotfound", "econnrefused", "etimedout", "network", "could not connect", "fetch failed", "connection error"].contains(where: text.contains) {
            return UserFacingError("I couldn't reach Claude.", recovery: "Check your connection or switch provider.", detail: detail)
        }
        return UserFacingError("Claude Code stopped with an error.", recovery: "Try again; if it keeps happening, check Claude Code in Terminal.",
                               detail: detail)
    }
}
