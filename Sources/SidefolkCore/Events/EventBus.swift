import Foundation
import Synchronization

/// Areas of data the UI may need to refresh.
public enum DataDomain: String, Sendable, CaseIterable {
    case notebook, memories, reminders, watchers, activity, extensions, skills, settings, attention, permissions, runs
    /// Steps skipped because nobody answered in time (D37).
    case skipped
    /// The AI conversations' history: a request, its reply, a deletion (D45).
    case conversations
}

/// A tool call as the companion and the Activity view see it.
public struct ToolActivity: Sendable, Hashable {
    public var id: String
    public var tool: String
    public var title: String
    public var summary: String
    public var category: ToolCategory
    public var caller: Caller
    public var card: ResultCard?
    public var error: String?
    public var undoAvailable: Bool
    /// The tool changes something (vs. only reading); read-only results feed answers, not cards.
    public var mutates: Bool
    /// How Guard let it run, once it did. Auto and Full access acts are shown as done without asking (D37).
    public var decision: ActivityEntry.Decision?

    /// It ran without a question the person would have had to answer in their earlier mode.
    public var actedWithoutAsking: Bool { decision == .autoMode || decision == .fullAccess }

    public init(id: String, tool: String, title: String, summary: String, category: ToolCategory, caller: Caller,
                card: ResultCard? = nil, error: String? = nil, undoAvailable: Bool = false, mutates: Bool = false) {
        self.id = id
        self.tool = tool
        self.title = title
        self.summary = summary
        self.category = category
        self.caller = caller
        self.card = card
        self.error = error
        self.undoAvailable = undoAvailable
        self.mutates = mutates
    }
}

public enum AppEvent: Sendable {
    case toolStarted(ToolActivity)
    case toolFinished(ToolActivity, ok: Bool)
    case approvalRequested(ApprovalRequest)
    case approvalResolved(id: String, decision: ApprovalDecision)
    case attention(AttentionDirective)
    case dataChanged(DataDomain)
    /// A report read a new value. Sent instead of `.dataChanged(.watchers)` when only the value moved, so a reading
    /// every few seconds refreshes one pill and one row, not every list.
    case watchReading(WatchReading)
    case agent(threadId: String, AgentEvent)
    case notice(String)
    /// Sidefolk's AI finished an extension draft: show the person its install preview (D39).
    case reviewExtension(URL)
    /// A trick or a game for the companion (D44), from the person's words or the AI.
    case companion(CompanionAct)
    /// A coin, dice or a hand the companion just drew (D44, amended), to play on the desktop.
    case toss(Toss)
}

/// Broadcasts events to any number of async subscribers. Slow subscribers drop the oldest events.
public final class EventBus: Sendable {
    private let subscribers = Mutex<[UUID: AsyncStream<AppEvent>.Continuation]>([:])

    public init() {}

    public func publish(_ event: AppEvent) {
        let targets = subscribers.withLock { Array($0.values) }
        for c in targets { c.yield(event) }
    }

    public func stream(bufferingNewest limit: Int = 256) -> AsyncStream<AppEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AppEvent>.makeStream(bufferingPolicy: .bufferingNewest(limit))
        continuation.onTermination = { [weak self] _ in
            _ = self?.subscribers.withLock { $0.removeValue(forKey: id) }
        }
        subscribers.withLock { $0[id] = continuation }
        return stream
    }

    public func changed(_ domain: DataDomain) { publish(.dataChanged(domain)) }
}
