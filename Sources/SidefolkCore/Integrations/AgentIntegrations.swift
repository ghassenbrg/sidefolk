import Foundation

/// Where other agents keep their configuration. Injected everywhere: tests use temp files, and the
/// app passes `.standard()` only after the user clicked and confirmed.
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
}

public enum AgentIntegration: String, Sendable, CaseIterable {
    /// Sidefolk's tools in Claude Code (user-scope MCP server "sidefolk").
    case claudeMCP
    /// The Sidefolk skill in Claude Code: when and how to use those tools.
    case claudeSkill
    /// Claude Code hooks that tell Sidefolk when a session needs you or finished.
    case claudeHooks
    /// Sidefolk's tools in Codex (`[mcp_servers.sidefolk]`).
    case codexMCP
    /// The Sidefolk skill in Codex.
    case codexSkill
    /// Codex hooks that tell Sidefolk when a session needs you or finished.
    case codexHooks

    public var title: String {
        switch self {
        case .claudeMCP: String(localized: "Sidefolk tools in Claude Code")
        case .claudeSkill: String(localized: "Sidefolk skill in Claude Code")
        case .claudeHooks: String(localized: "Claude Code session updates")
        case .codexMCP: String(localized: "Sidefolk tools in Codex")
        case .codexSkill: String(localized: "Sidefolk skill in Codex")
        case .codexHooks: String(localized: "Codex session updates")
        }
    }

    var isSkill: Bool { self == .claudeSkill || self == .codexSkill }
    var isHooks: Bool { self == .claudeHooks || self == .codexHooks }
}

public struct IntegrationStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case notInstalled
        case installed
        /// Installed, but pointing at another `sidefolk` (the app moved): installing again fixes it.
        case outdated(String)
        /// The agent isn't set up on this Mac (or its config can't be read).
        case unavailable(String)
    }

    public var integration: AgentIntegration
    public var file: URL
    public var state: State
}

/// What a click will do, for the confirmation sheet: the file, the plain-language changes and
/// where the backup will go.
public struct IntegrationPreview: Sendable, Equatable {
    public var integration: AgentIntegration
    public var install: Bool
    public var file: URL
    public var changes: [String]
    /// nil when the file doesn't exist yet or nothing would change.
    public var backup: URL?
    public var changesSomething: Bool
}

public struct IntegrationResult: Sendable, Equatable {
    public var changed: Bool
    public var backup: URL?
}

/// Connects Sidefolk to Claude Code and Codex by editing their config files, only after the user
/// clicked and confirmed (AGENTS.md, SECURITY.md §5): a timestamped backup beside the file first,
/// then an atomic write that leaves every unrelated key, hook and section exactly as it was.
///
/// Claude Code's MCP server is written into `~/.claude.json` directly rather than through
/// `claude mcp add --scope user`: the edit is deterministic and testable, needs no CLI on PATH or
/// CLI startup (network, auto-update), works across CLI versions, and gets the same backup and
/// exact removal as the other files. Claude Code writes the file with `JSON.stringify(_, null, 2)`,
/// which `OrderedJSON` reproduces, and a write is refused if the file changed since it was read.
public struct AgentIntegrations: Sendable {
    public static let serverName = "sidefolk"
    /// Hook events Sidefolk listens to, with a short timeout: hooks must never slow a session.
    public static let hookEvents = ["UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"]
    /// Codex's hooks have no Notification; PermissionRequest is when a session waits for an approval.
    public static let codexHookEvents = ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SessionEnd"]
    public static let hookTimeoutSeconds = 5
    /// Codex clamps a SessionEnd hook to 3 s (and warns about a longer one); the helper is done within 2.
    public static let codexHookTimeoutSeconds = 3

    public let locations: IntegrationLocations
    /// The stable path of the `sidefolk` helper (not inside a translocated or moving app bundle).
    public let helperPath: String
    /// Extra environment for the helper (e.g. `SIDEFOLK_HOME` for a dev build); empty in release.
    public let helperEnvironment: [String: String]
    /// The Sidefolk skill for other agents (skills/sidefolk/SKILL.md, shipped in the app); nil when this copy
    /// of Sidefolk has none, and then there is no skill to install.
    public let skill: String?
    private let clock: any Clock

