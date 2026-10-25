import Darwin
import Foundation
import Synchronization

/// What the local API serves. Sessions, jobs and status are optional so tests can leave them out.
public struct BridgeServices: Sendable {
    public var tools: ExternalToolGateway
    public var tokens: BrainTokenRegistry
    public var sessions: SessionTracker?
    public var jobs: JobTracker?
    public var status: StatusReader?

    public init(tools: ExternalToolGateway, tokens: BrainTokenRegistry, sessions: SessionTracker? = nil, jobs: JobTracker? = nil,
                status: StatusReader? = nil) {
        self.tools = tools
        self.tokens = tokens
        self.sessions = sessions
        self.jobs = jobs
        self.status = status
    }
}

/// The app's unix-socket API for its helpers (SECURITY.md T6): same-uid peers only, versioned
/// `hello` first, JSON lines up to 1 MiB, at most 8 connections, idle ones closed after 10 minutes.
/// A connection that presents a live brain token calls tools through that run's `BrainToolbox`;
/// every other connection is an external client limited to `ExternalToolPolicy`. No message can
/// make a caller `.user`.
public final class LocalAPIServer: Sendable {
    public struct Limits: Sendable {
        public var maxConnections = 8
        public var maxLineBytes = BridgeProtocol.maxLineBytes
        public var idleTimeout: TimeInterval = 600
        public var callsPerMinute = 60
        public var concurrentCalls = 4
        public init() {}
    }

    public let socketPath: String
    private let services: BridgeServices
    private let limits: Limits
    private let peerUID: @Sendable (Int32) -> uid_t?
    private let expectedUID: uid_t
    private let queue = DispatchQueue(label: "app.sidefolk.bridge")
    private let state = Mutex(State())

    private struct State {
        var running = false
        var listenFD: Int32 = -1
        var inode: ino_t = 0
        var accept: (any DispatchSourceRead)?
        var sweep: (any DispatchSourceTimer)?
        var connections: [UInt64: BridgeConnection] = [:]
        var nextId: UInt64 = 1
    }

    /// - Parameter peerUID: reads the peer's uid from an accepted socket; tests replace it to
    ///   simulate another user.
    public init(socket: URL, services: BridgeServices, limits: Limits = Limits(),
                peerUID: @escaping @Sendable (Int32) -> uid_t? = UnixSocket.peerUID, expectedUID: uid_t = getuid()) {
        socketPath = socket.path
        self.services = services
        self.limits = limits
        self.peerUID = peerUID
        self.expectedUID = expectedUID
    }

    /// Binds the socket. Throws `BridgeError.alreadyRunning` when another instance answers on it
    /// (the caller should focus that one and quit).
    public func start() throws {
        let path = socketPath
        guard path.utf8.count <= UnixSocket.maxPathBytes else { throw BridgeError.pathTooLong(path) }
        try PrivateDirectory.ensure((path as NSString).deletingLastPathComponent)
        try Self.clearStaleSocket(path)

        let fd = try UnixSocket.makeSocket()
        do {
            try UnixSocket.bind(fd, path: path)
            // The folder is 0700, so nobody else can reach the socket between bind and chmod.
            guard chmod(path, 0o600) == 0 else { throw BridgeError.system("chmod", errno) }
            guard listen(fd, 16) == 0 else { throw BridgeError.system("listen", errno) }
        } catch {
            close(fd)
            unlink(path)
            throw error
        }
        UnixSocket.setNonBlocking(fd)
        var st = stat()
        _ = lstat(path, &st)

        let accept = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        accept.setEventHandler { [weak self] in self?.acceptPending() }
        accept.setCancelHandler { close(fd) }
        let sweep = DispatchSource.makeTimerSource(queue: queue)
        let every = max(0.05, min(30, limits.idleTimeout / 2))
        sweep.schedule(deadline: .now() + every, repeating: every)
        sweep.setEventHandler { [weak self] in self?.closeIdle() }
        state.withLock { s in
            s.running = true
            s.listenFD = fd
            s.inode = st.st_ino
            s.accept = accept
            s.sweep = sweep
        }
        accept.resume()
        sweep.resume()
        Log.shared.info("bridge", "listening", ["socket": path])
    }

