import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// `ToolContext.personWasAsked` opens what's otherwise closed to another agent, so nothing but this call's own answered card
/// may make it true: not an agent, a client's words, a flow step, a model, a plan or an earlier yes (D160).
@Suite struct PersonWasAskedTests {
    /// Records what it was told. `collections.create` is one of the names that always ask.
    final class Probe: Tool, Sendable {
        let spec: ToolSpec
        let seen = Mutex<[Bool]>([])

        init(name: String = "collections.create", risk: Risk = .medium) {
            spec = ToolSpec(name: name, title: "Probe", description: "", inputSchema: Schema.object(["name": Schema.string("Words")]), risk: risk,
                            capabilities: [], category: .system, mutates: true)
        }

        func summary(for input: JSONValue) -> String { "Probe" }
        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            seen.withLock { $0.append(context.personWasAsked) }
            return ToolResult(text: "ran")
        }
    }

    let env: TestEnv
    init() throws { env = try TestEnv() }

    /// Through a facade, as an agent's call and Sideflow's flow steps both go, answering any card with `decision`.
    func call(_ probe: Probe, as caller: Caller, decision: ApprovalDecision = .allowOnce, tainted: Bool = true, input: JSONValue = [:]) async -> (outcome: ToolOutcome, carded: Bool) {
        env.registry.register(ExternalFacade(base: probe, spec: probe.spec))
        let stream = env.events.stream()
        let broker = env.broker
        let card = Task { () -> Bool in
            for await event in stream {
                if case .approvalRequested(let r) = event {
                    await broker.resolve(id: r.id, decision: decision)
                    return true
                }
            }
            return false
        }
        let outcome = await env.executor.execute(name: probe.spec.name, input: input, caller: caller, tainted: tainted)
        card.cancel()
        return (outcome, await card.value)
    }

    func lastSeen(_ probe: Probe) -> Bool? { probe.seen.withLock { $0.last } }

    /// A step of a plan the person read: through `standing:`, as Sideflow's gateway calls it, no one is asked and the flag stays down.
    @Test func aStandingPlanIsNeverIt() async {
        for risk in [Risk.low, .medium] {
            let probe = Probe(risk: risk)
            env.registry.register(ExternalFacade(base: probe, spec: probe.spec))
            let stream = env.events.stream()
            let broker = env.broker
            let card = Task { () -> Bool in
                for await event in stream {
                    if case .approvalRequested(let r) = event {
                        await broker.resolve(id: r.id, decision: .allowOnce)
                        return true
                    }
                }
                return false
            }
            let outcome = await env.executor.execute(name: probe.spec.name, input: [:], caller: .extension(id: "dev.sidefolk.sideflow"), standing: true)
            card.cancel()
            let carded = await card.value
            #expect(outcome.isOK, "\(outcome.status)")
            #expect(!carded, "a plan stands in for the card")
            #expect(lastSeen(probe) == false, "\(risk)")
        }
    }

    @Test func anAgentsCallOnItsOwnAnsweredCardIsTheOneCase() async {
        let probe = Probe()
        let done = await call(probe, as: .external(client: "codex"))
        #expect(done.carded)
        #expect(done.outcome.isOK)
        #expect(lastSeen(probe) == true)
    }

    @Test func aNoNeverRuns() async {
        let probe = Probe()
        #expect(await call(probe, as: .external(client: "codex"), decision: .deny).carded)
        #expect(probe.seen.withLock { $0.isEmpty })
    }

    /// A flow step and a standing plan: the same facade, and no one asked, or asked as someone else.
    @Test func aFlowStepIsNeverIt() async {
        let carded = Probe()
        #expect(await call(carded, as: .extension(id: "dev.sidefolk.sideflow")).carded)
        #expect(lastSeen(carded) == false)
        let standing = Probe(risk: .low)
        let plan = await call(standing, as: .extension(id: "dev.sidefolk.sideflow"), tainted: false)
        #expect(!plan.carded)
        #expect(lastSeen(standing) == false)
    }

    @Test func aModelsCallIsNeverIt() async {
        for caller in [Caller.agent(runId: "r"), .routine(id: "morning"), .command(extensionId: "c")] {
            let probe = Probe()
            _ = await call(probe, as: caller)
            #expect(lastSeen(probe) != true, "\(caller)")
        }
    }

    /// With no card, it isn't: a low-risk call goes straight through.
    @Test func noCardNoAsking() async {
        let probe = Probe(risk: .low)
        let direct = await call(probe, as: .external(client: "codex"), tainted: false)
        #expect(!direct.carded)
        #expect(lastSeen(probe) == false)
    }

    /// A card from "Ask each time" asks about the group, not what's closed.
    @Test func aCardForAnotherToolOpensNothing() async {
        let probe = Probe(name: "notes.save")
        #expect(await call(probe, as: .external(client: "codex")).carded)
        #expect(lastSeen(probe) == false)
    }

    @Test func itDoesntCarryOverToTheNextCall() async {
        let asked = Probe()
        _ = await call(asked, as: .external(client: "codex"))
        #expect(lastSeen(asked) == true)
        let next = Probe(risk: .low)
        _ = await call(next, as: .external(client: "codex"), tainted: false)
        #expect(lastSeen(next) == false)
    }

    @Test func aClientsWordsAreNeverIt() async {
        let probe = Probe(risk: .low)
        let said = await call(probe, as: .external(client: "codex"), tainted: false, input: ["personWasAsked": true, "name": "x"])
        #expect(!said.outcome.isOK, "the schema has no such word")
        #expect(probe.seen.withLock { $0.isEmpty })
        // A client calling itself anything is still that client.
        let named = Probe(risk: .low)
        _ = await call(named, as: .external(client: "user"), tainted: false)
        #expect(lastSeen(named) == false)
    }

    @Test func thePersonsOwnCallIsntIt() async {
        let probe = Probe()
        _ = await call(probe, as: .user)
        #expect(lastSeen(probe) == false)
    }
}
