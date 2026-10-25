import Darwin
import Foundation
import Synchronization

/// A connection to the app, as the MCP bridge sees it (tests substitute their own).
public protocol BridgeChannel: Sendable {
    func call(_ method: String, _ params: JSONValue, timeout: TimeInterval?) async throws -> JSONValue
    var isOpen: Bool { get }
    func close()
}

/// Opens connections to the app. `BridgeError.notRunning` means the app isn't there.
public protocol BridgeConnector: Sendable {
    func open(client: String) async throws -> any BridgeChannel
}

/// The helper side of the local API. Before sending anything it checks that the run folder is
/// private and the listening process belongs to the same user (T6), then says hello.
public final class BridgeClient: BridgeChannel, Sendable {
    public struct Hello: Sendable, Equatable {
        public var version: Int
        public var app: String
        public var caller: String
    }

    public let hello: Hello
    private let connection: Connection

    /// - Parameters:
    ///   - token: a brain run's token (from `$SIDEFOLK_RUN_DIR/token`); nil for external clients.
    public static func connect(socketPath: String, client: String, token: String? = nil, timeout: TimeInterval = 3) async throws -> BridgeClient {
        try verifyServerLocation(socketPath)
        let fd = try UnixSocket.makeSocket()
        do {
            try UnixSocket.connect(fd, path: socketPath)
            guard UnixSocket.peerUID(fd) == getuid() else { throw BridgeError.peerRejected }
        } catch {
            Darwin.close(fd)
            throw error
        }
        var sendTimeout = timeval(tv_sec: 5, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        let connection = Connection(fd: fd)
        connection.startReading()
        var params: JSONValue = ["version": .number(Double(BridgeProtocol.version)), "client": .string(client)]
        if let token { params = .object(params.objectValue!.merging(["token": .string(token)]) { $1 }) }
        do {
            let reply = try await connection.call(BridgeProtocol.Method.hello.rawValue, params, timeout: timeout)
            let hello = Hello(version: reply["version"]?.intValue ?? 0, app: reply.string("app") ?? "?",
                              caller: reply.string("caller") ?? "external")
            return BridgeClient(connection: connection, hello: hello)
        } catch {
            connection.close()
            throw error
        }
    }

    /// The run folder must be 0700 and ours, and the socket a socket we own, before we talk to it.
    static func verifyServerLocation(_ socketPath: String) throws {
        guard socketPath.utf8.count <= UnixSocket.maxPathBytes else { throw BridgeError.pathTooLong(socketPath) }
        var st = stat()
        guard lstat(socketPath, &st) == 0 else { throw BridgeError.notRunning }
        try PrivateDirectory.verify((socketPath as NSString).deletingLastPathComponent)
        guard st.st_mode & S_IFMT == S_IFSOCK, st.st_uid == getuid() else {
            throw BridgeError.unsafeLocation("\(socketPath) is not a socket you own")
        }
    }

    private init(connection: Connection, hello: Hello) {
        self.connection = connection
        self.hello = hello
    }

    public var isOpen: Bool { connection.isOpen }

    public func call(_ method: String, _ params: JSONValue = .object([:]), timeout: TimeInterval? = nil) async throws -> JSONValue {
        try await connection.call(method, params, timeout: timeout)
    }

    public func close() { connection.close() }
}

/// Multiplexes requests over one socket: a reader thread matches replies to waiting calls by id.
private final class Connection: Sendable {
    private let fd: Int32
    private let io = Mutex(true)
    private let state = Mutex<State>(State())

    private struct State {
        var next = 1
        var waiting: [Int: CheckedContinuation<JSONValue, Error>] = [:]
        var ended = false
    }

    init(fd: Int32) { self.fd = fd }

    var isOpen: Bool { !state.withLock { $0.ended } }

    func startReading() {
        Thread.detachNewThread { [self] in readLoop() }
    }

    func call(_ method: String, _ params: JSONValue, timeout: TimeInterval?) async throws -> JSONValue {
        let id = state.withLock { s in defer { s.next += 1 }; return s.next }
        let line = BridgeProtocol.line(BridgeProtocol.request(id: id, method: method, params: params))
        let timer = timeout.map { seconds in
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.fail(id, BridgeError.timedOut)
            }
        }
        defer { timer?.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            let ended = state.withLock { s in
                if !s.ended { s.waiting[id] = continuation }
                return s.ended
            }
            if ended { return continuation.resume(throwing: BridgeError.disconnected) }
            let sent = io.withLock { open in open && UnixSocket.writeAll(fd, line, timeout: 5) }
            if !sent {
                fail(id, BridgeError.disconnected)
                close()
            }
        }
    }

    func close() {
        // Wakes the reader, which closes the fd once it has stopped using it.
        io.withLock { open in if open { _ = shutdown(fd, SHUT_RDWR) } }
    }

    private func fail(_ id: Int, _ error: Error) {
        state.withLock { $0.waiting.removeValue(forKey: id) }?.resume(throwing: error)
    }

    private func readLoop() {
        var buffer = BridgeLineBuffer(limit: BridgeProtocol.maxLineBytes)
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        reading: while true {
            let n = read(fd, &chunk, chunk.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            let (lines, overflow) = chunk.withUnsafeBytes { buffer.append(UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
            for line in lines { deliver(line) }
            if overflow { break reading }
        }
        let waiting = state.withLock { s in
            s.ended = true
            defer { s.waiting = [:] }
            return Array(s.waiting.values)
        }
        for c in waiting { c.resume(throwing: BridgeError.disconnected) }
        io.withLock { open in
            open = false
            Darwin.close(fd)
        }
    }

    private func deliver(_ line: [UInt8]) {
        guard let message = try? JSONValue.parse(String(decoding: line, as: UTF8.self)) else { return }
        guard let id = message["id"]?.intValue else { return } // unsolicited notice (busy, idle close)
        guard let c = state.withLock({ $0.waiting.removeValue(forKey: id) }) else { return }
        if let error = message["error"] {
            c.resume(throwing: BridgeError.remote(code: error.string("code") ?? "error", message: error.string("message") ?? "Sidefolk refused the request."))
        } else {
            c.resume(returning: message["result"] ?? .null)
        }
    }
}

/// Connects to the app's socket with an optional brain token.
public struct SocketConnector: BridgeConnector {
    public let socketPath: String
    public let token: String?

    public init(socketPath: String, token: String? = nil) {
        self.socketPath = socketPath
        self.token = token
    }

    public func open(client: String) async throws -> any BridgeChannel {
        try await BridgeClient.connect(socketPath: socketPath, client: client, token: token)
    }

    /// The brain token, when this helper was started by a Sidefolk brain run (`SIDEFOLK_RUN_DIR`).
    /// The folder must be private and the token file a 0600 file we own.
    public static func brainToken(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String? {
        guard let dir = environment["SIDEFOLK_RUN_DIR"], !dir.isEmpty else { return nil }
        guard dir.hasPrefix("/") else { throw BridgeError.unsafeLocation("SIDEFOLK_RUN_DIR must be absolute") }
        try PrivateDirectory.verify(dir)
        let token = try PrivateDirectory.readSecretFile((dir as NSString).appendingPathComponent("token"))
        guard token.count == 64, token.allSatisfy(\.isHexDigit) else { throw BridgeError.unsafeLocation("the brain token is malformed") }
        return token
    }
}
