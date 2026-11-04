import Foundation
import Synchronization

public struct ToolOutcome: Sendable {
    public enum Status: Sendable {
        case ok(ToolResult)
        case denied(String)
        case failed(UserFacingError)
        /// Nobody answered the approval in time (D37): the step was skipped, or the task is to stop.
        case unanswered(stop: Bool)
    }

    public var activity: ToolActivity
    public var status: Status
    /// What an untrusted result counts as, so a card later in the run can say what was read (D71).
    public var source: TaintSource?

    public var isOK: Bool { if case .ok(let r) = status { return !r.isError } else { return false } }
    public var untrusted: Bool { if case .ok(let r) = status { return r.untrusted } else { return false } }

    /// Why it didn't run, for the person; nil when it ran.
    public var problem: UserFacingError? {
        switch status {
        case .ok: nil
        case .denied(let why): UserFacingError(verbatim: why)
        case .failed(let error): error
        case .unanswered: UserFacingError("You didn't answer in time. Nothing was changed.")
        }
    }

    /// What the model is told about this call.
    public var modelText: String {
        switch status {
        case .ok(let r):
            let body = r.untrusted ? UntrustedText.wrap(r.text, source: activity.tool) : r.text
            return r.isError ? "The tool reported a problem; it may or may not have changed something:\n\(body)" : body
        case .denied(let why): return "Not done: \(why) Do not retry this action unless the user asks again."
        case .failed(let e):
            // The recovery is how a model fixes its call ("…or an ISO date such as 2025-11-12T09:00:00").
            return "Failed: \(e.message)\(e.recovery.map { " " + $0 } ?? "")\(e.changedNothing ? " Nothing was changed." : "")"
        case .unanswered(stop: false):
            return "Skipped: the user didn't answer in time, so this step was skipped and nothing was done. "
                + "Carry on with the rest of the request without it, and tell the user what was skipped."
        case .unanswered(stop: true):
            return "Not done: the user didn't answer in time, so the task is stopping. Do not call any more tools."
        }
    }
}

/// A yes that holds only for now (a run, a conversation), listed beside "Always allowed" so it can be taken back.
public enum AllowedForNow: Sendable, Hashable, Identifiable {
    /// "Allow for this request" (D37): this tool, until Sidefolk's run ends.
    case tool(String)
    /// "Allow, and read pages it links to" (D119).
    case readingOn

    public var id: String {
        switch self {
        case .tool(let name): "tool:" + name
        case .readingOn: "reading-on"
        }
    }
}

/// The only path by which anything runs a tool: Guard, approval, execution, audit, events.
public final class ToolExecutor: Sendable {
    public let registry: ToolRegistry
    public let undo = UndoCenter()
    /// Steps Sidefolk's agent skipped because nobody answered in time (D37).
    public let skipped: SkippedSteps
    private let permissions: PermissionStore
    private let engine = PermissionEngine()
    private let broker: ApprovalBroker
    private let forRequest = RequestAllowances()
    /// Links the person said could be read on, by conversation (D119).
    public let research = ResearchMode()
    private let activity: ActivityStore
    private let events: EventBus
    let clock: any Clock
    /// The length of a minute in an unanswered wait; tests shorten it so "10 minutes" passes quickly.
    private let minute: TimeInterval

    public init(registry: ToolRegistry, permissions: PermissionStore, broker: ApprovalBroker, activity: ActivityStore,
                events: EventBus, clock: any Clock = SystemClock(), minute: TimeInterval = 60) {
        self.registry = registry
        self.permissions = permissions
        self.broker = broker
        self.activity = activity
        self.events = events
        self.clock = clock
        self.minute = minute
        skipped = SkippedSteps(events: events, clock: clock)
    }

    /// How long a card waits before it counts as "no" (SECURITY T1), for everyone but Sidefolk's own
    /// agent, whose cards wait as the person's "If I don't answer" setting says (D37).
    public static let approvalTimeout: TimeInterval = 120

