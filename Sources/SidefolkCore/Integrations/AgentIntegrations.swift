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

    public init(claudeConfig: URL, claudeSettings: URL, codexConfig: URL) {
        self.claudeConfig = claudeConfig
        self.claudeSettings = claudeSettings
        self.codexConfig = codexConfig
    }

    /// The real locations, honouring `CLAUDE_CONFIG_DIR` and `CODEX_HOME`.
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
    /// Claude Code hooks that tell Sidefolk when a session needs you or finished.
    case claudeHooks
    /// Sidefolk's tools in Codex (`[mcp_servers.sidefolk]`).
    case codexMCP

    public var title: String {
        switch self {
        case .claudeMCP: "Sidefolk tools in Claude Code"
        case .claudeHooks: "Claude Code session updates"
        case .codexMCP: "Sidefolk tools in Codex"
        }
    }
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
    public static let hookTimeoutSeconds = 5

    public let locations: IntegrationLocations
    /// The stable path of the `sidefolk` helper (not inside a translocated or moving app bundle).
    public let helperPath: String
    /// Extra environment for the helper (e.g. `SIDEFOLK_HOME` for a dev build); empty in release.
    public let helperEnvironment: [String: String]
    private let clock: any Clock

    public init(locations: IntegrationLocations, helperPath: String, helperEnvironment: [String: String] = [:],
                clock: any Clock = SystemClock()) {
        self.locations = locations
        self.helperPath = helperPath
        self.helperEnvironment = helperEnvironment
        self.clock = clock
    }

    public func file(for integration: AgentIntegration) -> URL {
        switch integration {
        case .claudeMCP: locations.claudeConfig
        case .claudeHooks: locations.claudeSettings
        case .codexMCP: locations.codexConfig
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
            case .claudeHooks:
                let ours = Self.ourHookCommands(in: try parseJSON(text, url))
                if ours.isEmpty { return make(.notInstalled) }
                let expected = Set(Self.hookEvents.map(hookCommand))
                return make(Set(ours) == expected ? .installed : .outdated(ours.first ?? ""))
            case .codexMCP:
                guard let command = TOMLSection.command(in: text, table: Self.codexTable) else {
                    return TOMLSection.contains(text, table: Self.codexTable) ? make(.outdated("")) : make(.notInstalled)
                }
                return make(command == helperPath ? .installed : .outdated(command))
            }
        } catch {
            return make(.unavailable("\(error)"))
        }
    }

    /// The agent's config folder must exist: Sidefolk never sets up an agent the user doesn't have.
    private func unavailableReason(_ integration: AgentIntegration) -> String? {
        let fm = FileManager.default
        switch integration {
        case .claudeMCP:
            return fm.fileExists(atPath: locations.claudeConfig.path) ? nil : "Claude Code isn't set up on this Mac."
        case .claudeHooks:
            let dir = locations.claudeSettings.deletingLastPathComponent().path
            return fm.fileExists(atPath: dir) ? nil : "Claude Code isn't set up on this Mac."
        case .codexMCP:
            let dir = locations.codexConfig.deletingLastPathComponent().path
            return fm.fileExists(atPath: dir) ? nil : "Codex isn't set up on this Mac."
        }
    }

    // MARK: Preview and apply

    public func preview(_ integration: AgentIntegration, install: Bool) throws -> IntegrationPreview {
        let config = AgentConfigFile(url: file(for: integration))
        let snapshot = try config.read()
        let updated = try edited(integration, install: install, text: snapshot.text)
        let changes = updated != snapshot.text
        return IntegrationPreview(integration: integration, install: install, file: config.url,
                                  changes: describe(integration, install: install),
                                  backup: changes && snapshot.text != nil ? config.backupURL(at: clock.now) : nil,
                                  changesSomething: changes)
    }

    @discardableResult
    public func install(_ integration: AgentIntegration) throws -> IntegrationResult { try apply(integration, install: true) }

    @discardableResult
    public func remove(_ integration: AgentIntegration) throws -> IntegrationResult { try apply(integration, install: false) }

    private func apply(_ integration: AgentIntegration, install: Bool) throws -> IntegrationResult {
        if install, let reason = unavailableReason(integration) { throw IntegrationError.unavailable(reason) }
        let config = AgentConfigFile(url: file(for: integration))
        let snapshot = try config.read()
        guard let updated = try edited(integration, install: install, text: snapshot.text), updated != snapshot.text else {
            return IntegrationResult(changed: false, backup: nil)
        }
        var backup: URL?
        if snapshot.text != nil {
            let url = config.backupURL(at: clock.now)
            try config.backup(snapshot, to: url)
            backup = url
        }
        try config.replace(with: updated, expecting: snapshot)
        Log.shared.info("integrations", "\(install ? "installed" : "removed") \(integration.rawValue)",
                        ["file": FolderAccess.displayPath(config.url.path), "backup": backup.map { FolderAccess.displayPath($0.path) } ?? "none"])
        return IntegrationResult(changed: true, backup: backup)
    }

    /// The new file text, or nil when there is nothing to remove from a missing file.
    func edited(_ integration: AgentIntegration, install: Bool, text: String?) throws -> String? {
        let url = file(for: integration)
        switch integration {
        case .claudeMCP:
            guard let text else {
                if install { throw IntegrationError.unavailable("Claude Code isn't set up on this Mac.") }
                return nil
            }
            var root = try parseJSON(text, url)
            var servers = root["mcpServers"] ?? .object([])
            guard servers.isObject else { throw IntegrationError.malformed(url.path, "mcpServers is not an object") }
            if install {
                servers[Self.serverName] = mcpServerEntry()
            } else {
                guard servers[Self.serverName] != nil else { return text }
                servers[Self.serverName] = nil
            }
            root["mcpServers"] = servers
            return Self.write(root, like: text)

        case .claudeHooks:
            var root = try text.map { try parseJSON($0, url) } ?? .object([])
            var hooks = root["hooks"] ?? .object([])
            guard hooks.isObject else { throw IntegrationError.malformed(url.path, "hooks is not an object") }
            hooks = Self.withoutOurHooks(hooks)
            if install {
                for event in Self.hookEvents {
                    var group: OrderedJSON = .object([])
                    if event == "PreToolUse" { group["matcher"] = .string("*") }
                    group["hooks"] = .array([.object([
                        .init(key: "type", value: .string("command")),
                        .init(key: "command", value: .string(hookCommand(event))),
                        .init(key: "timeout", value: .number("\(Self.hookTimeoutSeconds)")),
                    ])])
                    hooks[event] = .array((hooks[event]?.arrayValue ?? []) + [group])
                }
            }
            if case .object(let members) = hooks, members.isEmpty { root["hooks"] = nil } else { root["hooks"] = hooks }
            if text == nil, case .object(let members) = root, members.isEmpty { return nil }
            return Self.write(root, like: text ?? "")

        case .codexMCP:
            let current = text ?? ""
            let without = TOMLSection.removing(Self.codexTable, from: current)
            if !install { return text == nil ? nil : without }
            return TOMLSection.appending(codexSection(), to: without)
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

    /// `'/path/to/sidefolk' hook Stop` (quoted: the stable path has a space in "Application Support").
    func hookCommand(_ event: String) -> String {
        let env = helperEnvironment.sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.shellQuote($0.value)) " }.joined()
        return env + Self.shellQuote(helperPath) + " hook " + event
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

    /// `… sidefolk' hook Event` with the executable named `sidefolk`, whatever folder it is in.
    static func isOurHook(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: #"(^|[\s/'"])sidefolk'?"? hook [A-Za-z]+$"#, options: .regularExpression) else { return false }
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

    // MARK: Helpers

    private func describe(_ integration: AgentIntegration, install: Bool) -> [String] {
        let helper = FolderAccess.displayPath(helperPath)
        switch (integration, install) {
        case (.claudeMCP, true): return ["Adds the MCP server “sidefolk” (runs \(helper) mcp) to Claude Code's user settings."]
        case (.claudeMCP, false): return ["Removes the MCP server “sidefolk” from Claude Code. Other servers stay."]
        case (.claudeHooks, true):
            return ["Adds hooks for \(Self.hookEvents.joined(separator: ", ")) that run \(helper) hook (\(Self.hookTimeoutSeconds) s limit).",
                    "Your other hooks stay as they are."]
        case (.claudeHooks, false): return ["Removes Sidefolk's hooks from Claude Code. Your other hooks stay."]
        case (.codexMCP, true): return ["Adds [\(Self.codexTable)] (runs \(helper) mcp) to Codex's config."]
        case (.codexMCP, false): return ["Removes [\(Self.codexTable)] from Codex's config. The rest stays."]
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
