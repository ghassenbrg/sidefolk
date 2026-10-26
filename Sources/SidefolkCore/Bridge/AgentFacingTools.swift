import Foundation

/// Tools that let an agent (Sidefolk's own brain or an external MCP client) reach the user:
/// `notify.user`, `ask.user`, and a content-free `status`.
public enum AgentFacingTools {
    public static let maxAskSeconds: TimeInterval = 600

    public static func make(attention: AttentionCenter) -> [any Tool] {
        [NotifyUserTool(attention: attention), AskUserTool(attention: attention)]
    }

    public static func status(_ reader: StatusReader) -> any Tool { StatusTool(reader: reader) }

    /// An answer the user typed (instead of picking an option) arrives as this prefix + the text.
    public static let typedAnswerPrefix = "text:"

    /// "Claude Code" for "claude-code", "Codex" for "codex"; other names as given.
    public static func displayName(_ client: String) -> String {
        switch client.lowercased() {
        case "claude-code", "claude code", "claude": "Claude Code"
        case "codex", "codex-mcp-client", "codex_cli": "Codex"
        default: client.clipped(30)
        }
    }

    /// Where an attention item from this caller says it comes from.
    static func source(for caller: Caller) -> String {
        switch caller {
        case .user: "user"
        case .agent: "agent"
        case .routine(let id): "routine:\(id)"
        case .external(let client): "external:\(client)"
        case .extension(let id): "extension:\(id)"
        }
    }
}

struct NotifyUserTool: Tool {
    let attention: AttentionCenter

    var spec: ToolSpec {
        ToolSpec(
            name: "notify.user", title: String(localized: "Notify the user"),
            description: "Show the user a short message on their desktop, e.g. that a task finished. Use \"attention\" only when they should look now.",
            inputSchema: Schema.object([
                "title": Schema.string("One line, at most 120 characters."),
                "body": Schema.string("Optional detail, at most 600 characters."),
                "level": Schema.string("gentle (default) or attention.", enum: ["gentle", "attention"]),
            ], required: ["title"]),
            risk: .low, capabilities: [], category: .agents, mutates: false, external: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Notify: \(input.string("title") ?? "")") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let title = input.string("title") else { throw ToolError.invalidInput(String(localized: "a title is needed")) }
        // The schema only offers gentle and attention, so external agents stay capped at attention.
        let level: AttentionLevel = input.string("level") == "attention" ? .attention : .gentle
        let actions = level == .attention ? [AttentionAction(id: "dismiss", title: String(localized: "Dismiss"))] : []
        let item = await attention.post(AttentionRequest(level: level, source: AgentFacingTools.source(for: context.caller),
                                                         title: title.clipped(120), body: input.string("body")?.clipped(600),
                                                         actions: actions, refKind: "notify"))
        // Saying so keeps a caller from sending it again, louder, because it seemed to go nowhere.
        if await attention.isHeld(item.id) {
            return ToolResult(text: "Held for now: the user is busy, away or in quiet mode, or other notices came first. "
                + "Sidefolk shows it when it can; don't send it again.")
        }
        return ToolResult(text: "Shown to the user.")
    }
}

struct AskUserTool: Tool {
    let attention: AttentionCenter