    public init(locations: IntegrationLocations, helperPath: String, helperEnvironment: [String: String] = [:],
                skill: String? = nil, clock: any Clock = SystemClock()) {
        self.locations = locations
        self.helperPath = helperPath
        self.helperEnvironment = helperEnvironment
        self.skill = skill
        self.clock = clock
    }

    public func file(for integration: AgentIntegration) -> URL {
        switch integration {
        case .claudeMCP: locations.claudeConfig
        case .claudeSkill: Self.skillFile(in: locations.claudeSkills)
        case .claudeHooks: locations.claudeSettings
        case .codexMCP: locations.codexConfig
        case .codexSkill: Self.skillFile(in: locations.codexSkills)
        case .codexHooks: locations.codexHooks
        }
    }

    // MARK: Status

    public func status() -> [IntegrationStatus] { AgentIntegration.allCases.map(status) }

    public func status(_ integration: AgentIntegration) -> IntegrationStatus {
        let url = file(for: integration)
        func make(_ state: IntegrationStatus.State) -> IntegrationStatus { IntegrationStatus(integration: integration, file: url, state: state) }
        if let missing = unavailableReason(integration) { return make(.unavailable(missing)) }
        do {
            let text = try AgentConfigFile(url: url).read().text ?? ""
            switch integration {
            case .claudeMCP:
                guard let server = try parseJSON(text, url)["mcpServers"]?[Self.serverName] else { return make(.notInstalled) }
                let command = server["command"]?.stringValue ?? ""
                return make(command == helperPath ? .installed : .outdated(command))
            case .claudeHooks, .codexHooks:
                let ours = Self.ourHookCommands(in: try parseJSON(text, url))
                if ours.isEmpty { return make(.notInstalled) }
                return make(Set(ours) == Set(expectedHookCommands(integration)) ? .installed : .outdated(ours.first ?? ""))
            case .codexMCP:
                guard let command = TOMLSection.command(in: text, table: Self.codexTable) else {
                    return TOMLSection.contains(text, table: Self.codexTable) ? make(.outdated("")) : make(.notInstalled)
                }
                return make(command == helperPath ? .installed : .outdated(command))
            case .claudeSkill, .codexSkill:
                if text == installedSkill { return make(.installed) }
                // An older copy of ours is replaced on the next Connect; someone else's file only after a backup.
                return make(text.contains(Self.skillMarker) ? .outdated(url.path) : .notInstalled)
            }
        } catch {
            return make(.unavailable("\(error)"))
        }
    }

    /// The agent's config folder must exist: Sidefolk never sets up an agent the user doesn't have.
    private func unavailableReason(_ integration: AgentIntegration) -> String? {
        let fm = FileManager.default
        let claudeMissing = String(localized: "Claude Code isn't set up on this Mac.")
        let codexMissing = String(localized: "Codex isn't set up on this Mac.")
        switch integration {
        case .claudeMCP:
            return fm.fileExists(atPath: locations.claudeConfig.path) ? nil : claudeMissing
        case .claudeHooks, .claudeSkill:
            if integration.isSkill, let why = skillUnavailable(integration) { return why }
            let dir = locations.claudeSettings.deletingLastPathComponent().path
            return fm.fileExists(atPath: dir) ? nil : claudeMissing
        case .codexMCP, .codexHooks, .codexSkill:
            if integration.isSkill, let why = skillUnavailable(integration) { return why }
            let dir = locations.codexConfig.deletingLastPathComponent().path
            return fm.fileExists(atPath: dir) ? nil : codexMissing
        }
    }

    private func skillUnavailable(_ integration: AgentIntegration) -> String? {
        if skill == nil { return String(localized: "This copy of Sidefolk has no skill to install.") }
        if let link = linkedSkillPath(integration) {
            return String(localized: "\(FolderAccess.displayPath(link)) is a link to somewhere else, so Sidefolk leaves it as it is.")
        }
        return nil
    }

