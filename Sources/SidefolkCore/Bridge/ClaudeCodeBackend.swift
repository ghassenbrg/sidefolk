import Darwin
import Foundation
import Synchronization

/// Runs the user's Claude Code CLI as Sidefolk's brain on their subscription (D8, SECURITY.md T7).
/// The CLI gets no built-in tools, no user or project settings, no slash commands, no session
/// file and exactly one MCP server: `sidefolk mcp`, which reaches back into the app with a per-run
/// token so every tool call goes through this run's `BrainToolbox` (Guard, taint, audit). The
/// prompt travels over stdin, never argv. If the CLI's init event shows any other tool or server,
/// the run is killed and the backend disabled.
public final class ClaudeCodeBackend: BrainBackend, BrainUsageReporting {
    public let providerName = "Claude Code"
    /// T5: a run that calls this many tools, or the same call three times, is stopped.
    static let maxToolCalls = 25
    static let repeatedCallLimit = 3

    let claudePath: String
    let paths: SidefolkPaths
    let helperPath: String
    let registry: any RunTokenRegistry
    private let baseEnvironment: [String: String]
    private let ledger = UsageLedger()
    /// Binaries that failed the isolation check, process-wide: the app may build a new backend
    /// per run, and a disabled CLI must stay disabled until Sidefolk restarts.
    private static let disabled = Mutex<[String: String]>([:])
    private var disabledReason: String? { Self.disabled.withLock { $0[claudePath] } }

    /// - Parameters:
    ///   - claudePath: a path that passed `ClaudeBinary.locate`.
    ///   - helperPath: absolute path of the `sidefolk` helper that Claude Code launches as `mcp`.
    public init(claudePath: String, paths: SidefolkPaths, helperPath: String, registry: any RunTokenRegistry,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.claudePath = claudePath
        self.paths = paths
        self.helperPath = helperPath
        self.registry = registry
        baseEnvironment = environment
    }

    /// The backend for the app's runtime, or nil when no acceptable `claude` or helper exists.
    public static func make(settings: AppSettings, paths: SidefolkPaths, helperPath: String, registry: any RunTokenRegistry) -> ClaudeCodeBackend? {
        make(provider: settings.provider, paths: paths, helperPath: helperPath, registry: registry)
    }