    var spec: ToolSpec {
        ToolSpec(
            name: "ask.user", title: String(localized: "Ask the user"),
            description: "Ask the user a short question and wait for the answer. Offer 2 to 4 answer buttons when the choices are known; "
                + "leave options out to let them type the answer. Returns the chosen option, what they typed, or \"no answer\".",
            inputSchema: Schema.object([
                "question": Schema.string("The question, at most 200 characters."),
                "options": Schema.array("Optional: 2 to 4 short answers (at most 40 characters each).", items: Schema.string("An answer")),
                "timeout_seconds": Schema.integer("How long to wait, at most 600 (default 300).", minimum: 10, maximum: 600),
            ], required: ["question"]),
            risk: .low, capabilities: [], category: .agents, mutates: false, external: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Ask: \(input.string("question") ?? "")") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let question = input.string("question") else { throw ToolError.invalidInput(String(localized: "a question is needed")) }
        let options = (input["options"]?.arrayValue ?? []).compactMap { $0.stringValue?.clipped(40) }.filter { !$0.isEmpty }
        guard options.isEmpty || ((2...4).contains(options.count) && Set(options).count == options.count) else {
            throw ToolError.invalidInput(String(localized: "give 2 to 4 different options, or none to let the user type an answer"))
        }
        var timeout = min(Double(input["timeout_seconds"]?.intValue ?? 300), AgentFacingTools.maxAskSeconds)
        // Sidefolk's own brain calls tools with the executor's default 90 s timeout.
        if case .agent = context.caller { timeout = min(timeout, 80) }
        let actions = options.enumerated().map { AttentionAction(id: "option-\($0.offset)", title: $0.element, isPrimary: $0.offset == 0) }
        // Who is asking is shown with the question; agents must not pose as Sidefolk or the user.
        var asker: String?
        if case .external(let client) = context.caller { asker = String(localized: "\(AgentFacingTools.displayName(client)) asks") }
        let answer = await attention.ask(AttentionRequest(level: .attention, source: AgentFacingTools.source(for: context.caller),
                                                          title: question.clipped(200), body: asker, actions: actions, refKind: "ask"),
                                         timeout: max(10, timeout))
        guard let answer else { return ToolResult(text: "no answer") }
        if answer.hasPrefix(AgentFacingTools.typedAnswerPrefix) {
            return ToolResult(text: String(answer.dropFirst(AgentFacingTools.typedAnswerPrefix.count)).clipped(1000))
        }
        guard answer.hasPrefix("option-"), let index = Int(answer.dropFirst("option-".count)), options.indices.contains(index) else {
            return ToolResult(text: "no answer")
        }
        return ToolResult(text: options[index])
    }
}

/// Counts only: never titles or content, so any caller may read it.
public struct StatusSnapshot: Sendable, Equatable {
    public var appVersion = SidefolkVersion.current
    public var sessions = 0
    public var sessionsNeedingYou = 0
    public var jobsRunning = 0
    public var remindersPending = 0
    public var watchersActive = 0
    public var waiting = 0

    public init() {}

    public var json: JSONValue {
        [
            "app": .string(appVersion), "sessions": .number(Double(sessions)),
            "sessions_needing_you": .number(Double(sessionsNeedingYou)), "jobs_running": .number(Double(jobsRunning)),
            "reminders_pending": .number(Double(remindersPending)), "watchers_active": .number(Double(watchersActive)),
            "waiting": .number(Double(waiting)),
        ]
    }

    public init(json: JSONValue) {
        appVersion = json.string("app") ?? "?"
        sessions = json["sessions"]?.intValue ?? 0
        sessionsNeedingYou = json["sessions_needing_you"]?.intValue ?? 0
        jobsRunning = json["jobs_running"]?.intValue ?? 0
        remindersPending = json["reminders_pending"]?.intValue ?? 0
        watchersActive = json["watchers_active"]?.intValue ?? 0
        waiting = json["waiting"]?.intValue ?? 0
    }

    /// "2 sessions (1 needs you), 1 job running, 3 reminders, 1 watch, 0 waiting", in English: agents read
    /// it, and so does `sidefolk status` in Terminal.
    public var sentence: String {
        func n(_ count: Int, _ one: String, _ many: String) -> String { "\(count) \(count == 1 ? one : many)" }
        var parts = [n(sessions, "agent session", "agent sessions") + (sessionsNeedingYou > 0 ? " (\(sessionsNeedingYou) need you)" : "")]
        parts.append(n(jobsRunning, "job", "jobs") + " running")
        parts.append(n(remindersPending, "reminder", "reminders"))
        parts.append(n(watchersActive, "watch", "watches"))
        parts.append("\(waiting) waiting for you")
        return parts.joined(separator: ", ")
    }
}

public struct StatusReader: Sendable {
    let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    public func snapshot() async -> StatusSnapshot {
        var s = StatusSnapshot()
        let live = (try? await SessionStore(db).live()) ?? []
        s.sessions = live.count
        s.sessionsNeedingYou = live.filter { $0.state == .needsYou }.count
        s.jobsRunning = (try? await JobStore(db).running().count) ?? 0
        s.remindersPending = (try? await ReminderStore(db).pending().count) ?? 0
        s.watchersActive = (try? await WatcherStore(db).active().count) ?? 0
        s.waiting = ((try? await AttentionStore(db).open()) ?? []).filter { $0.level >= .attention }.count
        return s
    }
}

struct StatusTool: Tool {
    let reader: StatusReader

    var spec: ToolSpec {
        ToolSpec(name: "status", title: String(localized: "Sidefolk status"),
                 description: "How many agent sessions, jobs, reminders and watches Sidefolk is keeping track of (counts only).",
                 inputSchema: Schema.object([:]), risk: .low, capabilities: [], category: .system, mutates: false, external: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Read Sidefolk's status") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let s = await reader.snapshot()
        return ToolResult(text: "Sidefolk \(s.appVersion) is running: \(s.sentence).")
    }
}
