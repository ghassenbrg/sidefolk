import Foundation
import Synchronization

/// Replays canned assistant turns and records every request, so the loop, the runtime and the
/// context can be tested without a network or a quota.
public final class ScriptedModel: TurnModel {
    public enum Step: Sendable {
        case turn(ModelTurn)
        case failure(UserFacingError)
        /// Runs custom code: wait, move a clock, inspect the request.
        case perform(@Sendable (TurnRequest) async throws -> ModelTurn)
    }

    public let providerName: String
    private let state: Mutex<(steps: [Step], requests: [TurnRequest])>

    public init(_ steps: [Step], providerName: String = "Scripted") {
        self.providerName = providerName
        state = Mutex((steps, []))
    }

    public var requests: [TurnRequest] { state.withLock { $0.requests } }

    public func respond(to request: TurnRequest) async throws -> ModelTurn {
        let step = state.withLock { s -> Step? in
            s.requests.append(request)
            return s.steps.isEmpty ? nil : s.steps.removeFirst()
        }
        switch step {
        case .turn(let turn)?: return turn
        case .failure(let error)?: throw error
        case .perform(let work)?: return try await work(request)
        case nil: throw UserFacingError("The scripted model has no more turns.")
        }
    }

    public func check(model: String) async -> Result<String, UserFacingError> { .success("Scripted model ready.") }
}

public extension ModelTurn {
    /// A final answer.
    static func reply(_ text: String, usage: TokenUsage = TokenUsage(input: 10, output: 5)) -> ModelTurn {
        ModelTurn(text: text, stop: .end, usage: usage)
    }

    /// A turn that asks for tools.
    static func calling(_ calls: [ToolCall], text: String = "", usage: TokenUsage = TokenUsage(input: 10, output: 5)) -> ModelTurn {
        ModelTurn(text: text, toolCalls: calls, stop: .toolUse, usage: usage)
    }
}
