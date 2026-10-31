import Darwin
import Foundation

/// Owns the single device-wide mute lease. The guardian is a child of Sidefolk, not an extension,
/// so killing an extension's entire process tree cannot kill its recovery process.
actor OutputMuteRouter {
    typealias Failure = @Sendable (String) -> Void
    private var owner: String?
    private var process: OutputMuteProcess?
    private var token: UUID?
    private var failureHandler: Failure?
    private var sequences: [String: Int] = [:]
    private var closed = false
    private let executable: URL?

    init() { executable = Self.helperURL() }
    init(executable: URL?) { self.executable = executable }

    func set(_ enabled: Bool, owner id: String, sequence: Int, failed: @escaping Failure) throws {
        guard !closed else { throw UserFacingError("Sidefolk is stopping.") }
        // Actor messages can arrive out of order after the host awaits. A stale enable must never
        // revive a lease after a newer disable or after the extension has stopped.
        guard sequence > (sequences[id] ?? 0) else { return }
        sequences[id] = sequence
        if !enabled {
            guard owner == id else { return }
            try release()
            return
        }
        if owner == id, let process {
            guard process.healthy else { throw UserFacingError("Waiting for the Mac's sound output to be restored.") }
            failureHandler = failed
            return
        }
        guard owner == nil else { throw UserFacingError("Another extension is using the Mac's sound output.") }
        guard let executable else { throw UserFacingError("Sidefolk's sound helper couldn't be found.") }
        let newToken = UUID()
        let child: OutputMuteProcess
        do {
            child = try OutputMuteProcess.start(executable: executable) { [weak self] in
                Task { await self?.lost(id: id, token: newToken) }
            }
        } catch let uncertain as OutputMuteStartFailure {
            // A timed-out helper may still mute before it notices EOF. Keep ownership until it
            // exits, so a second helper can't race its restoration.
            token = newToken; owner = id; process = uncertain.process; failureHandler = failed
            throw UserFacingError("Sidefolk couldn't confirm audio routing. Check the Mac's mute control, then choose Mac and TV or Mac only.")
        }
        token = newToken
        owner = id
        process = child
        failureHandler = failed
    }

    func release(owner id: String) throws {
        sequences[id] = .max
        guard owner == id else { return }
        try release()
    }

    func releaseAll() throws { closed = true; try release() }

    private func release() throws {
        guard let child = process else { owner = nil; token = nil; failureHandler = nil; return }
        // Keep ownership if restoration doesn't finish: another request must not start a second
        // guardian while the first can still be restoring the same output.
        try child.stop()
        process = nil; owner = nil; token = nil; failureHandler = nil
    }

    private func lost(id: String, token expected: UUID) {
        guard owner == id, token == expected else { return }
        let failed = failureHandler
        if let process {
            do { try process.stop() } catch {
                failed?((error as? UserFacingError)?.message ?? error.localizedDescription)
                return
            }
        }
        process = nil; owner = nil; token = nil; failureHandler = nil
        failed?("The Mac's sound output changed. Check its mute control; sound may now play on both devices.")
    }

    private static func helperURL() -> URL? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let folder = executable.deletingLastPathComponent()
        let bundled = folder.deletingLastPathComponent().appendingPathComponent("Helpers/sidefolk")
        let development = folder.appendingPathComponent("sidefolk")
        return [bundled, development].first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private struct OutputMuteStartFailure: Error {
    let process: OutputMuteProcess
}

private final class OutputMuteProcess: @unchecked Sendable {
    private let process: Process
    private let input: Pipe
    private let output: Pipe
    private let lock = NSLock()
    private var stopping = false
    private var waitingForExit = false
    private let failed: @Sendable () -> Void

    private init(process: Process, input: Pipe, output: Pipe, failed: @escaping @Sendable () -> Void) {
        self.process = process; self.input = input; self.output = output; self.failed = failed
    }

    static func start(executable: URL, failed: @escaping @Sendable () -> Void) throws -> OutputMuteProcess {
        let process = Process(), input = try safePipe(), output = try safePipe()
        process.executableURL = executable
        process.arguments = ["--audio-guardian"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        process.environment = [:]
        try SpawnLock.withLock { try process.run() }
        let lease = OutputMuteProcess(process: process, input: input, output: output, failed: failed)
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
        var bytes = [UInt8](repeating: 0, count: 64)
        let count = poll(&descriptor, 1, 3000) > 0 ? Darwin.read(descriptor.fd, &bytes, bytes.count) : -1
        guard count == 3, String(decoding: bytes.prefix(max(0, count)), as: UTF8.self) == "ok\n" else {
            // Never kill a helper that might already have muted the output: closing the pipe tells
            // it to restore once it finishes starting.
            lease.cancelStartup()
            process.terminationHandler = { [weak lease] _ in lease?.unexpected() }
            if !process.isRunning { lease.unexpected() }
            throw OutputMuteStartFailure(process: lease)
        }
        output.fileHandleForReading.readabilityHandler = { [weak lease] handle in
            let data = handle.availableData
            if data.isEmpty || String(decoding: data, as: UTF8.self).contains("error") { lease?.unexpected() }
        }
        process.terminationHandler = { [weak lease] _ in lease?.unexpected() }
        if !process.isRunning { lease.unexpected() }
        return lease
    }

    private static func safePipe() throws -> Pipe {
        try SpawnLock.withLock {
            let pipe = Pipe()
            guard fcntl(pipe.fileHandleForReading.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0,
                  fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                throw UserFacingError("Sidefolk couldn't prepare its sound helper.")
            }
            return pipe
        }
    }

    private func unexpected() {
        lock.lock(); let report = !stopping || waitingForExit; stopping = true; waitingForExit = false; lock.unlock()
        guard report else { return }
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        failed()
    }

    var healthy: Bool {
        lock.lock(); defer { lock.unlock() }
        return !stopping && process.isRunning
    }

    private func cancelStartup() {
        lock.lock(); stopping = true; waitingForExit = true; lock.unlock()
        try? input.fileHandleForWriting.close()
    }

    func stop() throws {
        lock.lock(); stopping = true; lock.unlock()
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            lock.lock(); waitingForExit = true; lock.unlock()
            if !process.isRunning { unexpected() }
            throw UserFacingError("Waiting for the Mac's sound output to be restored.")
        }
        guard process.terminationReason == .exit, [0, 2].contains(process.terminationStatus) else {
            throw UserFacingError("Sidefolk couldn't confirm that the Mac's sound output was restored. Check the Mac's mute control.")
        }
    }

    deinit {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
    }
}