    /// - Parameters:
    ///   - tainted: untrusted content is in play for this caller's current task.
    ///   - mentions: the links the user typed in the request this call serves; links anywhere else
    ///     are model-built and Guard asks before they are fetched or opened.
    ///   - approvalTimeout: a card then waits at most this long (and two minutes at most) and silence
    ///     means "no", whoever the caller is.
    ///   - onWaiting: called when the call is parked waiting for the user's approval.
    public func execute(
        name: String, input: JSONValue, caller: Caller, tainted: Bool = false, taintedBy: TaintSource? = nil, mentions: UserMentions? = nil,
        timeout: TimeInterval = 90, approvalTimeout: TimeInterval? = nil, pickedFile: String? = nil, pickedFiles: [String] = [],
        onWaiting: (@Sendable (ApprovalRequest) -> Void)? = nil, standing: Bool = false, written: JSONValue? = nil, asker: ApprovalRequest.Asker? = nil
    ) async -> ToolOutcome {
        await perform(name: name, input: input, caller: caller, tainted: tainted, taintedBy: taintedBy, mentions: mentions, timeout: timeout,
                      approvalTimeout: approvalTimeout, onWaiting: onWaiting, answered: nil, pickedFile: pickedFile, pickedFiles: pickedFiles, standing: standing, written: written, asker: asker)
    }

    /// Guard's answer for this call, with nothing run, shown or logged (D110): what a card would be.
    func check(name: String, input: JSONValue, caller: Caller, tainted: Bool, standing: Bool) async -> ToolCheck? {
        guard let tool = registry.tool(named: name) else { return nil }
        let spec = tool.spec, input = input.objectValue == nil ? JSONValue.object([:]) : input, summary = tool.summary(for: input).clipped(240)
        func result(_ decision: ToolCheck.Decision, _ why: String? = nil) -> ToolCheck {
            ToolCheck(decision: decision, why: why, summary: summary, risk: spec.risk, mutates: spec.mutates)
        }
        if let missing = Self.missingRequired(spec.inputSchema, input) { return result(.deny, "Missing \(missing)") }
        if let problem = InputSchema.problem(spec.inputSchema, input, unknownKeys: false) { return result(.deny, problem) }
        if let why = tool.refusal(for: input, context: ToolContext(caller: caller, now: clock.now, tainted: tainted)) { return result(.deny, why) }
        guard let policy = try? await permissions.policy(now: clock.now) else { return result(.deny) }
        let grants = (try? await permissions.grants()) ?? [], scope = tool.scope(for: input)
        let folders = ((try? await permissions.folders()) ?? []) + Self.fullAccessFolders(scope, caller: caller, policy: policy)
        switch engine.evaluate(spec: spec, input: input, summary: summary, scope: scope, caller: caller, tainted: tainted,
                               policy: policy, grants: grants, folders: folders, standing: standing) {
        case .allow: return result(.allow)
        case .ask: return result(.ask)
        case .deny(let why):
            var check = result(.deny, why)
            if why == PermissionEngine.notShared { check.share = FolderAccess.sharingNeeded(read: scope.readPaths, write: scope.writePaths, folders: folders).map { .init(path: $0.path, write: $0.write) } }
            return check
        }
    }

    /// In Full access, the paths of this call that are in the person's home, as folders for this call alone (D185): nothing is
    /// added to the list Trust shows. They also reach the tool, which checks the folders Guard let it have. Nothing for anyone
    /// but Sidefolk's own agent: not a typed extension command, whose folder is the extension's to name (`GuardPolicy.mode(for:)`
    /// gives it the mode, not the home), and nothing outside the home or in a protected place.
    static func fullAccessFolders(_ scope: ToolScope, caller: Caller, policy: GuardPolicy) -> [GrantedFolder] {
        guard case .agent = caller, policy.mode(for: caller) == .fullAccess else { return [] }
        return Set(scope.readPaths + scope.writePaths).compactMap { path in
            FolderAccess.isOpenToFullAccess(path) ? FolderAccess.canonical(path).map { GrantedFolder(path: $0, access: .readwrite) } : nil
        }
    }

    /// Runs a skipped step on the person's click in Now. The click answers the question its card
    /// asked, which Now shows word for word; if Guard now asks something else (the folder was removed,
    /// say), that card is shown and waits as any card does for someone who is there. Nil when the
    /// step is no longer offered.
    public func runSkipped(id: String) async -> ToolOutcome? {
        guard let step = await skipped.take(id) else { return nil }
        let call = step.call
        return await perform(name: call.tool, input: call.input, caller: call.caller, tainted: call.tainted, taintedBy: step.request.taintedBy,
                             mentions: call.mentions,
                             timeout: 90, approvalTimeout: nil, onWaiting: nil, answered: step.request, standing: false, asker: nil)
    }

