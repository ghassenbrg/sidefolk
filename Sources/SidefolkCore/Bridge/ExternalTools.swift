import Foundation

/// Which Sidefolk tools other AI agents (any MCP client, through `sidefolk mcp`) may see and use
/// (SECURITY.md T4). An agent working in a hostile repo must not be able to borrow Sidefolk's
/// folder grants, network or commands, so the list is by name and closed: files, clipboard, open,
/// web, command watchers, skills, settings and extensions never appear. Within it, the person chooses
/// in Settings › Privacy › Other agents what each group may do (`AgentAccess`).
public enum ExternalToolPolicy {
    /// Always offered and run without asking: they reach the user only through Sidefolk's own bubbles,
    /// and `status` only counts.
    public static let always: Set<String> = ["notify.user", "ask.user", "status"]
    /// Adding to what the user has: `watch.list` shows an agent only its own watchers, `reminders.cancel`
    /// reaches only its own reminders, `watch.report` reads only this Mac's load.
    public static let saving: Set<String> = [
        "notes.save", "reminders.create", "reminders.cancel", "watch.create", "watch.report", "watch.list", "watch.stop",
    ]
    /// Reading the user's data (notes, reminders, today's plan).
    public static let reading: Set<String> = ["notes.search", "notes.list", "reminders.list", "agenda.today"]
    /// Changing the user's notes, or moving them to the Trash, where they stay restorable for 30 days.
    /// Never deleting for good: only the user empties the Trash.
    public static let changing: Set<String> = ["notes.update", "notes.trash"]

    public static var all: Set<String> { always.union(saving).union(reading).union(changing) }

    /// What `access` lets other agents do with the tool called `name`; nil for a tool they never get.
    public static func permission(_ name: String, access: AgentAccess) -> AgentPermission? {
        if always.contains(name) { return .allow }
        if saving.contains(name) { return access.save }
        if reading.contains(name) { return access.read }
        if changing.contains(name) { return access.change }
        return nil
    }

    public static func isExposed(_ name: String, access: AgentAccess = AgentAccess()) -> Bool {
        guard let p = permission(name, access: access) else { return false }
        return p != .off
    }

    /// Why this external call is refused before it reaches Guard, if it is. The external schemas
    /// already leave these out; this holds even if a schema check were ever skipped.
    static func refusal(_ name: String, input: JSONValue) -> String? {
        if name == "watch.create", let kind = input.string("kind")?.lowercased(), kind.contains("command") {
            return "Other agents can't create command watchers. Ask the user to set it up in Sidefolk."
        }
        // A web value would let an agent read pages through Sidefolk's network, and the weather reaches a
        // server too; this Mac's own load reaches nothing (T4).
        if name == "watch.report", input.string("source") != "metric" {
            return "Other agents can show only this Mac's cpu, memory, battery, disk or network. Ask the user to set up anything else in Sidefolk."
        }
        return nil
    }

    /// Notes saved by an agent carry a visible tag naming it (the tool records the source too).
    static func adjustedInput(_ name: String, input: JSONValue, schema: JSONValue, client: String) -> JSONValue {
        guard name == "notes.save", case .object(var fields) = input,
              let type = schema["properties"]?["tags"]?["type"]?.stringValue else { return input }
        let tag = "from-" + slug(client)
        switch (type, fields["tags"]) {
        case ("array", .array(let tags)?):
            if !tags.contains(.string(tag)) { fields["tags"] = .array(tags + [.string(tag)]) }
        case ("array", _):
            fields["tags"] = [.string(tag)]
        case ("string", .string(let tags)?):
            if !tags.split(separator: " ").contains(Substring(tag)) { fields["tags"] = .string((tags + " " + tag).trimmingCharacters(in: .whitespaces)) }
        case ("string", _):
            fields["tags"] = .string(tag)
        default:
            return input
        }
        return .object(fields)
    }

    /// "Claude Code" → "claude-code".
    static func slug(_ client: String) -> String {
        let lowered = client.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(lowered).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "agent" : String(collapsed.prefix(32))
    }
}

