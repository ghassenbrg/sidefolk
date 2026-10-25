import Foundation

/// Which Sidefolk tools other AI agents (any MCP client, through `sidefolk mcp`) may see and use
/// (SECURITY.md T4). An agent working in a hostile repo must not be able to borrow Sidefolk's
/// folder grants, network or commands, so the list is by name and closed: files, clipboard, open,
/// web, command watchers, skills, settings and extensions never appear.
public enum ExternalToolPolicy {
    /// Exposed and run without asking when the tool itself is low risk.
    public static let direct: Set<String> = [
        "notes.save", "reminders.create", "reminders.list", "watch.create", "watch.list", "watch.stop",
        "notify.user", "ask.user", "status",
    ]
    /// Exposed, but reading the user's notes always asks first.
    public static let asking: Set<String> = ["notes.search", "notes.list"]
    /// Watchers an external agent may keep active at once (T4).
    public static let maxActiveWatchers = 10

    public static func isExposed(_ name: String) -> Bool { direct.contains(name) || asking.contains(name) }

    /// The spec an external agent sees: reading tools raised to at least medium, and command
    /// watchers removed from `watch.create`'s schema.
    public static func externalSpec(_ spec: ToolSpec) -> ToolSpec {
        var spec = spec
        if asking.contains(spec.name) { spec.risk = max(spec.risk, .medium) }
        if spec.name == "watch.create" { spec.inputSchema = withoutCommandKind(spec.inputSchema) }
        return spec
    }

    /// Why this external call is refused before it reaches Guard, if it is.
    static func refusal(_ name: String, input: JSONValue) -> String? {
        if name == "watch.create", let kind = input.string("kind")?.lowercased(), kind.contains("command") {
            return "Other agents can't create command watchers. Ask the user to set it up in Sidefolk."
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

    private static func withoutCommandKind(_ schema: JSONValue) -> JSONValue {
        guard case .object(var root) = schema, case .object(var props)? = root["properties"],
              case .object(var kind)? = props["kind"], case .array(let values)? = kind["enum"] else { return schema }
        kind["enum"] = .array(values.filter { !($0.stringValue ?? "").lowercased().contains("command") })
        props["kind"] = .object(kind)
        root["properties"] = .object(props)
        return .object(root)
    }
}

/// Runs external agents' tool calls through their own `ToolExecutor` (Guard, approvals, audit and
/// events are shared with the app) whose registry only ever holds the exposed tools, wrapped with
/// the external spec. Anything else simply does not exist for them.
public final class ExternalToolGateway: Sendable {
    private let source: ToolRegistry
    private let exposed = ToolRegistry()
    private let executor: ToolExecutor
    private let watchers: WatcherStore?

    public init(registry: ToolRegistry, permissions: PermissionStore, broker: ApprovalBroker, activity: ActivityStore,
                events: EventBus, watchers: WatcherStore? = nil, clock: any Clock = SystemClock()) {
        source = registry
        self.watchers = watchers
        executor = ToolExecutor(registry: exposed, permissions: permissions, broker: broker, activity: activity,
                                events: events, clock: clock)
    }

    /// Undo for actions external agents took (e.g. a saved note) lives with this executor.
    public var undo: UndoCenter { executor.undo }

    /// The tools an external agent sees, by their specs.
    public func specs() -> [ToolSpec] {
        source.all.filter { ExternalToolPolicy.isExposed($0.spec.name) }.map { ExternalToolPolicy.externalSpec($0.spec) }
    }

    public func call(_ name: String, input: JSONValue, client: String) async -> ToolOutcome {
        let caller = Caller.external(client: client)
        guard let base = source.tool(named: name), ExternalToolPolicy.isExposed(base.spec.name) else {
            Log.shared.info("bridge", "external tool refused", ["client": client, "tool": name.clipped(80)])
            let act = ToolActivity(id: Identifier.make(), tool: name, title: name, summary: "Not available", category: .system,
                                   caller: caller, error: "Not exposed")
            return ToolOutcome(activity: act, status: .failed(UserFacingError("Sidefolk doesn't offer a tool called \(name) to other agents.")))
        }
        let facade = ExternalFacade(base: base, spec: ExternalToolPolicy.externalSpec(base.spec), watchers: watchers)
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
struct ExternalFacade: Tool {
    let base: any Tool
    let spec: ToolSpec
    let watchers: WatcherStore?

    func summary(for input: JSONValue) -> String { base.summary(for: input) }
    func scope(for input: JSONValue) -> ToolScope { base.scope(for: input) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        if let why = ExternalToolPolicy.refusal(spec.name, input: input) { throw ToolError.unavailable(why) }
        if spec.name == "watch.create", let watchers {
            let mine = try await watchers.active().filter { $0.source.hasPrefix("external:") }
            if mine.count >= ExternalToolPolicy.maxActiveWatchers {
                throw ToolError.unavailable("Other agents already have \(mine.count) watches running. Stop one first.")
            }
        }
        return try await base.run(input, context: context)
    }
}