    public func stop() {
        let (accept, sweep, connections, inode) = state.withLock { s in
            defer {
                s = State(nextId: s.nextId)
            }
            return (s.accept, s.sweep, Array(s.connections.values), s.inode)
        }
        accept?.cancel()
        sweep?.cancel()
        for c in connections { c.close() }
        // Unlink only the socket this instance created.
        var st = stat()
        if inode != 0, lstat(socketPath, &st) == 0, st.st_ino == inode, st.st_mode & S_IFMT == S_IFSOCK { unlink(socketPath) }
    }

    public var connectionCount: Int { state.withLock { $0.connections.count } }

    /// A leftover socket is removed only if it is ours and nobody answers on it (T6).
    static func clearStaleSocket(_ path: String) throws {
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        guard st.st_mode & S_IFMT == S_IFSOCK, st.st_uid == getuid() else {
            throw BridgeError.unsafeLocation("\(path) exists and is not Sidefolk's socket")
        }
        let probe = try UnixSocket.makeSocket()
        defer { close(probe) }
        do {
            try UnixSocket.connect(probe, path: path)
        } catch BridgeError.notRunning {
            unlink(path)
            return
        }
        throw BridgeError.alreadyRunning
    }

    // MARK: Connections

    private func acceptPending() {
        let fd = state.withLock { $0.listenFD }
        guard fd >= 0 else { return }
        while true {
            let client = Darwin.accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            UnixSocket.prepare(client)
            UnixSocket.setNonBlocking(client)
            guard peerUID(client) == expectedUID else {
                Log.shared.warning("bridge", "refused a connection from another user")
                close(client)
                continue
            }
            let id: UInt64? = state.withLock { s in
                guard s.running, s.connections.count < limits.maxConnections else { return nil }
                defer { s.nextId += 1 }
                return s.nextId
            }
            guard let id else {
                _ = UnixSocket.writeAll(client, BridgeProtocol.line(BridgeProtocol.failure(id: .null, .busy, "Too many connections to Sidefolk.")),
                                        timeout: 0.2)
                close(client)
                continue
            }
            let conn = BridgeConnection(id: id, fd: client, lineLimit: limits.maxLineBytes)
            state.withLock { $0.connections[id] = conn }
            conn.start(queue: queue, onLine: { [weak self] c, line in self?.handle(line, on: c) },
                       onEnd: { [weak self] c in self?.drop(c) })
            Log.shared.debug("bridge", "connection opened", ["id": "\(id)", "pid": UnixSocket.peerPID(client).map { "\($0)" } ?? "?"])
        }
    }

    private func drop(_ conn: BridgeConnection) {
        _ = state.withLock { $0.connections.removeValue(forKey: conn.id) }
        conn.close()
    }

    private func closeIdle() {
        let now = Date()
        let idle = state.withLock { s in s.connections.values.filter { $0.isIdle(since: now, timeout: limits.idleTimeout) } }
        for c in idle {
            c.send(BridgeProtocol.failure(id: .null, .unavailable, "Closed after 10 minutes without activity."))
            drop(c)
        }
    }

    // MARK: Requests

