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

    public init(restricted: Bool, settingSources: Bool, systemPromptFile: Bool) {
        self.restricted = restricted
        self.settingSources = settingSources
        self.systemPromptFile = systemPromptFile
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

    /// The first candidate that passes `problem(with:)`.
    public static func locate(configured: String, home: String = NSHomeDirectory()) -> Result<String, UserFacingError> {
        let list = candidates(configured: configured, home: home)
        var reasons: [String] = []
        for path in list {
            guard let reason = problem(with: path) else { return .success(path) }
            if FileManager.default.fileExists(atPath: path) { reasons.append(reason) }
        }
        if let reason = reasons.first {
            return .failure(UserFacingError("Sidefolk won't run Claude Code from there: \(reason)",
                                            recovery: "Reinstall Claude Code or choose another provider in Settings › AI."))
        }
        return .failure(UserFacingError("I couldn't find Claude Code on this Mac.",
                                        recovery: "Install it, or set its path in Settings › AI."))
    }

    /// Why this path must not be run, or nil if it may be.
    public static func problem(with path: String) -> String? {
        guard path.hasPrefix("/") else { return "the path must be absolute" }
        var linkInfo = stat()
        guard lstat(path, &linkInfo) == 0 else { return "\(path) doesn't exist" }
        if linkInfo.st_mode & S_IFMT == S_IFLNK, linkInfo.st_uid != getuid(), linkInfo.st_uid != 0 {
            return "\(path) is a link owned by another user"
        }
        guard let resolved = realpath(path, nil) else { return "\(path) is a broken link" }
        defer { free(resolved) }
        var st = stat()
        guard stat(resolved, &st) == 0, st.st_mode & S_IFMT == S_IFREG else { return "\(path) is not a file" }
        guard st.st_uid == getuid() || st.st_uid == 0 else { return "\(path) belongs to another user" }
        guard st.st_mode & 0o022 == 0 else { return "\(path) can be changed by other users" }
        guard st.st_mode & 0o111 != 0 else { return "\(path) is not executable" }
        return nil
    }

    /// Which required flags the help text lacks, and which optional ones it has.
    public static func flags(fromHelp help: String) -> (missing: [String], flags: ClaudeFlags) {
        let missing = requiredFlags.filter { !mentions(help, $0) }
        let flags = ClaudeFlags(restricted: mentions(help, "--restricted"), settingSources: mentions(help, "--setting-sources"),
                                systemPromptFile: mentions(help, "--system-prompt-file") || help.contains("--system-prompt[-file]"))
        return (missing, flags)
    }

    /// `--tools` but not `--tools-x`: the flag followed by something that can't continue a flag name.
    static func mentions(_ help: String, _ flag: String) -> Bool {
        var search = help[...]
        while let r = search.range(of: flag) {
            let before = r.lowerBound == help.startIndex ? " " : help[help.index(before: r.lowerBound)]
            let after = r.upperBound == help.endIndex ? " " : help[r.upperBound]
            let isFlagChar: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "-" }
            if !isFlagChar(before), !isFlagChar(after) { return true }
            search = help[r.upperBound...]
        }
        return false
    }

    private struct Fingerprint: Hashable {
        var path: String
        var inode: UInt64
        var size: Int64
        var mtime: Int
    }

    private static let cache = Mutex<[Fingerprint: ClaudeInstall]>([:])

    /// Runs `--version` and `--help` once per binary (keyed by inode, size and mtime, so an update
    /// is probed again). Never sends a prompt.
    public static func probe(_ path: String, environment: [String: String], cwd: String) async -> Result<ClaudeInstall, UserFacingError> {
        if let reason = problem(with: path) {
            return .failure(UserFacingError("Sidefolk won't run Claude Code: \(reason)", recovery: "Reinstall Claude Code or choose another provider."))
        }
        guard let fingerprint = fingerprint(path) else { return .failure(UserFacingError("Claude Code couldn't be read.")) }
        if let known = cache.withLock({ $0[fingerprint] }) { return .success(known) }

        guard let versionText = await outputRetrying(path, ["--version"], environment: environment, cwd: cwd),
              let helpText = await outputRetrying(path, ["--help"], environment: environment, cwd: cwd) else {
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

    private static func fingerprint(_ path: String) -> Fingerprint? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Fingerprint(path: path, inode: UInt64(st.st_ino), size: Int64(st.st_size), mtime: st.st_mtimespec.tv_sec)
    }

    /// stdout of a short, prompt-free invocation, or nil if it failed or took over 15 s.
    /// One retry: a cold start (or a busy Mac) can stall a first launch.
    private static func outputRetrying(_ path: String, _ arguments: [String], environment: [String: String], cwd: String) async -> String? {
        if let text = await output(of: path, arguments, environment: environment, cwd: cwd) { return text }
        return await output(of: path, arguments, environment: environment, cwd: cwd)
    }

    private static func output(of path: String, _ arguments: [String], environment: [String: String], cwd: String) async -> String? {
        guard let child = try? PipedChild.spawn(path, arguments: arguments, environment: environment, cwd: cwd) else { return nil }
        child.closeInput()
        // Killing the child is what ends the read loop on timeout.
        let timer = Task {
            try await Task.sleep(for: .seconds(8))
            child.signalGroup(SIGKILL)
        }
        defer { timer.cancel() }
        let reader = DescriptorLineReader(fd: child.output, limit: 1 << 20)
        var lines: [String] = []
        while let item = await reader.next() {
            if case .line(let bytes) = item { lines.append(String(decoding: bytes, as: UTF8.self)) }
        }
        guard case .exited(0) = await child.wait() else { return nil }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
