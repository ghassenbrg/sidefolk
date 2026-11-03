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

        // The user's own reminder can't be cancelled from here, and reads as not found.
        let users = try await s.runtime.scheduler.create(title: "Call Sam", at: Date().addingTimeInterval(3600), source: "user")
        let refused = try await s.call("reminders_cancel", ["id": .string(users.id)])
        #expect(refused.isError)
        #expect(refused.text.contains("couldn't find a reminder"), "\(refused.text)")
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
            let refused = try await s.call(tool, .object(arguments))
            #expect(refused.isError, "\(tool)")
            #expect(refused.text.contains("couldn't find a reminder"), "\(tool): \(refused.text)")
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
                     "About\u{2003}you", "Inbox\u{034F}", "Inbox\u{FE0F}", "Inbox\u{3164}", "Inbox\u{061C}", "Ａｂｏｕｔ ｙｏｕ", "Inbox\u{0085}"] {
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

    @Test func statusAnswersWithCountsOnly() async throws {
        let s = try await Stack()
        let status = try await s.call("status")
        #expect(status.text.hasPrefix("Sidefolk \(SidefolkVersion.current) is running"))
        await s.stop()
    }
}
