import Darwin
import Foundation
import Synchronization

public struct ExtensionProcessSpec: Sendable, Hashable {
    public var executable: String
    public var arguments: [String]
    /// The complete environment; nothing is inherited from Sidefolk.
    public var environment: [String: String]
    public var workingDirectory: String?

    public init(executable: String, arguments: [String], environment: [String: String], workingDirectory: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

/// Resource limits and I/O caps for one extension process (SECURITY T15, T17).
public struct ExtensionProcessLimits: Sendable, Hashable {
    public var maxResidentBytes: UInt64 = 512 * 1024 * 1024
    /// Fraction of one core; sustained above it for `cpuWindow` kills the group.
    public var maxCPUFraction = 0.5
    public var cpuWindow: TimeInterval = 60
    public var sampleInterval: TimeInterval = 5
    /// How often the process tree is walked, so children that leave the group are still known.
    public var treeInterval: TimeInterval = 1
    /// Processes the extension may have running at once, itself included (a fork bomb stops here).
    public var maxProcesses = 32
    public var maxLineBytes = 1024 * 1024
    public var stderrBytes = 16 * 1024
    /// Time between SIGTERM and SIGKILL.
    public var terminateGrace: TimeInterval = 2

    public init() {}
    public static let standard = ExtensionProcessLimits()
}

public enum ExtensionProcessOutput: Sendable, Hashable {
    case line(Data)
    /// A line longer than the cap; its bytes were discarded.
    case oversized
}

public struct ExtensionProcessExit: Sendable, Hashable, CustomStringConvertible {
    public enum Cause: Sendable, Hashable {
        case exited(Int32)
        case signaled(Int32)
    }

    public var cause: Cause
    /// Set when the watchdog killed the group, in plain words.
    public var watchdog: String?
    /// `terminate()` was called: the exit was asked for, not a crash.
    public var requested: Bool

    public var description: String {
        switch cause {
        case .exited(let code): "exited with status \(code)"
        case .signaled(let sig): "killed by signal \(sig)"
        }
    }
}

/// A child process started with `posix_spawn`: its own process group, only fds 0–2 inherited
/// (`POSIX_SPAWN_CLOEXEC_DEFAULT`; an inherited DB or socket fd would bypass the sandbox), default signal
/// handling, an explicit environment, stdout split into capped lines, stderr kept in a small ring for
/// diagnostics, and a `proc_pid_rusage` watchdog over the whole tree (SECURITY T15, MACOS-NOTES §11).
///
/// The process group alone isn't the extension: a child can `setsid()` into a group of its own and
/// would outlive disable, uninstall and quit. So every descendant is tracked by walking parent links
/// once a second (remembered by pid and start time, so a reused pid is never signalled), and stop,
/// exit and the watchdog signal all of them. Residual: a grandchild whose parent exits within the
/// same second it was forked is reparented to launchd before it is seen. It keeps the sandbox, and
/// the profile only allows `fork` to extensions whose install sheet said they run programs.
public final class ExtensionProcess: Sendable {
    private struct State {
        var pid: pid_t = 0
        var started = false
        var exit: ExtensionProcessExit?
        var requested = false
        var watchdog: String?
        var exitWaiters: [CheckedContinuation<ExtensionProcessExit, Never>] = []
        var stdinOpen = true
        var stderr = Data()
        /// Descendants seen so far, with their start times.
        var tree: [pid_t: UInt64] = [:]
    }

    public let spec: ExtensionProcessSpec
    public let limits: ExtensionProcessLimits
    private let state = Mutex(State())
    private let writeQueue = DispatchQueue(label: "app.sidefolk.extension.stdin")
    private let stdinFD: Int32
    private let stdoutFD: Int32
    private let stderrFD: Int32
    private let childFDs: (Int32, Int32, Int32)

    public init(spec: ExtensionProcessSpec, limits: ExtensionProcessLimits = .standard) throws {
        self.spec = spec
        self.limits = limits
        var fds: [Int32] = []
        // Created close-on-exec under the spawn lock, so no other child Sidefolk starts can inherit them.
        for _ in 0..<3 {
            guard let p = SpawnLock.pipe() else {
                for fd in fds { close(fd) }
                throw ExtensionError.spawn("Couldn't create pipes: \(String(cString: strerror(errno)))")
            }
            fds += [p.read, p.write]
        }
        childFDs = (fds[0], fds[3], fds[5])
        stdinFD = fds[1]
        stdoutFD = fds[2]
        stderrFD = fds[4]
        // Writing to a dead child must fail with EPIPE, not kill Sidefolk with SIGPIPE.
        _ = fcntl(stdinFD, F_SETNOSIGPIPE, 1)
    }

    deinit {
        let (a, b, c) = childFDs
        state.withLock { s in
            if !s.started {
                for fd in [a, b, c, stdinFD, stdoutFD, stderrFD] { close(fd) }
            }
        }
    }

    public var pid: pid_t { state.withLock { $0.pid } }
    public var hasExited: Bool { state.withLock { $0.exit != nil } }

    /// The last few KiB the process wrote to stderr (for logs only: it is untrusted).
    public var stderrTail: String {
        String(decoding: state.withLock { $0.stderr }, as: UTF8.self)
    }

    /// Spawns the process. `onOutput` runs on a reader thread, in order; `onExit` runs once, after the
    /// last output line was delivered.
    public func start(onOutput: @escaping @Sendable (ExtensionProcessOutput) -> Void,
                      onExit: @escaping @Sendable (ExtensionProcessExit) -> Void) throws {
        let pid = try spawn()
        state.withLock {
            $0.pid = pid
            $0.started = true
        }
        let (a, b, c) = childFDs
        close(a); close(b); close(c)

        let stdoutDone = DispatchSemaphore(value: 0)
        let stderrDone = DispatchSemaphore(value: 0)
        let maxLine = limits.maxLineBytes
        let outFD = stdoutFD
        Thread.detachNewThread {
            var splitter = ExtensionLineSplitter(maxLine: maxLine)
            Self.readLoop(outFD) { chunk in for event in splitter.feed(chunk) { onOutput(event) } }
            if let last = splitter.finish() { onOutput(last) }
            close(outFD)
            stdoutDone.signal()
        }
        let errFD = stderrFD
        let cap = limits.stderrBytes
        Thread.detachNewThread { [self] in
            Self.readLoop(errFD) { chunk in
                self.state.withLock { s in
                    s.stderr.append(contentsOf: chunk)
                    if s.stderr.count > cap { s.stderr.removeFirst(s.stderr.count - cap) }
                }
            }
            close(errFD)
            stderrDone.signal()
        }
        Thread.detachNewThread { [self] in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1, errno == EINTR {}
            // Anything the extension left behind, in its group or not, goes with it.
            _ = Darwin.kill(-pid, SIGKILL)
            signalTree(SIGKILL, refresh: false)
            _ = stdoutDone.wait(timeout: .now() + 2)
            _ = stderrDone.wait(timeout: .now() + 2)
            let signal = status & 0x7F
            let cause: ExtensionProcessExit.Cause = signal == 0 ? .exited((status >> 8) & 0xFF) : .signaled(signal)
            let (exit, waiters) = state.withLock { s -> (ExtensionProcessExit, [CheckedContinuation<ExtensionProcessExit, Never>]) in
                let e = ExtensionProcessExit(cause: cause, watchdog: s.watchdog, requested: s.requested)
                s.exit = e
                let w = s.exitWaiters
                s.exitWaiters = []
                return (e, w)
            }
            writeQueue.async { [self] in closeStdin() }
            for w in waiters { w.resume(returning: exit) }
            onExit(exit)
        }
        startWatchdog(pid: pid)
    }

    private func spawn() throws -> pid_t {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attr, Int16(flags))
        posix_spawnattr_setpgroup(&attr, 0)
        var all = sigset_t()
        sigfillset(&all)
        posix_spawnattr_setsigdefault(&attr, &all)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attr, &none)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        let (a, b, c) = childFDs
        posix_spawn_file_actions_adddup2(&actions, a, 0)
        posix_spawn_file_actions_adddup2(&actions, b, 1)
        posix_spawn_file_actions_adddup2(&actions, c, 2)
        if let dir = spec.workingDirectory {
            if #available(macOS 26, *) {
                posix_spawn_file_actions_addchdir(&actions, dir)
            } else {
                posix_spawn_file_actions_addchdir_np(&actions, dir)
            }
        }

