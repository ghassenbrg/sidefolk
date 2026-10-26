import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Guard must fail closed. Before the 0.1.0 review a call made from a stopped task (or after any failed read of the
/// settings) was judged against the default policy, in which nothing is switched off: with Clipboard turned off, a
/// stopped run still set the clipboard, and its result said it hadn't.
@Suite struct FailClosedTests {
    @Test func aStoppedTaskNeverActsAndNeverForgetsWhatIsOff() async throws {
        for disabled in [Set<Capability>([.clipboard]), []] {
            let b = try BuiltinEnv(clipboard: "before")
            try await b.env.permissions.setPolicy(GuardPolicy(disabled: disabled))
            let executor = b.env.executor
            let stopped = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await executor.execute(name: "clipboard.write", input: ["text": "after"], caller: .agent(runId: "r"))
            }
            let outcome = await stopped.value
            try await Task.sleep(for: .milliseconds(50))
            guard case .denied(let why) = outcome.status else { Issue.record("expected a refusal, got \(outcome.status)"); continue }
            #expect(why == "The request was stopped before this ran.")
            #expect(b.platform.clipboard == "before")
            #expect(try await b.env.activity.recent().map(\.decision) == [.blocked], "still in Activity")
            b.cleanup()
        }
    }

    @Test func workForACallerThatIsGoneNeverStarts() async throws {
        let ran = Shared(false)
        let stopped = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withTimeout(5) { ran.change { $0 = true } }
        }
        await #expect(throws: CancellationError.self) { try await stopped.value }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!ran.value)
    }

    /// Changing one setting never resets the others, and a policy that can't be read is never overwritten by the
    /// default (which would switch everything back on).
    @Test func changingTheModeKeepsWhatIsSwitchedOff() async throws {
        let env = try TestEnv()
        try await env.permissions.setPolicy(GuardPolicy(mode: .auto, disabled: [.shell, .network]))
        try await env.permissions.updatePolicy { $0.mode = .askEveryTime }
        let saved = try await env.permissions.policy()
        #expect(saved.mode == .askEveryTime && saved.disabled == [.shell, .network])

        try await env.db.writer.write { db in try KeyValue(key: PermissionStore.policyKey, value: "not a policy").save(db) }
        await #expect(throws: (any Error).self) { try await env.permissions.updatePolicy { $0.mode = .fullAccess } }
        let row = try await env.db.writer.read { db in try KeyValue.fetchOne(db, key: PermissionStore.policyKey) }
        #expect(row?.value == "not a policy", "left for the person to fix, not replaced by defaults")
    }
}
