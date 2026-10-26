import Darwin
import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// JSON lines as codex-cli 0.160.0 printed them (`codex exec --json`, recorded against a stand-in
/// Responses server, so no quota was spent).
enum CodexFixtures {
    static let threadStarted = #"{"type":"thread.started","thread_id":"01a175e0-8be3-7e60-8620-ddb12c289333"}"#
    static let turnStarted = #"{"type":"turn.started"}"#
    static let warning = #"{"type":"item.completed","item":{"id":"item_0","type":"error","message":"Model metadata for `mock-model` not found. Defaulting to fallback metadata; this can degrade performance and cause issues."}}"#
    static let toolStarted = #"{"type":"item.started","item":{"id":"item_1","type":"mcp_tool_call","server":"sidefolk","tool":"notes_save","arguments":{"text":"hello from probe"},"result":null,"error":null,"status":"in_progress"}}"#
    static let toolCompleted = #"{"type":"item.completed","item":{"id":"item_1","type":"mcp_tool_call","server":"sidefolk","tool":"notes_save","arguments":{"text":"hello from probe"},"result":{"content":[{"type":"text","text":"Saved the note."}],"structured_content":null},"error":null,"status":"completed"}}"#
    static let commentary = #"{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"Saving that now."}}"#
    static let message = #"{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"Saved it to your Inbox."}}"#
    static let completed = #"{"type":"turn.completed","usage":{"input_tokens":2400,"cached_input_tokens":1200,"cache_write_input_tokens":0,"output_tokens":52,"reasoning_output_tokens":10}}"#
    static let command = #"{"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'echo hi'","aggregated_output":"","exit_code":null,"status":"in_progress"}}"#
    static let webSearch = #"{"type":"item.started","item":{"id":"item_0","type":"web_search","id":"ws_1","query":"weather paris","action":{"type":"search","query":"weather paris"}}}"#
    static let otherServer = #"{"type":"item.started","item":{"id":"item_1","type":"mcp_tool_call","server":"github","tool":"create_issue","arguments":{},"result":null,"error":null,"status":"in_progress"}}"#
    static let fileChange = #"{"type":"item.completed","item":{"id":"item_4","type":"file_change","changes":[{"path":"/tmp/x.txt","kind":"add"}],"status":"completed"}}"#
    static let spawn = #"{"type":"item.started","item":{"id":"item_5","type":"collab_tool_call","tool":"spawn_agent","status":"in_progress"}}"#
    static let retrying = #"{"type":"error","message":"Reconnecting... 2/5 (unexpected status 401 Unauthorized: Missing bearer or basic authentication in header, url: https://api.openai.com/v1/responses)"}"#
    static let unauthorized = #"{"type":"turn.failed","error":{"message":"unexpected status 401 Unauthorized: Missing bearer or basic authentication in header, url: https://api.openai.com/v1/responses, request id: req_acde"}}"#

    /// `codex exec --help`, trimmed to the flags (same layout as 0.160.0).
    static let help = """
        Run Codex non-interactively

        Usage: codex exec [OPTIONS] [PROMPT]

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
              --enable <FEATURE>
              --disable <FEATURE>
              --strict-config
          -m, --model <MODEL>
          -s, --sandbox <SANDBOX_MODE>
          -C, --cd <DIR>
              --skip-git-repo-check
              --ephemeral
              --ignore-user-config
              --ignore-rules
              --json
          -h, --help
        """

    /// `codex features list` from 0.160.0 (every switch the brain uses, plus a feature from a "later version").
    static let features = """
        agent_message_board                      under development  false
        apps                                     stable             true
        auth_elicitation                         stable             true
        browser_use                              stable             true
        browser_use_external                     stable             true
        code_mode_host                           stable             true
        collaboration_modes                      removed            true
        computer_use                             stable             true
        enable_request_compression               stable             true
        fast_mode                                stable             true
        goals                                    stable             true
        hooks                                    stable             true
        image_generation                         stable             true
        in_app_browser                           stable             true
        memories                                 stable             false
        multi_agent                              stable             true
        plugins                                  stable             true
        remote_plugin                            stable             true
        shell_tool                               stable             true
        skill_mcp_dependency_install             stable             true
        skill_search                             stable             true
        sleep_tool                               stable             true
        tool_suggest                             stable             true
        unified_exec                             stable             true
        view_image                               stable             true
        teleport_tool                            experimental       true
        """
}