    /// The skill's folder or file when either is a symbolic link. People link skills in from their own
    /// checkouts; writing or deleting through the link would change their files, not the agent's setup.
    func linkedSkillPath(_ integration: AgentIntegration) -> String? {
        let file = file(for: integration)
        return [file.deletingLastPathComponent().path, file.path].first { path in
            var st = stat()
            return lstat(path, &st) == 0 && st.st_mode & S_IFMT == S_IFLNK
        }
    }

    // MARK: Preview and apply

    /// What applying an integration does to its file.
    enum Change: Equatable {
        case keep
        case write(String)
        /// The file goes: a skill Sidefolk installed, or a hooks file left with nothing in it.
        case delete
    }

    public func preview(_ integration: AgentIntegration, install: Bool) throws -> IntegrationPreview {
        let config = AgentConfigFile(url: file(for: integration))
        let snapshot = try config.read()
        let change = try edited(integration, install: install, text: snapshot.text)
        return IntegrationPreview(integration: integration, install: install, file: config.url,
                                  changes: describe(integration, install: install),
                                  backup: change != .keep && needsBackup(integration, snapshot) ? config.backupURL(at: clock.now) : nil,
                                  changesSomething: change != .keep)
    }

    @discardableResult
    public func install(_ integration: AgentIntegration) throws -> IntegrationResult { try apply(integration, install: true) }

    @discardableResult
    public func remove(_ integration: AgentIntegration) throws -> IntegrationResult { try apply(integration, install: false) }

    private func apply(_ integration: AgentIntegration, install: Bool) throws -> IntegrationResult {
        if install, let reason = unavailableReason(integration) { throw IntegrationError.unavailable(reason) }
        let config = AgentConfigFile(url: file(for: integration))
        let snapshot = try config.read()
        let change = try edited(integration, install: install, text: snapshot.text)
        guard change != .keep else { return IntegrationResult(changed: false, backup: nil) }
        var backup: URL?
        if needsBackup(integration, snapshot) {
            let url = config.backupURL(at: clock.now)
            try config.backup(snapshot, to: url)
            backup = url
        }
        switch change {
        case .write(let text): try config.replace(with: text, expecting: snapshot)
        // A skill's folder goes with it when nothing else is in it.
        case .delete: try config.delete(expecting: snapshot, removingEmptyFolder: integration.isSkill)
        case .keep: break
        }
        Log.shared.info("integrations", "\(install ? "installed" : "removed") \(integration.rawValue)",
                        ["file": FolderAccess.displayPath(config.url.path), "backup": backup.map { FolderAccess.displayPath($0.path) } ?? "none"])
        return IntegrationResult(changed: true, backup: backup)
    }

    /// Every file that exists is backed up before it changes, except a skill that is exactly the one Sidefolk
    /// installs: the app can write it again, and a backup beside it would keep its folder from going away.
    private func needsBackup(_ integration: AgentIntegration, _ snapshot: AgentConfigFile.Snapshot) -> Bool {
        guard let text = snapshot.text else { return false }
        return !(integration.isSkill && text == installedSkill)
    }

