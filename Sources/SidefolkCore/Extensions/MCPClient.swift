import Foundation
import Synchronization

public enum MCPError: Error, Sendable, Equatable, CustomStringConvertible {
    case timeout(method: String)
    case notRunning
    case exited(String)
    case protocolViolation(String)
    case server(code: Int, message: String)
    /// A `tools/call` result with `isError: true`: the tool ran and explains, in its own words, what went wrong.
    case toolFailed(String)
    case badResponse(String)

    public var description: String {
        switch self {
        case .timeout(let m): "No answer to \(m) within the time limit."
        case .notRunning: "The extension isn't running."
        case .exited(let why): "The extension stopped (\(why))."
        case .protocolViolation(let why): "The extension broke the protocol: \(why)."
        case .server(let code, let message): "The extension answered with error \(code): \(message)"
        case .toolFailed(let message): "The tool reported a problem: \(message)"
        case .badResponse(let what): "The extension sent an unexpected answer to \(what)."
        }
    }
}

/// A tool as an MCP server describes it, after hygiene. `hash` covers the raw definition, so any change
/// to name, title, description or schema shows up (SECURITY T14 "rug pull").
public struct MCPToolDefinition: Codable, Sendable, Hashable {
    public var name: String
    public var title: String?
    public var description: String
    public var inputSchema: JSONValue
    public var hash: String
}

public struct MCPServerInfo: Sendable, Hashable {
    public var name: String
    public var version: String
    public var protocolVersion: String
}

public struct MCPWatchResult: Sendable, Hashable {
    public var triggered: Bool
    public var state: JSONValue
    public var summary: String
}

public enum MCPClientEvent: Sendable {
    case toolsChanged
    case exited(ExtensionProcessExit)
    case protocolViolation(String)
    case rejectedServerRequest(String)
    /// `sidefolk/nudge` (D63); the host decides whether the extension may.
    case nudge
    /// `sidefolk/clipboard.source`: which app was in front for the copy just made (D68); the host decides.
    case clipboardSource
}

/// A minimal MCP client over an `ExtensionProcess` (JSON-RPC 2.0, one message per line). It advertises
/// no client capabilities and refuses every server-initiated request except `ping`, so an extension
/// can't borrow the user's model (`sampling/createMessage`), learn their folders (`roots/list`) or ask
/// them questions (`elicitation/create`) (SECURITY T17).
public final class MCPClient: Sendable {
    public static let protocolVersion = "2025-06-18"
    public static let maxInFlight = 16
    static let maxDescriptionBytes = 1024
    static let maxSchemaBytes = 16 * 1024
    static let maxTools = 256

    private struct Pending {
        var continuation: CheckedContinuation<JSONValue, Error>
        var timer: Task<Void, Never>?
    }

    private struct State {
        var nextId = 1
        var pending: [Int: Pending] = [:]
        var closed: MCPError?
    }

    public let process: ExtensionProcess
    private let state = Mutex(State())
    private let slots = MCPRequestSlots(MCPClient.maxInFlight)
    private let onEvent: @Sendable (MCPClientEvent) -> Void
    /// The person's language, added as `language` to every tool call and `sidefolk/` request, so a Sidefolk extension
    /// answers in it (D76). Nil for a plain MCP server, which gets requests exactly as MCP has them.
    private let language: (@Sendable () -> String)?

    public init(process: ExtensionProcess, language: (@Sendable () -> String)? = nil,
                onEvent: @escaping @Sendable (MCPClientEvent) -> Void = { _ in }) {
        self.process = process
        self.language = language
        self.onEvent = onEvent
    }

    public func start() throws {
        try process.start(onOutput: { [self] in handle($0) }, onExit: { [self] in handleExit($0) })
    }

    public var isAlive: Bool { state.withLock { $0.closed == nil } && !process.hasExited }

    // MARK: Requests

    public func initialize(timeout: TimeInterval = 30) async throws -> MCPServerInfo {
        let result = try await request("initialize", params: [
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": ["name": "Sidefolk", "version": .string(SidefolkVersion.current)],
        ], timeout: timeout)
        guard result.objectValue != nil else { throw MCPError.badResponse("initialize") }
        await notify("notifications/initialized")
        return MCPServerInfo(name: ExtensionText.line(result["serverInfo"]?["name"]?.stringValue ?? "", characters: 80),
                             version: ExtensionText.line(result["serverInfo"]?["version"]?.stringValue ?? "", characters: 40),
                             protocolVersion: ExtensionText.line(result["protocolVersion"]?.stringValue ?? "", characters: 40))
    }

