import Darwin
import Foundation
import Synchronization

/// Where a subscription CLI is, and whether Sidefolk may run it.
public enum CLILocation: Sendable, Equatable {
    case found(String)
    /// It's there, but Sidefolk won't run it: why.
    case unusable(String)
    case notFound
}

/// What Settings › AI shows about a subscription CLI, read without a prompt.
public enum CLIStatus: Sendable, Hashable {
    /// `login` is nil when Sidefolk can't ask (Claude Code checks its login when it runs).
    case ready(path: String, version: String, login: CodexLogin?)
    /// It's there, but Sidefolk won't run it: why, and what to do.
    case unusable(String)
    case notFound
}

/// What the subscription CLI brains (Claude Code, Codex) share (SECURITY.md T7): which executables
/// may run, the prompt-free probe, the allow-listed environment, and how a conversation becomes one
/// prompt.
enum CLIBrain {
    // MARK: Executables

    /// Why this path must not be run, or nil if it may be: absolute, a regular file (links resolved)
    /// owned by the user or root, executable, and not writable by anyone else.
    static func problem(with path: String) -> String? {
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

    struct Fingerprint: Hashable {
        var path: String
        var inode: UInt64
        var size: Int64
        var mtime: Int
    }

    /// Changes when the binary is updated in place, so a cached probe is redone.
    static func fingerprint(_ path: String) -> Fingerprint? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Fingerprint(path: path, inode: UInt64(st.st_ino), size: Int64(st.st_size), mtime: st.st_mtimespec.tv_sec)
    }

    struct Output {
        var status: ChildExit
        var text: String
        /// The last few KB of stderr, where some CLIs print status (`codex login status`).
        var errors: String
    }

    /// stdout of a short, prompt-free invocation (`--version`, `--help`), or nil if it didn't exit 0
    /// within 8 s. One retry: a cold start (or a busy Mac) can stall a first launch.
    static func outputRetrying(_ path: String, _ arguments: [String], environment: [String: String], cwd: String) async -> String? {
        for _ in 0..<2 {
            if let out = await run(path, arguments, environment: environment, cwd: cwd), case .exited(0) = out.status { return out.text }
        }
        return nil
    }

    /// stdout and exit status; nil when it couldn't start. Killing the child is what ends the read on timeout.
    static func run(_ path: String, _ arguments: [String], environment: [String: String], cwd: String,
                    timeout: TimeInterval = 8) async -> Output? {
        guard let child = try? PipedChild.spawn(path, arguments: arguments, environment: environment, cwd: cwd) else { return nil }
        child.closeInput()
        let timer = Task {
            try await Task.sleep(for: .seconds(timeout))
            child.signalGroup(SIGKILL)
        }
        defer { timer.cancel() }
        // Codex's model catalog is one JSON line of ~650 KB.
        let reader = DescriptorLineReader(fd: child.output, limit: 4 << 20)
        var lines: [String] = []
        while let item = await reader.next() {
            if case .line(let bytes) = item { lines.append(String(decoding: bytes, as: UTF8.self)) }
        }
        let status = await child.wait()
        return Output(status: status, text: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                      errors: await child.stderr().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Spawning

    /// Allow-listed environment (T7): never DYLD_*, NODE_OPTIONS, ANTHROPIC_* or OPENAI_*.
    static func environment(base: [String: String], tmp: String, cliPath: String) -> [String: String] {
        let user = base["USER"] ?? NSUserName()
        var env = [
            "HOME": NSHomeDirectory(), "USER": user, "LOGNAME": base["LOGNAME"] ?? user, "TMPDIR": tmp,
            "PATH": fixedPath(cliPath: cliPath),
        ]
        let lang = base["LANG"] ?? "en_US.UTF-8"
        env["LANG"] = lang.allSatisfy({ $0.isLetter || $0.isNumber || "._-@".contains($0) }) ? lang : "en_US.UTF-8"
        return env
    }

    /// The CLI's own folder (npm installs need `node` beside it) plus Homebrew and system folders.
    static func fixedPath(cliPath: String) -> String {
        var dirs = [(cliPath as NSString).deletingLastPathComponent, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                    "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        dirs.removeAll { !seen.insert($0).inserted }
        return dirs.joined(separator: ":")
    }

    /// Model names reach argv, so only plain names pass (never something that reads as a flag).
    static func isSafeModelName(_ model: String) -> Bool {
        (1...100).contains(model.count) && model.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-:[]".contains($0)) }
            && !model.hasPrefix("-")
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
}