    private func handle(_ bytes: [UInt8], on conn: BridgeConnection) {
        guard conn.isOpen else { return }
        conn.touch()
        guard let message = try? JSONValue.parse(String(decoding: bytes, as: UTF8.self)), let method = message.string("method") else {
            conn.send(BridgeProtocol.failure(id: .null, .badRequest, "Expected a JSON object with a method."))
            return
        }
        let id = message["id"] ?? .null
        let params = message["params"] ?? .object([:])

        guard let caller = conn.caller else {
            if method == BridgeProtocol.Method.hello.rawValue {
                hello(id: id, params: params, conn: conn)
            } else {
                conn.send(BridgeProtocol.failure(id: id, .helloRequired, "Say hello first."))
                drop(conn)
            }
            return
        }
        if case .agent(_, let token) = caller, !services.tokens.isBound(token, to: conn.id) {
            conn.send(BridgeProtocol.failure(id: id, .unauthorized, "This Sidefolk brain run has ended."))
            drop(conn)
            return
        }

        switch BridgeProtocol.Method(rawValue: method) {
        case .hello:
            conn.send(BridgeProtocol.failure(id: id, .badRequest, "Already said hello."))
        case .toolsList:
            conn.send(BridgeProtocol.reply(id: id, result: ["tools": .array(specs(for: caller).map(Self.describe))]))
        case .toolsCall:
            guard let name = params.string("name") else {
                conn.send(BridgeProtocol.failure(id: id, .badRequest, "tools/call needs a name."))
                return
            }
            if let refusal = conn.admitCall(now: Date(), limits: limits) {
                let why = refusal == .rateLimited ? "Too many calls to Sidefolk this minute. Try again shortly."
                    : "Too many Sidefolk calls at once. Wait for one to finish."
                conn.send(BridgeProtocol.failure(id: id, refusal, why))
                return
            }
            let input = params["arguments"] ?? .object([:])
            Task {
                let outcome = await self.call(name, input: input, caller: caller)
                conn.finishCall()
                conn.send(BridgeProtocol.reply(id: id, result: ["text": .string(outcome.promptText), "isError": .bool(!outcome.isOK)]))
            }
        case .status:
            Task {
                let snapshot = await self.services.status?.snapshot() ?? StatusSnapshot()
                conn.send(BridgeProtocol.reply(id: id, result: snapshot.json))
            }
        case .sessionEvent:
            guard let tracker = services.sessions, let event = SessionEvent(json: params) else {
                conn.send(BridgeProtocol.failure(id: id, .badRequest, "Not a session event Sidefolk understands."))
                return
            }
            Task {
                await tracker.apply(event)
                conn.send(BridgeProtocol.reply(id: id, result: ["ok": true]))
            }
        case .jobStart, .jobFinish:
            guard let jobs = services.jobs, let report = JobReport(json: params) else {
                conn.send(BridgeProtocol.failure(id: id, .badRequest, "Not a job report Sidefolk understands."))
                return
            }
            let client = caller.clientName
            let starting = method == BridgeProtocol.Method.jobStart.rawValue
            Task {
                let job = starting ? await jobs.start(report, client: client) : await jobs.finish(report, client: client)
                conn.send(BridgeProtocol.reply(id: id, result: ["id": .string(job.id)]))
            }
        case nil:
            conn.send(BridgeProtocol.failure(id: id, .notFound, "Unknown method \(method.clipped(60))."))
        }
    }

    private func hello(id: JSONValue, params: JSONValue, conn: BridgeConnection) {
        guard params["version"]?.intValue == BridgeProtocol.version else {
            conn.send(BridgeProtocol.failure(id: id, .version, "This Sidefolk speaks bridge version \(BridgeProtocol.version). Update the sidefolk helper."))
            drop(conn)
            return
        }
        let client = Self.clientName(params.string("client"))
        if let token = params.string("token") {
            guard let toolbox = services.tokens.claim(token, connection: conn.id) else {
                Log.shared.warning("bridge", "refused an unknown, expired or reused brain token")
                conn.send(BridgeProtocol.failure(id: id, .unauthorized, "Unknown or expired token."))
                drop(conn)
                return
            }
            conn.caller = .agent(toolbox, token: token)
        } else {
            conn.caller = .external(client)
        }
        conn.send(BridgeProtocol.reply(id: id, result: [
            "version": .number(Double(BridgeProtocol.version)), "app": .string(SidefolkVersion.current),
            "caller": .string(conn.caller?.kind ?? "external"),
        ]))
    }

    private func specs(for caller: BridgeCaller) -> [ToolSpec] {
        switch caller {
        case .agent(let toolbox, _): toolbox.specs
        case .external: services.tools.specs()
        }
    }

    private func call(_ name: String, input: JSONValue, caller: BridgeCaller) async -> ToolOutcome {
        switch caller {
        case .agent(let toolbox, _): await toolbox.call(name, input: input)
        case .external(let client): await services.tools.call(name, input: input, client: client)
        }
    }

    static func describe(_ spec: ToolSpec) -> JSONValue {
        ["name": .string(spec.name), "title": .string(spec.title), "description": .string(spec.description),
         "inputSchema": spec.inputSchema]
    }

