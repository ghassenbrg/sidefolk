import Foundation
import Synchronization

public struct ChatMessage: Sendable, Hashable, Codable {
    public enum Role: String, Sendable, Codable { case user, assistant }
    public var role: Role
    public var text: String
    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// One request for a brain: the system prompt (persona, rules, context), the recent conversation
/// ending with the user's message, and budgets.
public struct BrainTask: Sendable {
    public var runId: String
    public var threadId: String
    public var system: String
    public var messages: [ChatMessage]
    public var model: String
    public var maxSteps: Int
    public var deadline: Date

    public init(runId: String, threadId: String, system: String, messages: [ChatMessage], model: String,
                maxSteps: Int = 10, deadline: Date) {
        self.runId = runId
        self.threadId = threadId
        self.system = system
        self.messages = messages
        self.model = model
        self.maxSteps = maxSteps
        self.deadline = deadline
    }
}

/// The tools a brain may call during one run. Every call goes through `ToolExecutor` as
/// `Caller.agent(runId)`, and the toolbox tracks taint: once any result was untrusted, later calls
/// are evaluated as tainted.
public final class BrainToolbox: Sendable {
    public let runId: String
    public let specs: [ToolSpec]
    /// The links the user typed in the request this run answers (SECURITY T1, T2).
    public let mentions: UserMentions
    private let executor: ToolExecutor
    private let tainted = Mutex(false)
    private let closed = Mutex(false)
    private let emit: @Sendable (AgentEvent) -> Void
    private let results = Mutex<[ToolOutcome]>([])

    public init(runId: String, specs: [ToolSpec], executor: ToolExecutor, startTainted: Bool = false,
                mentions: UserMentions = .none, emit: @escaping @Sendable (AgentEvent) -> Void) {
        self.runId = runId
        self.specs = specs
        self.mentions = mentions
        self.executor = executor
        self.emit = emit
        tainted.withLock { $0 = startTainted }
    }

    public var isTainted: Bool { tainted.withLock { $0 } }
    public var outcomes: [ToolOutcome] { results.withLock { $0 } }

    /// The run ended: later calls are refused and cards still waiting are denied, so an Allow
    /// clicked afterwards never acts for a run that is gone.
    public func close() async {
        closed.withLock { $0 = true }
        await executor.cancelApprovals(runId: runId)
    }

    /// Runs a tool by its spec name or model-facing name.
    public func call(_ name: String, input: JSONValue) async -> ToolOutcome {
        let allowed = specs.contains { $0.name == name || $0.modelName == name } && !closed.withLock { $0 }
        guard allowed else {
            let act = ToolActivity(id: Identifier.make(), tool: name, title: name, summary: String(localized: "Not available"), category: .system,
                                   caller: .agent(runId: runId), error: "Tool not available")
            return ToolOutcome(activity: act, status: .failed(UserFacingError("The tool \(name) isn't available here.")))
        }
        let spec = specs.first { $0.name == name || $0.modelName == name }!
        emit(.phase(.working(spec.category)))
        let emit = self.emit
        let outcome = await executor.execute(name: spec.name, input: input, caller: .agent(runId: runId), tainted: isTainted,
                                             mentions: mentions, onWaiting: { _ in emit(.phase(.waitingForApproval)) })
        if outcome.untrusted { tainted.withLock { $0 = true } }
        results.withLock { $0.append(outcome) }
        emit(.toolFinished(outcome.activity, ok: outcome.isOK))
        emit(.phase(.thinking))
        return outcome
    }
}

/// A reasoning engine. `LoopBackend` drives API models turn by turn; `ClaudeCodeBackend` lets the
/// Claude Code CLI run the loop and receives its tool calls through the local bridge.
public protocol BrainBackend: Sendable {
    var providerName: String { get }
    func run(_ task: BrainTask, toolbox: BrainToolbox, emit: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentReply
    /// A cheap call that proves the provider is reachable and configured.
    func check() async -> Result<String, UserFacingError>
}

/// Lets the local API attribute incoming tool calls to a running brain (Claude Code backend).
public protocol RunTokenRegistry: Sendable {
    func register(token: String, toolbox: BrainToolbox)
    func unregister(token: String)
}
