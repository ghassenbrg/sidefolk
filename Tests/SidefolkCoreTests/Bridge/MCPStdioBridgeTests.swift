import Darwin
import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// The MCP server driven through in-memory pipes, as Claude Code or Codex would drive it.
struct MCPPipes {
    let toBridge = Pipe()
    let fromBridge = Pipe()
    let task: Task<Void, Never>
    private let lines: DescriptorLineReader

    init(connector: any BridgeConnector) {
        let bridge = MCPStdioBridge(connector: connector, input: toBridge.fileHandleForReading.fileDescriptor,
                                    output: fromBridge.fileHandleForWriting.fileDescriptor)
        task = Task { await bridge.run() }
        lines = DescriptorLineReader(fd: fromBridge.fileHandleForReading.fileDescriptor, limit: 1 << 20)
    }

    func send(_ message: JSONValue) { toBridge.fileHandleForWriting.write(Data((message.jsonString + "\n").utf8)) }
    func sendRaw(_ text: String) { toBridge.fileHandleForWriting.write(Data(text.utf8)) }

    func receive() async throws -> JSONValue {
        guard case .line(let bytes)? = await lines.next() else { throw BridgeError.disconnected }
        return try JSONValue.parse(String(decoding: bytes, as: UTF8.self))
    }

    func request(_ id: Int, _ method: String, _ params: JSONValue = [:]) async throws -> JSONValue {
        send(["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params])
        return try await receive()
    }

    func finish() async {
        try? toBridge.fileHandleForWriting.close()
        await task.value
    }
}

/// A connector that is never connected: the app isn't running.
struct NotRunning: BridgeConnector {
    func open(client: String) async throws -> any BridgeChannel { throw BridgeError.notRunning }
}

/// Records the client name and answers from a fixed tool list.
final class FakeConnector: BridgeConnector, Sendable {
    let clients = Mutex<[String]>([])
    let calls = Mutex<[JSONValue]>([])

    func open(client: String) async throws -> any BridgeChannel {
        clients.withLock { $0.append(client) }
        return FakeChannel(owner: self)
    }

    struct FakeChannel: BridgeChannel {
        let owner: FakeConnector
        var isOpen: Bool { true }
        func close() {}
        func call(_ method: String, _ params: JSONValue, timeout: TimeInterval?) async throws -> JSONValue {
            switch method {
            case "tools/list":
                return ["tools": [["name": "notes.save", "title": "Save a note", "description": "Saves",
                                   "inputSchema": ["type": "object", "properties": [:]]]]]
            case "tools/call":
                owner.calls.withLock { $0.append(params) }
                return ["text": "Saved to Inbox.", "isError": false]
            default:
                throw BridgeError.remote(code: "not_found", message: "no")
            }
        }
    }
}

@Suite struct MCPStdioBridgeTests {
    @Test func initializeEchoesTheVersionAndOffersOnlyTools() async throws {
        let fake = FakeConnector()
        let pipes = MCPPipes(connector: fake)
        let reply = try await pipes.request(1, "initialize", [
            "protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "claude-code", "version": "2.1"],
        ])
        #expect(reply["jsonrpc"] == "2.0")
        #expect(reply["id"] == 1)
        #expect(reply["result"]?.string("protocolVersion") == "2025-03-26")
        #expect(reply["result"]?["capabilities"]?.objectValue?.keys.sorted() == ["tools"])
        #expect(reply["result"]?["serverInfo"]?.string("name") == "sidefolk")

        pipes.send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        // Notifications get no answer: the next line is the ping's.
        let pong = try await pipes.request(2, "ping")
        #expect(pong["id"] == 2)
        #expect(pong["result"] == [:])

        let list = try await pipes.request(3, "tools/list")
        let tool = try #require(list["result"]?["tools"]?.arrayValue?.first)
        #expect(tool.string("name") == "notes_save")
        #expect(tool["inputSchema"]?.string("type") == "object")
        #expect(fake.clients.withLock { $0 } == ["claude-code"])

        let call = try await pipes.request(4, "tools/call", ["name": "notes_save", "arguments": ["title": "x"]])
        #expect(call["result"]?["content"]?.arrayValue?.first?.string("text") == "Saved to Inbox.")
        #expect(call["result"]?["isError"] == false)
        // MCP names map back to Sidefolk names.
        #expect(fake.calls.withLock { $0 }.first?.string("name") == "notes.save")
        await pipes.finish()
    }

    @Test func whenTheAppIsNotRunning() async throws {
        let pipes = MCPPipes(connector: NotRunning())
        _ = try await pipes.request(1, "initialize", ["protocolVersion": "2025-06-18", "clientInfo": ["name": "codex"]])
        let list = try await pipes.request(2, "tools/list")
        #expect(list["result"]?["tools"] == [])
        let call = try await pipes.request(3, "tools/call", ["name": "notes_save", "arguments": [:]])
        #expect(call["result"]?["isError"] == true)
        #expect(call["result"]?["content"]?.arrayValue?.first?.string("text") == MCPStdioBridge.notRunningMessage)
        await pipes.finish()
    }

    @Test func protocolErrors() async throws {
        let pipes = MCPPipes(connector: NotRunning())
        let unknown = try await pipes.request(1, "resources/list")
        #expect(unknown["error"]?["code"] == -32601)
        pipes.sendRaw("{not json\n")
        let parse = try await pipes.receive()
        #expect(parse["error"]?["code"] == -32700)
        #expect(parse["id"] == .null)
        await pipes.finish()
    }

    @Test func endToEndWithTheApp() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        h.env.registry.register(ProbeTool(name: "notes.save", risk: .low, result: { _ in ToolResult(text: "Saved.") }))
        h.env.registry.register(ProbeTool(name: "files.read", risk: .low))
        let pipes = MCPPipes(connector: SocketConnector(socketPath: h.dir.socket))
        _ = try await pipes.request(1, "initialize", ["protocolVersion": "2025-06-18", "clientInfo": ["name": "Claude Code"]])
        let list = try await pipes.request(2, "tools/list")
        #expect(list["result"]?.toolNames == ["notes_save"])
        let call = try await pipes.request(3, "tools/call", ["name": "notes_save", "arguments": ["x": "hello"]])
        #expect(call["result"]?["content"]?.arrayValue?.first?.string("text") == "Saved.")
        let refused = try await pipes.request(4, "tools/call", ["name": "files_read", "arguments": [:]])
        #expect(refused["result"]?["isError"] == true)
        #expect(try await h.env.activity.recent().first?.caller == "external:Claude Code")
        await pipes.finish()
    }

    @Test func brainTokenComesFromAPrivateRunFolder() throws {
        let dir = try ShortTempDir()
        defer { dir.remove() }
        let token = BrainTokenRegistry.makeToken()
        try PrivateDirectory.writeSecretFile(dir.path + "/token", contents: token)
        #expect(try SocketConnector.brainToken(environment: ["SIDEFOLK_RUN_DIR": dir.path]) == token)
        #expect(try SocketConnector.brainToken(environment: [:]) == nil)

        chmod(dir.path + "/token", 0o644)
        #expect(throws: BridgeError.self) { try SocketConnector.brainToken(environment: ["SIDEFOLK_RUN_DIR": dir.path]) }
        chmod(dir.path + "/token", 0o600)
        chmod(dir.path, 0o755)
        #expect(throws: BridgeError.self) { try SocketConnector.brainToken(environment: ["SIDEFOLK_RUN_DIR": dir.path]) }
        chmod(dir.path, 0o700)
    }
}