    /// Every tool the server lists (following pages), plus a note for each one that was refused.
    public func listTools(timeout: TimeInterval = 30) async throws -> (tools: [MCPToolDefinition], refused: [String]) {
        var tools: [MCPToolDefinition] = []
        var refused: [String] = []
        var cursor: String?
        for _ in 0..<20 {
            let params: JSONValue? = cursor.map { ["cursor": .string($0)] }
            let page = try await request("tools/list", params: params, timeout: timeout)
            guard let list = page["tools"]?.arrayValue else { throw MCPError.badResponse("tools/list") }
            for raw in list {
                switch Self.definition(raw) {
                case .success(let t) where !tools.contains(where: { $0.name == t.name }): tools.append(t)
                case .success(let t): refused.append("\(t.name): listed twice")
                case .failure(let why): refused.append(why.message)
                }
                guard tools.count <= Self.maxTools else { throw MCPError.protocolViolation("more than \(Self.maxTools) tools") }
            }
            guard let next = page["nextCursor"]?.stringValue, !next.isEmpty else { break }
            cursor = next
        }
        return (tools, refused)
    }

    static func definition(_ raw: JSONValue) -> Result<MCPToolDefinition, UserFacingError> {
        guard let name = raw["name"]?.stringValue, !name.isEmpty, name.utf8.count <= 128 else {
            return .failure(UserFacingError("A tool without a usable name"))
        }
        let shownName = ExtensionText.line(name, characters: 64)
        let schema = raw["inputSchema"] ?? ["type": "object"]
        guard schema.objectValue != nil else { return .failure(UserFacingError("\(shownName): input schema isn't an object")) }
        guard schema.jsonString.utf8.count <= maxSchemaBytes else {
            return .failure(UserFacingError("\(shownName): input schema is larger than 16 KB"))
        }
        let rawDescription = raw["description"]?.stringValue ?? ""
        let rawTitle = raw["title"]?.stringValue ?? raw["annotations"]?["title"]?.stringValue
        let hash = ExtensionHash.sha256(.object([
            "name": .string(name), "title": rawTitle.map { .string($0) } ?? .null,
            "description": .string(rawDescription), "inputSchema": schema,
        ]))
        return .success(MCPToolDefinition(
            name: name, title: rawTitle.map { ExtensionText.line($0, characters: 80) },
            description: ExtensionText.untrusted(rawDescription, bytes: maxDescriptionBytes),
            inputSchema: schema, hash: hash))
    }

    /// Text content of a tool result; `isError` results throw.
    public func callTool(name: String, arguments: JSONValue, timeout: TimeInterval = 30) async throws -> String {
        let result = try await request("tools/call", params: ["name": .string(name), "arguments": arguments], timeout: timeout)
        let text = Self.text(of: result)
        if case .bool(true)? = result["isError"] { throw MCPError.toolFailed(text) }
        return text
    }

    static func text(of result: JSONValue) -> String {
        var parts: [String] = []
        for item in result["content"]?.arrayValue ?? [] {
            switch item["type"]?.stringValue {
            case "text": parts.append(item["text"]?.stringValue ?? "")
            case "resource":
                parts.append(item["resource"]?["text"]?.stringValue ?? "[resource \(item["resource"]?["uri"]?.stringValue ?? "")]")
            case "resource_link": parts.append("[link: \(item["uri"]?.stringValue ?? "")]")
            case "image": parts.append("[image omitted]")
            case "audio": parts.append("[audio omitted]")
            default: continue
            }
        }
        if parts.isEmpty, let structured = result["structuredContent"] { parts.append(structured.jsonString) }
        return parts.joined(separator: "\n")
    }

    /// `sidefolk/watch.check {watcher, config, state}` → `{triggered, state, summary}`.
    public func watchCheck(watcher: String, config: JSONValue, state: JSONValue, timeout: TimeInterval = 30) async throws -> MCPWatchResult {
        let r = try await request("sidefolk/watch.check", params: [
            "watcher": .string(watcher), "config": config, "state": state,
        ], timeout: timeout)
        guard case .bool(let triggered)? = r["triggered"] else { throw MCPError.badResponse("sidefolk/watch.check") }
        return MCPWatchResult(triggered: triggered, state: r["state"] ?? .null, summary: r["summary"]?.stringValue ?? "")
    }

    /// `sidefolk/page.render {page, language}` → `{page: {summary, sections}}` (D62). `language` here wins over the client's.
    public func pageRender(page: String, language: String, timeout: TimeInterval = 30) async throws -> JSONValue {
        let r = try await request("sidefolk/page.render", params: ["page": .string(page), "language": .string(language)], timeout: timeout)
        guard let page = r["page"], page.objectValue != nil else { throw MCPError.badResponse("sidefolk/page.render") }
        return page
    }

