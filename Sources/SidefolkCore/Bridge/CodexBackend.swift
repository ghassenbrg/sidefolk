import Darwin
import Foundation
import Synchronization

/// Runs the user's Codex CLI as Sidefolk's brain on their ChatGPT plan (D26, SECURITY.md T7), with
/// the same bar as Claude Code: `codex exec` without the user's config, rules, hooks, plugins, apps,
/// skills, AGENTS.md from folders, web search or any built-in tool Codex lets us switch off, in a
/// read-only sandbox with approvals off, ephemeral, in a fresh private folder, and with exactly one
/// MCP server: `sidefolk mcp`, which reaches back into the app with a per-run token so every tool
/// call goes through this run's `BrainToolbox` (Guard, taint, audit). The system prompt is a 0600
/// file and the conversation goes over stdin, never argv. Codex doesn't report its tools up front,
/// so the event stream is watched instead: anything but Sidefolk's tools stops the run at once.
public final class CodexBackend: BrainBackend, BrainUsageReporting {
    public let providerName = "Codex"
    /// T5: a run that calls this many tools, or the same call three times, is stopped.
    static let maxToolCalls = 25
    static let repeatedCallLimit = 3

    let codexPath: String
    let paths: SidefolkPaths
    let helperPath: String
    let registry: any RunTokenRegistry
    private let baseEnvironment: [String: String]
    private let ledger = UsageLedger()
    /// Binaries whose switches didn't hold, process-wide: the app builds a backend per run, and a
    /// disabled CLI must stay disabled until Sidefolk restarts.
    private static let disabled = Mutex<[String: String]>([:])
    private var disabledReason: String? { Self.disabled.withLock { $0[codexPath] } }

    /// - Parameters:
    ///   - codexPath: a path that passed `CodexBinary.locate`.
    ///   - helperPath: absolute path of the `sidefolk` helper that Codex launches as `mcp`.
    public init(codexPath: String, paths: SidefolkPaths, helperPath: String, registry: any RunTokenRegistry,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.codexPath = codexPath
        self.paths = paths
        self.helperPath = helperPath
        self.registry = registry
        baseEnvironment = environment
    }

