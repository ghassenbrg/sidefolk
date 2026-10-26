import Foundation
import Synchronization

public struct ToolOutcome: Sendable {
    public enum Status: Sendable {
        case ok(ToolResult)
        case denied(String)
        case failed(UserFacingError)
    }

    public var activity: ToolActivity
    public var status: Status

    public var isOK: Bool { if case .ok(let r) = status { return !r.isError } else { return false } }
    public var untrusted: Bool { if case .ok(let r) = status { return r.untrusted } else { return false } }

    /// What the model is told about this call.
    public var modelText: String {
        switch status {
        case .ok(let r):
            let body = r.untrusted ? UntrustedText.wrap(r.text, source: activity.tool) : r.text
            return r.isError ? "The tool reported a problem; it may or may not have changed something:\n\(body)" : body
        case .denied(let why): return "Not done: \(why) Do not retry this action unless the user asks again."
        case .failed(let e): return "Failed: \(e.message)\(e.changedNothing ? " Nothing was changed." : "")"
        }
    }
}

/// Recent undoable actions, kept for 15 minutes. An older one is neither offered nor performed:
/// what it would put back may have changed since.
public actor UndoCenter {
    public static let lifetime: TimeInterval = 900
    private var entries: [String: (UndoAction, Date)] = [:]
    public init() {}

    public func register(_ action: UndoAction, id: String, now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.1) < Self.lifetime }
        entries[id] = (action, now)
    }

    public func has(_ id: String, now: Date = Date()) -> Bool {
        guard let (_, at) = entries[id] else { return false }
        return now.timeIntervalSince(at) < Self.lifetime
    }

    public func undo(_ id: String, now: Date = Date()) async throws -> String? {
        guard let (action, at) = entries.removeValue(forKey: id), now.timeIntervalSince(at) < Self.lifetime else { return nil }
        try await action.perform()
        return action.label
    }
}

/// The only path by which anything runs a tool: Guard, approval, execution, audit, events.
public final class ToolExecutor: Sendable {
    public let registry: ToolRegistry
    public let undo = UndoCenter()
    private let permissions: PermissionStore
    private let engine = PermissionEngine()
    private let broker: ApprovalBroker
    private let activity: ActivityStore
    private let events: EventBus
    private let clock: any Clock

    public init(registry: ToolRegistry, permissions: PermissionStore, broker: ApprovalBroker, activity: ActivityStore,
                events: EventBus, clock: any Clock = SystemClock()) {
        self.registry = registry
        self.permissions = permissions
        self.broker = broker
        self.activity = activity
        self.events = events
        self.clock = clock
    }

    /// How long any approval card waits before it counts as "no" (SECURITY T1).
    public static let approvalTimeout: TimeInterval = 120

