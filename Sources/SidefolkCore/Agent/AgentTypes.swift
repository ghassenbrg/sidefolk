import Foundation

public enum AgentPhase: Sendable, Hashable {
    case thinking
    case working(ToolCategory)
    case waitingForApproval
}

public struct AgentReply: Sendable {
    public var text: String
    public var cards: [ResultCard]
    /// The turn read outside content, so the words may echo it (saving them keeps them marked as the agent's).
    public var tainted: Bool
    public init(text: String, cards: [ResultCard] = [], tainted: Bool = false) {
        self.text = text
        self.cards = cards
        self.tainted = tainted
    }
}

/// What the UI hears while the agent handles a request.
public enum AgentEvent: Sendable {
    case started(runId: String, provider: String, model: String)
    case phase(AgentPhase)
    case toolStarted(ToolActivity)
    case toolFinished(ToolActivity, ok: Bool)
    case reply(AgentReply)
    case failed(UserFacingError)
    case finished(runId: String)
}
