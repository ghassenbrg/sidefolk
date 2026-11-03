import Foundation
import Testing
@testable import SidefolkCore

/// Sidefolk's tools from a shell: what `sidefolk notify`, `ask`, `remind`, `note`, `tools` and `call` mean, against a whole
/// Sidefolk in a temp home, and that they reach only what MCP does (T4).
@Suite(.serialized) struct ToolVerbsTests {
    struct Stack {
        let dir: ShortTempDir
        let runtime: SidefolkRuntime

        init() async throws {
            dir = try ShortTempDir()
            runtime = await SidefolkRuntime(paths: SidefolkPaths(home: URL(fileURLWithPath: dir.path)), db: try AppDatabase.inMemory(), platform: NullPlatform())
            try await runtime.start()
        }

        func run(_ arguments: String...) async throws -> ToolVerbs.Output {
            let request = try ToolVerbs.parse(arguments).get()
            return await ToolVerbs.run(request, paths: runtime.paths)
        }

        func stop() async { await runtime.stop() }
    }

    @Test func wordsBecomeTheToolsArguments() throws {
        #expect(try ToolVerbs.parse(["notify", "Tests passed", "--body", "All 12", "--attention"]).get()
            == .call(tool: "notify.user", input: ["title": "Tests passed", "body": "All 12", "level": "attention"]))
        #expect(try ToolVerbs.parse(["remind", "Stretch", "--at", "in 20 minutes", "--gentle"]).get()
            == .call(tool: "reminders.create", input: ["title": "Stretch", "when": "in 20 minutes", "level": "gentle"]))
        #expect(try ToolVerbs.parse(["note", "Oat milk", "--task", "--collection", "Shopping", "--tag", "a", "--tag", "b"]).get()
            == .call(tool: "notes.save", input: ["text": "Oat milk", "kind": "task", "collection": "Shopping", "tags": ["a", "b"]]))
        #expect(try ToolVerbs.parse(["ask", "Push?", "--options", "yes, no", "--timeout", "60"]).get()
            == .ask(input: ["question": "Push?", "options": ["yes", "no"], "timeout_seconds": 60], options: ["yes", "no"]))
        #expect(try ToolVerbs.parse(["call", "status"]).get() == .call(tool: "status", input: [:]))
        #expect(try ToolVerbs.parse(["tools", "--json"]).get() == .list(json: true))
    }

    @Test func aBadCommandLineSaysHow() {
        for arguments in [["notify"], ["remind", "Stretch"], ["note", "a", "b"], ["ask"], ["call"], ["call", "status", "not json"], ["call", "status", "[1]"],
                          ["notify", "x", "--body"], ["ask", "x", "--timeout", "soon"], ["tools", "extra"]] {
            guard case .failure = ToolVerbs.parse(arguments) else {
                Issue.record("\(arguments) should be refused")
                continue
            }
        }
    }

    @Test func noteRemindAndNotifyDoWhatTheySay() async throws {
        let s = try await Stack()
        let note = try await s.run("note", "Oat milk", "--task")
        #expect(note.code == 0, "\(note.error)")
        #expect(note.out.contains("Saved task"))
        let saved = try await s.runtime.notebook.items(limit: 5)
        #expect(saved.first?.source == "external:sidefolk-cli")

        let remind = try await s.run("remind", "Stretch", "--at", "in 20 minutes")
        #expect(remind.code == 0)
        #expect(await s.runtime.scheduler.upcoming().first?.source == "external:sidefolk-cli")

        let notify = try await s.run("notify", "Tests passed")
        #expect(notify.code == 0)
        #expect(notify.out.contains("Shown") || notify.out.contains("Held"))

        let bad = try await s.run("remind", "Stretch", "--at", "whenever")
        #expect(bad.code == ToolVerbs.failed)
        #expect(bad.error.contains("couldn't read"))
        await s.stop()
    }

    /// The answer in `$?`, so a script can branch on it.
    @Test func askExitsWithTheAnswersPlace() async throws {
        let s = try await Stack()
        let stream = s.runtime.events.stream()
        let attention = s.runtime.attention
        let answering = Task {
            for await e in stream {
                if case .attention(.present(let item, _)) = e, item.refKind == "ask" {
                    await attention.respond(id: item.id, actionId: "option-1")
                    return
                }
            }
        }
        let answer = try await s.run("ask", "Push?", "--options", "yes,no")
        await answering.value
        #expect(answer.out == "no")
        #expect(answer.code == 1)
        let unanswered = try await s.run("ask", "Still there?", "--timeout", "10", "--options", "yes,no")
        #expect(unanswered.code == ToolVerbs.noAnswer)
        await s.stop()
    }

    /// Nothing `sidefolk mcp` doesn't offer: no Noor, Sideflow or other extension tool, no files, shell or web.
    @Test func callReachesOnlyWhatOtherAgentsDo() async throws {
        let s = try await Stack()
        let listed = try await s.run("tools")
        let names = Set(listed.out.split(separator: "\n").compactMap { $0.split(separator: "\t").first.map(String.init) })
        #expect(names == Set(ExternalToolPolicy.all.map { $0.replacingOccurrences(of: ".", with: "_") }))
        #expect(!names.contains { $0.hasPrefix("extensions") || $0.hasPrefix("ext_") })

        let everyExtensionTool = s.runtime.registry.all.map(\.spec.name).filter { $0.hasPrefix("extensions.") }
        #expect(everyExtensionTool.contains("extensions.consent"))
        let closed = everyExtensionTool + ["extensions.plan", "files.read", "files.trash", "watch.command", "web.fetch", "clipboard.read", "calendar.today", "skills.create", "profile.list"]
        for tool in closed {
            for spelling in [tool, tool.replacingOccurrences(of: ".", with: "_")] {
                let refused = try await s.run("call", spelling, #"{"extension": "dev.sidefolk.prayer-times", "on": true, "what": "place"}"#)
                #expect(refused.code == ToolVerbs.failed, "\(spelling): \(refused.out)")
                #expect(refused.error.contains("doesn't offer"), "\(spelling): \(refused.error)")
            }
        }
        await s.stop()
    }

    @Test func aTurnedOffGroupStaysOff() async throws {
        let s = try await Stack()
        await s.runtime.settings.update { $0.agentAccess.save = .off }
        let refused = try await s.run("note", "Oat milk")
        #expect(refused.code == ToolVerbs.failed)
        #expect(refused.error.contains("What other agents may do"))
        #expect(try await s.runtime.notebook.items(limit: 5).isEmpty)
        await s.stop()
    }

    @Test func whenTheAppIsntRunning() async throws {
        let dir = try ShortTempDir()
        let output = await ToolVerbs.run(.call(tool: "status", input: [:]), paths: SidefolkPaths(home: URL(fileURLWithPath: dir.path)))
        #expect(output.code == ToolVerbs.unavailable)
        #expect(output.error == MCPStdioBridge.notRunningMessage)
        let status = await HelperCommands.statusJSON(paths: SidefolkPaths(home: URL(fileURLWithPath: dir.path)))
        #expect(!status.running)
        #expect(try JSONValue.parse(status.text)["running"] == false)
    }

    @Test func statusForScripts() async throws {
        let s = try await Stack()
        let status = await HelperCommands.statusJSON(paths: s.runtime.paths)
        #expect(status.running)
        let json = try JSONValue.parse(status.text)
        #expect(json["running"] == true)
        #expect(json["reminders_pending"] != nil)
        await s.stop()
    }
}