/// A shell script standing in for `codex`: answers the probes, records what `exec` was given, prints
/// canned JSON lines. Nothing reaches a model.
struct FakeCodex {
    let dir: ShortTempDir
    let path: String
    var capture: String { dir.path + "/capture" }

    init(stream: [String], then tail: String = "exit 0", features: String = CodexFixtures.features, signedIn: Bool = true,
         beforeStream: String = "") throws {
        dir = try ShortTempDir()
        path = dir.path + "/codex"
        mkdir(dir.path + "/capture", 0o700)
        let login = signedIn ? "echo 'Logged in using ChatGPT' >&2; exit 0" : "echo 'Not logged in' >&2; exit 1"
        let script = """
            #!/bin/sh
            case "$1 $2" in
              --version*) echo "codex-cli 0.160.0"; exit 0 ;;
              "exec --help") cat <<'SIDEFOLK_HELP_END'
            \(CodexFixtures.help)
            SIDEFOLK_HELP_END
              exit 0 ;;
              "features list") cat <<'SIDEFOLK_FEATURES_END'
            \(features)
            SIDEFOLK_FEATURES_END
              exit 0 ;;
              "login status") \(login) ;;
            esac
            C='\(dir.path)/capture'
            for a in "$@"; do printf '%s\\n' "$a"; done > "$C/argv"
            env > "$C/env"
            pwd > "$C/cwd"
            stat -f '%Lp' token > "$C/token-mode"
            stat -f '%Lp' instructions.md > "$C/instructions-mode"
            cat instructions.md > "$C/instructions"
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

extension BackendHarness {
    func codex(_ fake: FakeCodex, helper: String = "/usr/bin/true", effort: String? = nil) -> CodexBackend {
        CodexBackend(codexPath: fake.path, paths: paths, helperPath: helper, registry: tokens, reasoningEffort: effort,
                     environment: ["HOME": "/Users/x", "USER": "tester", "LANG": "en_GB.UTF-8", "OPENAI_API_KEY": "sk-CANARY0000000000",
                                   "DYLD_INSERT_LIBRARIES": "/tmp/x.dylib", "NODE_OPTIONS": "--require /tmp/evil.js"])
    }
}

@Suite struct CodexStreamTests {
    @Test func parsesRecordedLines() {
        #expect(CodexStream.parse(CodexFixtures.threadStarted) == .threadStarted)
        #expect(CodexStream.parse(CodexFixtures.turnStarted) == .other)
        #expect(CodexStream.parse(CodexFixtures.warning) == .item(.progress))
        #expect(CodexStream.parse(CodexFixtures.toolStarted) == .item(.sidefolkTool(name: "notes_save", arguments: ["text": "hello from probe"])))
        #expect(CodexStream.parse(CodexFixtures.toolCompleted) == .item(.progress), "a call counts once, when it starts")
        #expect(CodexStream.parse(CodexFixtures.message) == .item(.message("Saved it to your Inbox.")))
        #expect(CodexStream.parse(CodexFixtures.completed) == .turnCompleted(CodexUsage(inputTokens: 2400, outputTokens: 52)))
        guard case .error(let retry) = CodexStream.parse(CodexFixtures.retrying) else { Issue.record("error"); return }
        #expect(retry.hasPrefix("Reconnecting"))
        guard case .turnFailed(let message) = CodexStream.parse(CodexFixtures.unauthorized) else { Issue.record("turn.failed"); return }
        #expect(message.contains("401"))
        #expect(CodexStream.parse("not json") == .other)
    }

    /// Anything but messages and Sidefolk's own tools stops the run; what our switches should have made
    /// impossible also turns the backend off.
    @Test func refusesBuiltInActions() {
        func forbidden(_ line: String) -> (String, Bool)? {
            guard case .item(.forbidden(let what, let switchesFailed)) = CodexStream.parse(line) else { return nil }
            return (what, switchesFailed)
        }
        #expect(forbidden(CodexFixtures.command)?.0.contains("echo hi") == true)
        #expect(forbidden(CodexFixtures.command)?.1 == true)
        #expect(forbidden(CodexFixtures.webSearch)?.0.contains("weather paris") == true)
        #expect(forbidden(CodexFixtures.fileChange)?.0.contains("/tmp/x.txt") == true)
        #expect(forbidden(CodexFixtures.otherServer)?.0.contains("github") == true)
        #expect(forbidden(CodexFixtures.otherServer)?.1 == true)
        #expect(forbidden(CodexFixtures.spawn)?.1 == false, "helper agents can't be switched off on some models: stop, don't disable")
        #expect(forbidden(#"{"type":"item.started","item":{"id":"i","type":"image_generation"}}"#)?.1 == false)
    }

    @Test func errorsInPlainLanguage() {
        #expect(CodexStream.userFacingError(message: "unexpected status 401 Unauthorized", stderr: "", model: "").message == "Codex isn't signed in.")
        #expect(CodexStream.userFacingError(message: "You've hit your usage limit. Upgrade or try again later.", stderr: "", model: "").message
                == "Your ChatGPT plan's Codex limit is reached for now.")
        #expect(CodexStream.userFacingError(message: "", stderr: "Error: unknown configuration field `web_search`", model: "").message
                == "This version of Codex can't be run safely by Sidefolk.")
        #expect(CodexStream.userFacingError(message: "The 'gpt-x' model is not supported when using Codex with a ChatGPT account.",
                                            stderr: "", model: "gpt-x").message == "Codex can't use the model “gpt-x”.")
        let other = CodexStream.userFacingError(message: "boom sk-proj-abcdefghijklmnopqrstuv", stderr: "", model: "")
        #expect(other.detail?.contains("sk-proj-abc") == false)
    }
}

@Suite struct CodexBinaryTests {
    @Test func probesHelpFeaturesAndLogin() {
        #expect(CodexBinary.missingFlags(inHelp: CodexFixtures.help).isEmpty)
        #expect(CodexBinary.missingFlags(inHelp: CodexFixtures.help.replacingOccurrences(of: "--ignore-rules", with: "")) == ["--ignore-rules"])

        let features = CodexBinary.featuresToDisable(fromList: CodexFixtures.features)
        #expect(features.missing.isEmpty)
        #expect(Set(CodexBinary.mustDisable).isSubset(of: features.disable))
        // On by default, not reviewed (a later version's tool): off too. Kept plumbing and removed ones are left alone.
        #expect(features.disable.contains("teleport_tool"))
        #expect(features.disable.contains("fast_mode"))
        #expect(!features.disable.contains("code_mode_host"))
        #expect(!features.disable.contains("collaboration_modes"))
        #expect(!features.disable.contains("memories"))
        let renamed = CodexFixtures.features.replacingOccurrences(of: "shell_tool ", with: "shell_tool2 ")
        #expect(CodexBinary.featuresToDisable(fromList: renamed).missing == ["shell_tool"])

        #expect(CodexBinary.login(fromStatus: "Logged in using ChatGPT", exitCode: 0) == .chatGPT)
        #expect(CodexBinary.login(fromStatus: "Logged in using an API key - sk-proj-***ABCD", exitCode: 0) == .apiKey)
        #expect(CodexBinary.login(fromStatus: "Not logged in", exitCode: 1) == .signedOut)
    }

    @Test func candidatesCoverTheUsualInstalls() {
        let list = CodexBinary.candidates(configured: "", home: "/Users/me", path: "/Users/me/.bun/bin:relative:/opt/tools/bin",
                                          nvmVersions: ["v18.20.0", "v22.11.0"])
        #expect(Array(list.prefix(4)) == ["/Users/me/.local/bin/codex", "/Users/me/.codex/bin/codex", "/opt/homebrew/bin/codex",
                                          "/usr/local/bin/codex"])
        #expect(list.contains("/Users/me/.npm-global/bin/codex"))
        #expect(list.firstIndex(of: "/Users/me/.nvm/versions/node/v22.11.0/bin/codex")! < list.firstIndex(of: "/Users/me/.nvm/versions/node/v18.20.0/bin/codex")!)
        #expect(list.last == "/opt/tools/bin/codex")
        #expect(!list.contains { $0.hasPrefix("relative") })
        #expect(list.filter { $0 == "/Users/me/.bun/bin/codex" }.count == 1)
        #expect(CodexBinary.candidates(configured: "~/bin/codex", home: "/Users/me", path: nil).first == NSHomeDirectory() + "/bin/codex")
    }

    @Test func refusesBinariesInFoldersOthersCanWrite() throws {
        let dir = try ShortTempDir()
        defer { dir.remove() }
        let path = dir.path + "/codex"
        try "#!/bin/sh\n".write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o755)
        #expect(CodexBinary.folderProblem(path) == nil)
        chmod(dir.path, 0o777)
        #expect(CodexBinary.folderProblem(path) != nil)
        chmod(dir.path, 0o700)
    }
}

@Suite struct CodexInvocationTests {
    let task = BrainTask(runId: "r1", threadId: "t", system: "SYSTEM-SECRET about you",
                         messages: [ChatMessage(role: .user, text: "first PROMPT-SECRET"), ChatMessage(role: .assistant, text: "ok"),
                                    ChatMessage(role: .user, text: "now PROMPT-LATEST")],
                         model: "", deadline: Date())
    let install = CodexInstall(path: "/usr/local/bin/codex", version: "0.160.0", featuresToDisable: CodexBinary.mustDisable + ["fast_mode"])
    let base = ["HOME": "/Users/x", "USER": "me", "OPENAI_API_KEY": "sk-x", "DYLD_LIBRARY_PATH": "/x", "NODE_OPTIONS": "--inspect",
                "LANG": "fr_FR.UTF-8", "CODEX_HOME": "/Users/x/.codex-work"]

    @Test func argvIsIsolatedAndCarriesNoUserData() {
        let runDir = "/Users/x/Library/Application Support/Sidefolk/brain/run-r1"
        let inv = CodexBackend.invocation(task: task, install: install, runDir: runDir, helperPath: "/Apps/Side \"folk\"/sidefolk",
                                          sidefolkHome: "/home", reasoningEffort: nil, environment: base)
        let args = inv.arguments
        for secret in ["SYSTEM-SECRET", "PROMPT-SECRET", "PROMPT-LATEST"] {
            #expect(!args.contains { $0.contains(secret) })
        }
        func follows(_ flag: String, _ value: String) -> Bool {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return false }
            return args[i + 1] == value
        }
        func config(_ key: String) -> String? {
            args.indices.dropLast().first { args[$0] == "-c" && args[$0 + 1].hasPrefix(key + "=") }.map { String(args[$0 + 1].dropFirst(key.count + 1)) }
        }
        #expect(args.first == "exec")
        #expect(args.last == "-", "the conversation goes over stdin")
        for flag in ["--json", "--strict-config", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules"] {
            #expect(args.contains(flag))
        }
        #expect(follows("--sandbox", "read-only"))
        #expect(follows("--cd", runDir))
        #expect(!args.contains("--model"), "an empty model means Codex's default")
        #expect(config("approval_policy") == #""never""#)
        #expect(config("web_search") == #""disabled""#)
        #expect(config("project_doc_max_bytes") == "0")
        #expect(config("skills.include_instructions") == "false")
        #expect(config("model_instructions_file") == "\"\(runDir)/instructions.md\"")
        #expect(config("mcp_servers.sidefolk.command") == #""/Apps/Side \"folk\"/sidefolk""#)
        #expect(config("mcp_servers.sidefolk.args") == #"["mcp"]"#)
        #expect(config("mcp_servers.sidefolk.env.SIDEFOLK_RUN_DIR") == "\"\(runDir)\"")
        #expect(config("mcp_servers.sidefolk.default_tools_approval_mode") == #""approve""#)
        // A card may wait for the person a day at most (D37); Codex must not give up on the call first.
        #expect(config("mcp_servers.sidefolk.tool_timeout_sec") == String(24 * 60 * 60 + 300))
        #expect(config("model_reasoning_effort") == nil)
        for feature in install.featuresToDisable { #expect(follows("--disable", feature) || args.contains(feature)) }
        #expect(args.filter { $0 == "--disable" }.count == install.featuresToDisable.count)

        #expect(inv.files["instructions.md"]?.hasPrefix("SYSTEM-SECRET about you") == true)
        #expect(inv.files["instructions.md"]?.contains("AGENTS.md") == true)
        #expect(inv.input.contains("Earlier in this conversation:\nUser: first PROMPT-SECRET\nYou: ok"))
        #expect(inv.input.hasSuffix("The user's new message:\nnow PROMPT-LATEST"))
        #expect(!inv.input.contains("SYSTEM-SECRET"))
    }

    @Test func thinkHarderAndModelsReachArgv() {
        var named = task
        named.model = "gpt-5.5"
        let inv = CodexBackend.invocation(task: named, install: install, runDir: "/r", helperPath: "/h", sidefolkHome: "/home",
                                          reasoningEffort: "high", environment: [:])
        #expect(inv.arguments[inv.arguments.firstIndex(of: "--model")! + 1] == "gpt-5.5")
        #expect(inv.arguments.contains(#"model_reasoning_effort="high""#))
        named.model = "--dangerously-bypass-approvals-and-sandbox"
        let unsafe = CodexBackend.invocation(task: named, install: install, runDir: "/r", helperPath: "/h", sidefolkHome: "/home",
                                             reasoningEffort: nil, environment: [:])
        #expect(!unsafe.arguments.contains("--model"))
        #expect(!unsafe.arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
    }

    @Test func environmentIsAllowListed() {
        let inv = CodexBackend.invocation(task: task, install: install, runDir: "/r", helperPath: "/h", sidefolkHome: "/home",
                                          reasoningEffort: nil, environment: base)
        #expect(Set(inv.environment.keys) == ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "PATH", "CODEX_HOME"])
        #expect(inv.environment["TMPDIR"] == "/r/tmp")
        #expect(inv.environment["CODEX_HOME"] == "/Users/x/.codex-work")
        #expect(inv.environment["PATH"]?.hasPrefix("/usr/local/bin:/opt/homebrew/bin") == true)
        let relative = CodexBackend.environment(base: ["CODEX_HOME": "work"], tmp: "/t", codexPath: "/c/codex")
        #expect(relative["CODEX_HOME"] == nil)
    }
}

@Suite(.serialized) struct CodexRunTests {
    @Test func aRunWithRecordedOutput() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeCodex(stream: [CodexFixtures.threadStarted, CodexFixtures.turnStarted, CodexFixtures.warning,
                                          CodexFixtures.commentary, CodexFixtures.toolStarted, CodexFixtures.toolCompleted,
                                          CodexFixtures.message, CodexFixtures.completed])
        defer { fake.remove() }
        let backend = h.codex(fake)
        #expect(try await backend.check().get().hasPrefix("Codex 0.160.0"))

        let task = h.task()
        let reply = try await backend.run(task, toolbox: h.toolbox(task.runId), emit: { _ in })
        #expect(reply.text == "Saved it to your Inbox.", "the last message is the answer, not the commentary before a tool call")

        let argv = fake.captured("argv").components(separatedBy: "\n")
        #expect(argv.contains("--ignore-user-config"))
        #expect(argv.contains("teleport_tool"), "an unreviewed feature is switched off")
        #expect(!argv.contains { $0.contains("folks with jobs") || $0.contains("likes tea") })
        #expect(fake.captured("token-mode") == "600")
        #expect(fake.captured("instructions-mode") == "600")
        #expect(fake.captured("instructions").hasPrefix("About you: likes tea"))
        #expect(fake.captured("stdin").contains("folks with jobs"))
        let env = fake.captured("env")
        #expect(!env.contains("OPENAI") && !env.contains("DYLD") && !env.contains("NODE_OPTIONS") && !env.contains("CANARY"))
        let runDir = fake.captured("cwd")
        #expect(runDir.hasPrefix(h.home.path + "/brain/run-") || runDir.hasPrefix("/private" + h.home.path + "/brain/run-"))
        #expect(!FileManager.default.fileExists(atPath: runDir))
        #expect(h.tokens.count == 0)
        let usage = try #require(backend.takeUsage(runId: task.runId))
        #expect(usage.inputTokens == 2400)
        #expect(usage.outputTokens == 52)
        #expect(usage.steps == 2)
    }

    @Test func aBuiltInActionKillsTheRunAndDisablesTheBackend() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeCodex(stream: [CodexFixtures.threadStarted, CodexFixtures.command], then: "sleep 30")
        defer { fake.remove() }
        let task = h.task()
        let started = Date()
        do {
            _ = try await h.codex(fake).run(task, toolbox: h.toolbox(task.runId), emit: { _ in })
            Issue.record("expected an error")
        } catch let error as UserFacingError {
            #expect(error.message.hasPrefix("Sidefolk stopped using Codex because it tried to run a command"))
        }
        #expect(Date().timeIntervalSince(started) < 10)
        let pid = try #require(pid_t(fake.captured("pid")))
        #expect(await pollUntil { kill(pid, 0) != 0 })
        // Disabled from now on, even for a backend built afresh, without starting the CLI again.
        try FileManager.default.removeItem(atPath: fake.capture + "/pid")
        let fresh = h.codex(fake)
        await #expect(throws: UserFacingError.self) { _ = try await fresh.run(task, toolbox: h.toolbox(task.runId), emit: { _ in }) }
        #expect(fake.captured("pid").isEmpty)
        guard case .failure = await fresh.check() else { Issue.record("check must fail"); return }
    }

    @Test func helperAgentsStopTheRunOnly() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeCodex(stream: [CodexFixtures.threadStarted, CodexFixtures.spawn], then: "sleep 30")
        defer { fake.remove() }
        let task = h.task()
        do {
            _ = try await h.codex(fake).run(task, toolbox: h.toolbox(task.runId), emit: { _ in })
            Issue.record("expected an error")
        } catch let error as UserFacingError {
            #expect(error.message == "Codex tried to start helper agents, so I stopped it.")
        }
        #expect(try await h.codex(fake).check().get().hasPrefix("Codex"), "still usable")
    }

    @Test func signedOutNeverStartsARun() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeCodex(stream: [CodexFixtures.completed], signedIn: false)
        defer { fake.remove() }
        let task = h.task()
        do {
            _ = try await h.codex(fake).run(task, toolbox: h.toolbox(task.runId), emit: { _ in })
            Issue.record("expected an error")
        } catch let error as UserFacingError {
            #expect(error.message == "Codex isn't signed in.")
        }
        #expect(fake.captured("argv").isEmpty)
    }

    @Test func aFailedTurnIsExplained() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeCodex(stream: [CodexFixtures.threadStarted, CodexFixtures.turnStarted, CodexFixtures.retrying,
                                          CodexFixtures.unauthorized], then: "exit 1")
        defer { fake.remove() }
        let task = h.task()
        do {
            _ = try await h.codex(fake).run(task, toolbox: h.toolbox(task.runId), emit: { _ in })
            Issue.record("expected an error")
        } catch let error as UserFacingError {
            #expect(error.message == "Codex isn't signed in.")
        }
    }

    @Test func missingSwitchesFailClosed() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let renamed = CodexFixtures.features.replacingOccurrences(of: "hooks ", with: "hooks2 ")
        let fake = try FakeCodex(stream: [CodexFixtures.completed], features: renamed)
        defer { fake.remove() }
        let task = h.task()
        await #expect(throws: UserFacingError.self) { _ = try await h.codex(fake).run(task, toolbox: h.toolbox(task.runId), emit: { _ in }) }
        #expect(fake.captured("argv").isEmpty, "Codex must not have been run with a prompt")
    }

    @Test func deadlineStopsTheRun() async throws {
        let h = try BackendHarness()
        defer { h.remove() }
        let fake = try FakeCodex(stream: [CodexFixtures.threadStarted], then: "sleep 30")
        defer { fake.remove() }
        let task = h.task(seconds: 1)
        do {
            _ = try await h.codex(fake).run(task, toolbox: h.toolbox(task.runId), emit: { _ in })
            Issue.record("expected a timeout")
        } catch let error as UserFacingError {
            #expect(error.message == "Codex took too long, so I stopped it.")
        }
        let pid = try #require(pid_t(fake.captured("pid")))
        #expect(await pollUntil { kill(pid, 0) != 0 })
    }

    /// The whole path: the fake CLI starts the real `sidefolk mcp` helper the way Codex does, the helper
    /// reads the run's token and calls a tool through the app's socket and the run's toolbox.
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
            printf '%s\\n' '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"codex-mcp-client"}}}' \
              '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"notes_save","arguments":{"x":"from codex"}}}' \
              | SIDEFOLK_RUN_DIR="$PWD" SIDEFOLK_HOME='\(server.dir.path)' '\(helper)' mcp > "$C/mcp-out"
            """
        let fake = try FakeCodex(stream: [CodexFixtures.threadStarted, CodexFixtures.message, CodexFixtures.completed], beforeStream: mcpCall)
        defer { fake.remove() }
        let backend = CodexBackend(codexPath: fake.path, paths: SidefolkPaths(home: URL(fileURLWithPath: server.dir.path)),
                                   helperPath: helper, registry: server.tokens)
        let task = BrainTask(runId: "run-codex", threadId: "t", system: "s", messages: [ChatMessage(role: .user, text: "save")],
                             model: "", deadline: Date().addingTimeInterval(20))
        let toolbox = BrainToolbox(runId: task.runId, specs: server.env.registry.specs, executor: server.env.executor, emit: { _ in })
        _ = try await backend.run(task, toolbox: toolbox, emit: { _ in })
        #expect(fake.captured("mcp-out").contains("Saved from codex."))
        #expect(toolbox.outcomes.count == 1)
        #expect(try await server.env.activity.recent().first?.runId == "run-codex")
    }
}