    /// - Parameters:
    ///   - tainted: untrusted content is in play for this caller's current task.
    ///   - mentions: the links the user typed in the request this call serves; links anywhere else
    ///     are model-built and Guard asks before they are fetched or opened.
    ///   - approvalTimeout: capped at `ToolExecutor.approvalTimeout`.
    ///   - onWaiting: called when the call is parked waiting for the user's approval.
    public func execute(
        name: String, input: JSONValue, caller: Caller, tainted: Bool = false, mentions: UserMentions? = nil,
        timeout: TimeInterval = 90, approvalTimeout: TimeInterval = ToolExecutor.approvalTimeout,
        onWaiting: (@Sendable (ApprovalRequest) -> Void)? = nil
    ) async -> ToolOutcome {
        let callId = Identifier.make()
        guard let tool = registry.tool(named: name) else {
            let a = ToolActivity(id: callId, tool: name, title: name, summary: "Unknown tool", category: .system, caller: caller,
                                 error: "No such tool")
            return ToolOutcome(activity: a, status: .failed(UserFacingError("I don't have a tool called \(name).")))
        }
        let spec = tool.spec
        let input = input.objectValue == nil ? .object([:]) : input
        let summary = tool.summary(for: input).clipped(240)
        var act = ToolActivity(id: callId, tool: spec.name, title: spec.title, summary: summary, category: spec.category, caller: caller,
                               mutates: spec.mutates)

        if let missing = Self.missingRequired(spec.inputSchema, input) {
            act.error = "Missing \(missing)"
            return ToolOutcome(activity: act, status: .failed(UserFacingError("The request was missing “\(missing)”.")))
        }
        if let problem = InputSchema.problem(spec.inputSchema, input, unknownKeys: caller == .user) {
            act.error = "Invalid input"
            return ToolOutcome(activity: act, status: .failed(UserFacingError("That request didn't fit the tool: \(problem)",
                                                                              detail: "schema: \(problem)")))
        }

        if let why = tool.refusal(for: input, context: ToolContext(caller: caller, now: clock.now, tainted: tainted)) {
            await log(spec, act, caller: caller, input: input, decision: .blocked, outcome: nil, error: why)
            act.error = why
            return ToolOutcome(activity: act, status: .denied(why))
        }

        let scope = tool.scope(for: input)
        var decisionTag: ActivityEntry.Decision = .auto
        var extraFolders: [GrantedFolder] = []

        // Evaluate, possibly twice: once for folder access, once for the action itself.
        for _ in 0..<3 {
            let policy = (try? await permissions.policy()) ?? GuardPolicy()
            let grants = (try? await permissions.grants()) ?? []
            let folders = ((try? await permissions.folders()) ?? []) + extraFolders
            let decision = engine.evaluate(spec: spec, input: input, summary: summary, scope: scope, caller: caller,
                                           tainted: tainted, policy: policy, grants: grants, folders: folders, mentions: mentions)
            switch decision {
            case .allow(let tag):
                if tag == .always, let g = PermissionEngine.matchingGrant(spec: spec, scope: scope, caller: caller, grants: grants) {
                    try? await permissions.touchGrant(id: g.id)
                }
                if decisionTag == .auto { decisionTag = tag }
                return await run(tool, input: input, caller: caller, tainted: tainted, activity: act, decision: decisionTag, timeout: timeout)
            case .deny(let why):
                await log(spec, act, caller: caller, input: input, decision: .blocked, outcome: nil, error: why)
                act.error = why
                return ToolOutcome(activity: act, status: .denied(why))
            case .ask(let request):
                onWaiting?(request)
                guard let answer = await broker.requestIfRoom(request, timeout: min(approvalTimeout, Self.approvalTimeout)) else {
                    let why = "Another agent's request is already waiting for the user's answer. Try again after it is answered."
                    await log(spec, act, caller: caller, input: input, decision: .denied, outcome: nil, error: why)
                    act.error = why
                    return ToolOutcome(activity: act, status: .denied(why))
                }
                // An answer that arrives after the caller gave up (its run ended) never acts for it.
                guard answer.allowed, !Task.isCancelled else {
                    let why = answer == .expired ? "The request waited too long for your answer."
                        : answer.allowed ? "The request was withdrawn before it ran." : "You said no."
                    await log(spec, act, caller: caller, input: input, decision: .denied, outcome: nil, error: why)
                    act.error = why
                    return ToolOutcome(activity: act, status: .denied(why))
                }
                decisionTag = answer == .allowAlways ? .always : .allowed
                if case .folderAccess(let folder, let write) = request.details {
                    let access: GrantedFolder.Access = write ? .readwrite : .read
                    if answer == .allowAlways {
                        try? await permissions.grantFolder(folder, access: access)
                        events.changed(.permissions)
                    } else {
                        extraFolders.append(GrantedFolder(path: FolderAccess.canonical(folder) ?? folder, access: access))
                    }
                    continue
                }
                if answer == .allowAlways {
                    try? await permissions.addGrant(Grant(tool: spec.name, scope: PermissionEngine.grantScope(for: scope), callerKind: caller.kind))
                    events.changed(.permissions)
                }
                return await run(tool, input: input, caller: caller, tainted: tainted, activity: act, decision: decisionTag, timeout: timeout)
            }
        }
        act.error = "Permission loop"
        return ToolOutcome(activity: act, status: .denied("Sidefolk couldn't settle the permissions for this action."))
    }

    /// Denies the cards an agent run is still waiting on; call it when the run ends.
    public func cancelApprovals(runId: String) async {
        await broker.cancel(runId: runId)
    }

