import Foundation

/// What a Claude Code hook tells Sidefolk (via `sidefolk hook <Event>`). Hook payloads are
/// untrusted input (T4): every field is capped here, on the app side, whatever the helper sent.
public struct SessionEvent: Sendable, Equatable {
    public var agent: String
    public var event: String
    public var sessionId: String
    public var cwd: String?
    /// Notification text ("Claude needs your permission to use Bash").
    public var message: String?
    public var notificationType: String?
    public var toolName: String?
    /// The first line of the user's prompt, at most 120 characters.
    public var prompt: String?
    public var hostBundleId: String?
    public var hostPid: Int?
    public var tty: String?

    public init(agent: String = "claude-code", event: String, sessionId: String, cwd: String? = nil, message: String? = nil,
                notificationType: String? = nil, toolName: String? = nil, prompt: String? = nil,
                hostBundleId: String? = nil, hostPid: Int? = nil, tty: String? = nil) {
        self.agent = agent
        self.event = event
        self.sessionId = sessionId
        self.cwd = cwd
        self.message = message
        self.notificationType = notificationType
        self.toolName = toolName
        self.prompt = prompt
        self.hostBundleId = hostBundleId
        self.hostPid = hostPid
        self.tty = tty
    }

    public var json: JSONValue {
        var o: [String: JSONValue] = ["agent": .string(agent), "event": .string(event), "session_id": .string(sessionId)]
        o["cwd"] = cwd.map(JSONValue.string)
        o["message"] = message.map(JSONValue.string)
        o["notification_type"] = notificationType.map(JSONValue.string)
        o["tool_name"] = toolName.map(JSONValue.string)
        o["prompt"] = prompt.map(JSONValue.string)
        o["host_bundle_id"] = hostBundleId.map(JSONValue.string)
        o["host_pid"] = hostPid.map { .number(Double($0)) }
        o["tty"] = tty.map(JSONValue.string)
        return .object(o)
    }

    /// Validates and caps an event received over the socket.
    public init?(json: JSONValue) {
        func word(_ key: String, _ limit: Int) -> String? {
            guard let s = json.string(key), s.count <= limit,
                  s.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0) }) else { return nil }
            return s
        }
        guard let agent = word("agent", 40), let event = word("event", 40), let session = word("session_id", 128) else { return nil }
        self.agent = agent
        self.event = event
        sessionId = session
        cwd = json.string("cwd").flatMap { $0.hasPrefix("/") && $0.utf8.count <= 1024 && !$0.contains("\0") ? $0 : nil }
        message = json.string("message").map { Self.oneLine($0, 300) }
        notificationType = word("notification_type", 40)
        toolName = word("tool_name", 128)
        prompt = json.string("prompt").map { Self.oneLine($0, 120) }
        hostBundleId = word("host_bundle_id", 155)
        hostPid = json["host_pid"]?.intValue.flatMap { $0 > 1 && $0 < Int(Int32.max) ? $0 : nil }
        tty = json.string("tty").flatMap { $0.hasPrefix("/dev/") && $0.count <= 64 ? $0 : nil }
    }

    /// First line, control characters removed, capped.
    static func oneLine(_ text: String, _ limit: Int) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(first.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).clipped(limit)
    }
}

