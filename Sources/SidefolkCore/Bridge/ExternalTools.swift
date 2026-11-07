import Foundation

/// Which Sidefolk tools other AI agents (any MCP client, through `sidefolk mcp`) may see and use
/// (SECURITY.md T4). An agent working in a hostile repo must not be able to borrow Sidefolk's
/// folder grants, network or commands, so the list is by name and closed: files, clipboard, open,
/// web, command watchers, skills, settings and extensions never appear. Within it, the person chooses
/// in Settings › Privacy › Other agents what each group may do (`AgentAccess`).
public enum ExternalToolPolicy {
    /// Always offered and run without asking: they reach the user only through Sidefolk's own bubbles,
    /// and `status` only counts. `plans.approve_with_code` approves nothing without the code from the person's own card (D239).
    public static let always: Set<String> = ["notify.user", "ask.user", "status", PlanCodeTool.name]
    /// Always offered and always asked, whatever the settings say: how agents get past their shared room (D116), and
    /// making or changing a collection, since a name of theirs beside the person's own is theirs only on a yes (T3, T4, D160).
    public static let alwaysAsks: Set<String> = ["watch.more_room", "notes.collection", "collections.create"]
    /// Adding to what the user has: `watch.list` shows an agent only its own watchers, the `reminders.*` that change
    /// reach its own reminders freely and anyone else's on a card every time (`ReachesOthersRecords`, D160), `watch.report` reads only this Mac's load, and the rest move only its own.
    public static let saving: Set<String> = [
        "notes.save", "reminders.create", "reminders.update", "reminders.snooze", "reminders.complete", "reminders.cancel", "watch.create", "watch.report", "watch.list", "watch.stop",
        "watch.pause", "watch.resume", "watch.update", "watch.reorder",
    ]
    /// Reading the user's data (notes, reminders, today's plan).
    public static let reading: Set<String> = ["notes.search", "notes.list", "notes.get", "collections.list", "reminders.list", "agenda.today"]
    /// Changing the user's notes, or moving them to the Trash, where they stay restorable for 30 days.
    /// Never deleting for good: only the user empties the Trash.
    public static let changing: Set<String> = ["notes.update", "notes.trash", "notes.restore", "notes.arrange"]

    public static var all: Set<String> { always.union(alwaysAsks).union(saving).union(reading).union(changing) }

    /// What `access` lets other agents do with the tool called `name`; nil for a tool they never get.
    public static func permission(_ name: String, access: AgentAccess) -> AgentPermission? {
        if always.contains(name) { return .allow }
        if alwaysAsks.contains(name) { return .ask }
        if saving.contains(name) { return access.save }
        if reading.contains(name) { return access.read }
        if changing.contains(name) { return access.change }
        return nil
    }

    /// `permission` for a registered tool: the list above, or an extension's tool that opted in (`tools.<name>.agents`, D112), which only
    /// the person's switch for them decides, and which never runs without a card.
    static func permission(_ tool: any Tool, access: AgentAccess) -> AgentPermission? {
        if let ext = tool as? ExtensionTool, ext.forAgents { return access.extensions == .off ? .off : .ask }
        return permission(tool.spec.name, access: access)
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
        // The tool's own refusal speaks for the companion ("ask me directly"); here the reader is another agent.
        if name == "watch.create", let host = localHost(input) {
            return "“\(host)” is on this Mac or the local network, which other agents can't watch. Ask the user to set it up in Sidefolk."
        }
        if name == "watch.report", input.string("source") != "metric" {
            return "Other agents can show only this Mac's cpu, memory, battery, disk or network. Ask the user to set up anything else in Sidefolk."
        }
        return nil
    }

    /// The local host a web watch would reach, if it would.
    private static func localHost(_ input: JSONValue) -> String? {
        guard [WatchKind.urlChange, WatchKind.siteStatus].contains(input.string("kind") ?? ""), let target = input.string("target") else { return nil }
        let typed = target.contains("://") ? target : WebTarget.defaultScheme(for: target) + target
        do {
            try URLPolicy.checkHost(try URLPolicy.parseWebURL(typed))
        } catch URLPolicy.Violation.privateDestination(let host) {
            return host
        } catch {}
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
    fileprivate let exposed = ToolRegistry()
    fileprivate let executor: ToolExecutor

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
        return source.all.compactMap { tool in
            guard let permission = ExternalToolPolicy.permission(tool, access: access), permission != .off else { return nil }
            return facadeSpec(tool, access: access)
        }
    }

    /// The spec an agent gets. An extension's opted-in tool asks every time, whatever its manifest says (D112).
    private func facadeSpec(_ tool: any Tool, access: AgentAccess) -> ToolSpec {
        var spec = ExternalToolPolicy.externalSpec(tool.spec, access: access)
        if (tool as? ExtensionTool)?.forAgents == true { spec.risk = max(spec.risk, .medium) }
        return spec
    }

