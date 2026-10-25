import Darwin
import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Recorded stream-json lines in the shape Claude Code 2.1 prints them.
enum ClaudeFixtures {
    static let initOK = #"{"type":"system","subtype":"init","cwd":"/tmp/run","session_id":"5f1e2d3c","tools":["mcp__sidefolk__notes_save","mcp__sidefolk__reminders_create"],"mcp_servers":[{"name":"sidefolk","status":"connected"}],"model":"claude-sonnet-4-5","permissionMode":"default","slash_commands":[],"apiKeySource":"none","output_style":"default","uuid":"0b1c"}"#
    static let initWithBash = #"{"type":"system","subtype":"init","tools":["Bash","mcp__sidefolk__notes_save"],"mcp_servers":[{"name":"sidefolk","status":"connected"}],"model":"claude-sonnet-4-5"}"#
    static let initWithOtherServer = #"{"type":"system","subtype":"init","tools":["mcp__sidefolk__notes_save","mcp__github__create_issue"],"mcp_servers":[{"name":"sidefolk","status":"connected"},{"name":"github","status":"connected"}]}"#
    static let toolUse = #"{"type":"assistant","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"tool_use","id":"toolu_01","name":"mcp__sidefolk__notes_save","input":{"title":"Idea"}}],"stop_reason":"tool_use","usage":{"input_tokens":1200,"output_tokens":40}},"parent_tool_use_id":null,"session_id":"5f1e2d3c","uuid":"1a"}"#
    static let toolResult = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":[{"type":"text","text":"Saved to Inbox."}]}]},"parent_tool_use_id":null,"session_id":"5f1e2d3c","uuid":"2b"}"#
    static let text = #"{"type":"assistant","message":{"id":"msg_02","type":"message","role":"assistant","content":[{"type":"text","text":"Saved it to your Inbox."}],"stop_reason":"end_turn","usage":{"input_tokens":1300,"output_tokens":12}},"parent_tool_use_id":null,"session_id":"5f1e2d3c","uuid":"3c"}"#
    static let result = #"{"type":"result","subtype":"success","is_error":false,"duration_ms":4210,"duration_api_ms":3900,"num_turns":2,"result":"Saved it to your Inbox.","session_id":"5f1e2d3c","total_cost_usd":0.0123,"usage":{"input_tokens":2500,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000,"output_tokens":52},"permission_denials":[],"uuid":"4d"}"#
    static let notLoggedIn = #"{"type":"result","subtype":"success","is_error":true,"duration_ms":120,"num_turns":1,"result":"Not logged in · Please run /login","session_id":"9","total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0}}"#
    static let rateLimited = #"{"type":"result","subtype":"success","is_error":true,"num_turns":1,"result":"Claude AI usage limit reached|1761500000","usage":{"input_tokens":0,"output_tokens":0}}"#

    /// A help text with every flag the probe needs (formatted like commander's output).
    static let help = """
        Usage: claude [options] [command] [prompt]
        Options:
          --allowedTools, --allowed-tools <tools...>  Comma or space-separated list of tool names to allow
          --bare                                Minimal mode. Explicitly provide context via: --system-prompt[-file]
          --disable-slash-commands              Disable all skills and commands
          --input-format <format>               Input format (only works with --print)
          --mcp-config <configs...>             Load MCP servers from JSON files or strings
          --model <model>                       Model for the current session
          --no-session-persistence              Disable session persistence
          --output-format <format>              Output format (only works with --print)
          --permission-prompts <target>         Who answers permission prompts with --print
          -p, --print                           Print response and exit
          --restricted                          Restricted mode: ignores user, project and local settings files
          --setting-sources <sources>           Comma-separated list of setting sources to load
          --strict-mcp-config                   Only use MCP servers from --mcp-config
          --system-prompt <prompt>              System prompt to use for the session
          --tools <tools...>                    Specify the list of available tools from the built-in set
          --verbose                             Override verbose mode setting from config
        """
}

/// A shell script standing in for `claude`: answers the probe, records what it was given, prints
/// canned stream-json. Nothing reaches a model.
struct FakeClaude {
    let dir: ShortTempDir
    let path: String
    var capture: String { dir.path + "/capture" }

