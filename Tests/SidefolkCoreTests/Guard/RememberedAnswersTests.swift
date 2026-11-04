import Foundation
import Testing
@testable import SidefolkCore

/// What the person said yes to is listed where they can take it back (Trust › Allowed for now, Always allowed), and
/// "Forget everything I allowed" takes back all of it and nothing else.
@Suite struct RememberedAnswersTests {
    /// A tainted run whose cards are answered with `decision`; counts the cards.
    private func answering(_ env: TestEnv, _ decision: ApprovalDecision, cards: CallCounter) -> Task<Void, Never> {
        let stream = env.events.stream()
        let broker = env.broker
        return Task {
            for await e in stream {
                guard case .approvalRequested(let r) = e else { continue }
                cards.bump()
                await broker.resolve(id: r.id, decision: decision)
            }
        }
    }

    @Test func allowedForNowIsListedAndStopsAsked() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "applenotes.copy", risk: .medium, capabilities: [.macApps, .notebook],
                                        result: { _ in ToolResult(text: "Copied.", untrusted: true) }))
        let cards = CallCounter()
        let answer = answering(env, .allowForRequest, cards: cards)
        defer { answer.cancel() }
        #expect(await env.executor.allowedForNow().isEmpty)

        let box = BrainToolbox(runId: "run-1", specs: env.registry.specs, executor: env.executor, startTainted: true, emit: { _ in })
        _ = await box.call("applenotes.copy", input: ["x": "1"])
        _ = await box.call("applenotes.copy", input: ["x": "2"])
        #expect(cards.value == 1)
        #expect(await env.executor.allowedForNow() == [.tool("applenotes.copy")])

        // Stopped: the same run is asked again.
        await env.executor.stopAllowing(.tool("applenotes.copy"))
        #expect(await env.executor.allowedForNow().isEmpty)
        _ = await box.call("applenotes.copy", input: ["x": "3"])
        #expect(cards.value == 2)

        // It ends with the run, and is gone from the list.
        await box.close()
        #expect(await env.executor.allowedForNow().isEmpty)
    }

    @Test func forgetTakesBackEveryYesAndLeavesFolders() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "applenotes.copy", risk: .medium, capabilities: [.macApps, .notebook],
                                        result: { _ in ToolResult(text: "Copied.", untrusted: true) }))
        let cards = CallCounter()
        let answer = answering(env, .allowForRequest, cards: cards)
        defer { answer.cancel() }
        let box = BrainToolbox(runId: "run-1", specs: env.registry.specs, executor: env.executor, startTainted: true, emit: { _ in })
        _ = await box.call("applenotes.copy", input: ["x": "1"])
        try await env.permissions.addGrant(Grant(tool: "applenotes.list", scope: .object([:]), callerKind: "agent"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("remembered-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try await env.permissions.grantFolder(folder, access: .readwrite)
        try await env.permissions.updatePolicy { $0.disabled.insert(.network) }
        #expect(try await env.permissions.grants().count == 1)

        try await env.permissions.revokeAllGrants()
        await env.executor.stopAllowingAnything()

        #expect(try await env.permissions.grants().isEmpty)
        #expect(await env.executor.allowedForNow().isEmpty)
        // Folders are their own list and the policy is not a yes.
        #expect(try await env.permissions.folders().count == 1)
        #expect(try await env.permissions.policy().disabled == [.network])
        // The same tool asks again.
        _ = await box.call("applenotes.copy", input: ["x": "2"])
        #expect(cards.value == 2)
    }

    @Test func aGrantCanBeRevokedAndTheNextCallAsksAgain() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "clipboard.read", risk: .medium, capabilities: [.clipboard],
                                        result: { _ in ToolResult(text: "x") }))
        let cards = CallCounter()
        let answer = answering(env, .allowAlways, cards: cards)
        defer { answer.cancel() }
        let box = BrainToolbox(runId: "run-1", specs: env.registry.specs, executor: env.executor, startTainted: false, emit: { _ in })
        _ = await box.call("clipboard.read", input: [:])
        _ = await box.call("clipboard.read", input: [:])
        #expect(cards.value == 1)
        let grant = try #require(try await env.permissions.grants().first)
        try await env.permissions.revokeGrant(id: grant.id)
        _ = await box.call("clipboard.read", input: [:])
        #expect(cards.value == 2)
    }
}