    /// The same, from provider settings: what `BrainFactory.standard(claudeCodeBackend:)` passes.
    public static func make(provider: ProviderSettings, paths: SidefolkPaths, helperPath: String, registry: any RunTokenRegistry) -> ClaudeCodeBackend? {
        guard helperPath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: helperPath),
              case .success(let path) = ClaudeBinary.locate(configured: provider.claudePath) else { return nil }
        return ClaudeCodeBackend(claudePath: path, paths: paths, helperPath: helperPath, registry: registry)
    }

    /// Steps, tokens and tool calls of a finished run, for its `AgentRun` record.
    public func takeUsage(runId: String) -> BrainUsage? { ledger.take(runId) }

    /// Binary, version and flag probe only: never a prompt.
    public func check() async -> Result<String, UserFacingError> {
        if let reason = disabledReason { return .failure(Self.disabledError(reason)) }
        return await install().map { "Claude Code \($0.version) at \(FolderAccess.displayPath($0.path))" }
    }

    public func run(_ task: BrainTask, toolbox: BrainToolbox, emit: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentReply {
        if let reason = disabledReason { throw Self.disabledError(reason) }
        emit(.phase(.thinking))
        let install = try await install().get()

        let folder = try RunFolder.create(in: paths.brainWorkdir.path, runId: task.runId)
        defer { folder.remove() }
        let token = BrainTokenRegistry.makeToken()
        try PrivateDirectory.writeSecretFile(folder.path + "/token", contents: token)
        let invocation = Self.invocation(task: task, flags: install.flags, claudePath: install.path, runDir: folder.path,
                                         helperPath: helperPath, sidefolkHome: paths.home.path, environment: baseEnvironment)
        for (name, contents) in invocation.files { try PrivateDirectory.writeSecretFile(folder.path + "/" + name, contents: contents) }
        registry.register(token: token, toolbox: toolbox)
        defer { registry.unregister(token: token) }

        let child: PipedChild
        do {
            child = try PipedChild.spawn(install.path, arguments: invocation.arguments, environment: invocation.environment,
                                           cwd: folder.path)
        } catch {
            throw UserFacingError("Claude Code didn't start.", recovery: "Check Claude Code in Terminal.", detail: "\(error)")
        }
        // Written alongside reading, so a large message can't deadlock against a full stdout pipe.
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
        case .finished(let result, let texts):
            usage.steps = result.turns ?? 1
            usage.inputTokens = result.inputTokens
            usage.outputTokens = result.outputTokens
            if result.isError { throw ClaudeStream.userFacingError(message: result.text, stderr: stderr) }
            let text = result.text.isEmpty ? texts.joined(separator: "\n\n") : result.text
            return AgentReply(text: text, cards: LoopBackend.cards(toolbox.outcomes))
        case .isolationBroken(let reason):
            Self.disabled.withLock { $0[claudePath] = reason }
            Log.shared.error("brain", "claude code isolation check failed; backend disabled", ["reason": reason])
            throw Self.disabledError(reason)
        case .bridgeFailed:
            throw UserFacingError("Sidefolk's tools didn't connect to Claude Code.", recovery: "Try again, or restart Sidefolk.")
        case .tooManyCalls:
            usage.limit = "tools"
            throw UserFacingError("Claude kept calling tools, so I stopped it.", recovery: "Try asking in a different way.",
                                  changedNothing: toolbox.outcomes.isEmpty)
        case .timedOut:
            usage.limit = "deadline"
            throw UserFacingError("Claude took too long, so I stopped it.", recovery: "Try again in a moment.",
                                  changedNothing: toolbox.outcomes.isEmpty, detail: "timeout")
        case .cancelled:
            throw CancellationError()
        case .ended:
            throw ClaudeStream.userFacingError(message: "", stderr: stderr)
        }
    }

    private func install() async -> Result<ClaudeInstall, UserFacingError> {
        do { try PrivateDirectory.ensure(paths.brainWorkdir.path) } catch {
            return .failure(UserFacingError("Sidefolk's brain folder isn't private.", detail: "\(error)"))
        }
        let env = Self.environment(base: baseEnvironment, tmp: paths.brainWorkdir.path, claudePath: claudePath)
        return await ClaudeBinary.probe(claudePath, environment: env, cwd: paths.brainWorkdir.path)
    }

    private static func disabledError(_ reason: String) -> UserFacingError {
        UserFacingError("Sidefolk stopped using Claude Code because it couldn't keep it isolated.",
                        recovery: "Check Claude Code's managed settings, then restart Sidefolk, or choose another provider.",
                        detail: reason)
    }

    // MARK: Reading the stream

    enum Outcome {
        case finished(ClaudeResult, texts: [String])
        case isolationBroken(String)
        case bridgeFailed
        case tooManyCalls
        case timedOut
        case cancelled
        case ended
    }

    /// Reads stream-json until the result. The init event is checked before anything else counts.
    func consume(_ child: PipedChild, deadline: Date) async -> Outcome {
        let timedOut = Mutex(false)
        let timer = Task {
            try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            timedOut.withLock { $0 = true }
            child.signalGroup(SIGTERM)
        }
        defer { timer.cancel() }

        let reader = DescriptorLineReader(fd: child.output, limit: 32 << 20)
        var verified = false
        var texts: [String] = []
        var calls = 0
        var repeats: [String: Int] = [:]
        while let item = await reader.next() {
            guard case .line(let bytes) = item else { continue }
            switch ClaudeStream.parse(String(decoding: bytes, as: UTF8.self)) {
            case .initialized(let info):
                if let problem = ClaudeStream.isolationProblem(info) { return .isolationBroken(problem) }
                if info.mcpServers.first(where: { $0.name == "sidefolk" })?.status == "failed" { return .bridgeFailed }
                verified = true
            case .assistant(let text, let uses):
                guard verified else { return .isolationBroken("Claude Code answered before reporting what it loaded.") }
                if !text.isEmpty { texts.append(text) }
                for use in uses {
                    calls += 1
                    let key = use.name + " " + use.input.jsonString
                    repeats[key, default: 0] += 1
                    if calls > Self.maxToolCalls || repeats[key]! >= Self.repeatedCallLimit { return .tooManyCalls }
                }
            case .result(let result):
                // An error result (not signed in…) may come before init; success never may.
                guard verified || result.isError else { return .isolationBroken("Claude Code finished without reporting what it loaded.") }
                return .finished(result, texts: texts)
            case .other:
                continue
            }
        }
        if Task.isCancelled { return .cancelled }
        return timedOut.withLock { $0 } ? .timedOut : .ended
    }

    // MARK: Invocation

    struct Invocation: Equatable {
        var arguments: [String]
        var environment: [String: String]
        /// One stream-json user message, newline-terminated.
        var input: String
        /// Private files to write into the run folder (0600) before spawning.
        var files: [String: String]
    }

    /// Everything about the spawn except the token, built without side effects so tests can check
    /// that argv carries neither the prompt nor the token.
    static func invocation(task: BrainTask, flags: ClaudeFlags, claudePath: String, runDir: String, helperPath: String,
                           sidefolkHome: String, environment: [String: String]) -> Invocation {
        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
        if isSafeModelName(task.model) { args += ["--model", task.model] }
        args += ["--tools", "", "--strict-mcp-config", "--mcp-config", runDir + "/mcp.json", "--disable-slash-commands",
                 "--no-session-persistence", "--permission-prompts", "none", "--allowedTools", "mcp__sidefolk"]
        // --restricted ignores user, project and local settings (hooks, plugins, env); an empty
        // --setting-sources does the same on CLIs without it.
        args += flags.restricted ? ["--restricted"] : ["--setting-sources", ""]
        var files = ["mcp.json": mcpConfig(helperPath: helperPath, runDir: runDir, sidefolkHome: sidefolkHome)]
        // The system prompt holds user data (notes, About you), and argv is visible to every local
        // user through ps: it goes in a 0600 file, or into the stdin message.
        if flags.systemPromptFile {
            files["system.md"] = task.system
            args += ["--system-prompt-file", runDir + "/system.md"]
        } else {
            args += ["--system-prompt", "You are Sidefolk's brain. Follow the instructions at the start of the user's message."]
        }
        let text = conversation(task, inlineSystem: !flags.systemPromptFile)
        let message: JSONValue = ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": .string(text)]]]]
        return Invocation(arguments: args,
                          environment: Self.environment(base: environment, tmp: runDir + "/tmp", claudePath: claudePath),
                          input: message.jsonString + "\n", files: files)
    }

    /// The MCP config: only the Sidefolk bridge, told where this run's token is.
    static func mcpConfig(helperPath: String, runDir: String, sidefolkHome: String) -> String {
        let config: JSONValue = ["mcpServers": ["sidefolk": [
            "type": "stdio", "command": .string(helperPath), "args": ["mcp"],
            "env": ["SIDEFOLK_RUN_DIR": .string(runDir), "SIDEFOLK_HOME": .string(sidefolkHome)],
        ]]]
        return config.jsonString
    }

    /// The whole exchange as one user message: earlier turns as context, then the new message.
    static func conversation(_ task: BrainTask, inlineSystem: Bool) -> String {
        var parts: [String] = []
        if inlineSystem { parts.append("<instructions>\n\(task.system)\n</instructions>") }
        let earlier = task.messages.dropLast()
        if !earlier.isEmpty {
            let lines = earlier.map { "\($0.role == .user ? "User" : "You"): \($0.text)" }.joined(separator: "\n")
            parts.append("Earlier in this conversation:\n\(lines)")
        }
        if let last = task.messages.last {
            parts.append(earlier.isEmpty && !inlineSystem ? last.text : "The user's new message:\n\(last.text)")
        }
        return parts.joined(separator: "\n\n")
    }

    /// Allow-listed environment (T7): never DYLD_*, NODE_OPTIONS or ANTHROPIC_*.
    static func environment(base: [String: String], tmp: String, claudePath: String) -> [String: String] {
        let user = base["USER"] ?? NSUserName()
        var env = [
            "HOME": NSHomeDirectory(), "USER": user, "LOGNAME": base["LOGNAME"] ?? user, "TMPDIR": tmp,
            "PATH": fixedPath(claudePath: claudePath),
        ]
        let lang = base["LANG"] ?? "en_US.UTF-8"
        env["LANG"] = lang.allSatisfy({ $0.isLetter || $0.isNumber || "._-@".contains($0) }) ? lang : "en_US.UTF-8"
        return env
    }

    /// The CLI's own folder (npm installs need `node` beside it) plus Homebrew and system folders.
    static func fixedPath(claudePath: String) -> String {
        var dirs = [(claudePath as NSString).deletingLastPathComponent, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                    "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        dirs.removeAll { !seen.insert($0).inserted }
        return dirs.joined(separator: ":")
    }

    static func isSafeModelName(_ model: String) -> Bool {
        (1...100).contains(model.count) && model.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-:[]".contains($0)) }
    }
}

/// A fresh 0700 folder per brain run (cwd, token, MCP config, TMPDIR), removed afterwards.
struct RunFolder {
    let path: String

    static func create(in parent: String, runId: String) throws -> RunFolder {
        try PrivateDirectory.ensure(parent)
        let safe = runId.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }.prefix(40)
        let path = parent + "/run-" + (safe.isEmpty ? Identifier.make() : String(safe)) + "-" + String(Identifier.make().suffix(6))
        guard mkdir(path, 0o700) == 0 else { throw BridgeError.system("mkdir", errno) }
        try PrivateDirectory.verify(path)
        guard mkdir(path + "/tmp", 0o700) == 0 else { throw BridgeError.system("mkdir", errno) }
        return RunFolder(path: path)
    }

    func remove() { try? FileManager.default.removeItem(atPath: path) }
}