    /// - Parameter answered: a question the person already said "Allow" to, outside a card.
    private func perform(
        name: String, input: JSONValue, caller: Caller, tainted: Bool, taintedBy: TaintSource?, mentions: UserMentions?, timeout: TimeInterval,
        approvalTimeout: TimeInterval?, onWaiting: (@Sendable (ApprovalRequest) -> Void)?, answered: ApprovalRequest?, pickedFile: String? = nil, pickedFiles: [String] = [], standing: Bool = false, written: JSONValue? = nil, asker: ApprovalRequest.Asker? = nil
    ) async -> ToolOutcome {
        let callId = Identifier.make()
        guard let tool = registry.tool(named: name) else {
            let a = ToolActivity(id: callId, tool: name, title: name, summary: String(localized: "Unknown tool"), category: .system, caller: caller,
                                 error: "No such tool")
            return ToolOutcome(activity: a, status: .failed(UserFacingError("I don't have a tool called \(name).")))
        }
        let spec = tool.spec
        var input = input.objectValue == nil ? .object([:]) : input
        let summary = tool.summary(for: input).clipped(240)
        var act = ToolActivity(id: callId, tool: spec.name, title: spec.title, summary: summary, category: spec.category, caller: caller,
                               mutates: spec.mutates)
        if let written {
            act.written = .init(summary: tool.summary(for: written).clipped(240), input: written, length: ExtensionPlanRules.filledLength(input, template: written))
        }

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

        var scope = tool.scope(for: input)
        // Only where it can change the answer (Sidefolk's agent, after outside content, in a mode that answers for the
        // person) is a program asked where its call goes, and the call is then bound to what it confirmed (D72).
        if tainted, let policy = try? await permissions.policy(now: clock.now), [.auto, .fullAccess].contains(policy.mode(for: caller)) {
            (scope, input) = await tool.confirmReach(input, scope: scope)
        }
        var decisionTag: ActivityEntry.Decision = .auto
        // A file the person chose in the system's panel for this call: read of it alone, and only as themselves (SECURITY T12).
        // Set only by Sidefolk's own panel and drop code, from what the system handed over (D105, D141).
        let handedOver: Set<String> = caller == .user ? Set(([pickedFile].compactMap { $0 } + pickedFiles).compactMap(FolderAccess.canonical)) : []
        var extraFolders = handedOver.sorted().map { GrantedFolder(path: $0, access: .read) }
        // Folders the person allowed in a card for this call: a file there was named for this call, not picked from a
        // folder shared for good (D72).
        var answeredFolders: [String] = []
        var answered = answered
        // The person clicked "Run it now": they're here, so any further card waits as for anyone present.
        let present = answered != nil

        // Evaluate, possibly twice: once for folder access, once for the action itself.
        for _ in 0..<3 {
            // Fail closed: the default policy has nothing switched off, so a failed read (or a stopped task,
            // which GRDB refuses) must never stand in for the person's settings.
            guard let policy = try? await permissions.policy(now: clock.now) else {
                let why = Task.isCancelled ? String(localized: "The request was stopped before this ran.")
                    : String(localized: "Sidefolk couldn't read its permission settings, so it didn't do this.")
                await log(spec, act, caller: caller, input: input, decision: .blocked, outcome: nil, error: why)
                act.error = why
                return ToolOutcome(activity: act, status: .denied(why))
            }
            let grants = (try? await permissions.grants()) ?? []
            let folders = ((try? await permissions.folders()) ?? []) + extraFolders + Self.fullAccessFolders(scope, caller: caller, policy: policy)
            let decision = engine.evaluate(spec: spec, input: input, summary: summary, scope: scope, caller: caller,
                                           tainted: tainted, policy: policy, grants: grants, folders: folders, mentions: mentions,
                                           answeredFolders: answeredFolders, standing: standing)
            switch decision {
            case .allow(let tag):
                // A site allowed for good, used while outside content is in play, is the only site the call may reach:
                // a redirect from it could carry the address's path anywhere (D47).
                var site: String?
                if tag == .always, let g = PermissionEngine.matchingGrant(spec: spec, scope: scope, caller: caller, grants: grants) {
                    try? await permissions.touchGrant(id: g.id)
                }
                if tag == .always, tainted, let g = PermissionEngine.matchingGrant(
                    spec: spec, scope: scope, caller: caller, grants: grants.filter { $0.scope.string("host") != nil }) {
                    site = g.scope.string("host").flatMap(UserMentions.site)
                }
                if decisionTag == .auto { decisionTag = tag }
                return await run(tool, input: input, caller: caller, tainted: tainted, activity: act, decision: decisionTag,
                                 timeout: spec.timeout ?? timeout, folders: folders, site: site, handedOver: handedOver)
            case .deny(let why):
                await log(spec, act, caller: caller, input: input, decision: .blocked, outcome: nil, error: why)
                act.error = why
                return ToolOutcome(activity: act, status: .denied(why))
            case .ask(var request):
                // What the card needs to explain itself (D71); Guard's question is the same without it.
                let ext = ((tool as? ExternalFacade)?.base ?? tool) as? ExtensionTool
                if ext != nil || spec.name == CompanionJobTool.name, input.objectValue?.isEmpty == false { request.input = input.prettyString }
                request.firstParty = ext?.firstParty ?? true
                request.mode = policy.mode(for: caller)
                if tainted { request.taintedBy = taintedBy }
                // Reading a page, for Sidefolk's own agent, unless the person has it ask every time (D47, D119).
                let reading = spec.name == "web.fetch" && caller.kind == "agent" ? tool.scope(for: input).url : nil
                if let reading, let run = caller.runId, policy.internet(for: caller) != .askEachTime {
                    request.canKeepReading = await research.canOffer(run: run, for: reading)
                }
                // Another agent reading the notebook asks each time unless that group is allowed; say how to allow it (D185).
                request.canAllowAgentsToRead = caller.kind == "external" && ExternalToolPolicy.reading.contains(spec.name)
                var readByResearch = false
                var carriedOver = false
                if let asker {
                    request.asker = asker
                    request.firstParty = asker.firstParty
                    if case .text = request.details { request.effect = .actsForYou }
                }
                var thePersonAnswered = false
                let wait = approvalTimeout.map { (seconds: min($0, Self.approvalTimeout), whenTimeIsUp: UnansweredRule.Action?.none) }
                    ?? Self.wait(for: caller, policy: policy, present: present, minute: minute)
                let answer: ApprovalDecision
                if let given = answered, request.asksTheSame(as: given) {
                    answered = nil
                    answer = .allowOnce
                } else if request.canAllowForRequest, let run = caller.runId, await forRequest.covers(spec.name, run: run) {
                    answer = .allowOnce
                    carriedOver = true
                } else if let reading, let run = caller.runId, policy.internet(for: caller) != .askEachTime, await research.take(reading, run: run, now: clock.now) {
                    answer = .allowOnce
                    readByResearch = true
                } else {
                    onWaiting?(request)
                    guard let reply = await broker.requestIfRoom(request, timeout: wait.seconds) else {
                        let why = "Another agent's request is already waiting for the user's answer. Try again after it is answered."
                        await log(spec, act, caller: caller, input: input, decision: .denied, outcome: nil, error: why)
                        act.error = why
                        return ToolOutcome(activity: act, status: .denied(why))
                    }
                    answer = reply
                    thePersonAnswered = true
                }
                // An answer that arrives after the caller gave up (its run ended) never acts for it.
                guard answer.allowed, !Task.isCancelled else {
                    if answer == .expired, !Task.isCancelled, let then = wait.whenTimeIsUp {
                        let call = SkippedStep.Call(tool: spec.name, input: input, caller: caller, tainted: tainted, mentions: mentions)
                        return await unanswered(spec, act, request: request, stop: then == .stop, call: call)
                    }
                    let why = answer == .expired ? String(localized: "The request waited too long for your answer.")
                        : answer.allowed ? String(localized: "The request was withdrawn before it ran.") : String(localized: "You said no.")
                    await log(spec, act, caller: caller, input: input, decision: .denied, outcome: nil, error: why)
                    act.error = why
                    return ToolOutcome(activity: act, status: .denied(why))
                }
                decisionTag = readByResearch ? .research : carriedOver ? .allowedForRequest : answer == .allowAlways ? .always : .allowed
                if answer == .keepReading, request.canKeepReading, let run = caller.runId {
                    await research.grant(run: run, now: clock.now)
                    events.changed(.permissions)
                }
                if answer == .allowForRequest, request.canAllowForRequest, let run = caller.runId {
                    await forRequest.allow(spec.name, run: run)
                    events.changed(.permissions)
                }
                if case .folderAccess(let folder, let write) = request.details {
                    let access: GrantedFolder.Access = write ? .readwrite : .read
                    answeredFolders.append(FolderAccess.canonical(folder) ?? folder)
                    if answer == .allowAlways {
                        try? await permissions.grantFolder(folder, access: access)
                        events.changed(.permissions)
                    } else {
                        extraFolders.append(GrantedFolder(path: FolderAccess.canonical(folder) ?? folder, access: access))
                    }
                    continue
                }
                if answer == .allowAlways {
                    try? await permissions.addGrant(Grant(tool: spec.name, scope: PermissionEngine.grantScope(for: scope), callerKind: caller.grantKind))
                    events.changed(.permissions)
                }
                return await run(tool, input: input, caller: caller, tainted: tainted, activity: act, decision: decisionTag,
                                 timeout: spec.timeout ?? timeout, folders: folders, handedOver: handedOver, personWasAsked: thePersonAnswered)
            }
        }
        act.error = "Permission loop"
        return ToolOutcome(activity: act, status: .denied(String(localized: "Sidefolk couldn't settle the permissions for this action.")))
    }

