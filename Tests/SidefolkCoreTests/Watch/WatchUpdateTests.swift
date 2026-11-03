import Foundation
import Testing
@testable import SidefolkCore

/// Changing a watcher in place, and that it never gets past a limit that way (T4, T24).
@Suite struct WatchUpdateTests {
    let env: WatchEnv
    let engine: WatcherEngine
    let codex = Caller.external(client: "codex")

    init() throws {
        env = try WatchEnv()
        engine = env.reportEngine(FakeSampler())
    }

    func run(_ tool: String, _ input: JSONValue, as caller: Caller = .user) async -> ToolOutcome {
        await env.base.executor.execute(name: tool, input: input, caller: caller, mentions: UserMentions(text: input["target"]?.stringValue ?? ""))
    }

    func page(as caller: Caller = .user) async throws -> Watcher {
        let made = await run("watch.create", ["kind": "url_change", "target": "https://example.com", "title": "Prices"], as: caller)
        #expect(made.isOK, "\(made.status)")
        return try #require(await engine.list().first { $0.title == "Prices" })
    }

    @Test func aWatchChangesInPlaceAndUndoTakesItBack() async throws {
        let w = try await page()
        let outcome = await run("watch.update", ["id": .string(w.id), "title": "Pricing", "interval_minutes": 60, "level": "gentle", "mode": "repeat", "contains": "Sold out"])
        #expect(outcome.isOK, "\(outcome.status)")
        let after = try #require(await engine.watcher(id: w.id))
        #expect(after.title == "Pricing")
        #expect(after.intervalS == 3600)
        #expect(after.level == .gentle)
        #expect(after.mode == .repeat)
        #expect(after.condition.string("contains") == "Sold out")
        #expect(after.createdAt == w.createdAt)

        _ = try await env.base.executor.undo.undo(outcome.activity.id)
        let back = try #require(await engine.watcher(id: w.id))
        #expect(back.title == "Prices")
        #expect(back.intervalS == w.intervalS)
        #expect(back.level == w.level)
        #expect(back.mode == w.mode)
        #expect(back.condition.string("contains") == nil)
    }

    @Test func wordsForAnotherKindOfWatchAreRefused() async throws {
        let w = try await page()
        let wrong = await run("watch.update", ["id": .string(w.id), "becomes": "up"])
        #expect(!wrong.isOK)
        // A new address is a new watch: a change here can't point at something else after the fact.
        let address = await run("watch.update", ["id": .string(w.id), "target": "https://other.example"], as: .agent(runId: "r"))
        #expect(!address.isOK)
        #expect(await engine.watcher(id: w.id)?.config.string("url")?.contains("example.com") == true)
    }

    // MARK: No limit moves

    @Test func theFloorHoldsForEveryone() async throws {
        let w = try await page()
        #expect(await run("watch.update", ["id": .string(w.id), "interval_minutes": 0.01]).isOK)
        #expect(await engine.watcher(id: w.id)?.intervalS == 300)
    }

    @Test func anAgentCantRaiseItsOwnLevel() async throws {
        let w = try await page(as: codex)
        #expect(await run("watch.update", ["id": .string(w.id), "level": "critical"], as: codex).isOK)
        #expect(await engine.watcher(id: w.id)?.level == .attention)
        // Whoever asks: only the person's own watcher can be critical.
        _ = try await engine.edit(w.id, WatchEdit(level: .critical))
        #expect(await engine.watcher(id: w.id)?.level == .attention)
    }

    @Test func anAgentsWatchNeverLastsLongerForAChange() async throws {
        let w = try await page(as: codex)
        env.clock.advance(3600)
        #expect(await run("watch.update", ["id": .string(w.id), "mode": "repeat", "interval_minutes": 60], as: codex).isOK)
        #expect(await engine.watcher(id: w.id)?.expiresAt == w.expiresAt)
    }

    @Test func aChangeGivesAgentsNoMoreRoom() async throws {
        let before = await engine.externalRoom
        let w = try await page(as: codex)
        #expect(await run("watch.update", ["id": .string(w.id), "title": "Other", "interval_minutes": 30, "mode": "repeat"], as: codex).isOK)
        #expect(await engine.externalRoom == before)
    }

    @Test func aLiveValueMadeFastStopsAsSoonAsAFastOneWould() async throws {
        let made = await run("watch.report", ["source": "metric", "metric": "cpu", "every_seconds": 120], as: codex)
        #expect(made.isOK)
        let w = try #require(await engine.list().first)
        #expect(await run("watch.update", ["id": .string(w.id), "interval_minutes": 0.5], as: codex).isOK)
        let after = try #require(await engine.watcher(id: w.id))
        #expect(after.intervalS == 30)
        #expect(after.expiresAt == env.clock.now.addingTimeInterval(WatchLimits.fastReportLifetime))
        #expect(!(await run("watch.update", ["id": .string(w.id), "mode": "repeat"], as: codex)).isOK, "a live value stays one")
    }

    @Test func anAgentReachesOnlyItsOwn() async throws {
        let w = try await page()
        #expect(!(await run("watch.update", ["id": .string(w.id), "title": "Mine now"], as: codex)).isOK)
        #expect(await engine.watcher(id: w.id)?.title == "Prices")
    }

    // MARK: What other agents are told

    @Test func otherAgentsAreNotOfferedCritical() async throws {
        let tool = try #require(env.base.registry.tool(named: "watch.update"))
        let spec = ExternalToolPolicy.externalSpec(tool.spec)
        #expect(spec.inputSchema["properties"]?["level"]?["enum"] == ["gentle", "attention"])
        #expect(spec.description.contains("never makes it last longer"))
        // As D116 has it: their own watchers, by the save setting; only room is always asked.
        #expect(ExternalToolPolicy.saving.contains("watch.update"))
        #expect(!ExternalToolPolicy.alwaysAsks.contains("watch.update"))
    }
}
