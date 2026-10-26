import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// "Allow for this request" (D37): in a turn that read outside content, a step that can't carry data
/// off the Mac is asked once per tool for the rest of the run, so copying a library of Apple Notes in
/// batches isn't a card per batch.
@Suite struct RequestAllowanceTests {
    func card(_ caps: Set<Capability>, risk: Risk = .medium, mutates: Bool = true, tainted: Bool = true,
              caller: Caller = .agent(runId: "r"), mode: GuardMode = .askOncePerKind, scope: ToolScope = .none) -> ApprovalRequest? {
        let spec = ToolSpec(name: "t.x", title: "X", description: "", inputSchema: .object([:]), risk: risk, capabilities: caps,
                            category: .notes, mutates: mutates)
        let d = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: scope, caller: caller, tainted: tainted,
                                            policy: GuardPolicy(mode: mode), grants: [], folders: [])
        if case .ask(let r) = d { return r }
        return nil
    }

    @Test func offeredOnlyForWhatStaysOnTheMac() {
        // Reading and copying Apple Notes into the notebook: offered.
        #expect(card([.macApps])?.canAllowForRequest == true)
        #expect(card([.macApps, .notebook])?.canAllowForRequest == true)
        #expect(card([.clipboard], mutates: false)?.canAllowForRequest == true)
        // Anything that could carry data out: never.
        for caps: Set<Capability> in [[.network], [.apps], [.shell], [.filesWrite], [.extensions], [.macApps, .network]] {
            #expect(card(caps)?.canAllowForRequest == false, "\(caps)")
        }
        #expect(card([.memory], risk: .low)?.canAllowForRequest == false)
        // High risk, text to read in full, other agents, a clean turn (where "Always" is offered), Ask every time: never.
        #expect(card([.macApps], risk: .high)?.canAllowForRequest == false)
        #expect(card([], scope: ToolScope(text: "steps"))?.canAllowForRequest == false)
        #expect(card([.macApps], caller: .external(client: "codex"))?.canAllowForRequest == false)
        let clean = card([.macApps], tainted: false)
        #expect(clean?.canAllowForRequest == false && clean?.canAlways == true)
        #expect(card([.macApps], mode: .askEveryTime)?.canAllowForRequest == false)
    }

    @Test func oneCardForTheRestOfTheRun() async throws {
        let env = try TestEnv()
        let copied = CallCounter()
        env.registry.register(ProbeTool(name: "applenotes.copy", risk: .medium, capabilities: [.macApps, .notebook],
                                        result: { _ in copied.bump(); return ToolResult(text: "Copied 50 notes.", untrusted: true) }))
        let cards = Mutex<[ApprovalRequest]>([])
        let stream = env.events.stream()
        let broker = env.broker
        let answering = Task {
            for await e in stream {
                guard case .approvalRequested(let r) = e else { continue }
                cards.withLock { $0.append(r) }
                await broker.resolve(id: r.id, decision: .allowForRequest)
            }
        }
        defer { answering.cancel() }

        let box = BrainToolbox(runId: "run-1", specs: env.registry.specs, executor: env.executor, startTainted: true, emit: { _ in })
        for batch in 1...4 {
            let out = await box.call("applenotes.copy", input: ["x": .string("batch \(batch)")])
            #expect(out.isOK)
        }
        #expect(copied.value == 4)
        #expect(cards.withLock { $0.count } == 1)
        #expect(try await env.activity.recent().allSatisfy { $0.decision == .allowed })

        // It ends with the run: the next request asks again.
        await box.close()
        let next = BrainToolbox(runId: "run-2", specs: env.registry.specs, executor: env.executor, startTainted: true, emit: { _ in })
        _ = await next.call("applenotes.copy", input: ["x": "batch 5"])
        #expect(cards.withLock { $0.count } == 2)
    }
}
