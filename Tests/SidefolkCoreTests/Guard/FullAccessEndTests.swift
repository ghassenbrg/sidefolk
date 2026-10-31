import Foundation
import Testing
@testable import SidefolkCore

/// Full access with an end time (D84): "for 1 hour", "until tonight". Guard reads the mode it replaced once the end
/// has passed, whether or not anything noticed the moment.
@Suite struct FullAccessEndTests {
    @Test func itHandsBackTheModeItReplacedAtItsEnd() {
        let now = TestEnv.referenceDate
        var policy = GuardPolicy(mode: .auto)
        policy.choose(.fullAccess, fullAccessEnds: now.addingTimeInterval(3600))
        #expect(policy.mode == .fullAccess && policy.beforeFullAccess == .auto)
        #expect(policy.current(at: now.addingTimeInterval(3599)).mode == .fullAccess)
        let after = policy.current(at: now.addingTimeInterval(3600))
        #expect(after.mode == .auto && after.fullAccessEnds == nil)

        // Without an end it lasts; another mode forgets the end.
        policy.choose(.fullAccess)
        #expect(policy.current(at: .distantFuture).mode == .fullAccess)
        policy.choose(.fullAccess, fullAccessEnds: now)
        policy.choose(.askEveryTime)
        #expect(policy.fullAccessEnds == nil && policy.current(at: .distantFuture).mode == .askEveryTime)
    }

    @Test func choosingFullAccessAgainKeepsWhatItFirstReplaced() {
        var policy = GuardPolicy(mode: .askEveryTime)
        policy.choose(.fullAccess)
        policy.choose(.fullAccess, fullAccessEnds: TestEnv.referenceDate)
        #expect(policy.beforeFullAccess == .askEveryTime)
    }

    @Test func theEndSurvivesASaveAndAStoredBeforeIsNeverFullAccess() async throws {
        let env = try TestEnv()
        let ends = TestEnv.referenceDate.addingTimeInterval(1800)
        try await env.permissions.updatePolicy { $0.choose(.fullAccess, fullAccessEnds: ends) }
        let saved = try await env.permissions.policy(now: TestEnv.referenceDate)
        #expect(saved.mode == .fullAccess && saved.fullAccessEnds == ends)
        #expect(try await env.permissions.policy(now: ends).mode == .askOncePerKind)

        try await KVStore(env.db).set("guard.policy", ["mode": "fullAccess", "beforeFullAccess": "fullAccess",
                                                       "fullAccessEnds": .number(0)] as JSONValue)
        let odd = try await env.permissions.policy(now: TestEnv.referenceDate)
        #expect(odd.mode == .askOncePerKind, "an end in the past, and a mode to return to that can't be Full access")
    }

    /// Guard itself: a command that ran without a card under Full access asks again once its hour is over.
    @Test func guardAsksAgainOnceItHasEnded() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "shell.probe", risk: .medium, capabilities: [.shell]))
        try await env.permissions.updatePolicy { $0.choose(.fullAccess, fullAccessEnds: TestEnv.referenceDate.addingTimeInterval(3600)) }

        let during = await env.executor.execute(name: "shell.probe", input: ["x": "a"], caller: .agent(runId: "r"))
        #expect(during.isOK)
        #expect(try await env.activity.recent().first?.decision == .fullAccess)

        env.clock.advance(3600)
        let answer = env.autoAnswer(.deny)
        let after = await env.executor.execute(name: "shell.probe", input: ["x": "b"], caller: .agent(runId: "r"))
        #expect(await answer.value != nil, "Guard asked")
        #expect(!after.isOK)
    }
}
