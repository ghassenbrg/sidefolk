import Darwin
import Foundation
import Synchronization

/// A `claude` executable Sidefolk is willing to run as a brain, and what its CLI supports.
public struct ClaudeInstall: Sendable, Equatable {
    /// As found (e.g. `~/.local/bin/claude`); shown in Settings.
    public var path: String
    public var version: String
    public var flags: ClaudeFlags
}

/// Optional isolation flags; at least one way to ignore user and project settings must exist.
public struct ClaudeFlags: Sendable, Equatable {
    public var restricted: Bool
    public var settingSources: Bool
    /// Hidden in `--help` but named there as `--system-prompt[-file]`; keeps the prompt out of argv.
    public var systemPromptFile: Bool
    /// The levels `--effort` takes, as `--help` lists them; empty when this CLI has no such flag (D36).
    public var efforts: [ReasoningEffort]

    public init(restricted: Bool, settingSources: Bool, systemPromptFile: Bool, efforts: [ReasoningEffort] = []) {
        self.restricted = restricted
        self.settingSources = settingSources
        self.systemPromptFile = systemPromptFile
        self.efforts = efforts
    }
}

/// Finds and vets the Claude Code CLI (SECURITY.md T7): fixed locations only, owned by the user
/// or root and not writable by others, and its `--help` must list every isolation flag Sidefolk
/// relies on, or the brain refuses to run.
public enum ClaudeBinary {
    /// Flags the brain's argv uses; a CLI without any of them is not run (fail closed).
    public static let requiredFlags = [
        "--print", "--tools", "--strict-mcp-config", "--mcp-config", "--disable-slash-commands", "--no-session-persistence",
        "--permission-prompts", "--input-format", "--output-format", "--verbose", "--allowedTools", "--model",
    ]

    /// The settings path first (if any), then the fixed install locations. Never $PATH.
    public static func candidates(configured: String, home: String) -> [String] {
        var list: [String] = []
        let trimmed = configured.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { list.append((trimmed as NSString).expandingTildeInPath) }
        list += [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return list
    }

    /// The first candidate that passes `CLIBrain.problem(with:)`.
    public static func find(configured: String, home: String = NSHomeDirectory()) -> CLILocation {
        var reasons: [String] = []
        for path in candidates(configured: configured, home: home) {
            guard let reason = CLIBrain.problem(with: path) else { return .found(path) }
            if FileManager.default.fileExists(atPath: path) { reasons.append(reason) }
        }
        return reasons.first.map(CLILocation.unusable) ?? .notFound
    }

    /// For Settings: found, vetted and probed (`--version`, `--help`), never a prompt; with the
    /// efforts its `--effort` takes.
    public static func status(configured: String, workdir: String,
                              environment: [String: String] = ProcessInfo.processInfo.environment) async -> (CLIStatus, [ReasoningEffort]) {
        switch find(configured: configured) {
        case .notFound: return (.notFound, [])
        case .unusable(let reason): return (.unusable(reason), [])
        case .found(let path):
            try? PrivateDirectory.ensure(workdir)
            let env = CLIBrain.environment(base: environment, tmp: workdir, cliPath: path)
            switch await probe(path, environment: env, cwd: workdir) {
            case .success(let install): return (.ready(path: path, version: install.version, login: nil), install.flags.efforts)
            case .failure(let error): return (.unusable(error.description), [])
            }
        }
    }

    public static func locate(configured: String, home: String = NSHomeDirectory()) -> Result<String, UserFacingError> {
        switch find(configured: configured, home: home) {
        case .found(let path): .success(path)
        case .unusable(let reason):
            .failure(UserFacingError("Sidefolk won't run Claude Code from there: \(reason)",
                                     recovery: "Reinstall Claude Code or choose another provider in Settings › AI."))
        case .notFound:
            .failure(UserFacingError("I couldn't find Claude Code on this Mac.", recovery: "Install it, or set its path in Settings › AI."))
        }
    }

    /// Which required flags the help text lacks, and which optional ones it has.
    public static func flags(fromHelp help: String) -> (missing: [String], flags: ClaudeFlags) {
        let missing = requiredFlags.filter { !CLIBrain.mentions(help, $0) }
        let flags = ClaudeFlags(restricted: CLIBrain.mentions(help, "--restricted"),
                                settingSources: CLIBrain.mentions(help, "--setting-sources"),
                                systemPromptFile: CLIBrain.mentions(help, "--system-prompt-file") || help.contains("--system-prompt[-file]"),
                                efforts: efforts(fromHelp: help))
        return (missing, flags)
    }

    /// "--effort <level>  Effort level for the current session (low, medium, high, xhigh, max)": the
    /// list in the first parentheses of the flag's entry. A flag without a readable list offers nothing.
    static func efforts(fromHelp help: String) -> [ReasoningEffort] {
        guard let flag = help.range(of: "--effort ") else { return [] }
        let entry = help[flag.upperBound...].prefix(300)
        // The entry ends where the next flag's line starts.
        let own = entry.range(of: #"\n\s*--"#, options: .regularExpression).map { entry[..<$0.lowerBound] } ?? entry
        guard let open = own.firstIndex(of: "("), let close = own[open...].firstIndex(of: ")") else { return [] }
        return ReasoningEffort.known(own[own.index(after: open)..<close].split(separator: ",").map(String.init))
    }

    private static let cache = Mutex<[CLIBrain.Fingerprint: ClaudeInstall]>([:])

    /// Runs `--version` and `--help` once per binary (keyed by inode, size and mtime, so an update
    /// is probed again). Never sends a prompt.
    public static func probe(_ path: String, environment: [String: String], cwd: String) async -> Result<ClaudeInstall, UserFacingError> {
        if let reason = CLIBrain.problem(with: path) {
            return .failure(UserFacingError("Sidefolk won't run Claude Code: \(reason)", recovery: "Reinstall Claude Code or choose another provider."))
        }
        guard let fingerprint = CLIBrain.fingerprint(path) else { return .failure(UserFacingError("Claude Code couldn't be read.")) }
        if let known = cache.withLock({ $0[fingerprint] }) { return .success(known) }

        guard let versionText = await CLIBrain.outputRetrying(path, ["--version"], environment: environment, cwd: cwd),
              let helpText = await CLIBrain.outputRetrying(path, ["--help"], environment: environment, cwd: cwd) else {
            return .failure(UserFacingError("Claude Code didn't start.", recovery: "Run claude in Terminal to see what's wrong."))
        }
        let (missing, flags) = self.flags(fromHelp: helpText)
        guard missing.isEmpty, flags.restricted || flags.settingSources else {
            let absent = missing + (flags.restricted || flags.settingSources ? [] : ["--restricted or --setting-sources"])
            Log.shared.warning("brain", "claude CLI lacks isolation flags", ["missing": absent.joined(separator: " ")])
            return .failure(UserFacingError("This version of Claude Code can't be run safely by Sidefolk.",
                                            recovery: "Update Claude Code (claude update) or choose another provider.",
                                            detail: "missing: \(absent.joined(separator: " "))"))
        }
        let version = versionText.split(separator: " ").first.map(String.init) ?? versionText
        let install = ClaudeInstall(path: path, version: version.clipped(40), flags: flags)
        cache.withLock { $0[fingerprint] = install }
        return .success(install)
    }
}
