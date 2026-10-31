import Foundation
import Testing
@testable import SidefolkCore

/// Conversations you can come back to, start fresh or forget (D45).
@Suite struct ConversationsTests {
    typealias Harness = AgentRuntimeTests.Harness

    @Test func aNamedConversationContinuesAfterTheWindow() async throws {
        let model = ScriptedModel([.turn(.reply("One.")), .turn(.reply("Two.")), .turn(.reply("Three."))])
        let h = try Harness(model)

        let (first, _) = await h.run(AgentRequest(text: "First"))
        h.env.clock.advance(3 * 3600)
        let (implicit, _) = await h.run(AgentRequest(text: "Second"))
        let (named, _) = await h.run(AgentRequest(text: "And the first?", threadId: first.threadId))

        #expect(implicit.threadId != first.threadId)
        #expect(named.threadId == first.threadId)
        #expect(model.requests[2].messages.map(\.plainText) == ["First", "One.", "And the first?"])
        // Continuing it makes it the current conversation again, under the usual window.
        #expect(await h.runtime.activeThreadId == first.threadId)
    }

    @Test func aDeletedConversationIsNeverContinued() async throws {
        let model = ScriptedModel([.turn(.reply("One.")), .turn(.reply("Two."))])
        let h = try Harness(model)

        let (first, _) = await h.run(AgentRequest(text: "First"))
        try await h.runtime.deleteConversation(first.threadId)
        let (again, _) = await h.run(AgentRequest(text: "Again", threadId: first.threadId))

        #expect(again.threadId != first.threadId)
        #expect(model.requests[1].messages.count == 1)
        #expect(try await ExchangeStore(h.env.db).conversations().map(\.title) == ["Again"])
    }

    @Test func startingFreshKeepsTheEarlierConversation() async throws {
        let model = ScriptedModel([.turn(.reply("One.")), .turn(.reply("Two."))])
        let h = try Harness(model)

        let (first, _) = await h.run(AgentRequest(text: "First"))
        await h.runtime.endThread()
        h.env.clock.advance(60)
        let (second, _) = await h.run(AgentRequest(text: "Second"))

        #expect(second.threadId != first.threadId)
        #expect(model.requests[1].messages.count == 1)
        #expect(try await ExchangeStore(h.env.db).conversations().map(\.title) == ["Second", "First"])
    }

    @Test func deletingTheCurrentConversationStartsFresh() async throws {
        let model = ScriptedModel([.turn(.reply("One.")), .turn(.reply("Two.")), .turn(.reply("Three."))])
        let h = try Harness(model)
        let exchanges = ExchangeStore(h.env.db)

        let (kept, _) = await h.run(AgentRequest(text: "Keep me"))
        await h.runtime.endThread()
        let (gone, _) = await h.run(AgentRequest(text: "Forget me"))
        try await h.runtime.deleteConversation(gone.threadId)
        let (next, _) = await h.run(AgentRequest(text: "Next"))

        #expect(next.threadId != gone.threadId)
        #expect(model.requests[2].messages.count == 1)
        #expect(try await exchanges.contains(threadId: kept.threadId))
        #expect(try await !exchanges.contains(threadId: gone.threadId))
        #expect(await h.runtime.lastSent()?.messages.map(\.text) == ["Next"])
    }

    @Test func deletingARunningConversationStopsItFirst() async throws {
        let model = ScriptedModel([.perform { _ in
            try await Task.sleep(for: .seconds(30))
            return .reply("late")
        }])
        let h = try Harness(model)

        let handle = await h.runtime.submit(AgentRequest(text: "Take your time"))
        try await Task.sleep(for: .milliseconds(100))
        try await h.runtime.deleteConversation(handle.threadId)
        _ = await collect(handle.events)

        // The run's last note was written before the deletion, so nothing of it is left.
        #expect(try await ExchangeStore(h.env.db).count() == 0)
    }

    @Test func deletingAllForgetsEverything() async throws {
        let model = ScriptedModel([.turn(.reply("One.")), .turn(.reply("Two.")), .turn(.reply("Three."))])
        let h = try Harness(model)

        let (first, _) = await h.run(AgentRequest(text: "First"))
        await h.runtime.endThread()
        _ = await h.run(AgentRequest(text: "Second"))
        let changes = h.env.events.stream()
        try await h.runtime.deleteAllConversations()
        let (third, _) = await h.run(AgentRequest(text: "Third", threadId: first.threadId))

        #expect(third.threadId != first.threadId)
        #expect(model.requests[2].messages.count == 1)
        #expect(try await ExchangeStore(h.env.db).conversations().map(\.title) == ["Third"])
        var told = false
        for await event in changes {
            if case .dataChanged(.conversations) = event { told = true; break }
        }
        #expect(told)
    }