    init(stream: [String], then tail: String = "exit 0", help: String = ClaudeFixtures.help, beforeStream: String = "") throws {
        dir = try ShortTempDir()
        path = dir.path + "/claude"
        mkdir(dir.path + "/capture", 0o700)
        let script = """
            #!/bin/sh
            case "$1" in
              --version) echo "2.1.310 (Claude Code)"; exit 0 ;;
              --help) cat <<'SIDEFOLK_HELP_END'
            \(help)
            SIDEFOLK_HELP_END
              exit 0 ;;
            esac
            C='\(dir.path)/capture'
            for a in "$@"; do printf '%s\\n' "$a"; done > "$C/argv"
            env > "$C/env"
            pwd > "$C/cwd"
            stat -f '%Lp' token > "$C/token-mode"
            stat -f '%Lp' . > "$C/dir-mode"
            cat mcp.json > "$C/mcp.json"
            cat > "$C/stdin"
            echo $$ > "$C/pid"
            \(beforeStream)
            cat <<'SIDEFOLK_STREAM_END'
            \(stream.joined(separator: "\n"))
            SIDEFOLK_STREAM_END
            \(tail)
            """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o755)
    }

    func captured(_ name: String) -> String {
        (try? String(contentsOfFile: capture + "/" + name, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func remove() { dir.remove() }
}

struct BackendHarness {
    let env: TestEnv
    let home: ShortTempDir
    let tokens = BrainTokenRegistry()

    init() throws {
        env = try TestEnv()
        home = try ShortTempDir()
    }

    var paths: SidefolkPaths { SidefolkPaths(home: URL(fileURLWithPath: home.path)) }

    func backend(_ fake: FakeClaude, helper: String = "/usr/bin/true") -> ClaudeCodeBackend {
        ClaudeCodeBackend(claudePath: fake.path, paths: paths, helperPath: helper, registry: tokens,
                          environment: ["HOME": "/Users/x", "USER": "tester", "LANG": "en_GB.UTF-8",
                                        "ANTHROPIC_API_KEY": "sk-ant-CANARY0000000000", "DYLD_INSERT_LIBRARIES": "/tmp/x.dylib",
                                        "NODE_OPTIONS": "--require /tmp/evil.js"])
    }

    func task(_ prompt: String = "Save this idea: folks with jobs", system: String = "About you: likes tea", seconds: TimeInterval = 20) -> BrainTask {
        BrainTask(runId: "run-\(UUID().uuidString.prefix(8))", threadId: "t", system: system,
                  messages: [ChatMessage(role: .user, text: prompt)], model: "", deadline: Date().addingTimeInterval(seconds))
    }

    func toolbox(_ runId: String) -> BrainToolbox {
        BrainToolbox(runId: runId, specs: env.registry.specs, executor: env.executor, emit: { _ in })
    }

    func remove() { home.remove() }
}

@Suite struct ClaudeCodeInvocationTests {
    let task = BrainTask(runId: "r1", threadId: "t", system: "SYSTEM-SECRET about you",
                         messages: [ChatMessage(role: .user, text: "first PROMPT-SECRET"), ChatMessage(role: .assistant, text: "ok"),
                                    ChatMessage(role: .user, text: "now PROMPT-LATEST")],
                         model: "", deadline: Date())
    let base = ["HOME": "/Users/x", "USER": "me", "ANTHROPIC_BASE_URL": "https://evil.example", "DYLD_LIBRARY_PATH": "/x",
                "NODE_OPTIONS": "--inspect", "LANG": "fr_FR.UTF-8", "SECRET_TOKEN": "abc"]

    @Test func argvIsIsolatedAndCarriesNoUserData() {
        let flags = ClaudeFlags(restricted: true, settingSources: true, systemPromptFile: true)
        let inv = ClaudeCodeBackend.invocation(task: task, flags: flags, claudePath: "/opt/homebrew/bin/claude", runDir: "/r",
                                               helperPath: "/h/sidefolk", sidefolkHome: "/home", environment: base)
        let args = inv.arguments
        for secret in ["SYSTEM-SECRET", "PROMPT-SECRET", "PROMPT-LATEST"] {
            #expect(!args.contains { $0.contains(secret) })
        }
        func follows(_ flag: String, _ value: String) -> Bool {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return false }
            return args[i + 1] == value
        }
        #expect(args.first == "-p")
        #expect(follows("--tools", ""))
        #expect(follows("--input-format", "stream-json"))
        #expect(follows("--output-format", "stream-json"))
        #expect(follows("--mcp-config", "/r/mcp.json"))
        #expect(follows("--permission-prompts", "none"))
        #expect(follows("--allowedTools", "mcp__sidefolk"))
        #expect(follows("--system-prompt-file", "/r/system.md"))
        for flag in ["--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence", "--restricted", "--verbose"] {
            #expect(args.contains(flag))
        }
        #expect(!args.contains("--model"), "an empty model means the CLI default")
        #expect(inv.files["system.md"] == task.system)
        #expect(inv.input.contains("PROMPT-LATEST"))
        #expect(inv.input.hasSuffix("\n"))
        #expect(!inv.input.contains("SYSTEM-SECRET"))
    }

    @Test func environmentIsAllowListed() {
        let flags = ClaudeFlags(restricted: true, settingSources: false, systemPromptFile: true)
        let inv = ClaudeCodeBackend.invocation(task: task, flags: flags, claudePath: "/Users/x/.local/bin/claude", runDir: "/r",
                                               helperPath: "/h/sidefolk", sidefolkHome: "/home", environment: base)
        #expect(Set(inv.environment.keys) == ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "PATH"])
        #expect(inv.environment["TMPDIR"] == "/r/tmp")
        #expect(inv.environment["LANG"] == "fr_FR.UTF-8")
        #expect(inv.environment["PATH"] == "/Users/x/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        let mcp = try? JSONValue.parse(inv.files["mcp.json"] ?? "")
        #expect(mcp?["mcpServers"]?.objectValue?.keys.sorted() == ["sidefolk"])
        #expect(mcp?["mcpServers"]?["sidefolk"]?.string("command") == "/h/sidefolk")
        #expect(mcp?["mcpServers"]?["sidefolk"]?["args"] == ["mcp"])
        #expect(mcp?["mcpServers"]?["sidefolk"]?["env"] == ["SIDEFOLK_RUN_DIR": "/r", "SIDEFOLK_HOME": "/home"])
    }

    @Test func olderCLIsGetTheSystemPromptOverStdin() throws {
        let flags = ClaudeFlags(restricted: false, settingSources: true, systemPromptFile: false)
        var named = task
        named.model = "sonnet"
        let inv = ClaudeCodeBackend.invocation(task: named, flags: flags, claudePath: "/c/claude", runDir: "/r",
                                               helperPath: "/h", sidefolkHome: "/home", environment: [:])
        let args = inv.arguments
        #expect(!args.contains { $0.contains("SYSTEM-SECRET") })
        #expect(args[args.firstIndex(of: "--setting-sources")! + 1] == "")
        #expect(args[args.firstIndex(of: "--model")! + 1] == "sonnet")
        #expect(args.contains("--system-prompt"))
        #expect(inv.files["system.md"] == nil)
        let message = try JSONValue.parse(inv.input)
        #expect(message.string("type") == "user")
        let text = try #require(message["message"]?["content"]?.arrayValue?.first?.string("text"))
        #expect(text.hasPrefix("<instructions>\nSYSTEM-SECRET"))
        #expect(text.contains("Earlier in this conversation:\nUser: first PROMPT-SECRET\nYou: ok"))
        #expect(text.hasSuffix("The user's new message:\nnow PROMPT-LATEST"))
    }

    @Test func unsafeModelNamesAreDropped() {
        #expect(ClaudeCodeBackend.isSafeModelName("claude-sonnet-4-5"))
        #expect(ClaudeCodeBackend.isSafeModelName("opus[1m]"))
        #expect(!ClaudeCodeBackend.isSafeModelName(""))
        #expect(!ClaudeCodeBackend.isSafeModelName("--dangerously-skip-permissions x"))
    }
}

@Suite struct ClaudeStreamTests {
    @Test func parsesRecordedLines() {
        guard case .initialized(let info) = ClaudeStream.parse(ClaudeFixtures.initOK) else { Issue.record("init"); return }
        #expect(info.tools == ["mcp__sidefolk__notes_save", "mcp__sidefolk__reminders_create"])
        #expect(info.mcpServers == [ClaudeMCPServer(name: "sidefolk", status: "connected")])
        #expect(ClaudeStream.isolationProblem(info) == nil)

        #expect(ClaudeStream.parse(ClaudeFixtures.toolUse)
                == .assistant(text: "", toolUses: [ClaudeToolUse(name: "mcp__sidefolk__notes_save", input: ["title": "Idea"])]))
        #expect(ClaudeStream.parse(ClaudeFixtures.text) == .assistant(text: "Saved it to your Inbox.", toolUses: []))
        #expect(ClaudeStream.parse(ClaudeFixtures.toolResult) == .other)
        #expect(ClaudeStream.parse("not json") == .other)
        #expect(ClaudeStream.parse(#"{"type":"system","subtype":"api_retry","attempt":1}"#) == .other)

        guard case .result(let r) = ClaudeStream.parse(ClaudeFixtures.result) else { Issue.record("result"); return }
        #expect(r == ClaudeResult(text: "Saved it to your Inbox.", isError: false, subtype: "success", inputTokens: 3500, outputTokens: 52, turns: 2))
    }

    @Test func foreignToolsOrServersBreakIsolation() {
        guard case .initialized(let bash) = ClaudeStream.parse(ClaudeFixtures.initWithBash),
              case .initialized(let github) = ClaudeStream.parse(ClaudeFixtures.initWithOtherServer) else { Issue.record("init"); return }
        #expect(ClaudeStream.isolationProblem(bash)?.contains("Bash") == true)
        #expect(ClaudeStream.isolationProblem(github) != nil)
    }

    @Test func errorsInPlainLanguage() {
        #expect(ClaudeStream.userFacingError(message: "Not logged in · Please run /login", stderr: "").message == "Claude Code isn't signed in.")
        #expect(ClaudeStream.userFacingError(message: "Claude AI usage limit reached|1761500000", stderr: "").message
                == "Claude's usage limit is reached for now.")
        #expect(ClaudeStream.userFacingError(message: "", stderr: "Error: getaddrinfo ENOTFOUND api.anthropic.com").message
                == "I couldn't reach Claude.")
        let other = ClaudeStream.userFacingError(message: "boom sk-ant-abcdefghijklmnopqrstuv", stderr: "")
        #expect(other.detail?.contains("sk-ant-abc") == false)
    }
}

