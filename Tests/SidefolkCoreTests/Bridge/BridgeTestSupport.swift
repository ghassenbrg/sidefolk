import Darwin
import Foundation
import Synchronization
@testable import SidefolkCore

/// Shared mutable state for closures in tests.
final class BridgeRecorder<Value: Sendable>: Sendable {
    let value: Mutex<Value>
    init(_ initial: Value) { value = Mutex(initial) }
}

/// A short private folder under /tmp: `sun_path` holds only 104 bytes, and $TMPDIR paths are longer.
struct ShortTempDir {
    let path: String

    init() throws {
        var template = Array("/tmp/sf-XXXXXX".utf8CString)
        guard let made = mkdtemp(&template) else { throw BridgeError.system("mkdtemp", errno) }
        path = String(cString: made)
        chmod(path, 0o700)
    }

    var run: String { path + "/run" }
    var socket: String { run + "/sidefolk.sock" }

    func remove() { try? FileManager.default.removeItem(atPath: path) }
}

/// A LocalAPIServer over a TestEnv, on a short socket path, with every service wired.
struct BridgeHarness {
    let env: TestEnv
    let dir: ShortTempDir
    let tokens = BrainTokenRegistry()
    let attention: AttentionCenter
    let sessions: SessionTracker
    let jobs: JobTracker
    let server: LocalAPIServer

    init(limits: LocalAPIServer.Limits = .init(), peerUID: (@Sendable (Int32) -> uid_t?)? = nil) throws {
        env = try TestEnv()
        dir = try ShortTempDir()
        attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        sessions = SessionTracker(store: SessionStore(env.db), attention: attention, events: env.events, clock: env.clock)
        jobs = JobTracker(store: JobStore(env.db), attention: attention, events: env.events, clock: env.clock)
        let gateway = ExternalToolGateway(registry: env.registry, permissions: env.permissions, broker: env.broker,
                                          activity: env.activity, events: env.events, clock: env.clock)
        let services = BridgeServices(tools: gateway, tokens: tokens, sessions: sessions, jobs: jobs, status: StatusReader(db: env.db))
        server = LocalAPIServer(socket: URL(fileURLWithPath: dir.socket), services: services, limits: limits,
                                peerUID: peerUID ?? UnixSocket.peerUID)
    }

    func start() throws -> BridgeHarness {
        try server.start()
        return self
    }

    func connect(client: String = "test-agent", token: String? = nil) async throws -> BridgeClient {
        try await BridgeClient.connect(socketPath: dir.socket, client: client, token: token)
    }

    func stop() {
        server.stop()
        dir.remove()
    }
}

/// A plain socket for sending bytes the real client never would.
struct RawSocket {
    let fd: Int32

    init(path: String) throws {
        fd = try UnixSocket.makeSocket()
        try UnixSocket.connect(fd, path: path)
    }

    func send(_ text: String) { _ = UnixSocket.writeAll(fd, Array(text.utf8), timeout: 2) }

    /// The next line, or nil at end of stream or after `timeout`.
    func readLine(timeout: TimeInterval = 2) -> String? {
        var line: [UInt8] = []
        var byte: UInt8 = 0
        let deadline = Date().addingTimeInterval(timeout)
        while UnixSocket.waitReadable(fd, until: deadline) {
            guard read(fd, &byte, 1) == 1 else { return line.isEmpty ? nil : String(decoding: line, as: UTF8.self) }
            if byte == 0x0A { return String(decoding: line, as: UTF8.self) }
            line.append(byte)
        }
        return nil
    }

    /// True once the server closed its end.
    func isClosed(timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var byte: UInt8 = 0
        while UnixSocket.waitReadable(fd, until: deadline) {
            let n = read(fd, &byte, 1)
            if n == 0 { return true }
            if n < 0 { return errno != EAGAIN && errno != EINTR }
        }
        return false
    }

    func close() { Darwin.close(fd) }
}

extension JSONValue {
    var toolNames: Set<String> { Set((self["tools"]?.arrayValue ?? []).compactMap { $0.string("name") }) }
}

/// Waits up to `timeout` for `condition`.
func pollUntil(_ timeout: TimeInterval = 2, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
