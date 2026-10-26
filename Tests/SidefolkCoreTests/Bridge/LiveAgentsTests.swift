import Foundation
import Testing
@testable import SidefolkCore

/// The real Codex and Claude Code as *other agents* (D42): each CLI, given a config that knows only this
/// test's Sidefolk (temp home, real socket, the built `sidefolk mcp` helper), lists Sidefolk's tools and
/// calls `status`. Their own config files are never read or written: Codex runs with `--ignore-user-config`
/// and Sidefolk's server passed with `-c`, Claude Code with `--setting-sources ""` and `--strict-mcp-config`.
/// Each spends one tiny request of the person's plan, so each is off unless asked for:
/// `SIDEFOLK_LIVE_CODEX=1` and `SIDEFOLK_LIVE_CLAUDE=1`.
@Suite(.serialized) struct LiveAgentsTests {
    static let codex = ProcessInfo.processInfo.environment["SIDEFOLK_LIVE_CODEX"] == "1"
    static let claude = ProcessInfo.processInfo.environment["SIDEFOLK_LIVE_CLAUDE"] == "1"
    static let prompt = "Use only the sidefolk MCP server. List the names of its tools you can see, then call its status tool once. "
        + "Reply with the tool names and the status text, nothing else."

    struct Stack {
        let dir: ShortTempDir
        let runtime: SidefolkRuntime
        let helper: String
        let work: String

        init() async throws {
            helper = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/sidefolk").path
            dir = try ShortTempDir()
            runtime = await SidefolkRuntime(paths: SidefolkPaths(home: URL(fileURLWithPath: dir.path)), db: try AppDatabase.inMemory(),
                                            platform: NullPlatform())
            try await runtime.start()
            work = dir.path + "/work"
            try FileManager.default.createDirectory(atPath: work + "/tmp", withIntermediateDirectories: true)
        }

        /// The calls other agents made, as "caller tool".
        func externalCalls() async throws -> [String] {
            try await runtime.activity.recent().filter { $0.caller.hasPrefix("external:") }.map { "\($0.caller) \($0.tool)" }
        }

        func stop() async {
            _ = await runtime.stop()
            dir.remove()
        }
    }

    @Test(.enabled(if: codex, "set SIDEFOLK_LIVE_CODEX=1 to spend one small Codex request")) func codexListsAndCalls() async throws {
        let stack = try await Stack()
        let path = try CodexBinary.locate(configured: "").get()
        func toml(_ s: String) -> String { CodexBackend.toml(s) }
        var args = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules",
                    "--sandbox", "read-only", "--cd", stack.work]
        for (key, value) in [
            ("approval_policy", toml("never")), ("web_search", toml("disabled")), ("history.persistence", toml("none")),
            ("mcp_servers.sidefolk.command", toml(stack.helper)), ("mcp_servers.sidefolk.args", "[\(toml("mcp"))]"),
            ("mcp_servers.sidefolk.env.SIDEFOLK_HOME", toml(stack.dir.path)),
            ("mcp_servers.sidefolk.default_tools_approval_mode", toml("approve")),
        ] { args += ["-c", "\(key)=\(value)"] }
        // The person's hooks, plugins and shell stay out of it: only Sidefolk's tools.
        for feature in CodexBinary.mustDisable { args += ["--disable", feature] }
        args.append(Self.prompt)
        let out = await CLIBrain.run(path, args, environment: CLIBrain.environment(base: ProcessInfo.processInfo.environment,
                                                                                    tmp: stack.work + "/tmp", cliPath: path),
                                     cwd: stack.work, timeout: 180)
        let calls = try await stack.externalCalls()
        await stack.stop()
        let replies = (out?.text ?? "").components(separatedBy: "\n").compactMap { try? JSONValue.parse($0) }
            .compactMap { $0["item"] }.filter { $0.string("type") == "agent_message" }.compactMap { $0.string("text") }
        print("live codex: \(replies.last ?? "-")\nlive codex calls: \(calls)")
        #expect(calls.contains { $0.hasSuffix(" status") })
        #expect(replies.last?.contains("reminders_create") == true)
    }

    @Test(.enabled(if: claude, "set SIDEFOLK_LIVE_CLAUDE=1 to spend one small Claude Code request")) func claudeCodeListsAndCalls() async throws {
        let stack = try await Stack()
        let path = try ClaudeBinary.locate(configured: "").get()
        let config: JSONValue = ["mcpServers": ["sidefolk": ["type": "stdio", "command": .string(stack.helper), "args": ["mcp"],
                                                             "env": ["SIDEFOLK_HOME": .string(stack.dir.path)]]]]
        let configPath = stack.work + "/mcp.json"
        try config.jsonString.write(toFile: configPath, atomically: true, encoding: .utf8)
        let args = ["-p", Self.prompt, "--output-format", "json", "--model", "haiku", "--tools", "", "--strict-mcp-config",
                    "--mcp-config", configPath, "--allowedTools", "mcp__sidefolk", "--permission-prompts", "none",
                    "--no-session-persistence", "--disable-slash-commands", "--setting-sources", ""]
        let out = await CLIBrain.run(path, args, environment: CLIBrain.environment(base: ProcessInfo.processInfo.environment,
                                                                                    tmp: stack.work + "/tmp", cliPath: path),
                                     cwd: stack.work, timeout: 180)
        let calls = try await stack.externalCalls()
        await stack.stop()
        let reply = (try? JSONValue.parse(out?.text ?? ""))?.string("result") ?? out?.errors ?? "-"
        print("live claude: \(reply)\nlive claude calls: \(calls)")
        #expect(calls.contains { $0.hasSuffix(" status") })
        #expect(reply.contains("reminders_create"))
    }
}
