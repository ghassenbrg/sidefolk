import Darwin
import Foundation
import Synchronization

/// `sidefolk mcp`: a Model Context Protocol server on stdio (JSON-RPC 2.0, one message per line)
/// that forwards `tools/list` and `tools/call` to the running app over the local socket. It
/// advertises only the tools capability. When the app isn't running, the tool list is empty and
/// calls return a tool error asking the user to open Sidefolk.
public actor MCPStdioBridge {
    public static let notRunningMessage = "Sidefolk isn't running. Open Sidefolk and try again."
    static let fallbackProtocolVersion = "2025-06-18"
    /// What a client shows its model about the server as a whole; the Sidefolk skill says the rest.
    static let instructions = """
        Sidefolk is the user's desktop companion on this Mac. Use it to remind the user at a time, save notes and tasks \
        to their notebook, tell them when a web page, site, file or program changes, show a live value of this Mac, \
        notify them when your work finishes, or ask them a quick question on their desktop. Reading their notes and \
        reminders asks them first. Never save secrets, and send one notice per event.
        """

    private let connector: any BridgeConnector
    private let input: Int32
    private let output: Int32
    private var clientName = "mcp-client"
    private var channel: (any BridgeChannel)?
    private var connecting: Task<any BridgeChannel, Error>?
    /// MCP names ("notes_save") back to Sidefolk names ("notes.save").
    private var names: [String: String] = [:]

    /// - Parameters: `input`/`output` are file descriptors (stdin/stdout, or pipes in tests).
    public init(connector: any BridgeConnector, input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO) {
        self.connector = connector
        self.input = input
        self.output = output
        _ = fcntl(output, F_SETNOSIGPIPE, 1)
    }

    /// Serves until the client closes stdin. Requests run concurrently (a call may wait minutes
    /// for the user), replies are written whole, one per line.
    public func run() async {
        let reader = DescriptorLineReader(fd: input, limit: BridgeProtocol.maxLineBytes)
        await withTaskGroup(of: Void.self) { group in
            while let next = await reader.next() {
                guard case .line(let bytes) = next else {
                    write(Self.error(id: .null, code: -32700, message: "Message too large."))
                    continue
                }
                group.addTask { await self.handle(bytes) }
            }
        }
        channel?.close()
    }

    func handle(_ bytes: [UInt8]) async {
        guard let message = try? JSONValue.parse(String(decoding: bytes, as: UTF8.self)), message.objectValue != nil else {
            write(Self.error(id: .null, code: -32700, message: "Parse error"))
            return
        }
        guard let method = message.string("method") else { return } // a response to us: we never ask
        let params = message["params"] ?? .object([:])
        guard let id = message["id"] else {
            return // notifications (initialized, cancelled) need no answer
        }
        switch method {
        case "initialize":
            if let name = params["clientInfo"]?.string("name") { clientName = name }
            let version = params.string("protocolVersion") ?? Self.fallbackProtocolVersion
            write(Self.result(id: id, [
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "sidefolk", "title": "Sidefolk", "version": .string(SidefolkVersion.current)],
                "instructions": .string(Self.instructions),
            ]))
        case "ping":
            write(Self.result(id: id, .object([:])))
        case "tools/list":
            write(Self.result(id: id, ["tools": .array(await listTools())]))
        case "tools/call":
            let text: String
            let isError: Bool
            if let name = params.string("name") {
                (text, isError) = await callTool(name, arguments: params["arguments"] ?? .object([:]))
            } else {
                (text, isError) = ("A tool name is required.", true)
            }
            write(Self.result(id: id, ["content": [["type": "text", "text": .string(text)]], "isError": .bool(isError)]))
        default:
            write(Self.error(id: id, code: -32601, message: "Method not found: \(method.clipped(60))"))
        }
    }

    private func listTools() async -> [JSONValue] {
        guard let reply = try? await request("tools/list", .object([:])) else { return [] }
        var tools: [JSONValue] = []
        for spec in reply["tools"]?.arrayValue ?? [] {
            guard let name = spec.string("name") else { continue }
            let mcpName = name.replacingOccurrences(of: ".", with: "_")
            names[mcpName] = name
            var tool: [String: JSONValue] = ["name": .string(mcpName), "inputSchema": spec["inputSchema"] ?? ["type": "object"]]
            tool["title"] = spec["title"]
            tool["description"] = spec["description"]
            tools.append(.object(tool))
        }
        return tools
    }

    private func callTool(_ name: String, arguments: JSONValue) async -> (String, Bool) {
        do {
            let reply = try await request("tools/call", ["name": .string(names[name] ?? name), "arguments": arguments])
            return (reply.string("text") ?? "", reply["isError"]?.boolValue ?? false)
        } catch BridgeError.remote(_, let message) {
            return (message, true)
        } catch {
            return (Self.notRunningMessage, true)
        }
    }

    /// Sends a request to the app, connecting (or reconnecting after the app restarted) first.
    private func request(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        do {
            return try await openChannel().call(method, params, timeout: nil)
        } catch BridgeError.disconnected {
            channel = nil
            return try await openChannel().call(method, params, timeout: nil)
        }
    }

    /// One connection shared by concurrent requests; opened once even if several ask at the same time.
    private func openChannel() async throws -> any BridgeChannel {
        if let channel, channel.isOpen { return channel }
        if let connecting { return try await connecting.value }
        let connector = self.connector, client = clientName
        let task = Task { try await connector.open(client: client) }
        connecting = task
        defer { connecting = nil }
        let opened = try await task.value
        channel = opened
        return opened
    }

    private func write(_ message: JSONValue) {
        _ = UnixSocket.writeAll(output, BridgeProtocol.line(message), timeout: 30)
    }

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }
}

/// Reads newline-delimited messages from a file descriptor without blocking Swift's cooperative
/// threads: each read runs on a private queue.
final class DescriptorLineReader: Sendable {
    enum Item: Sendable {
        case line([UInt8])
        case tooLong
    }

    private let fd: Int32
    private let queue = DispatchQueue(label: "app.sidefolk.lines")
    private let state: Mutex<(buffer: BridgeLineBuffer, ready: [Item], ended: Bool)>

    init(fd: Int32, limit: Int) {
        self.fd = fd
        state = Mutex((BridgeLineBuffer(limit: limit), [], false))
    }

    /// The next line, or nil at end of input.
    func next() async -> Item? {
        while true {
            let (item, ended) = state.withLock { s -> (Item?, Bool) in
                s.ready.isEmpty ? (nil, s.ended) : (s.ready.removeFirst(), false)
            }
            if let item { return item }
            if ended { return nil }
            await fill()
        }
    }

    private func fill() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                var chunk = [UInt8](repeating: 0, count: 64 * 1024)
                var n: Int
                repeat { n = read(fd, &chunk, chunk.count) } while n < 0 && errno == EINTR
                state.withLock { s in
                    guard n > 0 else { s.ended = true; return }
                    let (lines, overflow) = chunk.withUnsafeBytes { s.buffer.append(UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
                    s.ready += lines.map(Item.line)
                    if overflow {
                        s.ready.append(.tooLong)
                        s.buffer = BridgeLineBuffer(limit: s.buffer.limit)
                    }
                }
                done.resume()
            }
        }
    }
}
