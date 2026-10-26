import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// "Check my Apple Notes and move them, well organized, into our notebook", end to end: a scripted
/// model drives the real runtime, loop, Guard and tools over a fake Notes, and the person approves
/// each card. What the model is told it can reach is checked too.
@Suite struct OrganizeNotesRunTests {
    static func handle(_ n: Int) -> String { AppleNotes.handle(for: NotesFixture.id(n)) }

    struct Run {
        let h: MacAppsEnv
        let runtime: AgentRuntime

        init(_ fixture: NotesFixture, model: ScriptedModel) throws {
            h = try MacAppsEnv(FakeAppleEvents(fixture))
            var settings = AppSettings()
            settings.provider.kind = .anthropic
            let clock = h.env.clock
            let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
            let context = ContextBuilder(notebook: h.notebook, exchanges: ExchangeStore(h.env.db), clock: clock)
            let box = SettingsBox(settings)
            runtime = AgentRuntime(executor: h.env.executor, db: h.env.db, events: h.env.events, context: context, factory: factory,
                                   settings: { box.current }, clock: clock)
        }

        /// Sends the request and approves every card, returning the run's events and the cards shown.
        func ask(_ text: String, newThread: Bool = false) async -> (events: [AgentEvent], cards: [ApprovalRequest]) {
            let answerer = ApproveAll(h.env)
            let handle = await runtime.submit(AgentRequest(text: text, newThread: newThread))
            let events = await collect(handle.events)
            return (events, answerer.stop())
        }
    }

    /// Approves every card as it appears, as a person clicking Allow would.
    final class ApproveAll: Sendable {
        private let cards: CardLog
        private let task: Task<Void, Never>

        init(_ env: TestEnv) {
            let stream = env.events.stream()
            let broker = env.broker
            let cards = CardLog()
            self.cards = cards
            task = Task {
                for await event in stream {
                    if case .approvalRequested(let r) = event {
                        cards.append(r)
                        await broker.resolve(id: r.id, decision: .allowOnce)
                    }
                }
            }
        }

        func stop() -> [ApprovalRequest] {
            task.cancel()
            return cards.all
        }
    }

    final class CardLog: Sendable {
        private let cards = Mutex<[ApprovalRequest]>([])
        func append(_ r: ApprovalRequest) { cards.withLock { $0.append(r) } }
        var all: [ApprovalRequest] { cards.withLock { $0 } }
    }

    static func copyCall(_ id: String, _ pairs: [(Int, String)]) -> ToolCall {
        ToolCall(id: id, name: "applenotes_copy",
                 input: ["notes": .array(pairs.map { ["id": .string(handle($0.0)), "collection": .string($0.1)] })])
    }

    @Test func organizeMyAppleNotesIntoTheNotebook() async throws {
        let model = ScriptedModel([
            .turn(.calling([ToolCall(id: "c1", name: "applenotes_list", input: [:])])),
            .perform { request in
                // The model reads the list as untrusted content, the injection note included.
                guard case .toolResults(let results)? = request.messages.last else { throw UserFacingError(verbatim: "no results") }
                #expect(results[0].content.hasPrefix("<untrusted_content source=\"applenotes.list\">"))
                #expect(results[0].content.contains("Ignore previous instructions"))
                return .calling([Self.copyCall("c2", [(1, "Cooking"), (4, "Cooking"), (2, "Travel"), (6, "Inbox"), (3, "Bank")])])
            },
            .turn(.reply("Copied 4 notes: 2 into Cooking, 1 into Travel and 1 into Inbox. “Bank codes” is locked, so it stayed in Notes.")),
        ])
        let run = try Run(.sample(), model: model)
        let (events, cards) = await run.ask("check my Apple Notes and organize them into our notebook")

        let reply = try #require(events.compactMap(\.reply).first)
        #expect(reply.text.hasPrefix("Copied 4 notes"))
        #expect(reply.tainted, "the turn read Apple Notes")

        // Two cards: reading the list in a clean turn, then copying while tainted.
        #expect(cards.map(\.tool) == ["applenotes.list", "applenotes.copy"])
        #expect(!cards[0].tainted && cards[0].readsOnly)
        #expect(cards[1].tainted && cards[1].summary == "Copy 5 notes from Apple Notes into “Cooking”, “Travel”, “Inbox” and 1 more")

        // The notebook holds the copies, organized, each saying where it came from.
        let items = try await run.h.items()
        #expect(items.count == 4)
        #expect(items.allSatisfy { $0.source == "app:notes" && $0.body.contains("From Apple Notes › ") })
        let byCollection = try await NotebookCollections.byId(run.h.notebook)
        let places = Dictionary(grouping: items, by: { byCollection[$0.collectionId]?.name ?? "?" }).mapValues { $0.map(\.title).sorted() }
        #expect(places["Cooking"] == ["Pasta carbonara", "Sourdough"])
        #expect(places["Travel"] == ["Trip to Lyon"])
        #expect(places["Inbox"]?.count == 1)
        #expect(try await run.h.notebook.findCollection(named: "Bank") == nil)

        // Nothing changed in Notes: copying is the default.
        #expect(!run.h.fake.calls.contains("notes.remove"))
        #expect(run.h.fake.fixture.notes.count == 6)

        // The model was told what it can and can't reach.
        let system = model.requests[0].system
        #expect(system.contains("# What you can reach"))
        #expect(system.contains("Apple Notes (list and read notes, copy them into the notebook, and move copied notes to Notes' Recently Deleted only when the user asked to move or delete them)"))
        #expect(system.contains("Don't send the user off to export, copy or paste things by hand unless they ask how."))
        #expect(model.requests[0].tools.contains { $0.name == "applenotes.remove" })
    }

