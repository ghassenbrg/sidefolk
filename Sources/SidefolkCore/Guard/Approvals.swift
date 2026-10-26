import Foundation

public struct ApprovalRequest: Sendable, Hashable, Identifiable {
    public enum Details: Sendable, Hashable {
        case none
        case command(String)
        case url(String)
        case paths([String])
        case folderAccess(folder: String, write: Bool)
        /// Text to read in full (a new skill's instructions).
        case text(String)
    }

    public var id: String
    public var tool: String
    public var title: String
    public var summary: String
    public var risk: Risk
    public var caller: Caller
    public var details: Details
    /// Whether "Always allow" may be offered.
    public var canAlways: Bool
    /// The request was triggered while untrusted content was in play.
    public var tainted: Bool
    /// The action only reads (private data such as the clipboard or Apple Notes) and sends nothing out.
    public var readsOnly: Bool
    /// Whether "Allow for this request" may be offered: the same tool then runs without a card until
    /// Sidefolk's run ends (D37). Only where "Always" isn't, and only for what can't carry data out.
    public var canAllowForRequest: Bool
    public var createdAt: Date

    public init(id: String = Identifier.make(), tool: String, title: String, summary: String, risk: Risk, caller: Caller,
                details: Details, canAlways: Bool, tainted: Bool = false, readsOnly: Bool = false, canAllowForRequest: Bool = false,
                createdAt: Date = Date()) {
        self.id = id
        self.tool = tool
        self.title = title
        self.summary = summary
        self.risk = risk
        self.caller = caller
        self.details = details
        self.canAlways = canAlways
        self.tainted = tainted
        self.readsOnly = readsOnly
        self.canAllowForRequest = canAllowForRequest
        self.createdAt = createdAt
    }

    /// Whether the person reading `other` was asked exactly this: same tool, same caller, same
    /// words and details (they come from the arguments), same risk and the same warning.
    public func asksTheSame(as other: ApprovalRequest) -> Bool {
        tool == other.tool && caller == other.caller && title == other.title && summary == other.summary
            && details == other.details && risk == other.risk && tainted == other.tainted
    }
}

public enum ApprovalDecision: Sendable, Hashable {
    case allowOnce
    case allowAlways
    /// This tool, for the rest of the run that asked (`ApprovalRequest.canAllowForRequest`).
    case allowForRequest
    case deny
    case expired

    public var allowed: Bool { self == .allowOnce || self == .allowAlways || self == .allowForRequest }
}

/// The tools the person allowed "for this request" (D37), by the run that asked. They end with the run.
actor RequestAllowances {
    private var tools: [String: Set<String>] = [:]

    func allow(_ tool: String, run: String) { tools[run, default: []].insert(tool) }
    func covers(_ tool: String, run: String) -> Bool { tools[run]?.contains(tool) == true }
    func end(run: String) { tools[run] = nil }
}

/// Parks approval requests until the user answers in the UI, or they expire.
public actor ApprovalBroker {
    private var waiting: [String: CheckedContinuation<ApprovalDecision, Never>] = [:]
    private var requests: [String: ApprovalRequest] = [:]
    private let events: EventBus

    public init(events: EventBus) { self.events = events }

    /// Other agents get one card at a time between them (SECURITY T1): while one waits, further
    /// requests are refused at once instead of burying the user in cards. Their names are
    /// self-chosen, so the limit is shared rather than per name.
    public static let maxPendingExternal = 1

    /// Whether a card for this caller may be shown now.
    public func hasRoom(for caller: Caller) -> Bool {
        caller.kind != "external" || requests.values.filter { $0.caller.kind == "external" }.count < Self.maxPendingExternal
    }

    /// Shows the card and waits for the answer. A request `hasRoom` refuses is denied at once.
    public func request(_ req: ApprovalRequest, timeout: TimeInterval) async -> ApprovalDecision {
        await requestIfRoom(req, timeout: timeout) ?? .deny
    }

    /// Shows the card and waits for the answer; nil, without a card, when `hasRoom` refuses it. The
    /// check and the registration happen in one step, so parallel requests can't both find room.
    public func requestIfRoom(_ req: ApprovalRequest, timeout: TimeInterval) async -> ApprovalDecision? {
        guard hasRoom(for: req.caller) else { return nil }
        requests[req.id] = req
        events.publish(.approvalRequested(req))
        let id = req.id
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            await self?.resolve(id: id, decision: .expired)
        }
        let decision = await withTaskCancellationHandler {
            await withCheckedContinuation { c in waiting[id] = c }
        } onCancel: {
            Task { await self.resolve(id: id, decision: .deny) }
        }
        timer.cancel()
        return decision
    }

    public func resolve(id: String, decision: ApprovalDecision) {
        guard let c = waiting.removeValue(forKey: id) else { return }
        requests[id] = nil
        events.publish(.approvalResolved(id: id, decision: decision))
        c.resume(returning: decision)
    }

    /// Denies every request a run is still waiting on: once the run ended, a later Allow must not act for it.
    public func cancel(runId: String) {
        for (id, req) in requests where req.caller.runId == runId { resolve(id: id, decision: .deny) }
    }

    public func pending() -> [ApprovalRequest] {
        requests.values.sorted { $0.createdAt < $1.createdAt }
    }
}