@Suite struct ClaudeBinaryTests {
    @Test func helpProbe() {
        let (missing, flags) = ClaudeBinary.flags(fromHelp: ClaudeFixtures.help)
        #expect(missing.isEmpty)
        #expect(flags == ClaudeFlags(restricted: true, settingSources: true, systemPromptFile: true))

        let old = ClaudeFixtures.help.replacingOccurrences(of: "--strict-mcp-config", with: "--strict-mcp-config-x")
        #expect(ClaudeBinary.flags(fromHelp: old).missing == ["--strict-mcp-config"])
        #expect(!ClaudeBinary.mentions("--toolsy --tools-list", "--tools"))
        #expect(ClaudeBinary.mentions("  --tools <tools...>", "--tools"))
        #expect(!ClaudeBinary.mentions("--system-prompt <p>", "--system-prompt-file"))
    }

    @Test func onlyTrustworthyBinaries() throws {
        let dir = try ShortTempDir()
        defer { dir.remove() }
        let path = dir.path + "/claude"
        try "#!/bin/sh\n".write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o755)
        #expect(ClaudeBinary.problem(with: path) == nil)
        chmod(path, 0o775)
        #expect(ClaudeBinary.problem(with: path) != nil)
        chmod(path, 0o644)
        #expect(ClaudeBinary.problem(with: path) != nil)
        #expect(ClaudeBinary.problem(with: "relative/claude") != nil)
        #expect(ClaudeBinary.candidates(configured: "", home: "/Users/me")
                == ["/Users/me/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
    }
}