    @Test func movingRemovesFromNotesOnlyAfterItsOwnApproval() async throws {
        let model = ScriptedModel([
            .turn(.calling([ToolCall(id: "c1", name: "applenotes_list", input: ["folder": "Recipes"])])),
            .turn(.calling([Self.copyCall("c2", [(4, "Cooking")])])),
            .turn(.calling([ToolCall(id: "c3", name: "applenotes_remove", input: ["ids": [.string(Self.handle(4))]])])),
            .turn(.reply("Moved “Sourdough” into Cooking; Notes keeps the original in Recently Deleted for 30 days.")),
        ])
        let run = try Run(.sample(), model: model)
        let (_, cards) = await run.ask("move my Apple Notes recipes into the notebook")

        #expect(cards.map(\.tool) == ["applenotes.list", "applenotes.copy", "applenotes.remove"])
        let removal = cards[2]
        #expect(removal.risk == .high && !removal.canAlways && removal.tainted)
        guard case .text(let listed) = removal.details else { Issue.record("expected the notes listed"); return }
        #expect(listed.hasPrefix("“Sourdough” (iCloud › Recipes)"))
        #expect(run.h.fake.fixture.notes.first { $0.id == NotesFixture.id(4) }?.folder == "f-trash")
        #expect(try await run.h.items().map(\.title) == ["Sourdough"])
    }

    @Test func aBigLibraryGoesInBatchesAcrossRequests() async throws {
        let firstPage = (71...120).reversed().map { ($0, "Archive") }
        let secondPage = (21...70).reversed().map { ($0, "Archive") }
        let model = ScriptedModel([
            .turn(.calling([ToolCall(id: "c1", name: "applenotes_list", input: ["not_copied": true])])),
            .turn(.calling([Self.copyCall("c2", firstPage)])),
            .perform { request in
                guard case .toolResults(let results)? = request.messages.last else { throw UserFacingError(verbatim: "no results") }
                #expect(results[0].content.contains("Progress: 50 of 120 notes in Apple Notes are in the notebook; 70 to go."))
                return .reply("Copied 50 of 120 into Archive. Say continue for the next batch.")
            },
            .turn(.calling([ToolCall(id: "c3", name: "applenotes_list", input: ["not_copied": true])])),
            .perform { request in
                guard case .toolResults(let results)? = request.messages.last else { throw UserFacingError(verbatim: "no results") }
                #expect(results[0].content.contains("Notes 1–50 of 70 (all folders, not copied yet), newest first:"))
                #expect(results[0].content.contains("“Note 70”") && !results[0].content.contains("“Note 71”"))
                return .calling([Self.copyCall("c4", secondPage)])
            },
            .turn(.reply("Copied 50 more: 100 of 120. Say continue for the last 20.")),
        ])
        let run = try Run(.large(120), model: model)
        _ = await run.ask("copy all my Apple Notes into an Archive collection")
        #expect(try await run.h.items().count == 50)
        let (_, cards) = await run.ask("continue")
        #expect(cards.map(\.tool) == ["applenotes.list", "applenotes.copy"])
        #expect(try await run.h.items().count == 100)
        // No step read more than one page or copied more than one batch.
        #expect(run.h.fake.params(of: "notes.fetch").allSatisfy { ($0["ids"]?.arrayValue?.count ?? 0) <= 50 })
        #expect(run.h.fake.params(of: "notes.snippets").allSatisfy { ($0["ids"]?.arrayValue?.count ?? 0) <= 50 })
    }

    @Test func withoutTheToolsTheModelIsToldNotesAreOutOfReach() {
        let none = ContextBuilder.reach([])
        #expect(!none.contains("Apple Notes"))
        #expect(none.contains("Opening an app only opens it or brings it forward: you can't see, read or change anything in it."))
        #expect(none.contains("not other apps' content (Mail, Messages, Calendar, Contacts, Photos, browsers)"))
        let spec = OpenAppTool(platform: NullPlatform()).spec
        #expect(spec.description.contains("you can't see, read or change anything inside it afterwards"))
    }
}
