import Foundation

/// Which of Sidefolk's tools an extension with `permissions.act` may ask to run, and how (D110, D127, SECURITY T44). Sidefolk's own are listed by
/// name, as `ExternalToolPolicy` lists them for other agents; what could widen an extension's own reach (other extensions' settings, skills, memory, Sidefolk's own
/// host tools) simply doesn't exist for it. Every other extension's tools and every MCP server's are reachable, the person's call on the founder's word (D127); those
/// that run outside a sandbox or can run anything are on a card every single time, never in a plan and never "Always".
public enum ExtensionActionPolicy {
    /// Reaching the person is all they do, so they keep their risk: the words are shown as the extension's.
    static let reachesThePerson: Set<String> = ["notify.user", "ask.user"]

    public static let builtIn: Set<String> = reachesThePerson.union([
        "agenda.today", "calendar.today", "calendar.create", "calendar.update", "calendar.delete",
        "notes.save", "notes.search", "notes.list", "notes.update", "notes.trash", "collections.list", "collections.create",
        "reminders.create", "reminders.list", "reminders.cancel", "reminders.complete", "reminders.snooze",
        "watch.create", "watch.list", "watch.pause", "watch.resume", "watch.stop", "watch.report",
        "web.fetch", "files.list", "files.read", "files.search", "files.mkdir", "files.move", "files.rename", "files.trash", "files.reveal",
        "clipboard.read", "clipboard.write", "open.url", "open.email", "open.app",
        "applenotes.list", "applenotes.read", "applenotes.copy", "applenotes.remove", "applereminders.list",
        "companion.play", "surfaces.open", "status", CompanionJobTool.name, AttentionSetTool.name, VoiceSayTool.name, AppearanceTool.name,
    ])

    /// Never without a card, whatever a plan says: what someone copied is theirs alone, and silent reads of it are surveillance.
    static let neverStanding: Set<String> = ["clipboard.read"]

    /// The only places a plan may leave for filling in at run time. Each holds words that stay inside Sidefolk and are shown as the
    /// extension's: a note's text, a reminder's title, a notice, a question, a line said aloud. A note search's words are the founder's exception:
    /// they choose what comes back (D127). Anything parsed as a time, anything that could pick a target or carry words off the Mac, is written out or gets a card each time (T44).
    static let fillable: [String: Set<String>] = [
        "notes.save": ["text"],
        // The founder's choice, knowing words from elsewhere then choose which notes come back (D127).
        "notes.search": ["query"],
        "voice.say": ["text"],
        "reminders.create": ["title"],
        "notify.user": ["title", "body"],
        "ask.user": ["question"],
    ]

    /// Whether `tool` is offered to the extension `id`: any other extension's or MCP server's, or one of Sidefolk's own on the list. Never its own: it has its program.
    static func offers(_ tool: any Tool, to id: String) -> Bool {
        if let ext = tool as? ExtensionTool { return ext.extensionId != id }
        return builtIn.contains(tool.spec.name)
    }

    /// Whether a card is all there can be: it runs outside any sandbox, or can run anything. It stays a card every time (D127).
    static func alwaysAsks(_ tool: any Tool) -> Bool {
        if !tool.spec.capabilities.isDisjoint(with: [.shell]) { return true }
        if let ext = tool as? ExtensionTool { return !ext.sandboxed }
        return false
    }

    /// Whether Sidefolk itself says a tool changes nothing: its own word for its own tools, and its signed extensions'. Anyone else's manifest
    /// saying so isn't taken (D71), because a practice run or a retry rests on it.
    static func readsOnly(_ tool: any Tool) -> Bool {
        let base = (tool as? ExternalFacade)?.base ?? tool
        // Telling the person something isn't reading, however little it changes.
        guard !base.spec.mutates, !reachesThePerson.contains(base.spec.name) else { return false }
        if let ext = base as? ExtensionTool { return ext.firstParty }
        return true
    }

    /// The tool as this caller gets it: at least medium, so it asks, unless a plan the person read covers the call; high, so it always asks, where a card is all there can be.
    static func spec(_ tool: any Tool) -> ToolSpec {
        guard !reachesThePerson.contains(tool.spec.name) else { return tool.spec }
        var spec = tool.spec
        spec.risk = alwaysAsks(tool) ? .high : max(spec.risk, .medium)
        return spec
    }
}