/// The brain's child process: only fds 0–2, its own environment, killed as a whole tree (T7, T15).
@Suite struct PipedChildTests {
    @Test func childrenOfTheBrainSeeOnlyStdioAndTheirEnvironment() async throws {
        let dir = try ShortTempDir()
        defer { dir.remove() }
        // An inheritable descriptor (like a database or socket fd) must not reach the child.
        let marker = open(dir.path + "/marker", O_CREAT | O_RDWR, 0o600)
        defer { close(marker) }
        let script = "if [ -e /dev/fd/\(marker) ]; then echo leaked; else echo clean; fi; env"
        let child = try PipedChild.spawn("/bin/sh", arguments: ["-c", script], environment: ["ONLY": "this"], cwd: dir.path)
        child.closeInput()
        let reader = DescriptorLineReader(fd: child.output, limit: 1 << 16)
        var lines: [String] = []
        while case .line(let bytes)? = await reader.next() { lines.append(String(decoding: bytes, as: UTF8.self)) }
        _ = await child.wait()
        #expect(lines.first == "clean")
        #expect(lines.contains("ONLY=this"))
        #expect(!lines.contains { $0.hasPrefix("HOME=") })
    }

    @Test func terminateStopsTheWholeTree() async throws {
        let dir = try ShortTempDir()
        defer { dir.remove() }
        let child = try PipedChild.spawn("/bin/sh", arguments: ["-c", "sleep 100 & echo $!; sleep 100"], environment: [:], cwd: dir.path)
        let reader = DescriptorLineReader(fd: child.output, limit: 1024)
        guard case .line(let bytes)? = await reader.next(), let grandchild = pid_t(String(decoding: bytes, as: UTF8.self)) else {
            Issue.record("no pid")
            return
        }
        await child.terminate(grace: 1)
        #expect(await pollUntil { kill(grandchild, 0) != 0 })
    }
}

