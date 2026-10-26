import Darwin
import Foundation
import Synchronization

/// Passes a `sidefolk run` command's stderr through to ours while keeping the last few kilobytes, so a
/// failure notice can say what went wrong instead of only the exit code. When our stderr is a terminal
/// the command gets a pseudo-terminal with the same settings and size, so it still sees a terminal there
/// (colours, progress bars); otherwise a pipe. Stdin and stdout stay the caller's own (T4).
final class StderrTee: @unchecked Sendable {
    /// What to give the command as its fd 2.
    let childEnd: Int32
    private let readEnd: Int32
    private let output: Int32
    private let isTerminal: Bool
    private let tail = Mutex(Data())
    private let drained = DispatchSemaphore(value: 0)
    private var resize: (any DispatchSourceSignal)?

    static let keep = 8_192

    /// - Parameter terminal: force the pseudo-terminal (tests); by default it follows `isatty(output)`.
    static func make(output: Int32 = STDERR_FILENO, terminal: Bool? = nil) -> StderrTee? {
        let tty = terminal ?? (isatty(output) != 0)
        let ends: (read: Int32, write: Int32)? = tty ? openTerminal(like: output) : SpawnLock.pipe()
        guard let ends else { return nil }
        return StderrTee(read: ends.read, write: ends.write, output: output, terminal: tty)
    }

    private init(read: Int32, write: Int32, output: Int32, terminal: Bool) {
        readEnd = read
        childEnd = write
        self.output = output
        isTerminal = terminal
        // Our stderr may be a pipe whose reader went away; that must not kill us before the command ends.
        // The command itself gets SIGPIPE's default back when it is spawned.
        signal(SIGPIPE, SIG_IGN)
        Thread.detachNewThread { [self] in pump() }
        if terminal { followWindowSize() }
    }

    /// Call once the command is running: only the command may hold the write end now, so the
    /// reader sees end-of-file when it (and anything it left running) is done with stderr.
    func childStarted() {
        close(childEnd)
    }

    /// Waits a moment for the last output (something the command started may still hold stderr open)
    /// and returns everything kept.
    func finish(within seconds: Double = 0.5) -> String {
        _ = drained.wait(timeout: .now() + seconds)
        resize?.cancel()
        return tail.withLock { String(decoding: $0, as: UTF8.self) }
    }

    private func pump() {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        var forwarding = true
        while true {
            let n = read(readEnd, &buffer, buffer.count)
            if n < 0, errno == EINTR { continue }
            // A pseudo-terminal reports EIO, a pipe 0, once nothing holds the other end.
            guard n > 0 else { break }
            if forwarding { forwarding = Self.writeAll(output, buffer, count: n) }
            tail.withLock { kept in
                kept.append(contentsOf: buffer[0..<n])
                if kept.count > Self.keep { kept.removeFirst(kept.count - Self.keep) }
            }
        }
        close(readEnd)
        drained.signal()
    }

    private static func writeAll(_ fd: Int32, _ buffer: [UInt8], count: Int) -> Bool {
        var done = 0
        while done < count {
            let n = buffer.withUnsafeBytes { write(fd, $0.baseAddress! + done, count - done) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return false }
            done += n
        }
        return true
    }

    private static func openTerminal(like fd: Int32) -> (read: Int32, write: Int32)? {
        SpawnLock.withLock {
            var settings = termios()
            var size = winsize()
            let hasSettings = tcgetattr(fd, &settings) == 0
            let hasSize = ioctl(fd, TIOCGWINSZ, &size) == 0
            var primary: Int32 = -1
            var secondary: Int32 = -1
            let rc = withUnsafeMutablePointer(to: &settings) { s in
                withUnsafeMutablePointer(to: &size) { w in
                    openpty(&primary, &secondary, nil, hasSettings ? s : nil, hasSize ? w : nil)
                }
            }
            guard rc == 0 else { return nil }
            // Bytes go through untouched; the real terminal turns \n into \r\n itself, so doing it here too doubles it.
            var raw = termios()
            if tcgetattr(secondary, &raw) == 0 {
                raw.c_oflag &= ~tcflag_t(OPOST)
                _ = tcsetattr(secondary, TCSANOW, &raw)
            }
            _ = fcntl(primary, F_SETFD, FD_CLOEXEC)
            _ = fcntl(secondary, F_SETFD, FD_CLOEXEC)
            return (primary, secondary)
        }
    }

    /// The command asks fd 2 how wide the terminal is; keep that answer true when the window is resized.
    private func followWindowSize() {
        let source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .global())
        let (output, readEnd) = (output, readEnd)
        source.setEventHandler {
            var size = winsize()
            if ioctl(output, TIOCGWINSZ, &size) == 0 { _ = ioctl(readEnd, TIOCSWINSZ, &size) }
        }
        source.resume()
        resize = source
    }

    /// The last lines a person would have read: escape sequences dropped, a line redrawn with \r
    /// counted once (progress bars), blank lines skipped. The text came from the command, so it is
    /// shown to the user but never handed to a model as instructions.
    static func lastLines(_ text: String, count: Int = 3, width: Int = 160) -> [String] {
        let plain = text
            .replacingOccurrences(of: #"\u001B\][^\u0007\u001B]*(\u0007|\u001B\\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\u001B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\u001B[@-_]"#, with: "", options: .regularExpression)
        let lines = plain.components(separatedBy: "\n").compactMap { raw -> String? in
            let shown = raw.split(separator: "\r", omittingEmptySubsequences: true).last.map(String.init) ?? ""
            let clean = String(shown.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
                .trimmingCharacters(in: .whitespaces)
            return clean.isEmpty ? nil : clean.clipped(width)
        }
        return Array(lines.suffix(count))
    }
}
