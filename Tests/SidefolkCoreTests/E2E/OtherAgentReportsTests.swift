import Foundation
import Testing
@testable import SidefolkCore

/// Other agents may show this Mac's load beside the companion (D42), but live values share four places: before the
/// review, any connected agent (under any names) could take all four and leave the person unable to show their own.
@Suite struct OtherAgentReportsTests {
    @Test func otherAgentsNeverTakeThePersonsPlaceBesideTheCompanion() async throws {
        let world = try await World([])
        let env = world.env
        let gateway = ExternalToolGateway(registry: env.registry, permissions: env.permissions, broker: env.broker, activity: env.activity,
                                          events: env.events, clock: env.clock)
        let input: JSONValue = ["source": "metric", "metric": "cpu", "every_seconds": 10]
        var outcomes: [ToolOutcome] = []
        for client in ["agent-a", "agent-b", "agent-c"] { outcomes.append(await gateway.call("watch.report", input: input, client: client)) }
        let allRan = outcomes.allSatisfy { $0.isOK }
        #expect(allRan, "a third runs on, out of the way (D116)")
        let shown = await world.engine.list()
        #expect(shown.filter { $0.display == .beside }.count == WatchLimits.maxExternalBeside)

        // The person still has a place, and a value past that runs too.
        for (metric, display) in [("memory", Watcher.Display.beside), ("battery", .quiet)] {
            let mine = await world.executor.execute(name: "watch.report", input: ["source": "metric", "metric": .string(metric), "every_seconds": 10],
                                                    caller: .user)
            #expect(mine.isOK, "\(mine.status)")
            let listed = await world.engine.list()
            #expect(listed.first { $0.config.string("metric") == metric }?.display == display, "\(metric)")
        }
        await world.engine.stop()
    }
}
