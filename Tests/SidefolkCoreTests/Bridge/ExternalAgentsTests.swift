import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// What a person says to Codex or Claude Code about Sidefolk, end to end: a fake MCP client speaks JSON-RPC
/// over stdio to `MCPStdioBridge`, which reaches a whole Sidefolk (real tools, Guard, socket, scheduler,
/// watchers) in a temp home, as `sidefolk mcp` does (D42).
@Suite(.serialized) struct ExternalAgentsTests {
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
        #expect(Set(byName.keys) == Set((ExternalToolPolicy.direct.union(ExternalToolPolicy.asking)).map { $0.replacingOccurrences(of: ".", with: "_") }))
        // Words written for other agents: they can't create collections, set critical alerts or read web values.
        let save = try #require(byName["notes_save"])
        #expect(save.string("description")?.contains("can't create collections") == true)
        #expect(save["inputSchema"]?["properties"]?["collection_kind"] == nil)
        #expect(byName["reminders_create"]?["inputSchema"]?["properties"]?["level"]?["enum"] == ["gentle", "attention"])
        #expect(byName["watch_report"]?["inputSchema"]?["properties"]?["source"]?["enum"] == ["metric"])
        #expect(byName["watch_report"]?["inputSchema"]?["properties"]?["url"] == nil)
        let initialize = try await s.pipes.request(3, "initialize", ["protocolVersion": "2025-06-18", "clientInfo": ["name": "codex-mcp-client"]])
        #expect(initialize["result"]?.string("instructions")?.contains("remind the user") == true)
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

    @Test func statusAnswersWithCountsOnly() async throws {
        let s = try await Stack()
        let status = try await s.call("status")
        #expect(status.text.hasPrefix("Sidefolk \(SidefolkVersion.current) is running"))
        await s.stop()
    }
}