    /// Client names are shown to the user as unverified labels: printable, short.
    static func clientName(_ raw: String?) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        let clean = String(String.UnicodeScalarView((raw ?? "").unicodeScalars.filter { allowed.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? "unknown agent" : String(clean.prefix(40))
    }
}

/// Who a connection speaks for, fixed by its `hello`.
enum BridgeCaller: Sendable {
    case agent(BrainToolbox, token: String)
    case external(String)

    var kind: String {
        switch self {
        case .agent: "agent"
        case .external: "external"
        }
    }

    var clientName: String {
        switch self {
        case .agent(let toolbox, _): "brain-\(toolbox.runId)"
        case .external(let client): client
        }
    }
}

/// One accepted socket: reads lines on the server queue, writes replies from any task.
final class BridgeConnection: Sendable {
    let id: UInt64
    private let fd: Int32
    private let io = Mutex(true)
    private let session: Mutex<SessionState>
    private let source = Mutex<(any DispatchSourceRead)?>(nil)

    private struct SessionState {
        var buffer: BridgeLineBuffer
        var caller: BridgeCaller?
        var inFlight = 0
        var callTimes: [Date] = []
        var lastActivity = Date()
    }

    init(id: UInt64, fd: Int32, lineLimit: Int) {
        self.id = id
        self.fd = fd
        session = Mutex(SessionState(buffer: BridgeLineBuffer(limit: lineLimit)))
    }

    var isOpen: Bool { io.withLock { $0 } }

    var caller: BridgeCaller? {
        get { session.withLock { $0.caller } }
        set { session.withLock { $0.caller = newValue } }
    }

    func start(queue: DispatchQueue, onLine: @escaping @Sendable (BridgeConnection, [UInt8]) -> Void,
               onEnd: @escaping @Sendable (BridgeConnection) -> Void) {
        let read = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        read.setEventHandler { [weak self] in
            guard let self else { return }
            switch self.readAvailable() {
            case .lines(let lines):
                for line in lines where self.isOpen { onLine(self, line) }
            case .linesThenEnd(let lines):
                for line in lines where self.isOpen { onLine(self, line) }
                onEnd(self)
            case .overflow(let lines):
                for line in lines where self.isOpen { onLine(self, line) }
                self.send(BridgeProtocol.failure(id: .null, .tooLarge, "Messages to Sidefolk are limited to 1 MiB."))
                onEnd(self)
            }
        }
        // Holds the connection until the fd is closed; dispatch drops the handler after cancel.
        read.setCancelHandler { self.closeDescriptor() }
        source.withLock { $0 = read }
        read.resume()
    }

    /// Closes the fd under the write lock so a reply in flight never writes to a reused fd.
    private func closeDescriptor() {
        io.withLock { open in
            open = false
            Darwin.close(fd)
        }
    }

    private enum ReadResult {
        case lines([[UInt8]])
        case linesThenEnd([[UInt8]])
        case overflow([[UInt8]])
    }

    private func readAvailable() -> ReadResult {
        var collected: [[UInt8]] = []
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n > 0 {
                let (lines, overflow) = session.withLock { s in chunk.withUnsafeBytes { s.buffer.append(UnsafeRawBufferPointer(rebasing: $0[0..<n])) } }
                collected += lines
                if overflow { return .overflow(collected) }
                continue
            }
            if n < 0, errno == EINTR { continue }
            if n < 0, errno == EAGAIN { return .lines(collected) }
            return .linesThenEnd(collected)
        }
    }

    func send(_ message: JSONValue) {
        let bytes = BridgeProtocol.line(message)
        let ok = io.withLock { open in open ? UnixSocket.writeAll(fd, bytes, timeout: 2) : true }
        if !ok { close() }
    }

    /// Stops replies and the rest of an already-read batch at once; the fd closes on cancel.
    func close() {
        io.withLock { $0 = false }
        let read = source.withLock { s in defer { s = nil }; return s }
        read?.cancel()
    }

    func touch() { session.withLock { $0.lastActivity = Date() } }

    func isIdle(since now: Date, timeout: TimeInterval) -> Bool {
        session.withLock { $0.inFlight == 0 && now.timeIntervalSince($0.lastActivity) >= timeout }
    }

    /// Counts a tool call against this connection's limits, or says why it is refused.
    func admitCall(now: Date, limits: LocalAPIServer.Limits) -> BridgeProtocol.Code? {
        session.withLock { s in
            s.callTimes.removeAll { now.timeIntervalSince($0) >= 60 }
            if s.callTimes.count >= limits.callsPerMinute { return .rateLimited }
            if s.inFlight >= limits.concurrentCalls { return .busy }
            s.callTimes.append(now)
            s.inFlight += 1
            return nil
        }
    }

    func finishCall() {
        session.withLock { s in
            s.inFlight -= 1
            s.lastActivity = Date()
        }
    }
}