    /// How long a card waits, and what silence means then. Sidefolk's own agent follows the person's
    /// "If I don't answer" setting (D37); everyone else, and a card for someone who is right there,
    /// waits two minutes and then counts as "no" (SECURITY T1). Every wait ends, so nothing in the
    /// background holds a question forever.
    static func wait(for caller: Caller, policy: GuardPolicy, present: Bool,
                     minute: TimeInterval) -> (seconds: TimeInterval, whenTimeIsUp: UnansweredRule.Action?) {
        guard case .agent = caller, !present else { return (approvalTimeout, nil) }
        return (Double(policy.unanswered.waitMinutes) * minute, policy.unanswered.whenTimeIsUp)
    }

    /// Nobody answered: the step is logged as skipped and kept so the person can still run it, and
    /// the model hears it was skipped (or that the task stops there).
    private func unanswered(_ spec: ToolSpec, _ act: ToolActivity, request: ApprovalRequest, stop: Bool,
                            call: SkippedStep.Call) async -> ToolOutcome {
        var act = act
        let why = stop ? String(localized: "You didn't answer in time, so the task stopped here.")
            : String(localized: "You didn't answer in time, so this step was skipped.")
        await log(spec, act, caller: call.caller, input: call.input, decision: .skipped, outcome: nil, error: why)
        await skipped.add(SkippedStep(request: request, skippedAt: clock.now, stoppedTask: stop, call: call))
        act.error = why
        act.decision = .skipped
        return ToolOutcome(activity: act, status: .unanswered(stop: stop))
    }

