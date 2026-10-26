import Foundation

/// "Copy Setup Instructions" in Settings › Agents: how to add Sidefolk to an MCP client it doesn't connect by
/// itself (Cursor, VS Code, Zed, any other), with the exact command and a config snippet for each, ready to
/// paste. Sidefolk changes nothing for these: the person pastes what they want where they want it. The text
/// stays English, like the `sidefolk` command's own output: it goes into other tools' config files.
extension AgentIntegrations {
    /// - Parameter skillFolder: where this copy of Sidefolk keeps the skill (`AgentSkills/sidefolk` in the app).
    public func setupInstructions(skillFolder: String?) -> String {
        var lines = [
            "Sidefolk for MCP clients (a local server over stdio; Sidefolk has to be running)",
            "",
            "Command: \(Self.shellQuote(helperPath)) mcp",
        ]
        if !helperEnvironment.isEmpty {
            lines.append("Environment: " + helperEnvironment.sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.shellQuote($0.value))" }.joined(separator: " "))
        }
        lines += ["", "Cursor (~/.cursor/mcp.json):", snippet(container: "mcpServers", typed: false)]
        lines += ["", "VS Code (MCP: Open User Configuration):", snippet(container: "servers", typed: true)]
        lines += ["", "Zed (settings.json):", snippet(container: "context_servers", typed: false)]
        if let skillFolder {
            lines += [
                "",
                "Skill (when and how an agent should use Sidefolk): copy the folder",
                skillFolder,
                "into your agent's skills folder, or give its SKILL.md to the agent as instructions.",
            ]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `{"<container>": {"sidefolk": {"command": …, "args": ["mcp"]}}}` as each client spells it.
    private func snippet(container: String, typed: Bool) -> String {
        var server: [OrderedJSON.Member] = []
        if typed { server.append(.init(key: "type", value: .string("stdio"))) }
        server.append(.init(key: "command", value: .string(helperPath)))
        server.append(.init(key: "args", value: .array([.string("mcp")])))
        if !helperEnvironment.isEmpty {
            server.append(.init(key: "env", value: .object(helperEnvironment.sorted { $0.key < $1.key }.map {
                .init(key: $0.key, value: .string($0.value))
            })))
        }
        let root: OrderedJSON = .object([.init(key: container, value: .object([.init(key: Self.serverName, value: .object(server))]))])
        return root.serialized()
    }
}
