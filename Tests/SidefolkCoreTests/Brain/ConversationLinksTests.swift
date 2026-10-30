import Foundation
import Testing
@testable import SidefolkCore

/// The way back from an Activity row or a note to the conversation it came from (D58), through the real agent loop
/// and tools: a note saved in one conversation and changed in another knows both, and forgets one that's deleted.
@Suite struct ConversationLinksTests {
    let runtime: SidefolkRuntime
    let clock = ManualClock(TestEnv.referenceDate)

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-links-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: clock)
    }

    func agent(_ model: ScriptedModel) -> AgentRuntime {
        var settings = AppSettings()
        settings.provider.kind = .anthropic
        let clock = self.clock
        let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
        let context = ContextBuilder(notebook: runtime.notebook, exchanges: runtime.exchanges, clock: clock)
        return AgentRuntime(executor: runtime.executor, db: runtime.db, events: runtime.events, context: context, factory: factory,
                            settings: { [settings] in settings }, clock: clock)
    }

    func ask(_ agent: AgentRuntime, _ text: String) async -> String? {
        let handle = await agent.submit(AgentRequest(text: text))
        for await _ in handle.events {}
        return handle.threadId
    }

    @Test func aNoteKnowsTheConversationsItCameFromAndWasChangedIn() async throws {
        let saving = ScriptedModel([
            .turn(.calling([ToolCall(id: "c1", name: "notes_save", input: ["text": "Tea ideas\nGenmaicha, hojicha"])])),
            .turn(.reply("Saved it to your Inbox.")),
        ])
        let first = agent(saving)
        let madeIn = try #require(await ask(first, "Save my tea ideas"))
        let item = try #require(try await runtime.notebook.search("Tea ideas").first)
        #expect(item.runId != nil)

        let changing = ScriptedModel([
            .turn(.calling([ToolCall(id: "c2", name: "notes_update", input: ["id": .string(item.id), "text": "Tea ideas\nGenmaicha, hojicha, sencha"])])),
            .turn(.reply("Added sencha.")),
        ])
        clock.advance(4 * 3600)
        let second = agent(changing)
        let changedIn = try #require(await ask(second, "Add sencha to my tea ideas"))
        #expect(changedIn != madeIn)
        #expect(try await runtime.notebook.item(id: item.id)?.body == "Genmaicha, hojicha, sencha")

        let links = try await runtime.exchanges.conversations(about: item)
        #expect(links.madeIn?.id == madeIn)
        #expect(links.madeIn?.title == "Save my tea ideas")
        #expect(links.changedIn.map(\.id) == [changedIn])

        // Each Activity row of either run leads to its conversation.
        let rows = try await runtime.activity.recent().filter { $0.tool.hasPrefix("notes.") }
        let byRun = try await runtime.exchanges.conversations(ofRuns: rows.compactMap(\.runId))
        #expect(Set(rows.compactMap { $0.runId.flatMap { byRun[$0]?.id } }) == [madeIn, changedIn])

        // A deleted conversation is no longer a place to go back to.
        try await first.deleteConversation(madeIn)
        let after = try await runtime.exchanges.conversations(about: item)
        #expect(after.madeIn == nil)
        #expect(after.changedIn.map(\.id) == [changedIn])
    }

    @Test func aChangeThatDidNotHappenIsNoLink() async throws {
        _ = await LocalIntentRunner(runtime: runtime).run(.note(kind: .note, text: "Tea ideas", collection: nil))
        let item = try #require(try await runtime.notebook.search("Tea ideas").first)
        let searching = ScriptedModel([
            .turn(.calling([ToolCall(id: "c1", name: "notes_search", input: ["query": "tea"])])),
            .turn(.reply("You have tea ideas.")),
        ])
        _ = await ask(agent(searching), "Any tea ideas?")
        let run = try #require(try await runtime.activity.recent().first { $0.tool == "notes.search" }?.runId)
        // The same conversation tried to change it, and the change failed or was refused.
        for decision in [ActivityEntry.Decision.failed, .denied, .skipped] {
            _ = try await runtime.activity.log(ActivityEntry(caller: "agent", tool: "notes.update", risk: "low", decision: decision,
                                                             summary: "Change “Tea ideas”", args: .object(["id": .string(item.id)]),
                                                             error: "It didn't happen.", runId: run))
        }
        #expect(try await runtime.exchanges.conversations(about: item) == ItemConversations())
    }

    @Test func notesSavedWithoutAConversationHaveNoLinks() async throws {
        // Saved by the person (a typed request without AI), and searched by a run that doesn't change it.
        _ = await LocalIntentRunner(runtime: runtime).run(.note(kind: .note, text: "Call the bank", collection: nil))
        let item = try #require(try await runtime.notebook.search("Call the bank").first)
        #expect(item.runId == nil)

        let searching = ScriptedModel([
            .turn(.calling([ToolCall(id: "c1", name: "notes_search", input: ["query": "bank"])])),
            .turn(.reply("You have a note about calling the bank.")),
        ])
        _ = await ask(agent(searching), "Do I have anything about the bank?")
        #expect(try await runtime.exchanges.conversations(about: item) == ItemConversations())
    }
}