    /// What the person said yes to for the length of a run or a conversation, and that is still holding (Trust › Allowed for
    /// now): tools allowed "for this request", and reading pages on.
    public func allowedForNow() async -> [AllowedForNow] {
        let tools = await forRequest.allTools().sorted().map(AllowedForNow.tool)
        return tools + (await research.isGranted(now: clock.now) ? [.readingOn] : [])
    }

    /// Takes one such yes back: the next call asks again.
    public func stopAllowing(_ item: AllowedForNow) async {
        switch item {
        case .tool(let name): await forRequest.revoke(tool: name)
        case .readingOn: await research.revokeAll()
        }
    }

    /// Takes every such yes back.
    public func stopAllowingAnything() async {
        await forRequest.revokeAll()
        await research.revokeAll()
    }

    /// Denies the cards an agent run is still waiting on, and ends what was allowed "for this
    /// request"; call it when the run ends.
    public func cancelApprovals(runId: String) async {
        await broker.cancel(runId: runId)
        await forRequest.end(run: runId)
        await research.end(run: runId)
        events.changed(.permissions)
    }

    private func run(_ tool: any Tool, input: JSONValue, caller: Caller, tainted: Bool, activity act: ToolActivity,
                     decision: ActivityEntry.Decision, timeout: TimeInterval, folders: [GrantedFolder], site: String? = nil,
                     handedOver: Set<String> = [], personWasAsked: Bool = false) async -> ToolOutcome {
        var act = act
        act.decision = decision
        events.publish(.toolStarted(act))
        let context = {
            var context = ToolContext(caller: caller, now: clock.now, tainted: tainted, folders: folders, site: site, handedOver: handedOver)
            context.onPlan = decision == .plan
            context.filledIn = act.written != nil
            // What happened here, not what anyone says: this call's own card, answered yes, for another agent. A plan or a
            // flow's step never has it (D160).
            if case .external = caller { context.personWasAsked = personWasAsked }
            return context
        }()
        do {
            var result = try await withTimeout(timeout) { try await tool.run(input, context: context) }
            if let placing = result.placing { result.take(await placing()) }
            act.card = result.card
            if let row = result.rowSummary { act.summary = row }
            if let undo = result.undo {
                await self.undo.register(undo, id: act.id)
                act.undoAvailable = true
            }
            if result.isError {
                act.error = "\(tool.spec.title) reported a problem"
                await log(tool.spec, act, caller: caller, input: input, decision: .failed, outcome: nil, error: result.rowError ?? result.text.clipped(300))
            } else if !tool.leavesNoRow(for: input, caller: caller) {
                await log(tool.spec, act, caller: caller, input: input, decision: decision,
                          outcome: (caller.kind == "command" ? result.rowOutcome : nil) ?? result.card?.title ?? result.text.clipped(160),
                          error: nil, undoable: act.undoAvailable)
            }
            // Each saved file is its own row: what was written into the person's folder, and where (D140).
            for file in result.placed {
                var row = act
                row.summary = String(localized: "Saved \((file.path as NSString).lastPathComponent) beside \((file.source as NSString).lastPathComponent)")
                await log(tool.spec, row, caller: caller, input: ["path": .string(file.path)], decision: decision, outcome: file.path, error: nil)
            }
            events.publish(.toolFinished(act, ok: !result.isError))
            if let run = caller.runId, caller.kind == "agent" {
                await research.toolReturned(tool.spec.name, run: run)
                // Under a yes, the model is told what it may read on to (D119). A long page gives up its end for them.
                let links = await research.note(links: result.links, from: tool.scope(for: input).url ?? "", run: run, now: clock.now)
                if !links.isEmpty {
                    let list = "\n\nLinks on this page:\n" + links.joined(separator: "\n")
                    result.text = String(result.text.prefix(max(0, UntrustedText.maxBytes - list.utf8.count - 500))) + list
                }
            }
            return ToolOutcome(activity: act, status: .ok(result), source: result.untrusted ? TaintSource.of(tool) : nil)
        } catch {
            let ufe = Self.userFacing(error, tool: tool.spec)
            act.error = ufe.message
            await log(tool.spec, act, caller: caller, input: input, decision: .failed, outcome: nil, error: ufe.detail ?? ufe.message)
            events.publish(.toolFinished(act, ok: false))
            // The detail (an Apple Events code, an HTTP status) is what diagnoses a failure from the log.
            Log.shared.warning("tools", "\(tool.spec.name) failed", ["error": String(describing: error), "detail": ufe.detail ?? ""])
            return ToolOutcome(activity: act, status: .failed(ufe))
        }
    }

