import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// Temp stand-ins for ~/.claude.json, ~/.claude/settings.json and ~/.codex/config.toml.
struct FakeAgentHome {
    let root: URL
    let locations: IntegrationLocations
    let helper = "/Users/me/Library/Application Support/Sidefolk/bin/sidefolk"
    let clock = ManualClock(TestEnv.referenceDate)

    init(claude: Bool = true, codex: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sf-integrations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if claude { try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true) }
        if codex { try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true) }
        locations = .standard(home: root.path, environment: [:])
    }

    var integrations: AgentIntegrations { AgentIntegrations(locations: locations, helperPath: helper, clock: clock) }

    func write(_ text: String, to url: URL, mode: mode_t = 0o600) throws {
        try text.write(to: url, atomically: false, encoding: .utf8)
        chmod(url.path, mode)
    }

    func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    func backups() -> [String] {
        let all = (try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? []
        return all.filter { $0.contains(".sidefolk-backup-") }.sorted()
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite struct IntegrationsTests {
    /// Shaped like a real ~/.claude.json (JSON.stringify(_, null, 2)), with keys Sidefolk must not touch.
    static let claudeJSON = """
        {
          "numStartups": 412,
          "installMethod": "native",
          "autoUpdates": false,
          "tipsHistory": {
            "new-user-warmup": 7,
            "prompt-queue": 1.5e2
          },
          "mcpServers": {
            "github": {
              "type": "http",
              "url": "https://api.githubcopilot.com/mcp/"
            }
          },
          "projects": {
            "/Users/me/git/app": {
              "allowedTools": [],
              "history": [],
              "lastCost": 0.1234500,
              "note": "café \\"quoted\\" \\\\ tab\\t"
            }
          },
          "oauthAccount": {
            "emailAddress": "me@example.com"
          }
        }

        """

    @Test func claudeMCPIsAddedAndRemovedExactly() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let file = home.locations.claudeConfig
        try home.write(Self.claudeJSON, to: file)
        let tools = home.integrations
        #expect(tools.status(.claudeMCP).state == .notInstalled)

        let preview = try tools.preview(.claudeMCP, install: true)
        #expect(preview.changesSomething)
        #expect(preview.backup?.lastPathComponent == ".claude.json.sidefolk-backup-20251022-100000")

        let result = try tools.install(.claudeMCP)
        #expect(result.changed)
        #expect(home.read(try #require(result.backup)) == Self.claudeJSON)
        var st = stat()
        stat(result.backup!.path, &st)
        #expect(st.st_mode & 0o777 == 0o600)
        stat(file.path, &st)
        #expect(st.st_mode & 0o777 == 0o600)

        let installed = home.read(file)
        let json = try JSONValue.parse(installed)
        #expect(json["mcpServers"]?["sidefolk"] == ["type": "stdio", "command": .string(home.helper), "args": ["mcp"], "env": [:]])
        #expect(json["mcpServers"]?["github"] != nil)
        // Everything else is byte for byte what it was: key order, number spelling, escapes.
        let expected = Self.claudeJSON.replacingOccurrences(of: """
                  "url": "https://api.githubcopilot.com/mcp/"
                }
              },
            """, with: """
                  "url": "https://api.githubcopilot.com/mcp/"
                },
                "sidefolk": {
                  "type": "stdio",
                  "command": "\(home.helper)",
                  "args": [
                    "mcp"
                  ],
                  "env": {}
                }
              },
            """)
        #expect(installed == expected)
        #expect(tools.status(.claudeMCP).state == .installed)

        // Installing again changes nothing and makes no second backup.
        #expect(try tools.install(.claudeMCP).changed == false)
        #expect(home.backups().count == 1)

        home.clock.advance(60)
        #expect(try tools.remove(.claudeMCP).changed)
        #expect(home.read(file) == Self.claudeJSON)
        #expect(home.backups().count == 2)
    }

    @Test func movedAppShowsAsOutdated() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        try home.write(Self.claudeJSON, to: home.locations.claudeConfig)
        try AgentIntegrations(locations: home.locations, helperPath: "/old/place/sidefolk").install(.claudeMCP)
        #expect(home.integrations.status(.claudeMCP).state == .outdated("/old/place/sidefolk"))
        try home.integrations.install(.claudeMCP)
        #expect(home.integrations.status(.claudeMCP).state == .installed)
    }

    @Test func malformedConfigIsLeftAlone() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        try home.write("{ \"numStartups\": 3, ", to: home.locations.claudeConfig)
        #expect(throws: IntegrationError.self) { try home.integrations.install(.claudeMCP) }
        #expect(home.read(home.locations.claudeConfig) == "{ \"numStartups\": 3, ")
        #expect(home.backups().isEmpty)
    }

    @Test func missingAgentsAreNotSetUp() throws {
        let home = try FakeAgentHome(claude: false, codex: false)
        defer { home.remove() }
        for integration in AgentIntegration.allCases {
            guard case .unavailable = home.integrations.status(integration).state else { Issue.record("\(integration)"); continue }
            #expect(throws: IntegrationError.self) { try home.integrations.install(integration) }
        }
        #expect(!FileManager.default.fileExists(atPath: home.locations.codexConfig.path))
    }

    @Test func symlinkedConfigStaysASymlink() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let real = home.root.appendingPathComponent("dotfiles-claude.json")
        try home.write(Self.claudeJSON, to: real)
        try FileManager.default.createSymbolicLink(at: home.locations.claudeConfig, withDestinationURL: real)
        try home.integrations.install(.claudeMCP)
        let attrs = try FileManager.default.attributesOfItem(atPath: home.locations.claudeConfig.path)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(home.read(real).contains("\"sidefolk\""))
    }

    @Test func concurrentEditIsNotOverwritten() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let file = AgentConfigFile(url: home.locations.claudeConfig)
        try home.write("{}\n", to: home.locations.claudeConfig)
        let snapshot = try file.read()
        try home.write("{\"numStartups\": 1}\n", to: home.locations.claudeConfig)
        let later = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: home.locations.claudeConfig.path)
        #expect(throws: IntegrationError.changedMeanwhile(home.locations.claudeConfig.path)) {
            try file.replace(with: "{\"x\": 1}\n", expecting: snapshot)
        }
        #expect(home.read(home.locations.claudeConfig) == "{\"numStartups\": 1}\n")
    }

    // MARK: Hooks

    static let settings = """
        {
          "permissions": {
            "allow": [
              "Bash(npm test)"
            ]
          },
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "~/bin/check-bash.sh"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "say done"
                  }
                ]
              }
            ]
          },
          "model": "opus"
        }

        """

    @Test func hooksMergeIdempotentlyAndRemoveExactly() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let file = home.locations.claudeSettings
        try home.write(Self.settings, to: file, mode: 0o644)
        let tools = home.integrations
        #expect(tools.status(.claudeHooks).state == .notInstalled)

        try tools.install(.claudeHooks)
        let installed = try JSONValue.parse(home.read(file))
        #expect(installed["permissions"] == ["allow": ["Bash(npm test)"]])
        #expect(installed["model"] == "opus")
        let pre = try #require(installed["hooks"]?["PreToolUse"]?.arrayValue)
        #expect(pre.count == 2)
        #expect(pre[0]["hooks"]?.arrayValue?.first?.string("command") == "~/bin/check-bash.sh")
        #expect(pre[1].string("matcher") == "*")
        let ours = try #require(pre[1]["hooks"]?.arrayValue?.first)
        #expect(ours.string("command") == "'\(home.helper)' hook PreToolUse")
        #expect(ours["timeout"] == 5)
        #expect(installed["hooks"]?["Stop"]?.arrayValue?.count == 2)
        for event in AgentIntegrations.hookEvents {
            #expect(installed["hooks"]?[event]?.arrayValue?.isEmpty == false)
        }
        #expect(tools.status(.claudeHooks).state == .installed)
        var st = stat()
        stat(file.path, &st)
        #expect(st.st_mode & 0o777 == 0o644)

        let once = home.read(file)
        #expect(try tools.install(.claudeHooks).changed == false)
        #expect(home.read(file) == once)

        try tools.remove(.claudeHooks)
        #expect(home.read(file) == Self.settings)
    }

    @Test func hooksIntoAMissingSettingsFile() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let tools = AgentIntegrations(locations: home.locations, helperPath: "/opt/sf/sidefolk", helperEnvironment: ["SIDEFOLK_HOME": "/tmp/dev home"])
        let result = try tools.install(.claudeHooks)
        #expect(result.changed)
        #expect(result.backup == nil)
        let commands = AgentIntegrations.ourHookCommands(in: try OrderedJSON.parse(home.read(home.locations.claudeSettings)))
        #expect(commands.contains("SIDEFOLK_HOME='/tmp/dev home' '/opt/sf/sidefolk' hook Stop"))
        try tools.remove(.claudeHooks)
        #expect(home.read(home.locations.claudeSettings) == "{}\n")
    }

    @Test func recognisesItsOwnHooksOnly() {
        #expect(AgentIntegrations.isOurHook("'/Users/me/Library/Application Support/Sidefolk/bin/sidefolk' hook Stop"))
        #expect(AgentIntegrations.isOurHook("SIDEFOLK_HOME='/x' '/opt/sidefolk' hook Notification"))
        #expect(AgentIntegrations.isOurHook("sidefolk hook Stop"))
        #expect(!AgentIntegrations.isOurHook("say done"))
        #expect(!AgentIntegrations.isOurHook("/usr/local/bin/notsidefolk hook Stop"))
        #expect(!AgentIntegrations.isOurHook("sidefolk hook Stop; curl evil"))
    }

    // MARK: Codex

    static let codex = """
        model = "gpt-5-codex"
        approval_policy = "on-request"

        [mcp_servers.github]
        command = "npx"
        args = ["-y", "@modelcontextprotocol/server-github"]

        [profiles.fast]
        model = "gpt-5-mini" # quick one

        """

    @Test func codexSectionIsAddedAndRemovedExactly() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let file = home.locations.codexConfig
        try home.write(Self.codex, to: file)
        let tools = home.integrations
        #expect(tools.status(.codexMCP).state == .notInstalled)

        try tools.install(.codexMCP)
        let text = home.read(file)
        #expect(text.hasPrefix(Self.codex))
        #expect(text.hasSuffix("[mcp_servers.sidefolk]\ncommand = \"\(home.helper)\"\nargs = [\"mcp\"]\n"))
        #expect(tools.status(.codexMCP).state == .installed)
        #expect(TOMLSection.command(in: text, table: "mcp_servers.github") == "npx")

        #expect(try tools.install(.codexMCP).changed == false)
        try tools.remove(.codexMCP)
        #expect(home.read(file) == Self.codex)
    }

    @Test func codexSectionInTheMiddleIsReplaced() throws {
        let home = try FakeAgentHome()
        defer { home.remove() }
        let file = home.locations.codexConfig
        let before = "model = \"o3\"\n\n[mcp_servers.\"sidefolk\"]\ncommand = \"/old/sidefolk\"\nargs = [\"mcp\"]\n\n[mcp_servers.sidefolk.env]\nX = \"1\"\n\n[profiles.a]\nmodel = \"o4\"\n"
        try home.write(before, to: file)
        #expect(home.integrations.status(.codexMCP).state == .outdated("/old/sidefolk"))
        try home.integrations.install(.codexMCP)
        let text = home.read(file)
        #expect(!text.contains("/old/sidefolk"))
        #expect(!text.contains("X = \"1\""))
        #expect(text.contains("[profiles.a]\nmodel = \"o4\"\n"))
        #expect(home.integrations.status(.codexMCP).state == .installed)
    }

    @Test func tomlQuoting() {
        #expect(TOMLSection.quote(#"/a "b"\c"#) == #""/a \"b\"\\c""#)
        #expect(TOMLSection.headerKey(" [ mcp_servers . 'sidefolk' ] # mine") == "mcp_servers.sidefolk")
        #expect(TOMLSection.headerKey("command = \"[x]\"") == nil)
    }

    // MARK: OrderedJSON

    @Test func orderedJSONRoundTrips() throws {
        let text = "{\n  \"b\": 1,\n  \"a\": [\n    true,\n    null,\n    -2.50e+3,\n    \"\\u2603 \\ud83d\\ude00 \\/\"\n  ],\n  \"e\": {},\n  \"f\": []\n}"
        let value = try OrderedJSON.parse(text)
        #expect(value.serialized() == text.replacingOccurrences(of: "\\u2603 \\ud83d\\ude00 \\/", with: "☃ 😀 /"))
        #expect(throws: OrderedJSON.ParseError.self) { try OrderedJSON.parse("{\"a\": 1} trailing") }
        #expect(throws: OrderedJSON.ParseError.self) { try OrderedJSON.parse("[1, 2,]") }
        #expect(OrderedJSON.quote("a\u{1}b") == "\"a\\u0001b\"")
    }
}
