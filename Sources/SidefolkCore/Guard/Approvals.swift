import Foundation

public struct ApprovalRequest: Sendable, Hashable, Identifiable {
    public enum Details: Sendable, Hashable {
        case none
        case command(String)
        case url(String)
        case paths([String])
        case folderAccess(folder: String, write: Bool)
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
    public var createdAt: Date

    public init(id: String = Identifier.make(), tool: String, title: String, summary: String, risk: Risk, caller: Caller,
                details: Details, canAlways: Bool, tainted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.tool = tool
        self.title = title
        self.summary = summary
        self.risk = risk
        self.caller = caller
        self.details = details
        self.canAlways = canAlways
        self.tainted = tainted
        self.createdAt = createdAt
    }
}

public enum ApprovalDecision: Sendable, Hashable {
    case allowOnce
    case allowAlways
    case deny
    case expired

    public var allowed: Bool { self == .allowOnce || self == .allowAlways }
}

/// Parks approval requests until the user answers in the UI, or they expire.
public actor ApprovalBroker {
    private var waiting: [String: CheckedContinuation<ApprovalDecision, Never>] = [:]
    private var requests: [String: ApprovalRequest] = [:]
    private let events: EventBus

    public init(events: EventBus) { self.events = events }

    public func request(_ req: ApprovalRequest, timeout: TimeInterval) async -> ApprovalDecision {
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

    public func pending() -> [ApprovalRequest] {
        requests.values.sorted { $0.createdAt < $1.createdAt }
    }
}
