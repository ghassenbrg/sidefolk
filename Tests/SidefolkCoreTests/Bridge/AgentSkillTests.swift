import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// Connect's skill and Codex hooks (D42), in temp stand-ins for ~/.claude and ~/.codex.
@Suite struct AgentSkillTests {
    static let skill = "---\nname: sidefolk\ndescription: Reach the user through Sidefolk.\n---\n\n# Sidefolk\n\nUse reminders_create.\n"

    func tools(_ home: FakeAgentHome, skill: String? = Self.skill) -> AgentIntegrations {
        AgentIntegrations(locations: home.locations, helperPath: home.helper, skill: skill, clock: home.clock)
    }

    @Test func skillsLiveWhereEachAgentReadsThem() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let t = tools(home)
        #expect(t.file(for: .claudeSkill).path == home.root.path + "/.claude/skills/sidefolk/SKILL.md")
        #expect(t.file(for: .codexSkill).path == home.root.path + "/.codex/skills/sidefolk/SKILL.md")
        #expect(t.file(for: .codexHooks).path == home.root.path + "/.codex/hooks.json")
        let moved = IntegrationLocations.standard(home: "/Users/me", environment: ["CLAUDE_CONFIG_DIR": "/cfg/claude", "CODEX_HOME": "/cfg/codex"])
        #expect(moved.claudeSkills.path == "/cfg/claude/skills")
        #expect(moved.codexSkills.path == "/cfg/codex/skills")
        #expect(moved.codexHooks.path == "/cfg/codex/hooks.json")
    }

    @Test func theSkillIsInstalledOnceAndRemovedCleanly() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let t = tools(home)
        for integration in [AgentIntegration.claudeSkill, .codexSkill] {
            let file = t.file(for: integration)
            #expect(t.status(integration).state == .notInstalled)
            let preview = try t.preview(integration, install: true)
            #expect(preview.changesSomething)
            #expect(preview.backup == nil)
            #expect(preview.changes.first?.contains("skills") == true)

            #expect(try t.install(integration).changed)
            let text = home.read(file)
            // The front matter stays first; the line under it says who put the file there.
            #expect(text.hasPrefix("---\nname: sidefolk\ndescription: Reach the user through Sidefolk.\n---\n\n<!-- Installed by Sidefolk"))
            #expect(text.hasSuffix("# Sidefolk\n\nUse reminders_create.\n"))
            #expect(t.status(integration).state == .installed)
            #expect(try t.install(integration).changed == false)

            #expect(try t.remove(integration).changed)
            #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
            #expect(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().deletingLastPathComponent().path))
            #expect(try t.remove(integration).changed == false)
        }
        #expect(home.backups().isEmpty)
    }

    @Test func aNewerSkillReplacesTheOldOneAfterABackup() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        try tools(home, skill: "---\nname: sidefolk\ndescription: old\n---\nold\n").install(.claudeSkill)
        let t = tools(home)
        #expect(t.status(.claudeSkill).state == .outdated(t.file(for: .claudeSkill).path))
        let result = try t.install(.claudeSkill)
        #expect(home.read(try #require(result.backup)).contains("description: old"))
        #expect(t.status(.claudeSkill).state == .installed)
        // Disconnect removes the skill; the backup of the old one stays beside it, so the folder does too.
        try t.remove(.claudeSkill)
        #expect(!FileManager.default.fileExists(atPath: t.file(for: .claudeSkill).path))
        #expect(home.backups().count == 1)
    }

    @Test func someoneElsesSkillIsBackedUpAndNeverRemoved() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let t = tools(home)
        let file = t.file(for: .codexSkill)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let theirs = "---\nname: sidefolk\ndescription: my own notes about Sidefolk\n---\n"
        try home.write(theirs, to: file)
        #expect(t.status(.codexSkill).state == .notInstalled)
        // Disconnect leaves a file Sidefolk didn't write.
        #expect(try t.remove(.codexSkill).changed == false)
        #expect(home.read(file) == theirs)
        let result = try t.install(.codexSkill)
        #expect(home.read(try #require(result.backup)) == theirs)
    }

    @Test func aLinkedSkillFolderIsLeftAlone() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let t = tools(home)
        let checkout = home.root.appendingPathComponent("git/sidefolk/skills/sidefolk")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        let source = "---\nname: sidefolk\ndescription: the repository's copy\n---\n"
        try home.write(source, to: checkout.appendingPathComponent("SKILL.md"))
        let skills = home.locations.claudeSkills
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: skills.appendingPathComponent("sidefolk"), withDestinationURL: checkout)

        guard case .unavailable(let why) = t.status(.claudeSkill).state else { Issue.record("a link should be unavailable"); return }
        #expect(why.contains("link"))
        #expect(throws: IntegrationError.self) { try t.install(.claudeSkill) }
        #expect(try t.remove(.claudeSkill).changed == false)
        #expect(home.read(checkout.appendingPathComponent("SKILL.md")) == source)
    }

    @Test func withoutASkillTheToolsStillConnect() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let t = tools(home, skill: nil)
        guard case .unavailable = t.status(.claudeSkill).state else { Issue.record("no skill to install"); return }
        #expect(throws: IntegrationError.self) { try t.install(.codexSkill) }
    }

    // MARK: Codex hooks

    @Test func codexHooksMergeIdempotentlyAndGoAwayCompletely() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let t = tools(home)
        let file = home.locations.codexHooks
        #expect(t.status(.codexHooks).state == .notInstalled)
        let fresh = try t.install(.codexHooks)
        #expect(fresh.backup == nil)
        let json = try JSONValue.parse(home.read(file))
        for event in AgentIntegrations.codexHookEvents {
            let group = try #require(json["hooks"]?[event]?.arrayValue?.first)
            // Codex reads matchers as patterns: a group without one matches every tool.
            #expect(group["matcher"] == nil)
            #expect(group["hooks"]?.arrayValue?.first?.string("command") == "'\(home.helper)' hook \(event) --agent codex")
            #expect(group["hooks"]?.arrayValue?.first?["timeout"] == 3)
        }
        #expect(json["hooks"]?["Notification"] == nil)
        #expect(t.status(.codexHooks).state == .installed)
        #expect(try t.install(.codexHooks).changed == false)
        // Codex's trust for hooks stays Codex's: nothing is written to config.toml.
        #expect(!FileManager.default.fileExists(atPath: home.locations.codexConfig.path))

        // A file Sidefolk created goes when its hooks go.
        try t.remove(.codexHooks)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func codexHooksKeepThePersonsOwn() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let t = tools(home)
        let file = home.locations.codexHooks
        let theirs = """
            {
              "hooks": {
                "SessionStart": [
                  {
                    "hooks": [
                      {
                        "command": "bash '/Users/me/.codex/herdr-agent-state.sh' session",
                        "timeout": 10,
                        "type": "command"
                      }
                    ]
                  }
                ]
              }
            }

            """
        try home.write(theirs, to: file, mode: 0o644)
        let result = try t.install(.codexHooks)
        #expect(home.read(try #require(result.backup)) == theirs)
        #expect(home.read(file).contains("herdr-agent-state.sh"))
        var st = stat()
        stat(file.path, &st)
        #expect(st.st_mode & 0o777 == 0o644)
        home.clock.advance(60)
        try t.remove(.codexHooks)
        #expect(home.read(file) == theirs)
    }

    @Test func hookCommandsNameTheirAgent() {
        #expect(AgentIntegrations.isOurHook("'/Users/me/Library/Application Support/Sidefolk/bin/sidefolk' hook Stop --agent codex"))
        #expect(!AgentIntegrations.isOurHook("sidefolk hook Stop --agent codex; rm -rf ~"))
        #expect(HookForwarder.agent(in: ["--agent", "codex"]) == "codex")
        #expect(HookForwarder.agent(in: []) == "claude-code")
        #expect(HookForwarder.agent(in: ["--agent", "evil app"]) == "claude-code")
    }

    // MARK: Other MCP clients

    @Test func setupInstructionsCarryPastableConfigs() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let t = AgentIntegrations(locations: home.locations, helperPath: home.helper, helperEnvironment: ["SIDEFOLK_HOME": "/tmp/qa home"])
        let text = t.setupInstructions(skillFolder: "/Applications/Sidefolk.app/Contents/Resources/AgentSkills/sidefolk")
        #expect(text.contains("Command: '\(home.helper)' mcp"))
        #expect(text.contains("Environment: SIDEFOLK_HOME='/tmp/qa home'"))
        #expect(text.contains("/Applications/Sidefolk.app/Contents/Resources/AgentSkills/sidefolk"))
        // Each snippet is valid JSON naming the same command.
        let snippets = text.components(separatedBy: "\n\n").compactMap { block -> JSONValue? in
            guard let start = block.firstIndex(of: "{") else { return nil }
            return try? JSONValue.parse(String(block[start...]))
        }
        #expect(snippets.count == 3)
        #expect(snippets[0]["mcpServers"]?["sidefolk"]?.string("command") == home.helper)
        #expect(snippets[1]["servers"]?["sidefolk"]?.string("type") == "stdio")
        #expect(snippets[2]["context_servers"]?["sidefolk"]?["args"] == ["mcp"])
        #expect(snippets[2]["context_servers"]?["sidefolk"]?["env"]?.string("SIDEFOLK_HOME") == "/tmp/qa home")
    }

    // MARK: The skill shipped in skills/sidefolk

    static var shipped: String {
        get throws {
            let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            return try String(contentsOf: repo.appendingPathComponent("skills/sidefolk/SKILL.md"), encoding: .utf8)
        }
    }

    /// The Agent Skills format both agents read, and no tool the MCP server doesn't offer.
    @Test func theShippedSkillIsWellFormed() throws {
        let text = try Self.shipped
        let lines = text.components(separatedBy: "\n")
        #expect(lines.first == "---")
        let end = try #require(lines.dropFirst().firstIndex(of: "---"))
        let front = lines[1..<end]
        #expect(front.contains("name: sidefolk"))
        let description = try #require(front.first { $0.hasPrefix("description: ") })
        #expect(description.count - "description: ".count <= 1024)
        #expect(front.count == 2)

        let offered = ExternalToolPolicy.all.map { $0.replacingOccurrences(of: ".", with: "_") }
        for tool in offered { #expect(text.contains(tool), "the skill explains \(tool)") }
        let named = Set(text.matches(of: /`([a-z]+_[a-z]+)/).map { String($0.1) })
        let known = Set(offered)
        #expect(named.subtracting(known).isEmpty, "names no tool Sidefolk doesn't offer: \(named.subtracting(known))")
        #expect(AgentIntegrations.marked(text).hasPrefix(lines[0..<end + 1].joined(separator: "\n") + "\n\n<!-- Installed by Sidefolk"))
    }
}

/// Codex sessions through its hooks (D42): no Notification event, PermissionRequest is the tap.
@Suite struct CodexSessionTests {
    @Test func aCodexSessionAsksForApprovalThenFinishes() async throws {
        let t = try await TrackerEnv()
        func codex(_ name: String, _ build: (inout SessionEvent) -> Void = { _ in }) -> SessionEvent {
            t.event(name) { e in
                e.agent = "codex"
                e.cwd = "/Users/me/git/pockito"
                build(&e)
            }
        }
        await t.sessions.apply(codex("UserPromptSubmit") { $0.prompt = "Run the migrations" })
        let waiting = await t.sessions.apply(codex("PermissionRequest") { $0.toolName = "Bash" })
        #expect(waiting?.state == .needsYou)
        #expect(waiting?.detail == "Asks to use Bash")
        var items = try await t.items()
        #expect(items.map(\.title) == ["Codex needs you in pockito"])

        await t.sessions.apply(codex("PreToolUse") { $0.toolName = "Bash" })
        items = try await t.items()
        #expect(items[0].state == .acknowledged)
        t.env.clock.advance(200)
        await t.sessions.apply(codex("Stop"))
        #expect(try await t.items().last?.title == "Codex finished in pockito")
    }

    /// The hook helper forwards Codex's payload (the same fields as Claude Code's) marked as Codex.
    @Test func theHookHelperMarksCodexEvents() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let pipe = Pipe()
        let payload = #"{"session_id":"019a-thread","cwd":"/Users/me/git/pockito","hook_event_name":"PermissionRequest","tool_name":"Bash","turn_id":"t1","model":"gpt-5"}"#
        pipe.fileHandleForWriting.write(Data(payload.utf8))
        try pipe.fileHandleForWriting.close()
        await HookForwarder.run(event: "PermissionRequest", agent: "codex", socketPath: h.dir.socket,
                                input: pipe.fileHandleForReading.fileDescriptor, environment: [:])
        let session = try #require(try await SessionStore(h.env.db).session(id: "019a-thread"))
        #expect(session.agent == "codex")
        #expect(session.state == .needsYou)
    }
}