        let argv = [spec.executable] + spec.arguments
        let envp = spec.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let rc = Self.withCStrings(argv) { argvPtr in
            Self.withCStrings(envp) { envPtr in
                SpawnLock.spawn { posix_spawn(&pid, spec.executable, &actions, &attr, argvPtr, envPtr) }
            }
        }
        guard rc == 0 else { throw ExtensionError.spawn("Couldn't start \(spec.executable): \(String(cString: strerror(rc)))") }
        return pid
    }

    private static func withCStrings<R>(_ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
        pointers.append(nil)
        defer { for p in pointers { free(p) } }
        return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
    }

    private static func readLoop(_ fd: Int32, _ deliver: (ArraySlice<UInt8>) -> Void) {
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                deliver(buffer[0..<n])
            } else if n < 0, errno == EINTR {
                continue
            } else {
                return
            }
        }
    }

    /// Writes bytes to stdin. Throws when the process is gone.
    public func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            writeQueue.async { [self] in
                guard state.withLock({ $0.stdinOpen }) else {
                    c.resume(throwing: ExtensionError.io("The extension isn't running."))
                    return
                }
                var offset = 0
                let ok = data.withUnsafeBytes { raw -> Bool in
                    while offset < raw.count {
                        let n = Darwin.write(stdinFD, raw.baseAddress! + offset, raw.count - offset)
                        if n < 0 { if errno == EINTR { continue }; return false }
                        offset += n
                    }
                    return true
                }
                if ok { c.resume() } else { c.resume(throwing: ExtensionError.io("The extension stopped reading its input.")) }
            }
        }
    }

    /// Must run on `writeQueue`, so a close never races a write onto a reused descriptor.
    private func closeStdin() {
        let wasOpen = state.withLock { s -> Bool in
            defer { s.stdinOpen = false }
            return s.stdinOpen
        }
        if wasOpen { close(stdinFD) }
    }

    /// Closes stdin and sends SIGTERM to the group, then SIGKILL after the grace period. Returns once exited.
    @discardableResult
    public func terminate() async -> ExtensionProcessExit {
        let (pid, started) = state.withLock { s -> (pid_t, Bool) in
            s.requested = true
            return (s.pid, s.started)
        }
        guard started else { return ExtensionProcessExit(cause: .exited(0), watchdog: nil, requested: true) }
        writeQueue.async { [self] in closeStdin() }
        // Walk the tree while the root is still alive: once it exits, its children belong to launchd.
        if !hasExited {
            _ = Darwin.kill(-pid, SIGTERM)
            signalTree(SIGTERM, refresh: true)
        }
        let grace = limits.terminateGrace
        let killer = Task { [self] in
            try await Task.sleep(for: .seconds(grace))
            _ = Darwin.kill(-pid, SIGKILL)
            signalTree(SIGKILL, refresh: true)
        }
        let exit = await waitForExit()
        killer.cancel()
        signalTree(SIGKILL, refresh: false)
        return exit
    }

    /// Descendants of the extension that are still alive (for tests and diagnostics).
    public var descendants: [pid_t] {
        state.withLock { $0.tree }.filter { ProcessTree.startTime($0.key) == $0.value }.map(\.key).sorted()
    }

    /// Records every process below the root (and in its group) that is alive now.
    @discardableResult
    func refreshTree() -> Int {
        let root = pid
        guard root > 0 else { return 0 }
        let found = ProcessTree.descendants(of: root)
        return state.withLock { s in
            s.tree = s.tree.filter { ProcessTree.startTime($0.key) == $0.value }
            for (p, start) in found { s.tree[p] = start }
            return s.tree.count
        }
    }

    /// Signals every known descendant whose pid still belongs to the same process.
    private func signalTree(_ signal: Int32, refresh: Bool) {
        if refresh { refreshTree() }
        for (p, start) in state.withLock({ $0.tree }) where ProcessTree.startTime(p) == start {
            _ = Darwin.kill(p, signal)
        }
    }

    public func waitForExit() async -> ExtensionProcessExit {
        await withCheckedContinuation { c in
            let done = state.withLock { s -> ExtensionProcessExit? in
                if let e = s.exit { return e }
                s.exitWaiters.append(c)
                return nil
            }
            if let done { c.resume(returning: done) }
        }
    }

    /// Kills the whole tree for exceeding a limit; the exit carries the reason.
    func killGroup(reason: String) {
        let pid = state.withLock { s -> pid_t in
            if s.watchdog == nil { s.watchdog = reason }
            return s.pid
        }
        signalTree(SIGKILL, refresh: true)
        _ = Darwin.kill(-pid, SIGKILL)
    }

    // MARK: Watchdog

    private func startWatchdog(pid: pid_t) {
        let limits = self.limits
        Task.detached { [weak self] in
            var lastCPU: UInt64?
            var lastAt = ContinuousClock.now
            var hotSince: ContinuousClock.Instant?
            var nextSample = ContinuousClock.now + .seconds(limits.sampleInterval)
            while let process = self, !process.hasExited {
                try? await Task.sleep(for: .seconds(min(limits.treeInterval, limits.sampleInterval)))
                guard !process.hasExited else { return }
                if process.refreshTree() + 1 > limits.maxProcesses {
                    process.killGroup(reason: String(localized: "It started more than \(limits.maxProcesses) processes."))
                    return
                }
                guard ContinuousClock.now >= nextSample else { continue }
                nextSample = ContinuousClock.now + .seconds(limits.sampleInterval)
                let usage = ProcessGroupUsage.sample(pids: [pid] + process.descendants)
                if usage.residentBytes > limits.maxResidentBytes {
                    process.killGroup(reason: String(localized: "It used more than \(limits.maxResidentBytes / 1_048_576) MB of memory."))
                    return
                }
                let now = ContinuousClock.now
                if let last = lastCPU {
                    let wall = Double((now - lastAt).components.seconds) + Double((now - lastAt).components.attoseconds) / 1e18
                    let cpu = Double(usage.cpuNanoseconds &- min(last, usage.cpuNanoseconds)) / 1e9
                    if wall > 0, cpu / wall > limits.maxCPUFraction {
                        let since = hotSince ?? lastAt
                        hotSince = since
                        if now - since >= .seconds(limits.cpuWindow) {
                            process.killGroup(reason: String(localized: "It kept using more than half a CPU core for a minute."))
                            return
                        }
                    } else {
                        hotSince = nil
                    }
                }
                lastCPU = usage.cpuNanoseconds
                lastAt = now
            }
        }
    }
}

