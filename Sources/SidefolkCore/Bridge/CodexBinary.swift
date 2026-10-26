import Darwin
import Foundation
import Synchronization

/// A `codex` executable Sidefolk is willing to run as a brain (SECURITY.md T7).
public struct CodexInstall: Sendable, Equatable {
    /// As found (e.g. `/usr/local/bin/codex`); shown in Settings.
    public var path: String
    /// "0.160.0".
    public var version: String
    /// Every feature to switch off for the run: all that are on by default, except the few the brain needs.
    public var featuresToDisable: [String]
    /// The catalog bundled with this version (models and the efforts each takes); empty when it can't print it.
    public var models: [ModelOption]

    public init(path: String, version: String, featuresToDisable: [String], models: [ModelOption] = []) {
        self.path = path
        self.version = version
        self.featuresToDisable = featuresToDisable
        self.models = models
    }
}

/// How the user signed in to Codex (`codex login status`).
public enum CodexLogin: Sendable, Equatable {
    /// Their ChatGPT plan: what this provider is for.
    case chatGPT
    /// An OpenAI API key: works, billed to that key.
    case apiKey
    case signedOut
}

/// Finds and vets the Codex CLI the same way as Claude Code (fixed and package-manager locations,
/// then the app's PATH; the binary owned by the user or root and not writable by others), and checks
/// that it has every isolation flag and feature switch the brain relies on, or the brain refuses to run.
public enum CodexBinary {
    /// `codex exec` flags the brain's argv uses; a CLI without any of them is not run (fail closed).
    public static let requiredFlags = [
        "--json", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules", "--sandbox", "--cd",
        "--config", "--disable", "--strict-config", "--model",
    ]

    /// Features that give Codex tools of its own (a shell, file edits, a browser, computer use,
    /// images, sub-agents, hooks, plugins, apps, skills). They must exist in `codex features list`:
    /// if one is renamed, Sidefolk can't be sure it is off.
    public static let mustDisable = [
        "shell_tool", "unified_exec", "apps", "plugins", "browser_use", "browser_use_external", "in_app_browser", "computer_use",
        "image_generation", "multi_agent", "hooks", "skill_search", "view_image", "goals", "tool_suggest",
        "skill_mcp_dependency_install", "sleep_tool", "remote_plugin",
    ]

    /// On-by-default features the brain keeps: `code_mode_host` runs the sandboxed JavaScript newer models
    /// use to call tools (Sidefolk's included); the rest are plumbing (retries, compression, MCP sign-in).
    /// Anything else that is on, including features added by later versions, is switched off.
    public static let kept: Set<String> = [
        "code_mode_host", "auth_elicitation", "tool_call_mcp_elicitation", "enable_request_compression", "unbounded_connection_retries",
        "system_proxy_fallback", "content_item_kinds", "compaction_image_budget", "guardian_reuse_parent_compaction",
    ]