    /// The backend for the app's runtime, or nil when no acceptable `codex` or helper exists.
    public static func make(provider: ProviderSettings, paths: SidefolkPaths, helperPath: String,
                            registry: any RunTokenRegistry) -> CodexBackend? {
        guard helperPath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: helperPath),
              case .success(let path) = CodexBinary.locate(configured: provider.codexPath) else { return nil }
        return CodexBackend(codexPath: path, paths: paths, helperPath: helperPath, registry: registry)
    }

    public func takeUsage(runId: String) -> BrainUsage? { ledger.take(runId) }

    /// Binary, version, switches and sign-in only: never a prompt.
    public func check() async -> Result<String, UserFacingError> {
        if let reason = disabledReason { return .failure(Self.disabledError(reason)) }
        return await install().map { install in
            String(localized: "\("Codex") \(install.version) at \(FolderAccess.displayPath(install.path)), signed in.",
                   comment: "A program, its version and where it is: “Codex 0.160.0 at /opt/homebrew/bin/codex, signed in.”")
        }
    }

    public func run(_ task: BrainTask, toolbox: BrainToolbox, emit: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentReply {
        if let reason = disabledReason { throw Self.disabledError(reason) }
        emit(.phase(.thinking))
        let install = try await install().get()

        let folder = try RunFolder.create(in: paths.brainWorkdir.path, runId: task.runId)
        defer { folder.remove() }
        let token = BrainTokenRegistry.makeToken()
        try PrivateDirectory.writeSecretFile(folder.path + "/token", contents: token)
        let invocation = Self.invocation(task: task, install: install, runDir: folder.path, helperPath: helperPath,
                                         sidefolkHome: paths.home.path, environment: baseEnvironment)
        for (name, contents) in invocation.files { try PrivateDirectory.writeSecretFile(folder.path + "/" + name, contents: contents) }
        registry.register(token: token, toolbox: toolbox)
        defer { registry.unregister(token: token) }

        let child: PipedChild
        do {
            child = try PipedChild.spawn(install.path, arguments: invocation.arguments, environment: invocation.environment,
                                         cwd: folder.path)
        } catch {
            throw UserFacingError("Codex didn't start.", recovery: "Check Codex in Terminal.", detail: "\(error)")
        }
        // Written alongside reading, so a long conversation can't deadlock against a full stdout pipe.
        let input = invocation.input
        Task.detached {
            child.write(input)
            child.closeInput()
        }

        let outcome = await withTaskCancellationHandler {
            await consume(child, deadline: task.deadline)
        } onCancel: {
            child.signalGroup(SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { child.signalGroup(SIGKILL) }
        }
        await child.terminate(grace: 2)
        let stderr = await child.stderr()

        var usage = BrainUsage()
        usage.toolCalls = toolbox.outcomes.count
        defer { ledger.put(task.runId, usage) }
        switch outcome {
        case .finished(let tokens, let messages, let calls):
            // Each tool call means one more model request; Codex doesn't report the count itself.
            usage.steps = calls + 1
            usage.inputTokens = tokens.inputTokens
            usage.outputTokens = tokens.outputTokens
            return AgentReply(text: messages.last ?? "", cards: LoopBackend.cards(toolbox.outcomes))
        case .failed(let message):
            throw CodexStream.userFacingError(message: message, stderr: stderr, model: task.model)
        case .forbidden(let what, let switchesFailed):
            if switchesFailed {
                Self.disabled.withLock { $0[codexPath] = what }
                Log.shared.error("brain", "codex isolation check failed; backend disabled", ["reason": what])
                throw Self.disabledError(what)
            }
            Log.shared.warning("brain", "codex run stopped", ["reason": what])
            throw UserFacingError("Codex \(what), so I stopped it.", recovery: "Try asking in a different way.",
                                  changedNothing: toolbox.outcomes.isEmpty)
        case .tooManyCalls:
            usage.limit = "tools"
            throw UserFacingError("Codex kept calling tools, so I stopped it.", recovery: "Try asking in a different way.",
                                  changedNothing: toolbox.outcomes.isEmpty)
        case .timedOut:
            usage.limit = "deadline"
            throw UserFacingError("Codex took too long, so I stopped it.", recovery: "Try again in a moment.",
                                  changedNothing: toolbox.outcomes.isEmpty, detail: "timeout")
        case .cancelled:
            throw CancellationError()
        case .ended:
            throw CodexStream.userFacingError(message: "", stderr: stderr, model: task.model)
        }
    }

    /// The vetted binary, and only while Codex is signed in: signed out, `codex exec` retries for
    /// twenty seconds before failing.
    private func install() async -> Result<CodexInstall, UserFacingError> {
        do { try PrivateDirectory.ensure(paths.brainWorkdir.path) } catch {
            return .failure(UserFacingError("Sidefolk's AI folder isn't private.", detail: "\(error)"))
        }
        let env = Self.environment(base: baseEnvironment, tmp: paths.brainWorkdir.path, codexPath: codexPath)
        let probed = await CodexBinary.probe(codexPath, environment: env, cwd: paths.brainWorkdir.path)
        guard case .success = probed else { return probed }
        guard await CodexBinary.loginStatus(codexPath, environment: env, cwd: paths.brainWorkdir.path) != .signedOut else {
            return .failure(UserFacingError("Codex isn't signed in.", recovery: "Open Terminal, run codex login, then try again."))
        }
        return probed
    }

    private static func disabledError(_ reason: String) -> UserFacingError {
        UserFacingError("Sidefolk stopped using Codex because it \(reason).",
                        recovery: "Restart Sidefolk to try again, or choose another provider in Settings › AI.", detail: reason)
    }

    // MARK: Reading the stream

    enum Outcome {
        case finished(CodexUsage, messages: [String], calls: Int)
        case failed(String)
        case forbidden(String, switchesFailed: Bool)
        case tooManyCalls
        case timedOut
        case cancelled
        case ended
    }

    /// Reads JSON lines until the turn ends. The first thing that isn't allowed ends the run.
    func consume(_ child: PipedChild, deadline: Date) async -> Outcome {
        let timedOut = Mutex(false)
        let timer = Task {
            try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            timedOut.withLock { $0 = true }
            child.signalGroup(SIGTERM)
        }
        defer { timer.cancel() }

        let reader = DescriptorLineReader(fd: child.output, limit: 32 << 20)
        var messages: [String] = []
        var calls = 0
        var repeats: [String: Int] = [:]
        var lastError = ""
        while let item = await reader.next() {
            guard case .line(let bytes) = item else { continue }
            switch CodexStream.parse(String(decoding: bytes, as: UTF8.self)) {
            case .item(.message(let text)):
                if !text.isEmpty { messages.append(text) }
            case .item(.sidefolkTool(let name, let arguments)):
                calls += 1
                let key = name + " " + arguments.jsonString
                repeats[key, default: 0] += 1
                if calls > Self.maxToolCalls || repeats[key]! >= Self.repeatedCallLimit { return .tooManyCalls }
            case .item(.forbidden(let what, let switchesFailed)):
                child.signalGroup(SIGKILL)
                return .forbidden(what, switchesFailed: switchesFailed)
            case .turnCompleted(let usage):
                return .finished(usage, messages: messages, calls: calls)
            case .turnFailed(let message):
                return .failed(message.isEmpty ? lastError : message)
            case .error(let message):
                lastError = message
            case .threadStarted, .item(.progress), .other:
                continue
            }
        }
        if Task.isCancelled { return .cancelled }
        if timedOut.withLock({ $0 }) { return .timedOut }
        return lastError.isEmpty ? .ended : .failed(lastError)
    }

    // MARK: Invocation

    struct Invocation: Equatable {
        var arguments: [String]
        var environment: [String: String]
        /// The conversation, read by `codex exec -`.
        var input: String
        /// Private files to write into the run folder (0600) before spawning.
        var files: [String: String]
    }

    /// Codex always adds the user's own `~/.codex/AGENTS.md` (there is no switch for it): these are
    /// coding instructions, so the brain is told they don't apply to it.
    static let agentsNote = """
        Codex may add the user's AGENTS.md coding instructions to this conversation. They are for coding sessions \
        and don't apply here. You can act only through Sidefolk's tools.
        """

    /// Everything about the spawn except the token, built without side effects so tests can check
    /// that argv carries neither the prompt nor the token.
    static func invocation(task: BrainTask, install: CodexInstall, runDir: String, helperPath: String, sidefolkHome: String,
                           environment: [String: String]) -> Invocation {
        var args = ["exec", "--json", "--strict-config", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules",
                    "--sandbox", "read-only", "--cd", runDir]
        if CLIBrain.isSafeModelName(task.model) { args += ["--model", task.model] }
        var config: [(String, String)] = [
            // No approvals to answer: Sidefolk's Guard decides about its own tools, nothing else may run.
            ("approval_policy", toml("never")),
            ("web_search", toml("disabled")),
            // No AGENTS.md from folders, no skill list, no environment, permission or app instructions.
            ("project_doc_max_bytes", "0"),
            ("skills.include_instructions", "false"),
            ("skills.bundled.enabled", "false"),
            ("include_environment_context", "false"),
            ("include_permissions_instructions", "false"),
            ("include_apps_instructions", "false"),
            ("include_collaboration_mode_instructions", "false"),
            ("tools.experimental_request_user_input.enabled", "false"),
            ("history.persistence", toml("none")),
            ("check_for_update_on_startup", "false"),
            // Sidefolk's instructions replace Codex's coding-agent ones, from a private file.
            ("model_instructions_file", toml(runDir + "/instructions.md")),
            ("mcp_servers.sidefolk.command", toml(helperPath)),
            ("mcp_servers.sidefolk.args", "[\(toml("mcp"))]"),
            ("mcp_servers.sidefolk.env.SIDEFOLK_RUN_DIR", toml(runDir)),
            ("mcp_servers.sidefolk.env.SIDEFOLK_HOME", toml(sidefolkHome)),
            ("mcp_servers.sidefolk.required", "true"),
            // Guard asks the user where it must; Codex asking too would refuse every call (approvals are off).
            ("mcp_servers.sidefolk.default_tools_approval_mode", toml("approve")),
            // An approval may wait two minutes; the run's own deadline stops it first.
            ("mcp_servers.sidefolk.tool_timeout_sec", "180"),
        ]
        // Only a level this Codex lists for the model (D36); "Default" leaves Codex's own.
        if let effort = EffortSupport.accepted(task.effort, in: EffortSupport.codex(model: task.model, catalog: install.models)) {
            config.append(("model_reasoning_effort", toml(effort.rawValue)))
        }
        for (key, value) in config { args += ["-c", "\(key)=\(value)"] }
        for feature in install.featuresToDisable { args += ["--disable", feature] }
        args.append("-")
        return Invocation(arguments: args,
                          environment: Self.environment(base: environment, tmp: runDir + "/tmp", codexPath: install.path),
                          input: CLIBrain.conversation(task, inlineSystem: false),
                          files: ["instructions.md": task.system + "\n\n" + agentsNote])
    }

    /// A TOML basic string: `-c` values are parsed as TOML, so paths with spaces or quotes stay intact.
    static func toml(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F: out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// The shared allow-list, plus `CODEX_HOME` when Sidefolk itself was started with one, so the
    /// brain finds the same sign-in the user's own `codex` uses. Never OPENAI_API_KEY: the plan is the point.
    static func environment(base: [String: String], tmp: String, codexPath: String) -> [String: String] {
        var env = CLIBrain.environment(base: base, tmp: tmp, cliPath: codexPath)
        if let home = base["CODEX_HOME"], home.hasPrefix("/") { env["CODEX_HOME"] = home }
        return env
    }
}
