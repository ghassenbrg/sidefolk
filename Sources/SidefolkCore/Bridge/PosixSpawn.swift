import Darwin
import Foundation

/// `posix_spawn` with the hygiene SECURITY.md asks for. Foundation's `Process` can neither start a
/// new process group nor close inherited descriptors (MACOS-NOTES §11).
enum PosixSpawn {
    struct Options {
        /// Put the child in its own process group so the whole tree can be signalled.
        var newProcessGroup = false
        /// Only fds 0–2 (as set by `stdio`) reach the child.
        var closeOtherDescriptors = false
        /// Child fds 0, 1, 2 come from these descriptors; nil keeps ours.
        var stdio: (Int32, Int32, Int32)?
        var cwd: String?
        /// Signals reset to their default action in the child (we may be ignoring them).
        var defaultSignals: [Int32] = [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGPIPE, SIGCHLD]
    }

    /// - Parameters:
    ///   - searchPath: look the executable up in PATH (`posix_spawnp`).
    ///   - environment: nil inherits ours.
    static func run(_ executable: String, arguments: [String], environment: [String: String]?, searchPath: Bool,
                    options: Options) throws -> pid_t {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        var flags = Int32(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        if options.newProcessGroup {
            flags |= Int32(POSIX_SPAWN_SETPGROUP)
            posix_spawnattr_setpgroup(&attr, 0)
        }
        if options.closeOtherDescriptors { flags |= Int32(POSIX_SPAWN_CLOEXEC_DEFAULT) }
        posix_spawnattr_setflags(&attr, Int16(flags))
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for s in options.defaultSignals { sigaddset(&defaults, s) }
        posix_spawnattr_setsigdefault(&attr, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attr, &mask)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if let (input, output, error) = options.stdio {
            posix_spawn_file_actions_adddup2(&actions, input, 0)
            posix_spawn_file_actions_adddup2(&actions, output, 1)
            posix_spawn_file_actions_adddup2(&actions, error, 2)
        } else if options.closeOtherDescriptors {
            for fd: Int32 in 0...2 { posix_spawn_file_actions_addinherit_np(&actions, fd) }
        }
        if let cwd = options.cwd {
            if #available(macOS 26, *) {
                posix_spawn_file_actions_addchdir(&actions, cwd)
            } else {
                posix_spawn_file_actions_addchdir_np(&actions, cwd)
            }
        }

        // strdup'd C strings, NULL-terminated, freed after the call.
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        let env = environment ?? ProcessInfo.processInfo.environment
        var envp: [UnsafeMutablePointer<CChar>?] = env.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let rc = SpawnLock.spawn {
            searchPath ? posix_spawnp(&pid, executable, &actions, &attr, argv, envp)
                : posix_spawn(&pid, executable, &actions, &attr, argv, envp)
        }
        guard rc == 0 else { throw PosixSpawnError(executable: executable, code: rc) }
        return pid
    }

    /// Blocks until `pid` ends (stops are ignored).
    static func wait(_ pid: pid_t) -> ChildExit {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 {
            if errno != EINTR { return .exited(127) }
        }
        return ChildExit(status: status)
    }

    /// Waits on a dedicated thread so Swift's cooperative pool is never blocked.
    static func waitAsync(_ pid: pid_t) async -> ChildExit {
        await withCheckedContinuation { c in
            Thread.detachNewThread { c.resume(returning: wait(pid)) }
        }
    }
}

struct PosixSpawnError: Error, CustomStringConvertible {
    var executable: String
    var code: Int32
    var description: String { "\(executable): \(String(cString: strerror(code)))" }
}

/// How a child process ended.
public enum ChildExit: Sendable, Equatable {
    case exited(Int32)
    case signaled(Int32)

    init(status: Int32) {
        let low = status & 0x7f
        self = low == 0 ? .exited((status >> 8) & 0xff) : .signaled(low)
    }

    /// The status a shell reports: the exit code, or 128 + signal.
    public var shellStatus: Int32 {
        switch self {
        case .exited(let code): code
        case .signaled(let signal): 128 + signal
        }
    }
}
