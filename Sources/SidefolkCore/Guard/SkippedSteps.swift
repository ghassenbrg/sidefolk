import Foundation

/// A step Sidefolk's own agent asked about that nobody answered in time (D37). Its run went on
/// without it (or stopped there); the person can still run it from Now, where it shows the words
/// its approval card had.
public struct SkippedStep: Sendable, Identifiable, Hashable {
    public var id: String { request.id }
    /// The question the card asked.
    public let request: ApprovalRequest
    public let skippedAt: Date
    /// The task stopped at this step instead of carrying on.
    public let stoppedTask: Bool
    let call: Call

    /// Everything needed to make the same call again, as the same caller in the same state.
    struct Call: Sendable, Hashable {
        let tool: String
        let input: JSONValue
        let caller: Caller
        let tainted: Bool
        let mentions: UserMentions?
    }
}

/// Skipped steps, kept in memory like undo: a day at most, the newest 20. After a restart they are
/// only in Activity, which shows them but can't run them again (the arguments there are redacted).
public actor SkippedSteps {
    public static let lifetime: TimeInterval = 86_400
    public static let limit = 20
    private var steps: [SkippedStep] = []
    private let events: EventBus
    private let clock: any Clock

    init(events: EventBus, clock: any Clock) {
        self.events = events
        self.clock = clock
    }

    func add(_ step: SkippedStep) {
        steps = Array((steps.filter { $0.id != step.id } + [step]).suffix(Self.limit))
        events.changed(.skipped)
    }

    /// The steps still offered, newest first.
    public func list() -> [SkippedStep] {
        let now = clock.now
        steps.removeAll { now.timeIntervalSince($0.skippedAt) >= Self.lifetime }
        return steps.reversed()
    }

    /// Removes and returns a step that is still offered.
    func take(_ id: String) -> SkippedStep? {
        let now = clock.now
        guard let i = steps.firstIndex(where: { $0.id == id }), now.timeIntervalSince(steps[i].skippedAt) < Self.lifetime else { return nil }
        defer { events.changed(.skipped) }
        return steps.remove(at: i)
    }

    public func dismiss(_ id: String) {
        guard steps.contains(where: { $0.id == id }) else { return }
        steps.removeAll { $0.id == id }
        events.changed(.skipped)
    }
}
