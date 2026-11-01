import Foundation

/// Where other agents keep their configuration. Injected everywhere: tests use temp files, and the
/// app uses `.forApp(paths:)`, edited only after the user clicked and confirmed.
public struct IntegrationLocations: Sendable, Equatable {
    /// Claude Code's global config with user-scope `mcpServers` (`~/.claude.json`).
    public var claudeConfig: URL
    /// Claude Code's user settings with `hooks` (`~/.claude/settings.json`).
    public var claudeSettings: URL
    /// Codex's config (`~/.codex/config.toml`).
    public var codexConfig: URL
    /// Claude Code's user skills (`~/.claude/skills`), one folder per skill with a SKILL.md.
    public var claudeSkills: URL
    /// Codex's user skills (`~/.codex/skills`; Codex also reads `~/.agents/skills`).
    public var codexSkills: URL
    /// Codex's user hooks (`~/.codex/hooks.json`), in Claude Code's format.
    public var codexHooks: URL

    /// The skills folders and Codex's hooks file default to their places beside the given configs.
    public init(claudeConfig: URL, claudeSettings: URL, codexConfig: URL, claudeSkills: URL? = nil, codexSkills: URL? = nil,
                codexHooks: URL? = nil) {
        self.claudeConfig = claudeConfig
        self.claudeSettings = claudeSettings
        self.codexConfig = codexConfig
        let claudeDir = claudeSettings.deletingLastPathComponent(), codexDir = codexConfig.deletingLastPathComponent()
        self.claudeSkills = claudeSkills ?? claudeDir.appendingPathComponent("skills", isDirectory: true)
        self.codexSkills = codexSkills ?? codexDir.appendingPathComponent("skills", isDirectory: true)
        self.codexHooks = codexHooks ?? codexDir.appendingPathComponent("hooks.json")
    }

    /// The real locations, honouring `CLAUDE_CONFIG_DIR` and `CODEX_HOME` (checked against Claude Code 2.1
    /// and Codex 0.160: each reads user skills from `<its folder>/skills/<name>/SKILL.md`).
    public static func standard(home: String = NSHomeDirectory(),
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> IntegrationLocations {
        let claudeDir = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        let codexDir = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.codex"
        return IntegrationLocations(
            claudeConfig: URL(fileURLWithPath: (claudeDir ?? home) + "/.claude.json"),
            claudeSettings: URL(fileURLWithPath: (claudeDir ?? home + "/.claude") + "/settings.json"),
            codexConfig: URL(fileURLWithPath: codexDir + "/config.toml"))
    }

    /// What the app may change. Only a copy on the person's own data folder gets the real locations; on
    /// any other (`SIDEFOLK_HOME`: `make dev`, agents' QA runs) Connect writes stand-ins inside that folder,
    /// whatever `CLAUDE_CONFIG_DIR` and `CODEX_HOME` say. A QA copy once pointed the person's Claude Code
    /// and Codex at its own helper, and both failed on every start once its folder was deleted (D86).
    public static func forApp(paths: SidefolkPaths, home: String = NSHomeDirectory(),
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> IntegrationLocations {
        if paths.isDefaultHome { return .standard(home: home, environment: environment) }
        // Laid out as `CLAUDE_CONFIG_DIR` and `CODEX_HOME` folders, so a throwaway agent can be pointed at them.
        let standIns = paths.agentConfigs
        return .standard(home: standIns.path, environment: ["CLAUDE_CONFIG_DIR": standIns.appendingPathComponent("claude").path,
                                                             "CODEX_HOME": standIns.appendingPathComponent("codex").path])
    }

    /// Where the app links the `sidefolk` command: `~/.local/bin/sidefolk`, or a stand-in inside any other
    /// data folder, as for `forApp`.
    public static func commandLineTool(paths: SidefolkPaths, home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: (paths.isDefaultHome ? home : paths.agentConfigs.path) + "/.local/bin/sidefolk")
    }

    /// Connect's words name the usual places ("~/.claude.json"); these are where this copy really writes each, as the
    /// person reads a path: the stand-ins in a dev or QA copy (D86), the folders `CLAUDE_CONFIG_DIR` and `CODEX_HOME`
    /// name, or the same words when they are the usual places.
    public func shownPlaces(commandLineTool: URL) -> [(usual: String, shown: String)] {
        [("~/.claude.json", claudeConfig), ("~/.claude/settings.json", claudeSettings), ("~/.claude/skills", claudeSkills),
         ("~/.codex/config.toml", codexConfig), ("~/.codex/skills", codexSkills), ("~/.codex/hooks.json", codexHooks),
         ("~/.local/bin/sidefolk", commandLineTool)]
            .map { ($0.0, FolderAccess.displayPath($0.1.path)) }
    }

    /// `text` with each usual place replaced by where it really is.
    public static func shown(_ text: String, places: [(usual: String, shown: String)]) -> String {
        places.reduce(text) { $0.replacingOccurrences(of: $1.usual, with: $1.shown) }
    }

    /// Starts the stand-ins off as this Mac's agents are: Connect never sets up an agent that isn't there,
    /// so empty stand-ins would leave nothing to connect in a dev copy. Only checks that the real files exist.
    public static func prepareStandIns(paths: SidefolkPaths, home: String = NSHomeDirectory(),
                                       environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard !paths.isDefaultHome else { return }
        let real = standard(home: home, environment: environment), standIns = forApp(paths: paths)
        let fm = FileManager.default
        func folder(_ url: URL) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if fm.fileExists(atPath: real.claudeSettings.deletingLastPathComponent().path) {
            folder(standIns.claudeSettings.deletingLastPathComponent())
        }
        if fm.fileExists(atPath: real.claudeConfig.path), !fm.fileExists(atPath: standIns.claudeConfig.path) {
            folder(standIns.claudeConfig.deletingLastPathComponent())
            fm.createFile(atPath: standIns.claudeConfig.path, contents: Data("{}\n".utf8), attributes: [.posixPermissions: 0o600])
        }
        if fm.fileExists(atPath: real.codexConfig.deletingLastPathComponent().path) {
            folder(standIns.codexConfig.deletingLastPathComponent())
        }
    }
}
