import Darwin
import Foundation
import Synchronization

public struct ShellResult: Sendable, Equatable {
    /// Exit code; 128 + signal number when the shell was killed by a signal.
    public var exitCode: Int32
    public var timedOut: Bool
    /// Standard output and error together, cut at the limit.
    public var output: String
    public var truncated: Bool
    /// The shell's pid, which is also its process group id (for tests that check nothing was left behind).
    public var pid: Int32
}

public enum ShellError: Error, Sendable, Equatable {
    case couldNotStart(String)
}

/// Runs one `/bin/sh -c` command the way a watcher must (docs/SECURITY.md T9): its own process group,
/// stdin from /dev/null, no inherited descriptors, a fixed environment, a deadline, capped output.
/// Whatever the command started is gone when it returns.
public enum ShellRunner {
    public static let timeout: TimeInterval = 30
    public static let grace: TimeInterval = 2
    public static let outputLimit = 64 * 1024

    static let path = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

    static func environment() -> [String] {
        let user = NSUserName()
        return [
            "PATH=\(path)", "HOME=\(NSHomeDirectory())", "USER=\(user)", "LOGNAME=\(user)", "SHELL=/bin/sh",
            "LANG=en_US.UTF-8", "TERM=dumb", "TMPDIR=\(NSTemporaryDirectory())",
        ]
    }

    public static func run(_ command: String, cwd: String, timeout: TimeInterval = ShellRunner.timeout,
                           grace: TimeInterval = ShellRunner.grace, outputLimit: Int = ShellRunner.outputLimit) async throws -> ShellResult {
        let child = try spawn(command, cwd: cwd)
        let run = Run(pid: child.pid, readFd: child.readFd, limit: outputLimit)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ShellResult, Never>) in
                run.start(timeout: timeout, grace: grace) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            run.terminate()
        }
    }

    // MARK: Spawning

    private static func spawn(_ command: String, cwd: String) throws -> (pid: pid_t, readFd: Int32) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw ShellError.couldNotStart("pipe: \(String(cString: strerror(errno)))") }
        let (readFd, writeFd) = (fds[0], fds[1])
        // Writing to a pipe whose reader is gone must be an error, not a signal that kills us.
        for fd in [readFd, writeFd] {
            _ = fcntl(fd, F_SETNOSIGPIPE, 1)
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        }
        let devNull = open("/dev/null", O_RDONLY | O_CLOEXEC)
        defer {
            close(writeFd)
            if devNull >= 0 { close(devNull) }
        }
        guard devNull >= 0 else {
            close(readFd)
            throw ShellError.couldNotStart("/dev/null: \(String(cString: strerror(errno)))")
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, devNull, 0)
        posix_spawn_file_actions_adddup2(&actions, writeFd, 1)
        posix_spawn_file_actions_adddup2(&actions, writeFd, 2)
        posix_spawn_file_actions_addchdir_np(&actions, cwd)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setpgroup(&attributes, 0)
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))

        let argv = ["/bin/sh", "-c", command].map { strdup($0) } + [nil]
        let envp = environment().map { strdup($0) } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, "/bin/sh", &actions, &attributes, argv, envp)
        guard status == 0 else {
            close(readFd)
            throw ShellError.couldNotStart(String(cString: strerror(status)))
        }
        return (pid, readFd)
    }

    // MARK: One running command

    private final class Run: Sendable {
        struct State {
            var output = Data()
            var truncated = false
            var timedOut = false
            var exited = false
            var reaped = false
            var exitCode: Int32 = 0
        }

        let pid: pid_t
        let readFd: Int32
        let limit: Int
        let state = Mutex(State())

        init(pid: pid_t, readFd: Int32, limit: Int) {
            self.pid = pid
            self.readFd = readFd
            self.limit = limit
        }

        func start(timeout: TimeInterval, grace: TimeInterval, finish: @escaping @Sendable (ShellResult) -> Void) {
            let group = DispatchGroup()
            let queue = DispatchQueue.global(qos: .utility)

            queue.async(group: group) { self.read() }
            queue.async(group: group) { self.wait() }

            queue.asyncAfter(deadline: .now() + timeout) { [self] in
                let alive = state.withLock { s -> Bool in
                    guard !s.exited else { return false }
                    s.timedOut = true
                    return true
                }
                guard alive else { return }
                killpg(pid, SIGTERM)
                queue.asyncAfter(deadline: .now() + grace) { [self] in
                    // Still running after the grace period: the shell has not been reaped, so the pid is still ours.
                    if !state.withLock({ $0.exited }) { killpg(pid, SIGKILL) }
                }
            }

            group.notify(queue: queue) { [self] in
                close(readFd)
                let s = state.withLock { $0 }
                finish(ShellResult(exitCode: s.exitCode, timedOut: s.timedOut, output: String(decoding: s.output, as: UTF8.self),
                                   truncated: s.truncated, pid: pid))
            }
        }

        /// Stops the command (the caller gave up). Safe to call at any time.
        func terminate() {
            let alive = state.withLock { s -> Bool in
                guard !s.exited else { return false }
                s.timedOut = true
                return true
            }
            if alive { killpg(pid, SIGKILL) }
        }

        private func wait() {
            var info = siginfo_t()
            while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) != 0, errno == EINTR {}
            let code: Int32 = info.si_code == CLD_EXITED ? info.si_status : 128 + info.si_status
            state.withLock { s in
                s.exited = true
                s.exitCode = code
            }
            // The shell is gone but not yet reaped, so its pid (and process group) cannot be reused:
            // anything it left behind in the group goes too, which also closes the output pipe.
            killpg(pid, SIGKILL)
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0, errno == EINTR {}
        }

        private func read() {
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                var p = pollfd(fd: readFd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&p, 1, 200)
                if ready < 0 {
                    if errno == EINTR { continue }
                    return
                }
                if ready == 0 {
                    // Nothing more is coming once the shell is gone, even if something outside the group holds the pipe.
                    if state.withLock({ $0.exited }) { return }
                    continue
                }
                let n = Darwin.read(readFd, &buffer, buffer.count)
                if n > 0 {
                    state.withLock { s in
                        let room = limit - s.output.count
                        if n > room { s.truncated = true }
                        if room > 0 { s.output.append(contentsOf: buffer.prefix(min(n, room))) }
                    }
                } else if n == 0 {
                    return
                } else if errno != EINTR, errno != EAGAIN {
                    return
                }
            }
        }
    }
}