/// Keeps `AgentSession` rows in step with Claude Code hook events and taps the user when a session
/// needs them or finished a long piece of work. Repeated events never repeat the tap.
public actor SessionTracker {
    /// Brings the session's host app (Terminal, iTerm2, VS Code…) to the front.
    public typealias OpenHandler = @Sendable (AgentSession) async -> Void

    /// Work shorter than this ends with a gentle notice instead of an attention tap.
    public static let longWork: TimeInterval = 120

    private let store: SessionStore
    private let attention: AttentionCenter
    private let events: EventBus
    private let clock: any Clock
    private var open: OpenHandler?
    private var workingSince: [String: Date] = [:]
    /// The open "needs you" item per session, withdrawn as soon as the session moves on.
    private var needsYouItem: [String: String] = [:]

    public init(store: SessionStore, attention: AttentionCenter, events: EventBus, clock: any Clock = SystemClock(),
                open: OpenHandler? = nil) {
        self.store = store
        self.attention = attention
        self.events = events
        self.clock = clock
        self.open = open
    }

    public func setOpenHandler(_ handler: @escaping OpenHandler) { open = handler }

    /// Routes the Open button of session bubbles. Call once at launch.
    public func start() async {
        await attention.onAction(kind: "session") { [weak self] item, action in
            guard action == "open", let id = item.refId else { return }
            await self?.openSession(id: id)
        }
    }

    public func openSession(id: String) async {
        guard let session = try? await store.session(id: id), let open else { return }
        await open(session)
    }

    @discardableResult
    public func apply(_ e: SessionEvent) async -> AgentSession? {
        let now = clock.now
        var session = (try? await store.session(id: e.sessionId)) ?? AgentSession(id: e.sessionId, agent: e.agent, cwd: e.cwd,
                                                                                   state: .idle, now: now)
        let before = session.state
        if let cwd = e.cwd { session.cwd = cwd }
        if let bundle = e.hostBundleId { session.hostApp = bundle }
        if let pid = e.hostPid { session.hostPid = pid }
        if let tty = e.tty { session.tty = tty }
        session.updatedAt = now

        switch e.event {
        case "UserPromptSubmit", "PreToolUse":
            if session.title == nil, let prompt = e.prompt, !prompt.isEmpty { session.title = prompt }
            if before != .working { workingSince[session.id] = now }
            session.state = .working
            session.detail = e.toolName.map { String(localized: "Using \($0)") }
            session.endedAt = nil
            await withdrawNeedsYou(session.id)
        case "Notification":
            if e.notificationType == "auth_success" { break }
            // Claude Code repeats "waiting for your input" a minute after it stopped; the
            // finished tap already covered that.
            if e.notificationType == "idle_prompt", before == .idle { break }
            session.state = .needsYou
            session.detail = e.message ?? String(localized: "Waiting for you")
            if before != .needsYou { await tapNeedsYou(session) }
        case "Stop":
            guard before != .idle else { break }
            session.state = .idle
            session.detail = String(localized: "Finished")
            await withdrawNeedsYou(session.id)
            let started = workingSince.removeValue(forKey: session.id) ?? (before == .working ? session.startedAt : now)
            await tapFinished(session, worked: now.timeIntervalSince(started))
        case "SessionEnd":
            session.state = .finished
            session.detail = String(localized: "Ended")
            session.endedAt = now
            workingSince[session.id] = nil
            await withdrawNeedsYou(session.id)
        case "SessionStart":
            session.endedAt = nil
        default:
            return session
        }

        try? await store.save(session)
        events.changed(.runs)
        return session
    }

    private func tapNeedsYou(_ s: AgentSession) async {
        let item = await attention.post(AttentionRequest(
            level: .attention, source: "session:\(s.id)", title: String(localized: "\(Self.agentName(s.agent)) needs you in \(Self.project(s))"),
            body: s.detail, actions: Self.actions,
            refKind: "session", refId: s.id))
        needsYouItem[s.id] = item.id
    }

    private func tapFinished(_ s: AgentSession, worked: TimeInterval) async {
        await attention.post(AttentionRequest(
            level: worked >= Self.longWork ? .attention : .gentle, source: "session:\(s.id)",
            title: String(localized: "\(Self.agentName(s.agent)) finished in \(Self.project(s))", comment: "An agent, then its project: “Claude finished in sidefolk”"), body: s.title,
            actions: Self.actions,
            refKind: "session", refId: s.id))
    }

    private static var actions: [AttentionAction] {
        [AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true),
         AttentionAction(id: "dismiss", title: String(localized: "Dismiss"))]
    }

    private func withdrawNeedsYou(_ sessionId: String) async {
        guard let id = needsYouItem.removeValue(forKey: sessionId) else { return }
        await attention.respond(id: id, actionId: nil)
    }

    static func agentName(_ agent: String) -> String {
        switch agent {
        case "claude-code": "Claude"
        case "codex": "Codex"
        default: agent
        }
    }

    static func project(_ s: AgentSession) -> String { s.projectName ?? String(localized: "a session") }
}
