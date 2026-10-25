import Foundation

/// What the companion's body should show. The app maps this onto the character rig.
public enum CompanionPose: Sendable, Hashable {
    case idle, sleeping, listening, thinking, waiting, success, error, alert, dragging, celebrating
    case working(ToolCategory)
}

/// Turns everything happening in Sidefolk into one pose, by priority (docs/PRODUCT.md §8):
/// dragging > waiting > alert > error/success (brief) > working > thinking > listening > idle > sleeping.
public struct CompanionMood: Sendable {
    public var dragging = false
    public var panelOpen = false
    public var asleep = false
    public private(set) var thinking: Set<String> = []
    public private(set) var working: [String: ToolCategory] = [:]
    public private(set) var approvals: Set<String> = []
    public private(set) var alerts: Set<String> = []
    private var transient: (pose: CompanionPose, until: Date)?

    public static let successHold: TimeInterval = 1.4
    public static let errorHold: TimeInterval = 2.4
    public static let celebrateHold: TimeInterval = 2.6

    public init() {}

    public func pose(at now: Date) -> CompanionPose {
        if dragging { return .dragging }
        if !approvals.isEmpty { return .waiting }
        if !alerts.isEmpty { return .alert }
        if let t = transient, t.until > now { return t.pose }
        if let category = working.values.first { return .working(category) }
        if !thinking.isEmpty { return .thinking }
        if panelOpen { return .listening }
        if asleep { return .sleeping }
        return .idle
    }

    /// When the current pose will change by itself (end of a brief success/error), if ever.
    public func nextChange(after now: Date) -> Date? {
        guard let t = transient, t.until > now else { return nil }
        return t.until
    }

    public mutating func apply(_ event: AppEvent, now: Date) {
        switch event {
        case .toolStarted(let a):
            working[a.id] = a.category
            asleep = false
        case .toolFinished(let a, let ok):
            working[a.id] = nil
            if working.isEmpty { flash(ok ? .success : .error, now: now) }
        case .approvalRequested(let r):
            approvals.insert(r.id)
            asleep = false
        case .approvalResolved(let id, _):
            approvals.remove(id)
        case .attention(.present(let item, let presentation)):
            switch presentation {
            case .attention, .system(_, alsoOnDesktop: true): alerts.insert(item.id)
            default: break
            }
            asleep = false
        case .attention(.withdraw(let id)):
            alerts.remove(id)
        case .agent(_, let e):
            switch e {
            case .started(let runId, _, _): thinking.insert(runId); asleep = false
            case .finished(let runId): thinking.remove(runId)
            case .failed: flash(.error, now: now)
            default: break
            }
        default:
            break
        }
    }

    /// Collapses an alert into the badge (the user saw it but has not answered yet).
    public mutating func quietAlert(id: String) { alerts.remove(id) }

    public mutating func celebrate(now: Date) { flash(.celebrating, now: now) }

    public mutating func clearRun(_ runId: String) {
        thinking.remove(runId)
    }

    private mutating func flash(_ pose: CompanionPose, now: Date) {
        let hold = pose == .error ? Self.errorHold : (pose == .celebrating ? Self.celebrateHold : Self.successHold)
        transient = (pose, now.addingTimeInterval(hold))
    }
}

/// Folks that sit beside the companion while their kind of job is live (DECISIONS D9).
public enum DutyFolk: String, Sendable, CaseIterable, Hashable {
    case tempo, scout, byte
}

public struct DutyRoster: Sendable, Equatable {
    public var reminderDueSoon = false
    public var activeWatchers = 0
    public var liveAgentWork = 0

    public init(reminderDueSoon: Bool = false, activeWatchers: Int = 0, liveAgentWork: Int = 0) {
        self.reminderDueSoon = reminderDueSoon
        self.activeWatchers = activeWatchers
        self.liveAgentWork = liveAgentWork
    }

    /// At most three, in a stable order.
    public var onDuty: [DutyFolk] {
        var folks: [DutyFolk] = []
        if reminderDueSoon { folks.append(.tempo) }
        if activeWatchers > 0 { folks.append(.scout) }
        if liveAgentWork > 0 { folks.append(.byte) }
        return folks
    }
}
