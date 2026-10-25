import Foundation
import Testing
@testable import SidefolkCore

/// One real, tiny call. Off unless `SIDEFOLK_LIVE_TESTS=1` and `ANTHROPIC_API_KEY` are set:
/// live calls cost the user's quota.
@Suite struct LiveBrainTests {
    static let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    static let enabled = ProcessInfo.processInfo.environment["SIDEFOLK_LIVE_TESTS"] == "1" && !key.isEmpty

    @Test(.enabled(if: enabled)) func anthropicAnswersOneWord() async throws {
        let model = AnthropicModel(apiKey: Secret(Self.key))
        let turn = try await model.respond(to: TurnRequest(model: "claude-haiku-5-5", system: "Answer with one word.",
                                                           messages: [.user("Hi")], tools: [], maxOutputTokens: 256, timeBudget: 60))
        #expect(turn.usage.output > 0)
    }
}
