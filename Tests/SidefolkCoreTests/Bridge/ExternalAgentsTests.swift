import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// What a person says to Codex or Claude Code about Sidefolk, end to end: a fake MCP client speaks JSON-RPC
/// over stdio to `MCPStdioBridge`, which reaches a whole Sidefolk (real tools, Guard, socket, scheduler,
/// watchers) in a temp home, as `sidefolk mcp` does (D42).
@Suite(.serialized) struct ExternalAgentsTests {
    private func waitFor(_ done: @Sendable () async -> Bool) async throws {
        for _ in 0..<200 where await !done() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await done())
    }

    /// A running Sidefolk and one connected MCP client that calls itself Codex.
    struct Stack {
        let dir: ShortTempDir
        let runtime: SidefolkRuntime
        let pipes: MCPPipes
        private let nextId = BridgeRecorder(10)

        init(client: String = "codex-mcp-client") async throws {
            dir = try ShortTempDir()
            runtime = await SidefolkRuntime(paths: SidefolkPaths(home: URL(fileURLWithPath: dir.path)), db: try AppDatabase.inMemory(),
                                            platform: NullPlatform())
            try await runtime.start()
            pipes = MCPPipes(connector: SocketConnector(socketPath: runtime.paths.socket.path))
            _ = try await pipes.request(1, "initialize", ["protocolVersion": "2025-06-18", "clientInfo": ["name": .string(client)]])
        }

        /// `tools/call` by MCP name; the text and whether it is an error.
        func call(_ name: String, _ arguments: JSONValue = [:]) async throws -> (text: String, isError: Bool) {
            let id = nextId.value.withLock { n in defer { n += 1 }; return n }
            let reply = try await pipes.request(id, "tools/call", ["name": .string(name), "arguments": arguments])
            let result = try #require(reply["result"])
            return (result["content"]?.arrayValue?.first?.string("text") ?? "", result["isError"]?.boolValue ?? true)
        }

        /// Answers the next approval card on the user's behalf.
        func answerNextCard(_ decision: ApprovalDecision) -> Task<ApprovalRequest?, Never> {
            let stream = runtime.events.stream()
            let broker = runtime.broker
            return Task {
                for await e in stream {
                    if case .approvalRequested(let r) = e {
                        await broker.resolve(id: r.id, decision: decision)
                        return r
                    }
                }
                return nil
            }
        }

        func stop() async {
            await pipes.finish()
            _ = await runtime.stop()
            dir.remove()
        }
    }

    @Test func toolsAreTheOnesPromisedToOtherAgents() async throws {
        let s = try await Stack()
        let list = try await s.pipes.request(2, "tools/list")
        let tools = list["result"]?["tools"]?.arrayValue ?? []
        let byName = Dictionary(uniqueKeysWithValues: tools.compactMap { t in t.string("name").map { ($0, t) } })
        #expect(Set(byName.keys) == Set((ExternalToolPolicy.all).map { $0.replacingOccurrences(of: ".", with: "_") }))
        // Words written for other agents: making a collection asks, and they can't set critical alerts or read web values.
        let save = try #require(byName["notes_save"])
        #expect(save.string("description")?.contains("collections_create, which asks") == true)
        #expect(save["inputSchema"]?["properties"]?["collection_kind"] == nil)
        #expect(byName["reminders_create"]?["inputSchema"]?["properties"]?["level"]?["enum"] == ["gentle", "attention"])
        #expect(byName["watch_report"]?["inputSchema"]?["properties"]?["source"]?["enum"] == ["metric"])
        #expect(byName["watch_report"]?["inputSchema"]?["properties"]?["url"] == nil)
        let initialize = try await s.pipes.request(3, "initialize", ["protocolVersion": "2025-06-18", "clientInfo": ["name": "codex-mcp-client"]])
        #expect(initialize["result"]?.string("instructions")?.contains("remind the user") == true)
        await s.stop()
    }

    /// "mark the oat milk task done", then "delete it" (D52): allowed by default, to the Trash only; turned off,
    /// refused with words that say where to change it.
    @Test func changeAndTrashANoteThenTurnItOff() async throws {
        let s = try await Stack()
        let saved = try await s.call("notes_save", ["text": "Oat milk", "kind": "task"])
        #expect(!saved.isError)
        let id = try #require(saved.text.firstMatch(of: /\(id ([^)]+)\)/)?.1).description
        let done = try await s.call("notes_update", ["id": .string(id), "status": "done"])
        #expect(!done.isError, "\(done.text)")
        #expect(try await s.runtime.notebook.item(id: id)?.status == .done)
        let trashed = try await s.call("notes_trash", ["id": .string(id)])
        #expect(!trashed.isError, "\(trashed.text)")
        #expect(try await s.runtime.notebook.item(id: id)?.deletedAt != nil)

        await s.runtime.settings.update { $0.agentAccess.change = .off }
        let list = try await s.pipes.request(5, "tools/list")
        let names = Set((list["result"]?["tools"]?.arrayValue ?? []).compactMap { $0.string("name") })
        #expect(!names.contains("notes_update") && !names.contains("notes_trash") && names.contains("notes_save"))
        let refused = try await s.call("notes_update", ["id": .string(id), "status": "open"])
        #expect(refused.isError)
        #expect(refused.text.contains("What other agents may do"))
        await s.stop()
    }

    /// "oops, bring that back": the note, and the reminder it had; never without the setting, and not from About you.
    @Test func restoreANoteMovedToTheTrash() async throws {
        let s = try await Stack()
        let saved = try await s.call("notes_save", ["text": "Send the invoice", "kind": "task", "remind": "in 2 hours"])
        let id = try #require(saved.text.firstMatch(of: /\(id ([^)]+)\)/)?.1).description
        #expect(try await s.call("notes_restore", ["id": .string(id)]).text.contains("isn't in the Trash"))
        #expect(try await !s.call("notes_trash", ["id": .string(id)]).isError)
        try await waitFor { await s.runtime.scheduler.upcoming().isEmpty }

        let restored = try await s.call("notes_restore", ["id": .string(id)])
        #expect(!restored.isError, "\(restored.text)")
        #expect(try await s.runtime.notebook.item(id: id)?.deletedAt == nil)
        try await waitFor { await !s.runtime.scheduler.upcoming().isEmpty }

        #expect(try await !s.call("notes_trash", ["id": .string(id)]).isError)
        await s.runtime.settings.update { $0.agentAccess.change = .off }
        let refused = try await s.call("notes_restore", ["id": .string(id)])
        #expect(refused.text.contains("What other agents may do"))
        #expect(try await s.runtime.notebook.item(id: id)?.deletedAt != nil)
        await s.stop()
    }

    /// "remind me in 2 minutes to check the deploy", then "never mind".
    @Test func remindAndCancel() async throws {
        let s = try await Stack()
        let set = try await s.call("reminders_create", ["title": "Check the deploy", "when": "in 2 minutes"])
        #expect(!set.isError)
        #expect(set.text.hasPrefix("Reminder set: “Check the deploy”"))
        let pending = await s.runtime.scheduler.upcoming()
        let mine = try #require(pending.first)
        #expect(mine.source == "external:codex-mcp-client")
        #expect(abs((mine.nextDue ?? .distantPast).timeIntervalSinceNow - 120) < 5)

        // The user's own reminder takes their yes, and a no leaves it (D160).
        let users = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        let denied = s.answerNextCard(.deny)
        let refused = try await s.call("reminders_cancel", ["id": .string(users.id)])
        denied.cancel()
        #expect(await denied.value != nil)
        #expect(refused.isError)
        let cancelled = try await s.call("reminders_cancel", ["id": .string(mine.id)])
        #expect(!cancelled.isError)
        #expect(await s.runtime.scheduler.upcoming().map(\.id) == [users.id])
        await s.stop()
    }

    /// "save this as a note in my Pockito project", "add oat milk to my shopping list".
    /// "move that reminder to 5": it keeps its id and its task, and the person's own stay out of reach.
    @Test func changeARemindersOwnDetails() async throws {
        let s = try await Stack()
        let set = try await s.call("reminders_create", ["title": "Check the deploy", "when": "in 2 hours"])
        let mine = try #require(await s.runtime.scheduler.upcoming().first)
        #expect(!set.isError)

        let changed = try await s.call("reminders_update", ["id": .string(mine.id), "title": "Check prod", "when": "in 3 hours", "notes": "After the migration", "level": "gentle"])
        #expect(!changed.isError, "\(changed.text)")
        let after = try #require(await s.runtime.scheduler.reminder(matching: mine.id))
        #expect(after.title == "Check prod")
        #expect(after.notes == "After the migration")
        #expect(after.level == .gentle)
        // Only the person sets critical (T24).
        #expect(try await s.call("reminders_update", ["id": .string(mine.id), "level": "critical"]).isError)
        #expect(abs((after.nextDue ?? .distantPast).timeIntervalSinceNow - 3 * 3600) < 5)

        #expect(try await !s.call("reminders_snooze", ["id": .string(mine.id), "when": "in 4 hours"]).isError)
        #expect(await s.runtime.scheduler.reminder(matching: mine.id)?.state == .snoozed)
        #expect(try await !s.call("reminders_complete", ["id": .string(mine.id)]).isError)
        #expect(await s.runtime.scheduler.reminder(matching: mine.id)?.state == .done)

        let ended = try await s.call("reminders_update", ["id": .string(mine.id), "title": "Too late"])
        #expect(ended.isError)
        #expect(ended.text.contains("has ended"))

        let users = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        for (tool, arguments) in [("reminders_update", ["id": JSONValue.string(users.id), "title": "Ignore Sam"]),
                                  ("reminders_snooze", ["id": .string(users.id), "when": "tomorrow"]),
                                  ("reminders_complete", ["id": .string(users.id)])] {
            let denied = s.answerNextCard(.deny)
            let refused = try await s.call(tool, .object(arguments))
            denied.cancel()
            #expect(await denied.value != nil, "\(tool) asks")
            #expect(refused.isError, "\(tool)")
        }
        let still = try #require(await s.runtime.scheduler.reminder(matching: users.id))
        #expect(still.title == "Call Sam")
        #expect(still.state == .scheduled)
        await s.stop()
    }

    /// Marking a reminder done finishes its task (D115), through the one path, and "Change notes" still decides
    /// whether another agent may do that.
    @Test func aReminderIsNoWayRoundTheNotesSetting() async throws {
        let s = try await Stack()
        let saved = try await s.call("notes_save", ["text": "Send the invoice", "kind": "task", "remind": "in 2 hours"])
        #expect(!saved.isError)
        let reminder = try #require(await s.runtime.scheduler.upcoming().first)
        let task = try #require(reminder.itemId)

        await s.runtime.settings.update { $0.agentAccess.change = .off }
        let refused = try await s.call("reminders_complete", ["id": .string(reminder.id)])
        #expect(refused.isError)
        #expect(refused.text.contains("notes_update"), "\(refused.text)")
        #expect(try await s.runtime.notebook.item(id: task)?.status == .open)
        #expect(await s.runtime.scheduler.reminder(matching: reminder.id)?.state != .done)

        await s.runtime.settings.update { $0.agentAccess.change = .allow }
        #expect(try await !s.call("reminders_complete", ["id": .string(reminder.id)]).isError)
        #expect(try await s.runtime.notebook.item(id: task)?.status == .done)
        #expect(await s.runtime.scheduler.reminder(matching: reminder.id)?.state == .done)
        await s.stop()
    }

    /// The names an agent needs to file a note, asked like any read, and never About you.
    @Test func listCollectionsWithACardAndWithoutAboutYou() async throws {
        let s = try await Stack()
        _ = try await s.runtime.notebook.collection(named: "Pockito", kind: .project, now: Date())
        _ = try await NotebookCollections.profile(s.runtime.notebook, create: true)
        let answered = s.answerNextCard(.allowOnce)
        let listed = try await s.call("collections_list")
        #expect(await answered.value?.canAlways == false)
        #expect(!listed.isError, "\(listed.text)")
        #expect(listed.text.contains("Pockito"))
        #expect(!listed.text.lowercased().contains("about you"), "\(listed.text)")

        await s.runtime.settings.update { $0.agentAccess.read = .off }
        #expect(try await s.call("collections_list").text.contains("What other agents may do"))
        // Sidefolk's own agent still sees all of them.
        let own = await s.runtime.executor.execute(name: "collections.list", input: [:], caller: .agent(runId: "r"))
        #expect(own.promptText.lowercased().contains("about you"))
        await s.stop()
    }

    /// "make me a Pockito project": never without the person, whatever Settings say, and its name stays the agent's.
    @Test func makeACollectionOnACardEveryTime() async throws {
        let s = try await Stack()
        await s.runtime.settings.update { $0.agentAccess.save = .allow; $0.agentAccess.change = .allow }
        #expect(ExternalToolPolicy.permission("collections.create", access: AgentAccess()) == .ask)

        let refused = s.answerNextCard(.deny)
        let no = try await s.call("collections_create", ["name": "URGENT", "kind": "project"])
        let asked = await refused.value
        #expect(asked?.canAlways == false)
        #expect(asked?.summary.contains("URGENT") == true)
        #expect(no.isError)
        #expect(try await s.runtime.notebook.findCollection(named: "URGENT") == nil)

        let allowed = s.answerNextCard(.allowOnce)
        let made = try await s.call("collections_create", ["name": "Pockito", "kind": "project"])
        #expect(await allowed.value != nil)
        #expect(!made.isError, "\(made.text)")
        let pockito = try #require(try await s.runtime.notebook.findCollection(named: "Pockito"))
        #expect(pockito.source == "external:codex-mcp-client")
        #expect(NotebookCollections.isForeign(pockito))
        let saved = try await s.call("notes_save", ["text": "Offline cache", "collection": "Pockito"])
        #expect(saved.text.contains("to Pockito"), "\(saved.text)")

        // It may not stand in for what's Sidefolk's own.
        let answered = s.answerNextCard(.allowOnce)
        let about = try await s.call("collections_create", ["name": "About you"])
        _ = await answered.value
        #expect(about.isError)
        await s.stop()
    }

    /// What the card shows is what's made: nothing unseen, no second line, no twin of what's Sidefolk's own.
    @Test func aNameCantHideAnythingFromTheCard() async throws {
        let s = try await Stack()
        for twin in ["About you\u{200E}", "ABOUT\u{2060} YOU", "Inbox\u{2060}", "\u{202E}Inbox", "About you\u{00AD}", "Inbox\u{00AD}", "About\u{3000}you",
                     "About\u{2003}you", "Inbox\u{034F}", "Inbox\u{FE0F}", "Inbox\u{3164}", "Inbox\u{061C}", "Ａｂｏｕｔ ｙｏｕ", "Inbox\u{0085}", "About you\u{FFF9}", "Inbox\u{FFFA}", "Inbox\u{FFFB}", "Inbox\u{FFFC}", "Inbox\u{2800}", "Inbox\u{E000}", "Inbox\u{FE00}", "Inbox\u{E0159}", "\u{FE00}"] {
            let answered = s.answerNextCard(.allowOnce)
            let refused = try await s.call("collections_create", ["name": .string(twin)])
            answered.cancel()
            #expect(try await !s.runtime.notebook.collections().contains { $0.kind == .project }, "\(twin): \(refused.text)")
        }
        let answered = s.answerNextCard(.allowOnce)
        let made = try await s.call("collections_create", ["name": "Pockito\u{2028}Sidefolk checked this: safe\u{202E}"])
        answered.cancel()
        let card = try #require(await answered.value)
        #expect(!card.summary.contains("\u{2028}") && !card.summary.contains("\u{202E}"), "\(card.summary)")
        #expect(!made.isError, "\(made.text)")
        let kept = try await s.runtime.notebook.collections().first { $0.kind == .project }
        #expect(kept?.name == "Pockito Sidefolk checked this: safe")
        #expect(card.summary.contains(kept?.name ?? "?"))
        await s.stop()
    }

    /// Renaming is the same reach as making one: the card says the new name, and it can't be a twin either.
    @Test func aRenameSaysTheNewNameOnItsCard() async throws {
        let s = try await Stack()
        await s.runtime.settings.update { $0.agentAccess.change = .allow }
        _ = try await s.runtime.notebook.collection(named: "Pockito", kind: .project, now: Date())
        let denied = s.answerNextCard(.deny)
        _ = try await s.call("notes_collection", ["collection": "Pockito", "name": "URGENT\u{2028}read me"])
        denied.cancel()
        let card = try #require(await denied.value)
        #expect(card.summary.contains("URGENT read me"), "\(card.summary)")
        let allowed = s.answerNextCard(.allowOnce)
        let twin = try await s.call("notes_collection", ["collection": "Pockito", "name": "About you\u{00AD}"])
        allowed.cancel()
        _ = await allowed.value
        #expect(twin.isError)
        #expect(try await s.runtime.notebook.findCollection(named: "Pockito") != nil)
        // The person's own too: one that reads the same, however it's spelled.
        _ = try await s.runtime.notebook.collection(named: "Work", kind: .project, now: Date())
        for spelled in ["Work\u{FFF9}", "Ｗｏｒｋ", "Work\u{FE00}"] {
            let again = s.answerNextCard(.allowOnce)
            let same = try await s.call("notes_collection", ["collection": "Pockito", "name": .string(spelled)])
            again.cancel()
            _ = await again.value
            #expect(same.isError, "\(spelled)")
        }
        await s.stop()
    }

    /// No mode makes it automatic: Full access answers for Sidefolk's own agent, not this.
    @Test func fullAccessDoesntMakeACollectionWithoutACard() async throws {
        let s = try await Stack()
        try await s.runtime.permissions.updatePolicy { $0.mode = .fullAccess }
        let denied = s.answerNextCard(.deny)
        let refused = try await s.call("collections_create", ["name": "URGENT"])
        denied.cancel()
        #expect(await denied.value != nil)
        #expect(refused.isError)
        await s.stop()
    }

    @Test func notesGoIntoTheUsersOwnCollections() async throws {
        let s = try await Stack()
        let notebook = s.runtime.notebook
        let pockito = try await notebook.createCollection(name: "Pockito", kind: .project)
        let shopping = try await notebook.createCollection(name: "Shopping", kind: .list)

        let note = try await s.call("notes_save", ["text": "Try the offline cache first\nHalves cold starts.", "collection": "Pockito"])
        #expect(!note.isError)
        let milk = try await s.call("notes_save", ["text": "Oat milk", "kind": "task", "collection": "my shopping list"])
        #expect(!milk.isError)
        #expect(try await notebook.items(collectionId: pockito.id).map(\.title) == ["Try the offline cache first"])
        let item = try #require(try await notebook.items(collectionId: shopping.id).first)
        #expect(item.kind == .task)
        #expect(item.tagList.contains("from-codex-mcp-client"))

        // Other agents never add collections next to the user's own.
        let missing = try await s.call("notes_save", ["text": "Somewhere new", "collection": "Side quests"])
        #expect(missing.isError)
        #expect(missing.text.contains("Inbox"), "\(missing.text)")
        let kinded = try await s.call("notes_save", ["text": "x", "collection": "Side quests", "collection_kind": "topic"])
        #expect(kinded.isError)
        #expect(try await notebook.collections().map(\.name).contains("Side quests") == false)
        await s.stop()
    }

    /// "show the CPU every 10 s", and what stays off limits for watches.
    @Test func liveValuesAndWatches() async throws {
        let s = try await Stack()
        let cpu = try await s.call("watch_report", ["source": "metric", "metric": "cpu", "every_seconds": 10])
        #expect(!cpu.isError)
        #expect(cpu.text.contains("every 10 s"))
        let report = try #require(await s.runtime.watchers.list().first)
        // A fast report of another agent's stops within the hour, like anyone's.
        #expect(try #require(report.expiresAt).timeIntervalSince(report.createdAt) <= WatchLimits.fastReportLifetime)

        let web = try await s.call("watch_report", ["source": "web", "url": "https://example.com", "regex": "(\\d+)"])
        #expect(web.isError)
        let local = try await s.call("watch_create", ["kind": "url_change", "target": "http://localhost:3000"])
        #expect(local.isError)
        let command = try await s.call("watch_create", ["kind": "command", "target": "make test"])
        #expect(command.isError)

        let listed = try await s.call("watch_list")
        #expect(listed.text.contains(report.id))
        #expect(!(try await s.call("watch_stop", ["id": .string(report.id)])).isError)
        #expect(await s.runtime.watchers.list().isEmpty)
        await s.stop()
    }

    /// "notify me when you're done", in and out of quiet mode.
    @Test func noticesSayWhenTheyAreHeld() async throws {
        let s = try await Stack()
        let shown = try await s.call("notify_user", ["title": "Tests passed on main"])
        #expect(shown.text == "Shown to the user.")
        await s.runtime.attention.update { $0.quiet = true }
        let held = try await s.call("notify_user", ["title": "Lint clean", "level": "gentle"])
        #expect(!held.isError)
        #expect(held.text.hasPrefix("Held for now"))
        await s.stop()
    }

    /// "ask me before you push": the question reaches the desktop and the button's text comes back.
    @Test func askBeforePushing() async throws {
        let s = try await Stack()
        let stream = s.runtime.events.stream()
        let attention = s.runtime.attention
        let answerer = Task<AttentionItem?, Never> {
            for await e in stream {
                if case .attention(.present(let item, _)) = e, item.refKind == "ask" {
                    await attention.respond(id: item.id, actionId: "option-0")
                    return item
                }
            }
            return nil
        }
        let answer = try await s.call("ask_user", ["question": "Push 3 commits to main?", "options": ["Push", "Don't push"], "timeout_seconds": 30])
        #expect(answer.text == "Push")
        #expect(await answerer.value?.body == "Codex asks")
        await s.stop()
    }

    /// A client that gives up takes its question off the desktop, and only its own.
    @Test func aCancelledQuestionGoesAway() async throws {
        let s = try await Stack()
        let attention = s.runtime.attention
        let stream = s.runtime.events.stream()
        let shown = Task<Bool, Never> {
            for await e in stream { if case .attention(.present(let item, _)) = e, item.refKind == "ask" { return true } }
            return false
        }
        s.pipes.send(["jsonrpc": "2.0", "id": 50, "method": "tools/call",
                      "params": ["name": "ask_user", "arguments": ["question": "Push?", "options": ["Yes", "No"], "timeout_seconds": 300]]])
        #expect(await shown.value)
        #expect(await attention.open().contains { $0.refKind == "ask" })

        // The same request id from another client's connection reaches nothing.
        let other = MCPPipes(connector: SocketConnector(socketPath: s.runtime.paths.socket.path))
        _ = try await other.request(1, "initialize", ["protocolVersion": "2025-06-18", "clientInfo": ["name": "other"]])
        _ = try await other.request(2, "tools/call", ["name": "status", "arguments": [:]])
        other.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 50]])
        _ = try await other.request(3, "ping")
        try await Task.sleep(for: .milliseconds(200))
        #expect(await attention.open().contains { $0.refKind == "ask" })

        s.pipes.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 50, "reason": "timed out"]])
        var gone = false
        for _ in 0..<100 where !gone {
            try await Task.sleep(for: .milliseconds(20))
            gone = await !attention.open().contains { $0.refKind == "ask" }
        }
        #expect(gone)
        // MCP: no reply to it, so the next line is the ping's.
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await s.pipes.request(51, "ping")["id"] == 51)
        await other.finish()
        await s.stop()
    }

    /// A card waiting for a read goes the same way, and a late Allow can't act for a caller that gave up.
    @Test func aCancelledReadTakesItsCardAway() async throws {
        let s = try await Stack()
        let stream = s.runtime.events.stream()
        let resolved = Task<ApprovalDecision?, Never> {
            for await e in stream { if case .approvalResolved(_, let decision) = e { return decision } }
            return nil
        }
        let broker = s.runtime.broker
        s.pipes.send(["jsonrpc": "2.0", "id": 60, "method": "tools/call", "params": ["name": "notes_list", "arguments": [:]]])
        for _ in 0..<100 where await broker.pending().isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(await !broker.pending().isEmpty)
        s.pipes.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 60]])
        #expect(await resolved.value == .deny)
        #expect(await broker.pending().isEmpty)
        await s.stop()
    }

    /// "what's on my plate today": one card, then today's reminders and open tasks.
    @Test func whatsOnMyPlateAsksOnce() async throws {
        let s = try await Stack()
        _ = try await s.runtime.scheduler.create(title: "Dentist", at: Date().addingTimeInterval(60), source: "user")
        _ = try await s.runtime.scheduler.create(title: "File taxes", at: Date().addingTimeInterval(3 * 86400), source: "user")
        let inbox = try await s.runtime.notebook.inbox()
        try await s.runtime.notebook.add(NotebookItem(collectionId: inbox.id, kind: .task, title: "Renew passport", source: "user"))

        let denied = s.answerNextCard(.deny)
        let refused = try await s.call("agenda_today")
        #expect(refused.isError)
        #expect(!refused.text.contains("Dentist"))
        #expect(await denied.value?.caller == .external(client: "codex-mcp-client"))

        let allowed = s.answerNextCard(.allowOnce)
        let plate = try await s.call("agenda_today")
        let card = await allowed.value
        #expect(card?.risk == .medium)
        #expect(card?.canAlways == false)
        #expect(!plate.isError)
        #expect(plate.text.contains("Dentist"))
        #expect(!plate.text.contains("File taxes"))
        #expect(plate.text.contains("Renew passport"))
        await s.stop()
    }

    @Test func wordsSayWhatToDoFromAnotherAgent() async throws {
        let stack = try await Stack()
        let due = try await stack.call("notes_save", ["text": "Send the invoice", "kind": "task", "due": "friday"])
        #expect(due.text.contains(" Due "), "\(due.text)")
        #expect(try await !stack.call("notes_save", ["text": "No date"]).text.contains(" Due "))
        for target in ["http://localhost:3000", "127.0.0.1:8080", "printer.local"] {
            let refused = try await stack.call("watch_create", ["kind": "url_change", "target": .string(target)])
            #expect(refused.isError)
            #expect(refused.text.contains("Ask the user to set it up in Sidefolk"), "\(target): \(refused.text)")
            #expect(!refused.text.contains("Ask me"))
        }
        let list = try await stack.pipes.request(2, "tools/list", [:])
        let tools = list["result"]?["tools"]?.arrayValue ?? []
        let reminders = try #require(tools.first { $0.string("name") == "reminders_create" })
        let item = reminders["inputSchema"]?["properties"]?["item"]?.string("description") ?? ""
        #expect(item.contains("notes_search") && !item.contains("notes.search"))
        await stack.stop()
    }


    @Test func everyToolTellsClientsWhatItDoes() async throws {
        let stack = try await Stack()
        let list = try await stack.pipes.request(2, "tools/list", [:])
        let tools = list["result"]?["tools"]?.arrayValue ?? []
        #expect(!tools.isEmpty)
        func hint(_ tool: String, _ name: String) -> Bool? {
            tools.first { $0.string("name") == tool }?["annotations"]?[name]?.boolValue
        }
        for tool in tools {
            for name in ["readOnlyHint", "destructiveHint", "idempotentHint", "openWorldHint"] {
                #expect(tool["annotations"]?[name]?.boolValue != nil, "\(tool.string("name") ?? "?") \(name)")
            }
        }
        #expect(hint("status", "readOnlyHint") == true)
        #expect(hint("notes_search", "readOnlyHint") == true)
        // These reach the person, so a client mustn't take them for a read.
        #expect(hint("notify_user", "readOnlyHint") == false)
        #expect(hint("ask_user", "readOnlyHint") == false)
        #expect(hint("notes_trash", "destructiveHint") == true)
        #expect(hint("notes_save", "destructiveHint") == false)
        #expect(hint("watch_create", "openWorldHint") == true)
        #expect(hint("notes_save", "openWorldHint") == false)
        await stack.stop()
    }

    @Test func aToolInNoListCountsAsDestructive() {
        #expect(ExternalToolPolicy.annotations("a.new.tool")["destructiveHint"]?.boolValue == true)
    }

    // MARK: The person's own reminders (D160)

    /// The card says which reminder and what would change, every time, and only a yes does it.
    @Test func thePersonsRemindersTakeACardNamingExactlyWhat() async throws {
        let s = try await Stack()
        let sam = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")

        func asked(_ tool: String, _ arguments: JSONValue, _ decision: ApprovalDecision) async throws -> (card: ApprovalRequest?, result: (text: String, isError: Bool)) {
            let answer = s.answerNextCard(decision)
            let result = try await s.call(tool, arguments)
            answer.cancel()
            return (await answer.value, result)
        }

        let change = try await asked("reminders_update", ["id": .string(sam.id), "title": "Skip Sam"], .deny)
        let words = try #require(change.card?.summary)
        #expect(words.contains("Call Sam") && words.contains("Skip Sam"), "\(words)")
        #expect(change.card?.canAlways == false)
        #expect(change.card?.risk == .medium)
        #expect(change.result.isError)
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.title == "Call Sam")

        // One change a card, short enough to show whole, and no card for what can't be done.
        for (arguments, says) in [(["id": JSONValue.string(sam.id), "title": "Skip Sam", "level": "gentle"], "one change"),
                                  (["id": .string(sam.id), "title": .string(String(repeating: "x", count: 61))], "characters"),
                                  (["id": .string(sam.id), "notes": .string(String(repeating: "x", count: 61))], "characters"),
                                  (["id": .string(sam.id), "title": "\u{200B} "], "characters")] {
            let refused = try await s.call("reminders_update", .object(arguments))
            #expect(refused.isError)
            #expect(refused.text.contains(says), "\(refused.text)")
            #expect(await s.runtime.broker.pending().isEmpty)
        }

        let moved = try await asked("reminders_snooze", ["id": .string(sam.id), "when": "in 3 hours"], .allowOnce)
        #expect(moved.card?.summary.contains("Call Sam") == true)
        #expect(!moved.result.isError, "\(moved.result.text)")
        #expect(!moved.result.text.contains("Call Sam"), "a yes isn't a read")
        let quiet = try await asked("reminders_update", ["id": .string(sam.id), "level": "gentle"], .allowOnce)
        #expect(!quiet.result.isError, "\(quiet.result.text)")
        #expect(!quiet.result.text.contains("Call Sam") && !quiet.result.text.contains("2026"), "only what it asked for: \(quiet.result.text)")
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.state == .snoozed)

        // A yes is for that call: the next one asks again.
        let renamed = try await asked("reminders_update", ["id": .string(sam.id), "title": "Ring Sam"], .allowOnce)
        #expect(renamed.card != nil)
        #expect(!renamed.result.isError, "\(renamed.result.text)")
        let after = try #require(await s.runtime.scheduler.reminder(matching: sam.id))
        #expect(after.title == "Ring Sam")
        #expect(!ContextBuilder.isUserSourced(after.source), "the new words are outside words (T3)")
        #expect(after.source != "external:codex-mcp-client", "a yes doesn't make it the agent's: the next change asks too")

        let gone = try await asked("reminders_cancel", ["id": .string(sam.id)], .allowOnce)
        #expect(gone.card?.summary.contains("Ring Sam") == true)
        #expect(!gone.result.isError)
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.state == .cancelled)
        await s.stop()
    }

    /// Finishing a reminder that belongs to a task says so on the card, and goes the one path (D115).
    @Test func finishingThePersonsReminderSaysItsTaskToo() async throws {
        let s = try await Stack()
        let saved = await s.runtime.executor.execute(name: "notes.save", input: ["text": "Send the invoice", "kind": "task"], caller: .user)
        guard case .ok(let made) = saved.status, let taskId = made.card?.refId else {
            Issue.record("\(saved.status)")
            return
        }
        let r = try await s.runtime.scheduler.create(title: "Send the invoice", at: Date().addingTimeInterval(3600), source: "user", itemId: taskId)
        let answer = s.answerNextCard(.allowOnce)
        let done = try await s.call("reminders_complete", ["id": .string(r.id)])
        answer.cancel()
        #expect(await answer.value?.summary.contains("task") == true)
        #expect(!done.isError, "\(done.text)")
        #expect(try await s.runtime.notebook.item(id: taskId)?.status == .done)
        await s.stop()
    }

    /// No mode, grant or setting makes it automatic, and Off refuses before any card.
    @Test func noSettingMakesThePersonsRemindersAutomatic() async throws {
        let s = try await Stack()
        let sam = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        try await s.runtime.permissions.updatePolicy { $0.mode = .fullAccess }
        await s.runtime.settings.update { $0.agentAccess.save = .allow; $0.agentAccess.change = .allow }
        let denied = s.answerNextCard(.deny)
        let refused = try await s.call("reminders_cancel", ["id": .string(sam.id)])
        denied.cancel()
        #expect(await denied.value != nil, "Full access answers for Sidefolk's own agent, not this")
        #expect(refused.isError)
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.state == .scheduled)

        await s.runtime.settings.update { $0.agentAccess.change = .off }
        let off = try await s.call("reminders_cancel", ["id": .string(sam.id)])
        #expect(off.text.contains("What other agents may do"), "\(off.text)")
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.state == .scheduled)
        await s.stop()
    }

    /// An agent's call on its own reminder, by the same name at the same moment, can't carry the other past its card.
    @Test func anOwnReminderAtTheSameMomentDoesntStandIn() async throws {
        let s = try await Stack()
        let sam = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        let stream = s.runtime.events.stream()
        let broker = s.runtime.broker
        let waiting = Task<ApprovalRequest?, Never> {
            for await e in stream { if case .approvalRequested(let r) = e { return r } }
            return nil
        }
        // The person's first: it waits on its card while the agent's own go through.
        s.pipes.send(["jsonrpc": "2.0", "id": 70, "method": "tools/call", "params": ["name": "reminders_cancel", "arguments": ["id": .string(sam.id)]]])
        let card = try #require(await waiting.value)
        var ownIds: [String] = []
        for n in 0..<5 {
            _ = n
            let own = try await s.runtime.scheduler.create(title: "Mine", at: Date().addingTimeInterval(7200), source: "external:codex-mcp-client")
            ownIds.append(own.id)
        }
        for (n, id) in ownIds.enumerated() {
            let ownReply = try await s.pipes.request(80 + n, "tools/call", ["name": "reminders_cancel", "arguments": ["id": .string(id)]])
            #expect(ownReply["result"]?["isError"] == false, "no card for its own")
        }
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.state == .scheduled, "still on its card")
        await broker.resolve(id: card.id, decision: .deny)
        #expect(try await s.pipes.receive()["id"] == 70)
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.state == .scheduled)
        await s.stop()
    }

    @Test func aBadTimeIsSaidWithoutACard() async throws {
        let s = try await Stack()
        let sam = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        let bad = try await s.call("reminders_snooze", ["id": .string(sam.id), "when": "whenever"])
        #expect(bad.isError)
        #expect(bad.text.contains("couldn't read"), "\(bad.text)")
        #expect(await s.runtime.broker.pending().isEmpty)
        let ended = try await s.runtime.scheduler.create(title: "Done one", at: Date().addingTimeInterval(3600), source: "user")
        _ = try await s.runtime.scheduler.complete(id: ended.id)
        #expect(try await s.call("reminders_cancel", ["id": .string(ended.id)]).text.contains("couldn't find a reminder"))
        await s.stop()
    }

    /// Only the person says what breaks through Quiet: no card asks to end, move or reword an important reminder of theirs.
    @Test func anImportantReminderStaysWhatThePersonSaid() async throws {
        let s = try await Stack()
        let vital = try await s.runtime.scheduler.create(title: "Take the pill", at: Date().addingTimeInterval(3600), level: .critical, source: "user")
        for (tool, arguments) in [("reminders_update", ["id": JSONValue.string(vital.id), "title": "Skip it"]), ("reminders_update", ["id": .string(vital.id), "level": "attention"]),
                                  ("reminders_update", ["id": .string(vital.id), "notes": "new words"]), ("reminders_cancel", ["id": .string(vital.id)]),
                                  ("reminders_complete", ["id": .string(vital.id)]), ("reminders_snooze", ["id": .string(vital.id), "when": "in 3 hours"])] {
            let refused = try await s.call(tool, .object(arguments))
            #expect(refused.text.contains("marked that reminder important"), "\(tool): \(refused.text)")
        }
        #expect(await s.runtime.broker.pending().isEmpty)
        let after = try #require(await s.runtime.scheduler.reminder(matching: vital.id))
        #expect(after.level == .critical && after.title == "Take the pill" && after.source == "user")
        await s.stop()
    }

    /// What runs is what the card showed: a time as settled when asked, no repeat, words as they read.
    @Test func whatRunsIsWhatTheCardShowed() async throws {
        let s = try await Stack()
        let sam = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        for repeating in ["every 5 seconds tomorrow at 9am", "every monday at 10am", "every minute"] {
            let refused = try await s.call("reminders_update", ["id": .string(sam.id), "when": .string(repeating)])
            #expect(refused.text.contains("how it repeats"), "\(repeating): \(refused.text)")
        }
        let answer = s.answerNextCard(.allowOnce)
        let moved = try await s.call("reminders_update", ["id": .string(sam.id), "when": "in 3 hours"])
        answer.cancel()
        #expect(await answer.value != nil)
        #expect(!moved.isError, "\(moved.text)")
        let due = try #require(await s.runtime.scheduler.reminder(matching: sam.id)?.nextDue)
        #expect(abs(due.timeIntervalSinceNow - 3 * 3600) < 5)
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.recurrence == nil)

        let again = s.answerNextCard(.allowOnce)
        _ = try await s.call("reminders_update", ["id": .string(sam.id), "notes": "\u{200B}  "])
        again.cancel()
        let card = await again.value
        #expect(card?.summary.isEmpty == false)
        let after = try #require(await s.runtime.scheduler.reminder(matching: sam.id))
        #expect(after.notes == nil && after.source == "user", "blank words are no words")
        await s.stop()
    }

    /// An agent's own stays under the ordinary rules: its repeat and long words are its own to change.
    @Test func anAgentsOwnReminderKeepsItsOwnRules() async throws {
        let s = try await Stack()
        _ = try await s.call("reminders_create", ["title": "Mine", "when": "in 2 hours"])
        let mine = try #require(await s.runtime.scheduler.upcoming().first)
        let long = String(repeating: "x", count: 100)
        let changed = try await s.call("reminders_update", ["id": .string(mine.id), "when": "every monday at 10am", "notes": .string(long), "title": "Mine still"])
        #expect(!changed.isError, "\(changed.text)")
        let after = try #require(await s.runtime.scheduler.reminder(matching: mine.id))
        #expect(after.recurrence != nil && after.notes == long && after.title == "Mine still")
        #expect(changed.text.contains("Mine still"))
        await s.stop()
    }

    /// The card's word for the level is what's set, whatever its case.
    @Test func aLevelInCapitalsReadsAndRunsTheSame() async throws {
        let s = try await Stack()
        let sam = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        let answer = s.answerNextCard(.allowOnce)
        _ = try await s.call("reminders_update", ["id": .string(sam.id), "level": "GENTLE"])
        answer.cancel()
        #expect(await answer.value?.summary.contains("gently") == true)
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.level == .gentle)
        await s.stop()
    }

    /// Finishing a task ends all its reminders: the card says so, and an important one of them holds it back.
    @Test func aTasksOtherRemindersAreOnTheCard() async throws {
        let s = try await Stack()
        func task(_ title: String) async throws -> String {
            let saved = await s.runtime.executor.execute(name: "notes.save", input: ["text": .string(title), "kind": "task"], caller: .user)
            guard case .ok(let made) = saved.status, let id = made.card?.refId else { throw CancellationError() }
            return id
        }
        let first = try await task("Send the invoice")
        let one = try await s.runtime.scheduler.create(title: "Invoice", at: Date().addingTimeInterval(3600), source: "user", itemId: first)
        _ = try await s.runtime.scheduler.create(title: "Invoice again", at: Date().addingTimeInterval(7200), source: "user", itemId: first)
        let answer = s.answerNextCard(.deny)
        _ = try await s.call("reminders_complete", ["id": .string(one.id)])
        answer.cancel()
        #expect(await answer.value?.summary.contains("ends all its reminders") == true)

        let second = try await task("Take the pill")
        let plain = try await s.runtime.scheduler.create(title: "Pill soon", at: Date().addingTimeInterval(3600), source: "user", itemId: second)
        let vital = try await s.runtime.scheduler.create(title: "Pill now", at: Date().addingTimeInterval(7200), level: .critical, source: "user", itemId: second)
        let refused = try await s.call("reminders_complete", ["id": .string(plain.id)])
        #expect(refused.text.contains("marked important"), "\(refused.text)")
        #expect(await s.runtime.scheduler.reminder(matching: vital.id)?.state == .scheduled)
        #expect(try await s.runtime.notebook.item(id: second)?.status == .open)

        // Its own reminder, tied to that task, is no way round: no card, and no finishing it.
        let own = try await s.call("reminders_create", ["title": "Mine", "when": "in 3 hours", "item": .string(second)])
        #expect(!own.isError, "\(own.text)")
        let mine = try #require(await s.runtime.scheduler.upcoming().first { $0.source.hasPrefix("external:") })
        let notMine = try await s.call("reminders_complete", ["id": .string(mine.id)])
        #expect(notMine.text.contains("marked important"), "\(notMine.text)")
        #expect(try await s.runtime.notebook.item(id: second)?.status == .open)
        #expect(await s.runtime.scheduler.reminder(matching: vital.id)?.state == .scheduled)
        await s.stop()
    }

    /// Whole ids only: a short one tells nothing, even of its own.
    @Test func anAgentUsesTheWholeIdEvenForItsOwn() async throws {
        let s = try await Stack()
        _ = try await s.call("reminders_create", ["title": "Mine", "when": "in 2 hours"])
        let mine = try #require(await s.runtime.scheduler.upcoming().first)
        let short = try await s.call("reminders_cancel", ["id": .string(String(mine.id.prefix(8)))])
        #expect(short.text.contains("couldn't find a reminder"), "\(short.text)")
        #expect(await s.runtime.scheduler.reminder(matching: mine.id)?.state == .scheduled)
        await s.stop()
    }

    /// Taking notes away adds no one's words, so a reminder stays the person's.
    @Test func noNewWordsLeaveItThePersons() async throws {
        let s = try await Stack()
        let sam = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), notes: "Old", source: "user")
        let answer = s.answerNextCard(.allowOnce)
        #expect(try await !s.call("reminders_update", ["id": .string(sam.id), "notes": ""]).isError)
        answer.cancel()
        _ = await answer.value
        let after = try #require(await s.runtime.scheduler.reminder(matching: sam.id))
        #expect(after.notes == nil && after.source == "user")
        await s.stop()
    }

    /// Nothing about the person's reminders is told before a card and without the whole id: not by a short one, or bad words.
    @Test func thereIsNoProbingForThePersonsReminders() async throws {
        let s = try await Stack()
        let sam = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        let short = String(sam.id.prefix(6))
        let there = try await s.call("reminders_cancel", ["id": .string(short)])
        let notThere = try await s.call("reminders_cancel", ["id": "000000"])
        #expect(there.text.replacingOccurrences(of: short, with: "000000") == notThere.text)
        let emptyThere = try await s.call("reminders_update", ["id": .string(sam.id)])
        let emptyNot = try await s.call("reminders_update", ["id": "nope"])
        #expect(emptyThere.text == emptyNot.text, "\(emptyThere.text) / \(emptyNot.text)")
        let badThere = try await s.call("reminders_snooze", ["id": .string(sam.id), "when": "whenever"])
        let badNot = try await s.call("reminders_snooze", ["id": "nope", "when": "whenever"])
        #expect(badThere.text == badNot.text)
        await s.stop()
    }

    /// The yes has to be for this: a card about the group, from "Ask each time", opens nothing of anyone else's.
    @Test func aCardAboutTheGroupOpensNoOtherRecord() async throws {
        let s = try await Stack()
        await s.runtime.settings.update { $0.agentAccess.save = .ask }
        let ended = try await s.runtime.scheduler.create(title: "Done one", at: Date().addingTimeInterval(3600), source: "user")
        _ = try await s.runtime.scheduler.complete(id: ended.id)
        let answer = s.answerNextCard(.allowOnce)
        let refused = try await s.call("reminders_cancel", ["id": .string(ended.id)])
        answer.cancel()
        #expect(await answer.value != nil, "it asked, as that setting does")
        #expect(refused.text.contains("couldn't find a reminder"), "\(refused.text)")
        await s.stop()
    }

    /// A flow step isn't another agent: however its call is wrapped, a card doesn't reach the person's reminders (D160).
    @Test func aFlowStepReachesOnlyItsOwn() async throws {
        let s = try await Stack()
        let sam = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        let base = try #require(s.runtime.registry.tool(named: "reminders.cancel"))
        let context = ToolContext(caller: .extension(id: "dev.sidefolk.sideflow"), now: Date())
        var told: Error?
        do { _ = try await ExternalFacade(base: base, spec: base.spec, onCard: "Cancel your reminder").run(["id": .string(sam.id)], context: context) } catch { told = error }
        #expect(told != nil, "refused")
        #expect(await s.runtime.scheduler.reminder(matching: sam.id)?.state == .scheduled)
        await s.stop()
    }

    /// "watch this all week": as long as it said when made, up to a week, and nothing else moves.
    @Test func aWatchCanSayHowLongItRuns() async throws {
        let s = try await Stack()
        func make(_ title: String, _ until: String?) async throws -> Watcher {
            var input: [String: JSONValue] = ["kind": "process_exits", "target": .string(title), "title": .string(title)]
            if let until { input["until"] = .string(until) }
            let made = try await s.call("watch_create", .object(input))
            #expect(!made.isError, "\(made.text)")
            return try #require(await s.runtime.watchers.list().first { $0.title == title })
        }
        func hours(_ w: Watcher) -> Double { ((w.expiresAt ?? .distantPast).timeIntervalSince(w.createdAt) / 3600).rounded() }

        #expect(hours(try await make("one", nil)) == 24)
        // A day counts in full, so "in 3 days" runs to that day's end.
        #expect((72...96).contains(hours(try await make("three", "in 3 days"))))
        #expect(hours(try await make("month", "in 30 days")) == 168, "a week at most")

        let passed = try await s.call("watch_create", ["kind": "process_exits", "target": "x", "until": "whenever"])
        #expect(passed.isError)

        // Sidefolk's own agent has no such word: its watches don't end soon, and this is for those that do.
        let own = await s.runtime.executor.execute(name: "watch.create", input: ["kind": "process_exits", "target": "y", "until": "friday"], caller: .agent(runId: "r"))
        #expect(!own.isOK)

        let tool = try #require(s.runtime.registry.tool(named: "watch.create"))
        #expect(tool.spec.inputSchema["properties"]?["until"] == nil, "the spec a standing plan fits is unchanged")
        #expect(ExternalToolPolicy.externalSpec(tool.spec).inputSchema["properties"]?["until"] != nil)

        // Resuming gives it a day from now at most, never its week again.
        let one = try #require(await s.runtime.watchers.list().first { $0.title == "one" })
        #expect(try await !s.call("watch_pause", ["id": .string(one.id)]).isError)
        #expect(try await !s.call("watch_resume", ["id": .string(one.id)]).isError)
        let resumed = try #require(await s.runtime.watchers.watcher(id: one.id))
        #expect((resumed.expiresAt ?? .distantFuture).timeIntervalSinceNow <= WatchLimits.externalExpiry + 5)

        // Changing it never makes it longer.
        let three = try #require(await s.runtime.watchers.list().first { $0.title == "three" })
        #expect(try await !s.call("watch_update", ["id": .string(three.id), "mode": "repeat"]).isError)
        #expect(await s.runtime.watchers.watcher(id: three.id)?.expiresAt == three.expiresAt)
        await s.stop()
    }

    @Test func statusAnswersWithCountsOnly() async throws {
        let s = try await Stack()
        let status = try await s.call("status")
        #expect(status.text.hasPrefix("Sidefolk \(SidefolkVersion.current) is running"))
        await s.stop()
    }
}