    private func run(_ tool: any Tool, input: JSONValue, caller: Caller, tainted: Bool, activity act: ToolActivity,
                     decision: ActivityEntry.Decision, timeout: TimeInterval) async -> ToolOutcome {
        var act = act
        events.publish(.toolStarted(act))
        let context = ToolContext(caller: caller, now: clock.now, tainted: tainted)
        do {
            let result = try await withTimeout(timeout) { try await tool.run(input, context: context) }
            act.card = result.card
            if let undo = result.undo {
                await self.undo.register(undo, id: act.id)
                act.undoAvailable = true
            }
            if result.isError {
                act.error = "\(tool.spec.title) reported a problem"
                await log(tool.spec, act, caller: caller, input: input, decision: .failed, outcome: nil, error: result.text.clipped(300))
            } else {
                await log(tool.spec, act, caller: caller, input: input, decision: decision, outcome: result.card?.title ?? result.text.clipped(160), error: nil)
            }
            events.publish(.toolFinished(act, ok: !result.isError))
            return ToolOutcome(activity: act, status: .ok(result))
        } catch {
            let ufe = Self.userFacing(error, tool: tool.spec)
            act.error = ufe.message
            await log(tool.spec, act, caller: caller, input: input, decision: .failed, outcome: nil, error: ufe.detail ?? ufe.message)
            events.publish(.toolFinished(act, ok: false))
            Log.shared.warning("tools", "\(tool.spec.name) failed", ["error": String(describing: error)])
            return ToolOutcome(activity: act, status: .failed(ufe))
        }
    }

    private func log(_ spec: ToolSpec, _ act: ToolActivity, caller: Caller, input: JSONValue, decision: ActivityEntry.Decision,
                     outcome: String?, error: String?) async {
        let entry = ActivityEntry(at: clock.now, caller: caller.kind == "agent" ? "agent" : "\(caller.kind):\(caller)",
                                  tool: spec.name, risk: spec.risk.rawValue, decision: decision, summary: act.summary,
                                  args: Redactor.arguments(input), outcome: outcome.map { Redactor.redact($0).clipped(300) },
                                  error: error.map { Redactor.redact($0).clipped(300) }, runId: caller.runId)
        _ = try? await activity.log(entry)
        events.changed(.activity)
    }

    static func missingRequired(_ schema: JSONValue, _ input: JSONValue) -> String? {
        guard let required = schema["required"]?.arrayValue else { return nil }
        for case .string(let key) in required {
            guard let v = input[key], !v.isNull else { return key }
            if case .string(let s) = v, s.trimmingCharacters(in: .whitespaces).isEmpty { return key }
        }
        return nil
    }

    static func userFacing(_ error: Error, tool: ToolSpec) -> UserFacingError {
        if let e = error as? UserFacingError { return e }
        if let e = error as? ToolError {
            switch e {
            case .invalidInput(let m): return UserFacingError("That didn't work: \(m)", detail: e.description)
            case .notFound(let m): return UserFacingError("I couldn't find \(m).", detail: e.description)
            case .unavailable(let m): return UserFacingError(m, detail: e.description)
            }
        }
        if error is TimeoutError {
            return UserFacingError("“\(tool.title)” took too long, so I stopped it.", recovery: "Try again in a moment.",
                                   changedNothing: !tool.mutates, detail: "timeout")
        }
        return UserFacingError("“\(tool.title)” didn't work.", recovery: nil, changedNothing: !tool.mutates,
                               detail: String(describing: error))
    }
}

public struct TimeoutError: Error, Sendable {}

/// Runs `work`, throwing `TimeoutError` if it takes longer than `seconds`. Returns on time even when
/// `work` ignores cancellation (blocking I/O, a stuck extension): a task group would wait for it, so
/// `work` runs in its own task, is cancelled at the deadline and is left to finish on its own. Its
/// late result is dropped; any side effect it still has happens after the caller was told it stopped.
public func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    let first = FirstResult<T>()
    let worker = Task {
        do { first.finish(.success(try await work())) } catch { first.finish(.failure(error)) }
    }
    let timer = Task {
        try? await Task.sleep(for: .seconds(seconds))
        if !Task.isCancelled, first.finish(.failure(TimeoutError())) { worker.cancel() }
    }
    defer { timer.cancel() }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { first.install($0) }
    } onCancel: {
        worker.cancel()
        first.finish(.failure(CancellationError()))
    }
}

/// Resumes one continuation with whichever result arrives first, even before it is installed.
private final class FirstResult<T: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, any Error>?
        var result: Result<T, any Error>?
    }
    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<T, any Error>) {
        let ready = state.withLock { s -> Result<T, any Error>? in
            if s.result == nil { s.continuation = continuation }
            return s.result
        }
        if let ready { continuation.resume(with: ready) }
    }

    /// True when this result was the first.
    @discardableResult
    func finish(_ result: Result<T, any Error>) -> Bool {
        let (waiting, won) = state.withLock { s -> (CheckedContinuation<T, any Error>?, Bool) in
            guard s.result == nil else { return (nil, false) }
            s.result = result
            defer { s.continuation = nil }
            return (s.continuation, true)
        }
        waiting?.resume(with: result)
        return won
    }
}