/// Walking an extension's processes: its group, and everything below it by parent links.
enum ProcessTree {
    /// When `pid` started (µs since 1970), or nil when it is gone. Pid and start time together name
    /// one process; a pid alone may have been reused.
    static func startTime(_ pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }

    static func children(of pid: pid_t) -> [pid_t] {
        list { proc_listchildpids(pid, $0, $1) }
    }

    static func group(_ pgid: pid_t) -> [pid_t] {
        list { proc_listpgrppids(pgid, $0, $1) }
    }

    private static func list(_ call: (UnsafeMutableRawPointer, Int32) -> Int32) -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 512)
        let count = pids.withUnsafeMutableBytes { call($0.baseAddress!, Int32($0.count)) }
        return Array(pids.prefix(max(0, min(Int(count), pids.count)))).filter { $0 > 0 }
    }

    /// Every live process below `root` or in its group (the root itself excluded), with start times.
    static func descendants(of root: pid_t, limit: Int = 4096) -> [pid_t: UInt64] {
        var found: [pid_t: UInt64] = [:]
        var queue = children(of: root) + group(root)
        while let pid = queue.popLast(), found.count < limit {
            guard pid != root, found[pid] == nil, let start = startTime(pid) else { continue }
            found[pid] = start
            queue += children(of: pid)
        }
        return found
    }
}