/// Guard's answer for a call that isn't being made: what the person would see, without running anything.
public struct ToolCheck: Sendable {
    public enum Decision: String, Sendable { case allow, ask, deny }

    public var decision: Decision
    public var why: String?
    public var summary: String
    public var risk: Risk
    public var mutates: Bool
    /// The folder that would let it through, when all that's in the way is that it isn't shared.
    public var share: String?

    public init(decision: Decision, why: String? = nil, summary: String, risk: Risk, mutates: Bool) {
        self.decision = decision
        self.why = why
        self.summary = summary
        self.risk = risk
        self.mutates = mutates
    }
}

/// Runs what extensions with `permissions.act` ask for through a `ToolExecutor` of their own, like other agents' (Guard, approvals,
/// audit and events are shared with the app), whose registry holds only the tools they may reach, wrapped with their risk. Nothing
/// here decides anything: it only says who is asking.
public final class ExtensionActionGateway: Sendable {
    private let source: ToolRegistry
    private let exposed = ToolRegistry()
    private let executor: ToolExecutor

    public init(registry: ToolRegistry, permissions: PermissionStore, broker: ApprovalBroker, activity: ActivityStore,
                events: EventBus, clock: any Clock = SystemClock()) {
        source = registry
        executor = ToolExecutor(registry: exposed, permissions: permissions, broker: broker, activity: activity, events: events, clock: clock)
    }

    /// Undo for what extensions did (a saved note) lives with this executor, as other agents' does.
    public var undo: UndoCenter { executor.undo }

    /// The tool as `id` may reach it; nil for one it can't.
    func tool(named name: String, for id: String) -> (any Tool)? {
        guard let base = source.tool(named: name), ExtensionActionPolicy.offers(base, to: id) else { return nil }
        return ExternalFacade(base: base, spec: ExtensionActionPolicy.spec(base))
    }

    /// What `id` may ask for, with the words each tool's author may show a model (D24): an extension gets the same specs.
    func tools(for id: String) -> [any Tool] {
        source.all.filter { ExtensionActionPolicy.offers($0, to: id) }.map { ExternalFacade(base: $0, spec: ExtensionActionPolicy.spec($0)) }
    }

    /// - Parameters:
    ///   - standing: the call fits a plan the person read and allowed.
    ///   - written: the plan's step as written, when it filled words in: what History keeps.
    func call(_ name: String, input: JSONValue, extensionId id: String, asker: ApprovalRequest.Asker, standing: Bool, written: JSONValue? = nil, timeout: TimeInterval?) async -> ToolOutcome {
        guard let facade = tool(named: name, for: id) else {
            let caller = Caller.extension(id: id)
            let act = ToolActivity(id: Identifier.make(), tool: name, title: name, summary: "Not available", category: .system, caller: caller, error: "Not offered")
            return ToolOutcome(activity: act, status: .denied("Sidefolk doesn't offer that tool to extensions."))
        }
        exposed.register(facade)
        let limit = timeout ?? facade.spec.timeout ?? (facade.spec.name == "ask.user" ? AgentFacingTools.maxAskSeconds + 15 : 90)
        // Evaluating medium calls as tainted makes Guard ask every time and never offer "Always allow" (T1, as other agents): an
        // extension's calls can carry whatever it read.
        return await executor.execute(name: facade.spec.name, input: input, caller: .extension(id: id), tainted: facade.spec.risk >= .medium,
                                      timeout: limit, standing: standing, written: written, asker: asker)
    }

    func check(_ name: String, input: JSONValue, extensionId id: String, standing: Bool) async -> ToolCheck? {
        guard let facade = tool(named: name, for: id) else { return nil }
        exposed.register(facade)
        return await executor.check(name: facade.spec.name, input: input, caller: .extension(id: id), tainted: facade.spec.risk >= .medium, standing: standing)
    }

    /// The card that lets a plan stand (`extensions.plan`). Never tainted: it is the person reading what will happen, in full.
    func askForPlan(_ tool: ExtensionPlanTool, input: JSONValue, extensionId id: String, asker: ApprovalRequest.Asker) async -> ToolOutcome {
        exposed.register(tool)
        return await executor.execute(name: tool.spec.name, input: input, caller: .extension(id: id), timeout: 10, asker: asker)
    }
}
