import Foundation

public struct ToolOutcome: Sendable {
    public enum Status: Sendable {
        case ok(ToolResult)
        case denied(String)
        case failed(UserFacingError)
    }

    public var activity: ToolActivity
    public var status: Status

    public var isOK: Bool { if case .ok = status { return true } else { return false } }
    public var untrusted: Bool { if case .ok(let r) = status { return r.untrusted } else { return false } }

    /// What the model is told about this call.
    public var modelText: String {
        switch status {
        case .ok(let r): return r.untrusted ? UntrustedText.wrap(r.text, source: activity.tool) : r.text
        case .denied(let why): return "Not done: \(why) Do not retry this action unless the user asks again."
        case .failed(let e): return "Failed: \(e.message)\(e.changedNothing ? " Nothing was changed." : "")"
        }
    }
}

/// Recent undoable actions, kept for 15 minutes.
public actor UndoCenter {
    private var entries: [String: (UndoAction, Date)] = [:]
    public init() {}

    public func register(_ action: UndoAction, id: String, now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.1) < 900 }
        entries[id] = (action, now)
    }

    public func has(_ id: String) -> Bool { entries[id] != nil }

    public func undo(_ id: String) async throws -> String? {
        guard let (action, _) = entries.removeValue(forKey: id) else { return nil }
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

    /// - Parameters:
    ///   - tainted: untrusted content is in play for this caller's current task.
    ///   - onWaiting: called when the call is parked waiting for the user's approval.
    public func execute(
        name: String, input: JSONValue, caller: Caller, tainted: Bool = false,
        timeout: TimeInterval = 90, approvalTimeout: TimeInterval = 600,
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
        var act = ToolActivity(id: callId, tool: spec.name, title: spec.title, summary: summary, category: spec.category, caller: caller)

        if let missing = Self.missingRequired(spec.inputSchema, input) {
            act.error = "Missing \(missing)"
            return ToolOutcome(activity: act, status: .failed(UserFacingError("The request was missing “\(missing)”.")))
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
                                           tainted: tainted, policy: policy, grants: grants, folders: folders)
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
                let answer = await broker.request(request, timeout: approvalTimeout)
                guard answer.allowed else {
                    let why = answer == .expired ? "The request waited too long for your answer." : "You said no."
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
            await log(tool.spec, act, caller: caller, input: input, decision: decision, outcome: result.card?.title ?? result.text.clipped(160), error: nil)
            events.publish(.toolFinished(act, ok: true))
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

/// Runs `work`, throwing `TimeoutError` if it takes longer than `seconds`.
public func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