    /// - Parameter undoable: the call's undo is registered; Activity offers it on this row too.
    private func log(_ spec: ToolSpec, _ act: ToolActivity, caller: Caller, input: JSONValue, decision: ActivityEntry.Decision,
                     outcome: String?, error: String?, undoable: Bool = false) async {
        // A plan's step that filled words in is kept as written, and how long they were: what it found stays out of History, the founder's choice (D127).
        let written = act.written
        let outcome = written.flatMap { w in outcome.map { _ in String(localized: "Filled in when it ran, length \(w.length)", comment: "History: a step of a plan the person allowed, with what it filled in left out") } } ?? outcome
        // A failure's words can quote the call's. "You said no" and Guard's reasons can't, and say what really happened.
        let error = written == nil || decision != .failed ? error : error.map { _ in "\(spec.title) reported a problem" }
        let entry = ActivityEntry(at: clock.now, caller: caller.kind == "agent" ? "agent" : "\(caller.kind):\(caller)",
                                  tool: spec.name, risk: spec.risk.rawValue, decision: decision, summary: written?.summary ?? act.summary,
                                  args: Redactor.arguments(written?.input ?? input), outcome: outcome.map { Redactor.redact($0).clipped(300) },
                                  error: error.map { Redactor.redact($0).clipped(300) }, runId: caller.runId)
        // Detached so the audit row lands even when the run was just stopped: GRDB's async access throws once
        // its task is cancelled, and a step refused by Stop or Quit would vanish from Activity.
        let activity = self.activity
        let row = await Task.detached { try? await activity.log(entry).id }.value
        if undoable, let row { await undo.link(row: row, to: act.id) }
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
            case .unavailable(let m): return UserFacingError(verbatim: m, detail: e.description)
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
    // `work` runs in a task of its own, which doesn't inherit cancellation: started for a caller that is
    // already gone, it would act (set the clipboard, move a file) while the caller hears it was stopped.
    try Task.checkCancellation()
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
