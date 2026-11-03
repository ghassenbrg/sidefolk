import Foundation
import Testing
@testable import SidefolkCore

/// What left Ask is still in History, answer included (D136).
@Suite struct CommandOutcomeTests {
    private func probe(_ env: TestEnv) {
        env.registry.register(ProbeTool(name: "ext.calc.work", risk: .low, mutates: false, result: { _ in
            var result = ToolResult(text: "2+2 = 4", card: ResultCard(kind: .extensionResult, title: "Calculate"))
            result.rowOutcome = "2+2 = 4"
            return result
        }))
    }

    @Test func aCommandKeepsItsAnswer() async throws {
        let env = try TestEnv()
        probe(env)
        _ = await env.executor.execute(name: "ext.calc.work", input: .object([:]), caller: .command(extensionId: "calc"))
        #expect(try await env.activity.recent().first?.outcome == "2+2 = 4")
    }

    @Test func aToolAnAIRanKeepsWhatItAlwaysDid() async throws {
        let env = try TestEnv()
        probe(env)
        _ = await env.executor.execute(name: "ext.calc.work", input: .object([:]), caller: .agent(runId: "r1"))
        #expect(try await env.activity.recent().first?.outcome == "Calculate")
    }
}