    /// What applying `integration` does to a file with this text (nil: there is no file).
    func edited(_ integration: AgentIntegration, install: Bool, text: String?) throws -> Change {
        let url = file(for: integration)
        func written(_ new: String) -> Change { new == text ? .keep : .write(new) }
        switch integration {
        case .claudeMCP:
            guard let text else {
                if install { throw IntegrationError.unavailable(String(localized: "Claude Code isn't set up on this Mac.")) }
                return .keep
            }
            var root = try parseJSON(text, url)
            var servers = root["mcpServers"] ?? .object([])
            guard servers.isObject else { throw IntegrationError.malformed(url.path, "mcpServers is not an object") }
            if install {
                servers[Self.serverName] = mcpServerEntry()
            } else {
                guard servers[Self.serverName] != nil else { return .keep }
                servers[Self.serverName] = nil
            }
            root["mcpServers"] = servers
            return written(Self.write(root, like: text))

        case .claudeHooks, .codexHooks:
            var root = try text.map { try parseJSON($0, url) } ?? .object([])
            var hooks = root["hooks"] ?? .object([])
            guard hooks.isObject else { throw IntegrationError.malformed(url.path, "hooks is not an object") }
            hooks = Self.withoutOurHooks(hooks)
            if install { hooks = withOurHooks(hooks, integration) }
            if case .object(let members) = hooks, members.isEmpty { root["hooks"] = nil } else { root["hooks"] = hooks }
            if case .object(let members) = root, members.isEmpty {
                // Codex's hooks.json holds nothing but hooks: an empty one goes, as if it had never been made.
                if text == nil { return .keep }
                if integration == .codexHooks { return .delete }
            }
            return written(Self.write(root, like: text ?? ""))

        case .codexMCP:
            let current = text ?? ""
            let without = TOMLSection.removing(Self.codexTable, from: current)
            if !install { return text == nil ? .keep : written(without) }
            return written(TOMLSection.appending(codexSection(), to: without))

        case .claudeSkill, .codexSkill:
            if install {
                if let why = skillUnavailable(integration) { throw IntegrationError.unavailable(why) }
                return written(installedSkill ?? "")
            }
            // Only a skill Sidefolk installed is removed, never through a link; a file of the person's own with
            // the same name stays.
            guard let text, text.contains(Self.skillMarker), linkedSkillPath(integration) == nil else { return .keep }
            return .delete
        }
    }

    // MARK: Claude Code

    func mcpServerEntry() -> OrderedJSON {
        var members: [OrderedJSON.Member] = [
            .init(key: "type", value: .string("stdio")),
            .init(key: "command", value: .string(helperPath)),
            .init(key: "args", value: .array([.string("mcp")])),
        ]
        members.append(.init(key: "env", value: .object(helperEnvironment.sorted { $0.key < $1.key }.map {
            .init(key: $0.key, value: .string($0.value))
        })))
        return .object(members)
    }

