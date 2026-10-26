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
    /// The reasoning effort to ask for (D36); nil sends nothing. Backends send it only where the
    /// provider and model accept it (`EffortSupport`).
    public var effort: ReasoningEffort?
    public var maxSteps: Int
    public var deadline: Date

    public init(runId: String, threadId: String, system: String, messages: [ChatMessage], model: String,
                effort: ReasoningEffort? = nil, maxSteps: Int = 10, deadline: Date) {
        self.runId = runId
        self.threadId = threadId
        self.system = system
        self.messages = messages
        self.model = model
        self.effort = effort
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
    private let pause = Mutex(Pause())
    private let stop = Mutex<(requested: Bool, action: (@Sendable () -> Void)?)>((false, nil))

    /// Time spent waiting for the person's answer, which doesn't count against the run (D37).
    private struct Pause {
        var open = 0
        var since: Date?
        var total: TimeInterval = 0
    }

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

    /// When the run must end: `base` moved by every wait for the person's answer, or nil while a card
    /// is waiting (the deadline can't pass then). Time spent deciding, or away, isn't the run's time,
    /// so a run that waited ten minutes on a skipped step still has its own budget left (D37).
    public func deadline(from base: Date) -> Date? {
        pause.withLock { p in p.open > 0 ? nil : base.addingTimeInterval(p.total) }
    }

    /// The person didn't answer in time and their setting says to stop the task.
    public var stoppedUnanswered: Bool { stop.withLock { $0.requested } }

    /// What ends the run when `stoppedUnanswered` becomes true; the runtime cancels the backend with it.
    public func onStop(_ action: @escaping @Sendable () -> Void) {
        let now = stop.withLock { s -> Bool in
            s.action = action
            return s.requested
        }
        if now { action() }
    }

    private func beginWait() {
        let now = executor.clock.now
        pause.withLock { p in
            if p.open == 0 { p.since = now }
            p.open += 1
        }
    }

    private func endWait() {
        let now = executor.clock.now
        pause.withLock { p in
            p.open -= 1
            if p.open == 0, let since = p.since {
                p.total += max(0, now.timeIntervalSince(since))
                p.since = nil
            }
        }
    }

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
        // One call may wait twice (folder access, then the action); the pause covers both.
        let waited = Mutex(false)
        let outcome = await executor.execute(name: spec.name, input: input, caller: .agent(runId: runId), tainted: isTainted,
                                             mentions: mentions, onWaiting: { [self] _ in
            let first = waited.withLock { w in
                defer { w = true }
                return !w
            }
            if first { beginWait() }
            emit(.phase(.waitingForApproval))
        })
        if waited.withLock({ $0 }) { endWait() }
        if outcome.untrusted { tainted.withLock { $0 = true } }
        if case .unanswered(stop: true) = outcome.status {
            let action = stop.withLock { s -> (@Sendable () -> Void)? in
                s.requested = true
                return s.action
            }
            action?()
        }
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