    /// The settings path first (if any), then the usual install locations (npm, Homebrew, the
    /// standalone installer, Volta, Bun, pnpm, nvm), then the folders on the app's PATH.
    public static func candidates(configured: String, home: String, path: String?, nvmVersions: [String] = []) -> [String] {
        var list: [String] = []
        let trimmed = configured.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { list.append((trimmed as NSString).expandingTildeInPath) }
        list += [home + "/.local/bin/codex", home + "/.codex/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                 home + "/.npm-global/bin/codex", home + "/.volta/bin/codex", home + "/.bun/bin/codex", home + "/Library/pnpm/codex"]
        list += nvmVersions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            .map { home + "/.nvm/versions/node/\($0)/bin/codex" }
        list += (path ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }.map { $0 + "/codex" }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    /// The first candidate that passes `CLIBrain.problem(with:)`, in a folder only its owner can change.
    public static func find(configured: String, home: String = NSHomeDirectory(),
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> CLILocation {
        let nvm = (try? FileManager.default.contentsOfDirectory(atPath: home + "/.nvm/versions/node")) ?? []
        var reasons: [String] = []
        for path in candidates(configured: configured, home: home, path: environment["PATH"], nvmVersions: nvm)
        where FileManager.default.fileExists(atPath: path) {
            guard let reason = CLIBrain.problem(with: path) ?? folderProblem(path) else { return .found(path) }
            reasons.append(reason)
        }
        return reasons.first.map(CLILocation.unusable) ?? .notFound
    }

    public static func locate(configured: String, home: String = NSHomeDirectory(),
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> Result<String, UserFacingError> {
        switch find(configured: configured, home: home, environment: environment) {
        case .found(let path): .success(path)
        case .unusable(let reason):
            .failure(UserFacingError("Sidefolk won't run Codex from there: \(reason)",
                                     recovery: "Reinstall Codex or choose another provider in Settings › AI."))
        case .notFound:
            .failure(UserFacingError("I couldn't find Codex on this Mac.",
                                     recovery: "Install it with \(installCommand) (or \(brewCommand)), then run codex login."))
        }
    }

    /// Commands stay out of the sentence, so translations can't change them.
    private static let installCommand = "npm install -g @openai/codex"
    private static let brewCommand = "brew install --cask codex"

    /// For Settings: found, vetted, probed and asked whether it's signed in, plus the models it
    /// lists. Never a prompt.
    public static func status(configured: String, workdir: String,
                              environment: [String: String] = ProcessInfo.processInfo.environment) async -> (CLIStatus, [ModelOption]) {
        switch find(configured: configured, environment: environment) {
        case .notFound: return (.notFound, [])
        case .unusable(let reason): return (.unusable(reason), [])
        case .found(let path):
            try? PrivateDirectory.ensure(workdir)
            let env = CodexBackend.environment(base: environment, tmp: workdir, codexPath: path)
            switch await probe(path, environment: env, cwd: workdir) {
            case .success(let install):
                return (.ready(path: path, version: install.version, login: await loginStatus(path, environment: env, cwd: workdir)),
                        install.models)
            case .failure(let error):
                return (.unusable(error.description), [])
            }
        }
    }

    /// PATH can name any folder: one that other users can write to could swap the binary (or, for
    /// a link, its target).
    static func folderProblem(_ path: String) -> String? {
        let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: path)).map {
            ($0.hasPrefix("/") ? $0 : ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent($0))
        }
        for file in [path, target].compactMap({ $0 }) {
            let folder = (file as NSString).deletingLastPathComponent
            var st = stat()
            guard stat(folder, &st) == 0 else { return String(localized: "\(folder) can't be read") }
            guard st.st_mode & 0o022 == 0 else { return String(localized: "\(folder) can be changed by other users") }
        }
        return nil
    }

    /// Which required flags `codex exec --help` lacks.
    public static func missingFlags(inHelp help: String) -> [String] {
        requiredFlags.filter { !CLIBrain.mentions(help, $0) }
    }

    /// `codex features list`: one feature per line, "name   stage (one or two words)   true|false".
    public static func features(fromList text: String) -> [(name: String, stage: String, enabled: Bool)] {
        text.split(separator: "\n").compactMap { line in
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count >= 3, let last = words.last, last == "true" || last == "false" else { return nil }
            return (words[0], words[1..<(words.count - 1)].joined(separator: " "), last == "true")
        }
    }

    /// What to switch off, and the switches this version lacks (then the brain must not run).
    static func featuresToDisable(fromList text: String) -> (disable: [String], missing: [String]) {
        let listed = features(fromList: text)
        let names = Set(listed.map(\.name))
        let extra = listed.filter { $0.enabled && $0.stage != "removed" && !kept.contains($0.name) && !mustDisable.contains($0.name) }
        return (mustDisable + extra.map(\.name).sorted(), mustDisable.filter { !names.contains($0) })
    }

    /// `codex login status`: exit 0 with "Logged in using ChatGPT" (or "… an API key"), exit 1 "Not logged in".
    public static func login(fromStatus text: String, exitCode: Int32) -> CodexLogin {
        let lower = text.lowercased()
        guard exitCode == 0, lower.contains("logged in"), !lower.contains("not logged in") else { return .signedOut }
        return lower.contains("api key") ? .apiKey : .chatGPT
    }

    private static let cache = Mutex<[CLIBrain.Fingerprint: CodexInstall]>([:])

    /// Runs `--version`, `exec --help`, `features list` and reads the bundled model catalog once per
    /// binary (an update is probed again). Never sends a prompt.
    public static func probe(_ path: String, environment: [String: String], cwd: String) async -> Result<CodexInstall, UserFacingError> {
        if let reason = CLIBrain.problem(with: path) {
            return .failure(UserFacingError("Sidefolk won't run Codex: \(reason)", recovery: "Reinstall Codex or choose another provider."))
        }
        guard let fingerprint = CLIBrain.fingerprint(path) else { return .failure(UserFacingError("Codex couldn't be read.")) }
        if let known = cache.withLock({ $0[fingerprint] }) { return .success(known) }

        guard let versionText = await CLIBrain.outputRetrying(path, ["--version"], environment: environment, cwd: cwd),
              let helpText = await CLIBrain.outputRetrying(path, ["exec", "--help"], environment: environment, cwd: cwd),
              let featureText = await CLIBrain.outputRetrying(path, ["features", "list"], environment: environment, cwd: cwd) else {
            return .failure(UserFacingError("Codex didn't start.", recovery: "Run codex in Terminal to see what's wrong."))
        }
        let features = featuresToDisable(fromList: featureText)
        let missing = missingFlags(inHelp: helpText) + features.missing.map { "feature \($0)" }
        guard missing.isEmpty else {
            Log.shared.warning("brain", "codex CLI lacks isolation switches", ["missing": missing.joined(separator: " ")])
            return .failure(UserFacingError("This version of Codex can't be run safely by Sidefolk.",
                                            recovery: "Update Codex (npm install -g @openai/codex@latest) or choose another provider.",
                                            detail: "missing: \(missing.joined(separator: " "))"))
        }
        // "codex-cli 0.160.0"
        let version = versionText.split(separator: " ").last.map(String.init) ?? versionText
        let install = CodexInstall(path: path, version: version.clipped(40), featuresToDisable: features.disable,
                                   models: await listModels(path, environment: environment, cwd: cwd))
        cache.withLock { $0[fingerprint] = install }
        return .success(install)
    }

    /// The models Codex lists for people to pick (`visibility: list`), from `codex debug models --bundled`,
    /// with the reasoning efforts each takes.
    public static func models(fromCatalog text: String) -> [ModelOption] {
        let models = (try? JSONValue.parse(text))?["models"]?.arrayValue ?? []
        return models.filter { $0.string("visibility") == "list" }.compactMap { model in
            guard let slug = model.string("slug") else { return nil }
            let levels = (model["supported_reasoning_levels"]?.arrayValue ?? []).compactMap { $0.string("effort") }
            return ModelOption(id: slug, efforts: ReasoningEffort.known(levels),
                               defaultEffort: model.string("default_reasoning_level").flatMap(ReasoningEffort.init(rawValue:)))
        }
    }

    /// The catalog bundled with this Codex, read offline; empty when this version can't print it.
    public static func listModels(_ path: String, environment: [String: String], cwd: String) async -> [ModelOption] {
        guard let out = await CLIBrain.run(path, ["debug", "models", "--bundled"], environment: environment, cwd: cwd),
              case .exited(0) = out.status else { return [] }
        return models(fromCatalog: out.text)
    }

    /// Not cached: signing in or out happens in Terminal at any time. Reads only Codex's own status.
    public static func loginStatus(_ path: String, environment: [String: String], cwd: String) async -> CodexLogin {
        guard let out = await CLIBrain.run(path, ["login", "status"], environment: environment, cwd: cwd) else { return .signedOut }
        guard case .exited(let code) = out.status else { return .signedOut }
        // It prints the status on stderr.
        return login(fromStatus: out.text + "\n" + out.errors, exitCode: code)
    }
}
