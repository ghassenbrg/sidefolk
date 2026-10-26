import Foundation

/// The parts of `codex exec --json` (JSON lines) the Codex brain acts on, as codex-cli 0.160 prints them:
/// `thread.started`, `turn.started`, `item.started|updated|completed`, `turn.completed`, `turn.failed`, `error`.
public enum CodexStreamEvent: Sendable, Equatable {
    case threadStarted
    case item(CodexItem)
    case turnCompleted(CodexUsage)
    case turnFailed(String)
    /// A top-level `error`: Codex reports retries ("Reconnecting... 2/5") this way; only `turn.failed` ends the turn.
    case error(String)
    case other
}

public struct CodexUsage: Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
}

/// What an item says Codex is doing.
public enum CodexItem: Sendable, Equatable {
    /// A finished message to the user (Codex may send a few; the last one is the answer).
    case message(String)
    /// A Sidefolk tool call starting (each call is reported again when it ends; only the start counts).
    case sidefolkTool(name: String, arguments: JSONValue)
    /// Reasoning, plans, a Sidefolk call finishing, a warning: nothing to act on.
    case progress
    /// Something Sidefolk didn't allow. `switchesFailed` means it should have been impossible with the
    /// flags Sidefolk passes (a command, a file change, a web search, another MCP server), so the
    /// backend is turned off; otherwise (helper agents, which some models always have) only the run stops.
    case forbidden(String, switchesFailed: Bool)
}

public enum CodexStream {
    public static func parse(_ line: String) -> CodexStreamEvent {
        guard let json = try? JSONValue.parse(line) else { return .other }
        switch json.string("type") {
        case "thread.started":
            return .threadStarted
        case "item.started", "item.updated", "item.completed":
            guard let item = json["item"] else { return .other }
            return .item(classify(item, completed: json.string("type") == "item.completed",
                                  started: json.string("type") == "item.started"))
        case "turn.completed":
            let usage = json["usage"] ?? .object([:])
            return .turnCompleted(CodexUsage(inputTokens: usage["input_tokens"]?.intValue ?? 0,
                                             outputTokens: usage["output_tokens"]?.intValue ?? 0))
        case "turn.failed":
            return .turnFailed(json["error"]?.string("message") ?? "")
        case "error":
            return .error(json.string("message") ?? "")
        default:
            return .other
        }
    }

    /// Allow-list: messages, reasoning, plans, warnings and Sidefolk's own MCP tools. Anything else,
    /// including item types this version of Sidefolk doesn't know, stops the run.
    static func classify(_ item: JSONValue, completed: Bool, started: Bool) -> CodexItem {
        let type = item.string("type") ?? "?"
        switch type {
        case "agent_message":
            return completed ? .message(item.string("text") ?? "") : .progress
        case "reasoning", "todo_list", "error":
            return .progress
        case "mcp_tool_call":
            let server = item.string("server") ?? "?"
            let tool = item.string("tool") ?? "?"
            guard server == "sidefolk" else {
                return .forbidden("used \(server.clipped(40))’s tool \(tool.clipped(40)), which Sidefolk didn't give it", switchesFailed: true)
            }
            return started ? .sidefolkTool(name: tool, arguments: item["arguments"] ?? .object([:])) : .progress
        case "command_execution":
            return .forbidden("tried to run a command (\((item.string("command") ?? "").clipped(80)))", switchesFailed: true)
        case "file_change":
            let paths = (item["changes"]?.arrayValue ?? []).compactMap { $0.string("path") }
            return .forbidden("tried to change files (\(paths.prefix(3).joined(separator: ", ").clipped(120)))", switchesFailed: true)
        case "web_search":
            return .forbidden("tried to search the web (\((item.string("query") ?? "").clipped(80)))", switchesFailed: true)
        case "collab_tool_call":
            return .forbidden("tried to start helper agents", switchesFailed: false)
        default:
            return .forbidden("did something Sidefolk doesn't recognise (\(type.clipped(40)))", switchesFailed: false)
        }
    }

    /// Plain-language errors for the ways a Codex run fails.
    static func userFacingError(message: String, stderr: String, model: String) -> UserFacingError {
        let text = (message + "\n" + stderr).lowercased()
        let detail = Redactor.redact(message.isEmpty ? stderr : message).clipped(300)
        if ["unknown configuration field", "unknown feature flag", "error loading config", "unexpected argument"].contains(where: text.contains) {
            return UserFacingError("This version of Codex can't be run safely by Sidefolk.",
                                   recovery: "Update Codex (npm install -g @openai/codex@latest) or choose another provider.", detail: detail)
        }
        if ["401", "unauthorized", "not logged in", "codex login", "token expired", "refresh token"].contains(where: text.contains) {
            return UserFacingError("Codex isn't signed in.", recovery: "Open Terminal, run codex login, then try again.", detail: detail)
        }
        if ["usage limit", "rate limit", "429", "too many requests", "quota"].contains(where: text.contains) {
            return UserFacingError("Your ChatGPT plan's Codex limit is reached for now.",
                                   recovery: "Try again later or switch provider in Settings › AI.", detail: detail)
        }
        if !model.isEmpty, text.contains("model"), ["not supported", "does not exist", "not found", "unknown model", "invalid model"].contains(where: text.contains) {
            return UserFacingError("Codex can't use the model “\(model)”.",
                                   recovery: "Pick another model in Settings › AI, or leave it empty for Codex's default.", detail: detail)
        }
        if ["error sending request", "dns", "connection refused", "connection reset", "network", "timed out", "stream disconnected"].contains(where: text.contains) {
            return UserFacingError("I couldn't reach OpenAI.", recovery: "Check your connection or switch provider.", detail: detail)
        }
        return UserFacingError("Codex stopped with an error.", recovery: "Try again; if it keeps happening, check Codex in Terminal.",
                               detail: detail)
    }
}
