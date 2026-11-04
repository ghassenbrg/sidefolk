import Foundation
import Testing
@testable import SidefolkCore

/// A card from another agent reading the notebook can open "Read your notes and reminders" for all agents (D185): the
/// group setting Trust shows, not a grant for one agent, whose name is its own (T4). Nothing else can.
@Suite struct AgentsReadFlipTests {
    let runtime: SidefolkRuntime

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-flip-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: ManualClock(TestEnv.referenceDate))
    }

    /// Calls as another agent and answers its card with `decision`; the card, if one came.
    func call(_ tool: String, client: String = "claude-code", answer decision: ApprovalDecision) async -> (ToolOutcome, ApprovalRequest?) {
        let stream = runtime.events.stream()
        let runtime = self.runtime
        let asked = Task { () -> ApprovalRequest? in
            for await event in stream {
                if case .approvalRequested(let r) = event {
                    await runtime.answer(r, decision)
                    return r
                }
            }
            return nil
        }
        let outcome = await runtime.gateway.call(tool, input: [:], client: client)
        asked.cancel()
        return (outcome, await asked.value)
    }

    @Test func theCardOffersItAndTheChoiceOpensTheGroup() async throws {
        #expect(await runtime.settings.current.agentAccess.read == .ask)
        let first = await call("notes.list", answer: .allowAgentsToRead)
        #expect(first.1?.canAllowAgentsToRead == true)
        #expect(first.0.isOK)
        #expect(await runtime.settings.current.agentAccess.read == .allow)
        // The next call, from any agent, runs without a card.
        let second = await call("notes.list", client: "codex", answer: .deny)
        #expect(second.1 == nil && second.0.isOK)
        // Only that group: the others stay as they were.
        let access = await runtime.settings.current.agentAccess
        #expect(access.save == .allow && access.change == .allow && access.extensions == .ask)
    }

    @Test func allowOnceLeavesTheSettingAlone() async throws {
        let first = await call("notes.list", answer: .allowOnce)
        #expect(first.0.isOK)
        #expect(await runtime.settings.current.agentAccess.read == .ask)
        let second = await call("notes.list", answer: .deny)
        #expect(second.1 != nil && !second.0.isOK)
    }

    @Test func noOtherCardOffersItAndAForgedChoiceOnlyAllowsOnce() async throws {
        // Another agent changing someone else's record, a collection, more room: never the offer.
        let more = await call("watch.more_room", answer: .allowAgentsToRead)
        #expect(more.1?.canAllowAgentsToRead == false)
        #expect(await runtime.settings.current.agentAccess.read == .ask)
        // Sidefolk's own agent: its cards never have it.
        var card = ApprovalRequest(tool: "notes.list", title: "t", summary: "s", risk: .medium, caller: .agent(runId: "r"), details: .none, canAlways: true)
        card.canAllowAgentsToRead = true
        let forged = card
        let id = forged.id
        let stream = runtime.events.stream()
        let broker = runtime.broker
        let waiting = Task { () -> ApprovalDecision in await broker.request(forged, timeout: 5) }
        for await event in stream { if case .approvalRequested(let r) = event, r.id == id { break } }
        await runtime.answer(forged, .allowAgentsToRead)
        #expect(await waiting.value == .allowOnce)
        #expect(await runtime.settings.current.agentAccess.read == .ask)
    }
}
