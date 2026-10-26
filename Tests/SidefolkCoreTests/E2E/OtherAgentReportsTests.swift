import Foundation
import Testing
@testable import SidefolkCore

/// Other agents may show this Mac's load beside the companion (D42), but live values share four places: before the
/// review, any connected agent (under any names) could take all four and leave the person unable to show their own.
@Suite struct OtherAgentReportsTests {
    @Test func otherAgentsNeverTakeMoreThanHalfTheLiveValues() async throws {
        let world = try await World([])
        let env = world.env
        let gateway = ExternalToolGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity,
                                          events: env.events, clock: env.clock)
        let input: JSONValue = ["source": "metric", "metric": "cpu", "every_seconds": 10]
        var outcomes: [ToolOutcome] = []
        for client in ["agent-a", "agent-b", "agent-c"] { outcomes.append(await gateway.call("watch.report", input: input, client: client)) }
        #expect(outcomes.map(\.isOK) == [true, true, false])
        #expect(outcomes[2].problem?.message.contains("Other agents already show 2 live values") == true, "\(outcomes[2].status)")

        // The person still has their two.
        for metric in ["memory", "battery"] {
            let mine = await world.executor.execute(name: "watch.report", input: ["source": "metric", "metric": .string(metric), "every_seconds": 10],
                                                    caller: .user)
            #expect(mine.isOK, "\(mine.status)")
        }
        #expect(await world.engine.list().filter { $0.mode == .report }.count == 4)
        await world.engine.stop()
    }
}