    public func call(_ name: String, input: JSONValue, client: String) async -> ToolOutcome {
        let caller = Caller.external(client: client)
        let access = access()
        func turnedOff(_ base: any Tool) -> ToolOutcome {
            Log.shared.info("bridge", "external tool turned off", ["client": client, "tool": name.clipped(80)])
            let act = ToolActivity(id: Identifier.make(), tool: name, title: base.spec.title, summary: "Turned off", category: .system,
                                   caller: caller, error: "Turned off in Settings")
            return ToolOutcome(activity: act, status: .failed(UserFacingError(
                "The user turned this off for other agents in Sidefolk's Settings › Trust › What other agents may do. Ask them to do it in Sidefolk instead.")))
        }
        if let base = source.tool(named: name), ExternalToolPolicy.permission(base, access: access) == .off {
            return turnedOff(base)
        }
        guard let base = source.tool(named: name), let permission = ExternalToolPolicy.permission(base, access: access), permission != .off else {
            Log.shared.info("bridge", "external tool refused", ["client": client, "tool": name.clipped(80)])
            let act = ToolActivity(id: Identifier.make(), tool: name, title: name, summary: "Not available", category: .system,
                                   caller: caller, error: "Not exposed")
            return ToolOutcome(activity: act, status: .failed(UserFacingError("Sidefolk doesn't offer a tool called \(name) to other agents.")))
        }
        // What isn't this agent's to touch without asking: a card each time, saying exactly what would happen (D160).
        if let others = base as? ReachesOthersRecords {
            do {
                if let asked = try await others.onACard(input, caller: caller) {
                    guard access.change != .off else { return turnedOff(base) }
                    return await askFirst(base, words: asked.words, input: asked.input, caller: caller, access: access)
                }
            } catch {
                let act = ToolActivity(id: Identifier.make(), tool: base.spec.name, title: base.spec.title, summary: base.summary(for: input),
                                       category: base.spec.category, caller: caller, error: "\(error)")
                return ToolOutcome(activity: act, status: .failed(ToolExecutor.userFacing(error, tool: base.spec)))
            }
        }
        let facade = ExternalFacade(base: base, spec: facadeSpec(base, access: access))
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

extension ExternalToolGateway {
    /// One call on someone else's record, on a card every time. Under a key of its own, so an agent's call on its own
    /// record, by the same name at the same moment, can't stand in for it and run without the card.
    private func askFirst(_ base: any Tool, words: String, input: JSONValue, caller: Caller, access: AgentAccess) async -> ToolOutcome {
        var spec = facadeSpec(base, access: access)
        spec.risk = max(spec.risk, .medium)
        let key = "\(spec.name)#\(Identifier.make())"
        exposed.register(ExternalFacade(base: base, spec: spec, onCard: words), key: key)
        defer { exposed.remove(key: key) }
        return await executor.execute(name: key, input: input, caller: caller, tainted: true, timeout: 90, approvalTimeout: 120)
    }
}

/// A tool whose record may belong to someone else than the agent calling it.
protocol ReachesOthersRecords {
    /// When this call would touch a record not the caller's own: what the card says, exactly, and the input that then runs,
    /// settled now, so what happens is what it said. Nil when it wouldn't, or there's nothing there, which the tool then says
    /// as ever. Throws what can't be done, so no card asks for it.
    func onACard(_ input: JSONValue, caller: Caller) async throws -> (words: String, input: JSONValue)?
}

/// An exposed tool as external agents get it: the external spec, refusals checked at run time
/// (after Guard, so they are audited), otherwise the real tool.
/// Watcher quotas live in `WatcherEngine.add`, counted in the same actor step as the insert.
struct ExternalFacade: Tool {
    let base: any Tool
    let spec: ToolSpec
    /// The card's words for a record not the caller's own; nil for everything else.
    var onCard: String?
    /// A refusal decided before the call: the plan's limit was reached (D189).
    var refused: String?
    /// The call fits a plan nobody read (Full access answered it, or Auto let the line through): History says so (D187, D188).
    var unread = false

    func summary(for input: JSONValue) -> String { onCard ?? base.summary(for: input) }
    func scope(for input: JSONValue) -> ToolScope { base.scope(for: input) }
    func refusal(for input: JSONValue, context: ToolContext) -> String? { refused ?? base.refusal(for: input, context: context) }
    /// What the real tool says of its own rows: every external call goes through here, and a tool that writes its own row (the plan code's, which keeps the code out of History)
    /// would otherwise get a second one with its input.
    func leavesNoRow(for input: JSONValue, caller: Caller) -> Bool { base.leavesNoRow(for: input, caller: caller) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        if let why = ExternalToolPolicy.refusal(spec.name, input: input) { throw ToolError.unavailable(why) }
        var context = context
        // A card from "Ask each time" asks about the group, not this: it doesn't open what's otherwise closed.
        context.personWasAsked = context.personWasAsked && (onCard != nil || ExternalToolPolicy.alwaysAsks.contains(spec.name))
        return try await base.run(input, context: context)
    }
}