@Suite(.serialized) struct ClaudeCodeRunTests {
    @Test func aRunWithRecordedOutput() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeClaude(stream: [ClaudeFixtures.initOK, ClaudeFixtures.toolUse, ClaudeFixtures.toolResult, ClaudeFixtures.text,
                                           ClaudeFixtures.result])
        defer { fake.remove() }
        let backend = h.backend(fake)
        #expect(try await backend.check().get().hasPrefix("Claude Code 2.1.310"))

        let task = h.task()
        let events = BridgeRecorder<[AgentEvent]>([])
        let reply = try await backend.run(task, toolbox: h.toolbox(task.runId), emit: { e in events.value.withLock { $0.append(e) } })
        #expect(reply.text == "Saved it to your Inbox.")
        if case .phase(.thinking)? = events.value.withLock({ $0.first }) {} else { Issue.record("thinking first") }

        // What the CLI was given.
        let argv = fake.captured("argv").components(separatedBy: "\n")
        #expect(argv.contains("--restricted"))
        #expect(!argv.contains { $0.contains("folks with jobs") || $0.contains("likes tea") })
        #expect(fake.captured("token-mode") == "600")
        #expect(fake.captured("dir-mode") == "700")
        #expect(fake.captured("stdin").contains("folks with jobs"))
        let env = fake.captured("env")
        #expect(!env.contains("ANTHROPIC") && !env.contains("DYLD") && !env.contains("NODE_OPTIONS") && !env.contains("CANARY"))
        #expect(env.contains("HOME=\(NSHomeDirectory())"))
        let runDir = fake.captured("cwd")
        #expect(runDir.hasPrefix(h.home.path + "/brain/run-") || runDir.hasPrefix("/private" + h.home.path + "/brain/run-"))
        #expect(fake.captured("mcp.json").contains("SIDEFOLK_RUN_DIR"))