/// Runs external agents' tool calls through their own `ToolExecutor` (Guard, approvals, audit and
/// events are shared with the app) whose registry only ever holds the exposed tools, wrapped with
/// the external spec. Anything else simply does not exist for them.
public final class ExternalToolGateway: Sendable {
    private let source: ToolRegistry
    private let exposed = ToolRegistry()
    private let executor: ToolExecutor

    private let access: @Sendable () -> AgentAccess

    public init(registry: ToolRegistry, permissions: PermissionStore, broker: ApprovalBroker, activity: ActivityStore,
                events: EventBus, clock: any Clock = SystemClock(), access: @escaping @Sendable () -> AgentAccess = { AgentAccess() }) {
        source = registry
        self.access = access
        executor = ToolExecutor(registry: exposed, permissions: permissions, broker: broker, activity: activity,
                                events: events, clock: clock)
    }

    /// Undo for actions external agents took (e.g. a saved note) lives with this executor.
    public var undo: UndoCenter { executor.undo }

    /// The tools an external agent sees, by their specs.
    public func specs() -> [ToolSpec] {
        let access = access()
        return source.all.filter { ExternalToolPolicy.isExposed($0.spec.name, access: access) }
            .map { ExternalToolPolicy.externalSpec($0.spec, access: access) }
    }

    public func call(_ name: String, input: JSONValue, client: String) async -> ToolOutcome {
        let caller = Caller.external(client: client)
        let access = access()
        if let base = source.tool(named: name), ExternalToolPolicy.permission(base.spec.name, access: access) == .off {
            Log.shared.info("bridge", "external tool turned off", ["client": client, "tool": name.clipped(80)])
            let act = ToolActivity(id: Identifier.make(), tool: name, title: base.spec.title, summary: "Turned off", category: .system,
                                   caller: caller, error: "Turned off in Settings")
            return ToolOutcome(activity: act, status: .failed(UserFacingError(
                "The user turned this off for other agents in Sidefolk's Settings › Privacy › Other agents. Ask them to do it in Sidefolk instead.")))
        }
        guard let base = source.tool(named: name), ExternalToolPolicy.isExposed(base.spec.name, access: access) else {
            Log.shared.info("bridge", "external tool refused", ["client": client, "tool": name.clipped(80)])
            let act = ToolActivity(id: Identifier.make(), tool: name, title: name, summary: "Not available", category: .system,
                                   caller: caller, error: "Not exposed")
            return ToolOutcome(activity: act, status: .failed(UserFacingError("Sidefolk doesn't offer a tool called \(name) to other agents.")))
        }
        let facade = ExternalFacade(base: base, spec: ExternalToolPolicy.externalSpec(base.spec, access: access))
        exposed.register(facade)
        let input = ExternalToolPolicy.adjustedInput(base.spec.name, input: input, schema: facade.spec.inputSchema, client: client)
        // Evaluating medium calls as tainted makes Guard ask every time and never offer
        // "Always allow" to an external caller (T1); low-risk calls keep running directly (T4).
        return await executor.execute(name: facade.spec.name, input: input, caller: caller,
                                      tainted: facade.spec.risk >= .medium,
                                      timeout: base.spec.name == "ask.user" ? AgentFacingTools.maxAskSeconds + 15 : 90,
                                      approvalTimeout: 120)
    }
}

/// An exposed tool as external agents get it: the external spec, refusals checked at run time
/// (after Guard, so they are audited), otherwise the real tool.
/// Watcher quotas live in `WatcherEngine.add`, counted in the same actor step as the insert.
struct ExternalFacade: Tool {
    let base: any Tool
    let spec: ToolSpec

    func summary(for input: JSONValue) -> String { base.summary(for: input) }
    func scope(for input: JSONValue) -> ToolScope { base.scope(for: input) }
    func refusal(for input: JSONValue, context: ToolContext) -> String? { base.refusal(for: input, context: context) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        if let why = ExternalToolPolicy.refusal(spec.name, input: input) { throw ToolError.unavailable(why) }
        return try await base.run(input, context: context)
    }
}