    /// `'/path/to/sidefolk' hook Stop` (quoted: the stable path has a space in "Application Support"), with
    /// `--agent codex` for Codex's hooks.
    func hookCommand(_ event: String, agent: String = "claude-code") -> String {
        let env = helperEnvironment.sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.shellQuote($0.value)) " }.joined()
        return env + Self.shellQuote(helperPath) + " hook " + event + (agent == "claude-code" ? "" : " --agent " + agent)
    }

    func expectedHookCommands(_ integration: AgentIntegration) -> [String] {
        integration == .codexHooks ? Self.codexHookEvents.map { hookCommand($0, agent: "codex") } : Self.hookEvents.map { hookCommand($0) }
    }

    /// Adds one matcher group with our handler to each event. Claude Code matches every tool with "*"; Codex reads
    /// matchers as patterns, where a group without one already matches every tool.
    func withOurHooks(_ hooks: OrderedJSON, _ integration: AgentIntegration) -> OrderedJSON {
        var hooks = hooks
        let codex = integration == .codexHooks
        for event in codex ? Self.codexHookEvents : Self.hookEvents {
            var group: OrderedJSON = .object([])
            if event == "PreToolUse", !codex { group["matcher"] = .string("*") }
            group["hooks"] = .array([.object([
                .init(key: "type", value: .string("command")),
                .init(key: "command", value: .string(hookCommand(event, agent: codex ? "codex" : "claude-code"))),
                .init(key: "timeout", value: .number("\(codex ? Self.codexHookTimeoutSeconds : Self.hookTimeoutSeconds)")),
            ])])
            hooks[event] = .array((hooks[event]?.arrayValue ?? []) + [group])
        }
        return hooks
    }

    /// Our hook commands anywhere in a settings object.
    static func ourHookCommands(in root: OrderedJSON) -> [String] {
        guard case .object(let events)? = root["hooks"] else { return [] }
        return events.flatMap { event in
            (event.value.arrayValue ?? []).flatMap { group in
                (group["hooks"]?.arrayValue ?? []).compactMap { $0["command"]?.stringValue }.filter(isOurHook)
            }
        }
    }

    /// Drops our handlers, then any matcher group or event they leave empty. Everything else stays.
    static func withoutOurHooks(_ hooks: OrderedJSON) -> OrderedJSON {
        guard case .object(let events) = hooks else { return hooks }
        var kept: [OrderedJSON.Member] = []
        for event in events {
            guard case .array(let groups) = event.value else { kept.append(event); continue }
            var keptGroups: [OrderedJSON] = []
            for var group in groups {
                guard case .array(let handlers)? = group["hooks"] else { keptGroups.append(group); continue }
                let remaining = handlers.filter { !isOurHook($0["command"]?.stringValue ?? "") }
                if remaining.count == handlers.count { keptGroups.append(group); continue }
                if remaining.isEmpty { continue }
                group["hooks"] = .array(remaining)
                keptGroups.append(group)
            }
            if keptGroups.isEmpty && !groups.isEmpty { continue }
            kept.append(.init(key: event.key, value: .array(keptGroups)))
        }
        return .object(kept)
    }

    /// `… sidefolk' hook Event` (or `… hook Event --agent codex`) with the executable named `sidefolk`,
    /// whatever folder it is in.
    static func isOurHook(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let pattern = #"(^|[\s/'"])sidefolk'?"? hook [A-Za-z]+( --agent [a-z-]+)?$"#
        guard let range = trimmed.range(of: pattern, options: .regularExpression) else { return false }
        return !range.isEmpty
    }

    // MARK: Codex

    static let codexTable = "mcp_servers.sidefolk"

    func codexSection() -> String {
        var lines = ["[\(Self.codexTable)]", "command = \(TOMLSection.quote(helperPath))", "args = [\"mcp\"]"]
        if !helperEnvironment.isEmpty {
            lines += ["", "[\(Self.codexTable).env]"]
            lines += helperEnvironment.sorted { $0.key < $1.key }.map { "\($0.key) = \(TOMLSection.quote($0.value))" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: The Sidefolk skill

    static let skillName = "sidefolk"
    /// Starts the line Sidefolk puts under the skill's front matter: how it knows its own copy, and how the
    /// person reading the file learns where it came from.
    static let skillMarker = "<!-- Installed by Sidefolk"

    static func skillFile(in folder: URL) -> URL {
        folder.appendingPathComponent(skillName, isDirectory: true).appendingPathComponent("SKILL.md")
    }

    /// The skill as installed: the shipped text with that line.
    var installedSkill: String? { skill.map(Self.marked) }

    static func marked(_ skill: String) -> String {
        let note = "\(skillMarker) from Settings › Agents. Disconnect there removes it; Connect replaces any edits. -->\n"
        // The front matter has to stay first for the agents to read the skill's name and description.
        guard skill.hasPrefix("---\n"), let close = skill.range(of: "\n---\n", range: skill.index(skill.startIndex, offsetBy: 3)..<skill.endIndex) else {
            return skill + (skill.hasSuffix("\n") ? "\n" : "\n\n") + note
        }
        return String(skill[..<close.upperBound]) + "\n" + note + String(skill[close.upperBound...])
    }

    // MARK: Helpers

    private func describe(_ integration: AgentIntegration, install: Bool) -> [String] {
        let helper = FolderAccess.displayPath(helperPath)
        let folder = FolderAccess.displayPath(file(for: integration).deletingLastPathComponent().path)
        switch (integration, install) {
        case (.claudeMCP, true): return [String(localized: "Adds the MCP server “sidefolk” (runs \(helper) mcp) to Claude Code's user settings.")]
        case (.claudeMCP, false): return [String(localized: "Removes the MCP server “sidefolk” from Claude Code. Other servers stay.")]
        case (.claudeHooks, true):
            let events = Self.hookEvents.joined(separator: ", ")
            return [String(localized: "Adds hooks for \(events) that run \(helper) hook (\(Self.hookTimeoutSeconds) s limit)."),
                    String(localized: "Your other hooks stay as they are.")]
        case (.claudeHooks, false): return [String(localized: "Removes Sidefolk's hooks from Claude Code. Your other hooks stay.")]
        case (.codexMCP, true): return [String(localized: "Adds [\(Self.codexTable)] (runs \(helper) mcp) to Codex's config.")]
        case (.codexMCP, false): return [String(localized: "Removes [\(Self.codexTable)] from Codex's config. The rest stays.")]
        case (.claudeSkill, true), (.codexSkill, true):
            return [String(localized: "Adds the Sidefolk skill in \(folder), which tells the agent when and how to use Sidefolk's tools.")]
        case (.claudeSkill, false), (.codexSkill, false):
            return [String(localized: "Removes the Sidefolk skill from \(folder). Your other skills stay.")]
        case (.codexHooks, true):
            let events = Self.codexHookEvents.joined(separator: ", ")
            return [String(localized: "Adds hooks for \(events) that run \(helper) hook (\(Self.codexHookTimeoutSeconds) s limit)."),
                    String(localized: "Codex asks you to trust them once, the next time it starts. Your other hooks stay as they are.")]
        case (.codexHooks, false): return [String(localized: "Removes Sidefolk's hooks from Codex. Your other hooks stay.")]
        }
    }

    private func parseJSON(_ text: String, _ url: URL) throws -> OrderedJSON {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .object([]) }
        let value: OrderedJSON
        do { value = try OrderedJSON.parse(text) } catch { throw IntegrationError.malformed(url.path, "\(error)") }
        guard value.isObject else { throw IntegrationError.malformed(url.path, "not a JSON object") }
        return value
    }

    /// Keeps the file's trailing newline convention.
    private static func write(_ root: OrderedJSON, like original: String) -> String {
        root.serialized() + (original.hasSuffix("\n") || original.isEmpty ? "\n" : "")
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// Just enough TOML to own one table (and its subtables) in someone else's file: find it by its
/// header, remove it, append it. Every other line is left byte for byte.
enum TOMLSection {
    /// Whether `table` or one of its subtables has a header in `text`.
    static func contains(_ text: String, table: String) -> Bool {
        text.components(separatedBy: "\n").contains { headerKey($0).map { isOwned($0, table) } ?? false }
    }

    static func removing(_ table: String, from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var inside = false
        for line in lines {
            if let key = headerKey(line) { inside = isOwned(key, table) }
            if !inside { out.append(line) }
        }
        // Trailing blank lines our block leaves behind collapse to the file's own ending.
        lines = out
        while lines.count > 1, lines[lines.count - 1].isEmpty, lines[lines.count - 2].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    static func appending(_ section: String, to text: String) -> String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return section }
        let base = text.hasSuffix("\n") ? text : text + "\n"
        return base + "\n" + section
    }

    /// The `command = "…"` value inside `table`.
    static func command(in text: String, table: String) -> String? {
        var inside = false
        for line in text.components(separatedBy: "\n") {
            if let key = headerKey(line) { inside = key == table; continue }
            guard inside else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "command" { return unquote(parts[1]) }
        }
        return nil
    }

    /// `[a.b]` or `[[a.b]]` → "a.b", with quoted keys unquoted and spaces around dots removed.
    static func headerKey(_ line: String) -> String? {
        var t = line.trimmingCharacters(in: .whitespaces)
        if let hash = t.firstIndex(of: "#"), !t[..<hash].contains("\"") { t = String(t[..<hash]).trimmingCharacters(in: .whitespaces) }
        guard t.hasPrefix("["), t.hasSuffix("]") else { return nil }
        let inner = t.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).trimmingCharacters(in: .whitespaces)
        return inner.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .joined(separator: ".")
    }

    private static func isOwned(_ key: String, _ table: String) -> Bool { key == table || key.hasPrefix(table + ".") }

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F: out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    private static func unquote(_ value: String) -> String? {
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 { return String(value.dropFirst().dropLast()) }
        guard value.hasPrefix("\""), let data = value.data(using: .utf8),
              let s = try? JSONDecoder().decode(String.self, from: data) else { return nil }
        return s
    }
}
