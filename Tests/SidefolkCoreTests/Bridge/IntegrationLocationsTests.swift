import Foundation
import Testing
@testable import SidefolkCore

/// Which agent configs the app may change (D86): a copy on another data folder never reaches the person's.
@Suite struct IntegrationLocationsTests {
    static func everyPath(_ l: IntegrationLocations) -> [String] {
        [l.claudeConfig, l.claudeSettings, l.claudeSkills, l.codexConfig, l.codexHooks, l.codexSkills].map(\.path)
    }

    static func dataFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sf-standins-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func aCopyOnAnotherDataFolderNeverResolvesToTheRealConfigs() {
        let me = NSHomeDirectory(), folder = Self.dataFolder()
        // What the QA run that broke the founder's agents had, and an agent's shell that names the real folders.
        let environments = [[:], ProcessInfo.processInfo.environment,
                            ["CLAUDE_CONFIG_DIR": me + "/.claude", "CODEX_HOME": me + "/.codex"]]
        let real = Set(environments.flatMap { Self.everyPath(.standard(home: me, environment: $0)) })
        for paths in [SidefolkPaths(home: folder), SidefolkPaths.standard(environment: ["SIDEFOLK_HOME": folder.path])] {
            #expect(!paths.isDefaultHome)
            for environment in environments {
                let resolved = Self.everyPath(.forApp(paths: paths, home: me, environment: environment))
                    + [IntegrationLocations.commandLineTool(paths: paths, home: me).path]
                for path in resolved {
                    #expect(path.hasPrefix(paths.agentConfigs.path + "/"), "\(path)")
                    #expect(!real.contains(path) && !path.hasPrefix(me + "/.claude") && !path.hasPrefix(me + "/.codex"))
                    #expect(path != me + "/.local/bin/sidefolk")
                }
            }
        }
    }

    @Test func thePersonsOwnDataFolderGetsTheRealOnes() {
        let env = ["CLAUDE_CONFIG_DIR": "/cfg/claude"]
        for paths in [SidefolkPaths.standard(environment: [:]), SidefolkPaths(home: SidefolkPaths.defaultHome),
                      SidefolkPaths.standard(environment: ["SIDEFOLK_HOME": SidefolkPaths.defaultHome.path + "/"])] {
            #expect(paths.isDefaultHome)
            #expect(IntegrationLocations.forApp(paths: paths, home: "/Users/me", environment: env)
                    == .standard(home: "/Users/me", environment: env))
            #expect(IntegrationLocations.commandLineTool(paths: paths, home: "/Users/me").path == "/Users/me/.local/bin/sidefolk")
        }
    }

    /// Every file under a folder with its contents, to show nothing in it changed.
    static func snapshot(_ root: URL) throws -> [String: Data] {
        let fm = FileManager.default
        var all: [String: Data] = [:]
        for sub in try fm.subpathsOfDirectory(atPath: root.path) {
            all[sub] = fm.contents(atPath: root.appendingPathComponent(sub).path) ?? Data()
        }
        return all
    }

    /// The stand-ins start as this Mac's agents are, Connect works in them, and the real files stay as they were.
    @Test func connectInADevCopyStaysInsideItsFolder() throws {
        let person = try FakeAgentHome(codex: false), folder = Self.dataFolder()
        defer { person.remove(); try? FileManager.default.removeItem(at: folder) }
        let realConfig = person.root.appendingPathComponent(".claude.json")
        try person.write(IntegrationsTests.claudeJSON, to: realConfig)
        let before = try FileManager.default.subpathsOfDirectory(atPath: person.root.path).sorted()

        let paths = SidefolkPaths(home: folder)
        IntegrationLocations.prepareStandIns(paths: paths, home: person.root.path, environment: [:])
        let locations = IntegrationLocations.forApp(paths: paths, home: person.root.path, environment: [:])
        let tools = AgentIntegrations(locations: locations, helperPath: folder.appendingPathComponent("bin/sidefolk").path,
                                      helperEnvironment: ["SIDEFOLK_HOME": folder.path])
        #expect(person.read(locations.claudeConfig) == "{}\n")
        #expect(tools.status(.codexMCP).state == .unavailable(String(localized: "Codex isn't set up on this Mac.")))
        try tools.install(.claudeMCP)
        try tools.install(.claudeHooks)
        #expect(tools.status(.claudeMCP).state == .installed)
        #expect(tools.status(.claudeHooks).state == .installed)
        #expect(locations.claudeConfig.path == folder.path + "/agent-configs/claude/.claude.json")

        #expect(person.read(realConfig) == IntegrationsTests.claudeJSON)
        #expect(try FileManager.default.subpathsOfDirectory(atPath: person.root.path).sorted() == before)
    }

    /// All six things Connect writes (both agents' tools, skills and hooks), and their removal, land in the
    /// stand-ins of a dev copy, even when its shell names the person's real folders; not one byte of theirs changes.
    @Test func everyConnectionInADevCopyWritesOnlyUnderItsFolder() throws {
        let person = try FakeAgentHome(), folder = Self.dataFolder()
        defer { person.remove(); try? FileManager.default.removeItem(at: folder) }
        try person.write(IntegrationsTests.claudeJSON, to: person.root.appendingPathComponent(".claude.json"))
        try person.write("model = \"o4\"\n", to: person.root.appendingPathComponent(".codex/config.toml"))
        let before = try Self.snapshot(person.root)
        let shell = ["CLAUDE_CONFIG_DIR": person.root.path + "/.claude", "CODEX_HOME": person.root.path + "/.codex"]

        let paths = SidefolkPaths(home: folder)
        IntegrationLocations.prepareStandIns(paths: paths, home: person.root.path, environment: [:])
        let tools = AgentIntegrations(locations: .forApp(paths: paths, home: person.root.path, environment: shell),
                                      helperPath: folder.appendingPathComponent("bin/sidefolk").path,
                                      helperEnvironment: ["SIDEFOLK_HOME": folder.path], skill: AgentSkillTests.skill)
        for integration in AgentIntegration.allCases {
            #expect(tools.file(for: integration).path.hasPrefix(paths.agentConfigs.path + "/"), "\(integration)")
            try tools.install(integration)
            #expect(tools.status(integration).state == .installed, "\(integration)")
        }
        #expect(try Self.snapshot(person.root) == before)
        for integration in AgentIntegration.allCases { try tools.remove(integration) }
        #expect(try Self.snapshot(person.root) == before)
    }
}