        // Cleaned up afterwards, usage recorded.
        #expect(!FileManager.default.fileExists(atPath: runDir))
        #expect(h.tokens.count == 0)
        let usage = try #require(backend.takeUsage(runId: task.runId))
        #expect(usage.inputTokens == 3500)
        #expect(usage.outputTokens == 52)
        #expect(usage.steps == 2)
    }

    @Test func foreignToolKillsTheRunAndDisablesTheBackend() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeClaude(stream: [ClaudeFixtures.initWithBash], then: "sleep 30")
        defer { fake.remove() }
        let backend = h.backend(fake)
        let task = h.task()
        let started = Date()
        await #expect(throws: UserFacingError.self) { _ = try await backend.run(task, toolbox: h.toolbox(task.runId), emit: { _ in }) }
        #expect(Date().timeIntervalSince(started) < 10)
        let pid = try #require(pid_t(fake.captured("pid")))
        #expect(await pollUntil { kill(pid, 0) != 0 })
        // Disabled from now on, even for a backend built afresh, without starting the CLI again.
        try FileManager.default.removeItem(atPath: fake.capture + "/pid")
        let fresh = h.backend(fake)
        await #expect(throws: UserFacingError.self) { _ = try await fresh.run(task, toolbox: h.toolbox(task.runId), emit: { _ in }) }
        #expect(fake.captured("pid").isEmpty)
        guard case .failure = await fresh.check() else { Issue.record("check must fail"); return }
    }

    @Test func deadlineStopsTheRun() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeClaude(stream: [ClaudeFixtures.initOK], then: "sleep 30")
        defer { fake.remove() }
        let task = h.task(seconds: 1)
        do {
            _ = try await h.backend(fake).run(task, toolbox: h.toolbox(task.runId), emit: { _ in })
            Issue.record("expected a timeout")
        } catch let error as UserFacingError {
            #expect(error.message == "Claude took too long, so I stopped it.")
        }
        let pid = try #require(pid_t(fake.captured("pid")))
        #expect(await pollUntil { kill(pid, 0) != 0 })
    }

    @Test func signedOutIsExplained() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeClaude(stream: [ClaudeFixtures.notLoggedIn], then: "exit 1")
        defer { fake.remove() }
        let task = h.task()
        do {
            _ = try await h.backend(fake).run(task, toolbox: h.toolbox(task.runId), emit: { _ in })
            Issue.record("expected an error")
        } catch let error as UserFacingError {
            #expect(error.message == "Claude Code isn't signed in.")
        }
    }

    @Test func missingIsolationFlagsFailClosed() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let help = ClaudeFixtures.help.replacingOccurrences(of: "--strict-mcp-config", with: "--strict-mcp-cfg")
        let fake = try FakeClaude(stream: [ClaudeFixtures.initOK, ClaudeFixtures.result], help: help)
        defer { fake.remove() }
        let task = h.task()
        await #expect(throws: UserFacingError.self) { _ = try await h.backend(fake).run(task, toolbox: h.toolbox(task.runId), emit: { _ in }) }
        #expect(fake.captured("argv").isEmpty, "the CLI must not have been run with a prompt")
        guard case .failure = await h.backend(fake).check() else { Issue.record("check must fail"); return }
    }

    /// The whole path: the fake CLI starts the real `sidefolk mcp` helper the way Claude Code would,
    /// the helper reads the run's token and calls a tool through the app's socket and the run's toolbox.
    @Test func toolCallsReachTheRunsToolboxThroughTheHelper() async throws {
        let helper = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/sidefolk").path
        guard FileManager.default.isExecutableFile(atPath: helper) else { return } // built by `swift build`
        let server = try BridgeHarness().start()
        defer { server.stop() }
        server.env.registry.register(ProbeTool(name: "notes.save", risk: .low, result: { input in
            ToolResult(text: "Saved \(input.string("x") ?? "").")
        }))
        let mcpCall = """
            printf '%s\\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"claude-code"}}}' \
              '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"notes_save","arguments":{"x":"from the brain"}}}' \
              | SIDEFOLK_RUN_DIR="$PWD" SIDEFOLK_HOME='\(server.dir.path)' '\(helper)' mcp > "$C/mcp-out"
            """
        let fake = try FakeClaude(stream: [ClaudeFixtures.initOK, ClaudeFixtures.result], beforeStream: mcpCall)
        defer { fake.remove() }
        let backend = ClaudeCodeBackend(claudePath: fake.path, paths: SidefolkPaths(home: URL(fileURLWithPath: server.dir.path)),
                                        helperPath: helper, registry: server.tokens)
        let task = BrainTask(runId: "run-e2e", threadId: "t", system: "s", messages: [ChatMessage(role: .user, text: "save")],
                             model: "", deadline: Date().addingTimeInterval(20))
        let toolbox = BrainToolbox(runId: task.runId, specs: server.env.registry.specs, executor: server.env.executor, emit: { _ in })
        _ = try await backend.run(task, toolbox: toolbox, emit: { _ in })
        #expect(fake.captured("mcp-out").contains("Saved from the brain."))
        #expect(toolbox.outcomes.count == 1)
        #expect(try await server.env.activity.recent().first?.runId == "run-e2e")
    }
}