/// Memory and CPU time of a set of processes.
enum ProcessGroupUsage {
    struct Sample {
        var residentBytes: UInt64
        var cpuNanoseconds: UInt64
    }

    private static let timebase: (UInt64, UInt64) = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    static func sample(pids members: [pid_t]) -> Sample {
        var rss: UInt64 = 0
        var ticks: UInt64 = 0
        for pid in Set(members) {
            var info = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &info) { p in
                p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard rc == 0 else { continue }
            rss += info.ri_resident_size
            ticks += info.ri_user_time + info.ri_system_time
        }
        // rusage CPU times are Mach absolute-time units on Apple silicon.
        return Sample(residentBytes: rss, cpuNanoseconds: ticks * timebase.0 / timebase.1)
    }
}

/// Splits a byte stream into lines of at most `maxLine` bytes; longer lines are reported, not kept.
struct ExtensionLineSplitter {
    let maxLine: Int
    private var buffer = Data()
    private var discarding = false

    init(maxLine: Int) { self.maxLine = maxLine }

    mutating func feed(_ chunk: ArraySlice<UInt8>) -> [ExtensionProcessOutput] {
        var out: [ExtensionProcessOutput] = []
        var rest = chunk
        while let nl = rest.firstIndex(of: 0x0A) {
            let piece = rest[rest.startIndex..<nl]
            if discarding || buffer.count + piece.count > maxLine {
                if !discarding { out.append(.oversized) }
                discarding = false
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.append(contentsOf: piece)
                if buffer.last == 0x0D { buffer.removeLast() }
                if !buffer.isEmpty { out.append(.line(buffer)) }
                buffer = Data()
            }
            rest = rest[(nl + 1)...]
        }
        if !rest.isEmpty, !discarding {
            if buffer.count + rest.count > maxLine {
                out.append(.oversized)
                discarding = true
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.append(contentsOf: rest)
            }
        }
        return out
    }

    /// The final unterminated line, if any.
    mutating func finish() -> ExtensionProcessOutput? {
        defer { buffer = Data() }
        return discarding || buffer.isEmpty ? nil : .line(buffer)
    }
}