    @Test func summariesNameEachConversationByItsFirstRequest() async throws {
        let env = try TestEnv()
        let store = ExchangeStore(env.db)
        let t0 = env.clock.now
        func add(_ thread: String, _ role: Exchange.Role, _ text: String, _ minutes: Double, spoken: Bool = false) async throws {
            let meta: JSONValue? = role == .user ? ExchangeMeta.user(attachment: nil, tainted: false, spoken: spoken) : nil
            try await store.append(Exchange(threadId: thread, role: role, content: text, meta: meta, now: t0.addingTimeInterval(minutes * 60)))
        }
        try await add("a", .user, "Plan my week", 0)
        try await add("a", .assistant, "Monday: the 50% review, then gym.", 1)
        try await add("a", .user, "Move the gym to Tuesday", 2)
        try await add("b", .user, "What's the weather like?", 10, spoken: true)
        try await add("b", .assistant, "Sunny.", 11)
        try await add("c", .event, "Stopped. Nothing was changed.", 20)

        let all = try await store.conversations()
        #expect(all.map(\.id) == ["b", "a"])
        #expect(all.map(\.title) == ["What's the weather like?", "Plan my week"])
        #expect(all.map(\.requests) == [1, 2])
        #expect(all.map(\.spoken) == [true, false])
        #expect(all[1].startedAt == t0 && all[1].updatedAt == t0.addingTimeInterval(120))

        // Every word, in a request or a reply; what is typed is literal.
        #expect(try await store.conversations(matching: "gym tuesday").map(\.id) == ["a"])
        #expect(try await store.conversations(matching: "sunny").map(\.id) == ["b"])
        #expect(try await store.conversations(matching: "50%").map(\.id) == ["a"])
        #expect(try await store.conversations(matching: "5_%").isEmpty)
        #expect(try await store.conversations(matching: "rain").isEmpty)
    }

    @Test func theTranscriptPutsEachStepBeforeItsReply() async throws {
        let model = ScriptedModel([.turn(.calling([call("c1")])), .turn(.reply("Saved to Ideas.")), .turn(.reply("You're welcome."))])
        let h = try Harness(model)

        let (first, _) = await h.run(AgentRequest(text: "Save tea as an idea"))
        h.env.clock.advance(60)
        _ = await h.run(AgentRequest(text: "Thanks"))
        let exchanges = try await ExchangeStore(h.env.db).conversation(first.threadId)
        let steps = try await ActivityStore(h.env.db).steps(ofRuns: ConversationTranscript.runIds(exchanges))
        let lines = ConversationTranscript.lines(exchanges, steps: steps)

        #expect(lines.map(\.text) == ["Save tea as an idea", steps[0].summary, "Saved to Ideas.", "Thanks", "You're welcome."])
        #expect(lines.map(\.kind) == [.request(spoken: false, attachment: nil), .step(done: true), .reply(tainted: false),
                                      .request(spoken: false, attachment: nil), .reply(tainted: false)])
    }

    @Test func aTranscriptShowsFailuresAndRunsStillGoing() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let exchanges = [
            Exchange(id: "1", threadId: "t", role: .user, content: "Rename the invoices",
                     meta: ExchangeMeta.user(attachment: AgentAttachment(text: "…", source: "Invoices", untrusted: true), tainted: false), now: t0),
            Exchange(id: "2", threadId: "t", role: .event, content: "Stopped. Nothing was changed.", meta: ["runId": "r1"], now: t0 + 5),
            Exchange(id: "3", threadId: "t", role: .user, content: "Try again", meta: ExchangeMeta.user(attachment: nil, tainted: false), now: t0 + 9),
            Exchange(id: "4", threadId: "t", role: .event, content: "The AI didn't answer.", meta: ["runId": "r2", "outcome": "failed"], now: t0 + 12),
        ]
        let steps = [
            ActivityEntry(at: t0 + 2, caller: "agent", tool: "files.rename", risk: "medium", decision: .denied, summary: "Rename 3 files",
                          error: "You said not now.", runId: "r1"),
            ActivityEntry(at: t0 + 10, caller: "agent", tool: "files.list", risk: "low", decision: .auto, summary: "List Invoices", runId: "r2"),
        ]

        let lines = ConversationTranscript.lines(exchanges, steps: steps)

        #expect(lines.map(\.text) == ["Rename the invoices", "Rename 3 files", "Stopped. Nothing was changed.", "Try again", "List Invoices",
                                      "The AI didn't answer."])
        // Only a run that broke is a failure; a stopped one is drawn calm.
        #expect(lines.map(\.kind) == [.request(spoken: false, attachment: "Invoices"), .step(done: false), .note(failed: false),
                                      .request(spoken: false, attachment: nil), .step(done: true), .note(failed: true)])
        #expect(lines.map(\.detail) == [nil, "You said not now.", nil, nil, nil, nil])
    }

    @Test(arguments: ["new conversation", "New chat", "start fresh", "let's start over", "start a new conversation", "Forget this conversation",
                      "clear the chat", "change the subject", "new topic please", "Pip, start over!"])
    func freshStartWords(_ text: String) {
        let parsed = IntentParser().parse(text, now: TimeTest.wednesday10)
        #expect(parsed?.intent == .newConversation, "\(text)")
        #expect(parsed?.hint.hasSuffix("no AI") == true)
    }

    @Test(arguments: ["start over the report from scratch", "a new chat app idea", "clear my history", "delete all conversations",
                      "remind me to start fresh tomorrow", "what's a good topic for a new conversation?"])
    func notAFreshStart(_ text: String) {
        #expect(IntentParser().parse(text, now: TimeTest.wednesday10)?.intent != .newConversation, "\(text)")
    }
}