    /// Sends a request and waits for its response, at most `timeout` seconds and 16 at a time.
    public func request(_ method: String, params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue {
        await slots.acquire()
        defer { slots.release() }
        let id = try state.withLock { s -> Int in
            if let closed = s.closed { throw closed }
            defer { s.nextId += 1 }
            return s.nextId
        }
        var message: [String: JSONValue] = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method)]
        if let params { message["params"] = params }
        if let language, method == "tools/call" || method.hasPrefix("sidefolk/"), var object = params?.objectValue ?? (params == nil ? [:] : nil),
           object["language"] == nil {
            object["language"] = .string(language())
            message["params"] = .object(object)
        }
        let line = Data((JSONValue.object(message).jsonString + "\n").utf8)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<JSONValue, Error>) in
                let closed = state.withLock { s -> MCPError? in
                    if let closed = s.closed { return closed }
                    s.pending[id] = Pending(continuation: c, timer: nil)
                    return nil
                }
                if let closed {
                    c.resume(throwing: closed)
                    return
                }
                let timer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled, let self, self.finish(id, .failure(MCPError.timeout(method: method))) else { return }
                    await self.notify("notifications/cancelled", params: ["requestId": .number(Double(id)), "reason": "timeout"])
                }
                let settled = state.withLock { s -> Bool in
                    guard s.pending[id] != nil else { return true }
                    s.pending[id]?.timer = timer
                    return false
                }
                if settled { timer.cancel() }
                Task { [self] in
                    do { try await process.write(line) } catch { finish(id, .failure(MCPError.notRunning)) }
                }
            }
        } onCancel: {
            _ = finish(id, .failure(CancellationError()))
        }
    }

    public func notify(_ method: String, params: JSONValue? = nil) async {
        var message: [String: JSONValue] = ["jsonrpc": "2.0", "method": .string(method)]
        if let params { message["params"] = params }
        try? await process.write(Data((JSONValue.object(message).jsonString + "\n").utf8))
    }

    /// Stops the process (SIGTERM to its group, SIGKILL after the grace period).
    @discardableResult
    public func shutdown() async -> ExtensionProcessExit { await process.terminate() }

    // MARK: Incoming

    /// Resolves a pending request once. Returns false when it was already settled.
    @discardableResult
    private func finish(_ id: Int, _ outcome: Result<JSONValue, Error>) -> Bool {
        guard let p = state.withLock({ $0.pending.removeValue(forKey: id) }) else { return false }
        p.timer?.cancel()
        p.continuation.resume(with: outcome)
        return true
    }

    private func closeAll(_ error: MCPError) {
        let pending = state.withLock { s -> [Pending] in
            if s.closed == nil { s.closed = error }
            defer { s.pending = [:] }
            return Array(s.pending.values)
        }
        for p in pending {
            p.timer?.cancel()
            p.continuation.resume(throwing: error)
        }
    }

    private func handle(_ output: ExtensionProcessOutput) {
        guard case .line(let data) = output else {
            let why = "it sent a message larger than 1 MiB"
            closeAll(.protocolViolation(why))
            onEvent(.protocolViolation(why))
            return
        }
        // Anything that isn't a JSON object (log noise on stdout) is ignored.
        guard let message = try? JSONValue.parse(data), message.objectValue != nil else { return }
        if let method = message["method"]?.stringValue {
            if let id = message["id"], !id.isNull {
                answerServerRequest(id: id, method: method)
            } else if method == "notifications/tools/list_changed" {
                onEvent(.toolsChanged)
            } else if method == "sidefolk/nudge" {
                onEvent(.nudge)
            } else if method == "sidefolk/clipboard.source" {
                onEvent(.clipboardSource)
            }
            return
        }
        guard let id = message["id"]?.intValue else { return }
        if let error = message["error"] {
            let text = ExtensionText.untrusted(error["message"]?.stringValue ?? "", bytes: 500)
            finish(id, .failure(MCPError.server(code: error["code"]?.intValue ?? 0, message: text)))
        } else {
            finish(id, .success(message["result"] ?? .null))
        }
    }

    private func answerServerRequest(id: JSONValue, method: String) {
        let reply: JSONValue
        if method == "ping" {
            reply = ["jsonrpc": "2.0", "id": id, "result": .object([:])]
        } else {
            reply = ["jsonrpc": "2.0", "id": id,
                     "error": ["code": -32601, "message": .string("Sidefolk doesn't offer \(ExtensionText.line(method, characters: 60)) to extensions.")]]
            onEvent(.rejectedServerRequest(ExtensionText.line(method, characters: 60)))
        }
        let line = Data((reply.jsonString + "\n").utf8)
        Task { [process] in try? await process.write(line) }
    }

    private func handleExit(_ exit: ExtensionProcessExit) {
        closeAll(.exited(exit.watchdog ?? exit.description))
        onEvent(.exited(exit))
    }
}

/// At most `limit` requests in flight; later ones wait their turn.
final class MCPRequestSlots: Sendable {
    private let state: Mutex<(free: Int, waiters: [CheckedContinuation<Void, Never>])>

    init(_ limit: Int) { state = Mutex((limit, [])) }

    func acquire() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { s -> Bool in
                if s.free > 0 { s.free -= 1; return true }
                s.waiters.append(c)
                return false
            }
            if ready { c.resume() }
        }
    }

    func release() {
        let next = state.withLock { s -> CheckedContinuation<Void, Never>? in
            if s.waiters.isEmpty { s.free += 1; return nil }
            return s.waiters.removeFirst()
        }
        next?.resume()
    }
}
