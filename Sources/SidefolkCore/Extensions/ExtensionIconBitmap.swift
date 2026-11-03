import CryptoKit
import Darwin
import Foundation

/// An extension's PDF icon, as a picture Sidefolk can draw without running the PDF. A few kilobytes of PDF can take minutes or gigabytes
/// to draw, and no reading of the file can tell (SECURITY T47). So macOS's own `sips` draws it once, in a process of its own, sandboxed,
/// watched and killed past its limits, and everything else draws only that bitmap.
public enum ExtensionIconBitmap {
    public static let side = 256
    /// Of its own work, so a busy Mac doesn't count against an icon. The wall clock only gives up, and blames nothing.
    static let cpuSeconds: Double = 3
    static let wallSeconds: TimeInterval = 15
    static let bytes: UInt64 = 300 * 1024 * 1024
    private static let lock = NSLock()

    public enum Outcome: Equatable {
        case drawn(String)
        /// Its own drawing broke a limit: remembered, so it costs that only once.
        case tooCostly
        /// A busy Mac, a full disk, a missing tool: nothing about the icon, and tried again next time.
        case notNow
    }

    /// The folder for bitmaps: named by what they were drawn from, and drawn from a copy of those very bytes.
    public static var folder: String { NSTemporaryDirectory() + "sidefolk-icon-bitmaps" }

    /// The bitmap for this PDF, if it can be had: a blank icon otherwise, and the extension goes on working. Off the main thread.
    public static func path(forPDF path: String) -> String? {
        if case .drawn(let bitmap) = outcome(forPDF: path) { return bitmap }
        return nil
    }

    /// Blocks while it draws, one at a time.
    public static func outcome(forPDF path: String) -> Outcome {
        guard let data = FileManager.default.contents(atPath: path), data.count <= ExtensionIcon.maxBytes else { return .notNow }
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let done = folder + "/" + name + ".png", refused = folder + "/" + name + ".refused"
        // Before the lock, so a file already drawn never waits for another being drawn.
        if FileManager.default.fileExists(atPath: done) { return .drawn(done) }
        if FileManager.default.fileExists(atPath: refused) { return .tooCostly }
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: done) { return .drawn(done) }
        guard (try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else { return .notNow }
        let work = folder + "/" + UUID().uuidString
        let source = work + ".pdf", drawing = work + ".png"
        defer { for leftover in [source, drawing] { try? FileManager.default.removeItem(atPath: leftover) } }
        guard FileManager.default.createFile(atPath: source, contents: data) else { return .notNow }
        switch draw(source, to: drawing) {
        case .finished where (try? FileManager.default.moveItem(atPath: drawing, toPath: done)) != nil:
            return .drawn(done)
        case .overLimit:
            FileManager.default.createFile(atPath: refused, contents: nil)
            return .tooCostly
        default:
            return .notNow
        }
    }

    private enum Drawing { case finished, overLimit, failed }

    private static func draw(_ source: String, to destination: String) -> Drawing {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        // The parser reads what it's given and nothing else of the person's, can reach no service, and can start nothing that outlives it.
        let profile = """
        (version 1)(allow default)(deny network*)(deny mach-lookup)(deny file-write*)
        (allow file-write* (subpath (param "OUT")) (literal "/dev/null"))
        (deny file-read* (subpath "/Users"))
        (deny process-fork)(deny process-exec*)(allow process-exec (literal "/usr/bin/sips"))
        (deny iokit-open)(deny appleevent-send)(deny lsopen)
        """
        // The sandbox matches real paths: the temporary folder's usual name goes through a link.
        let real = FolderAccess.canonical(folder) ?? folder
        process.arguments = ["-p", profile, "-D", "OUT=\(real)", "/usr/bin/sips", "-s", "format", "png", "-z", "\(side)", "\(side)", source, "--out", destination]
        process.environment = ["TMPDIR": real + "/", "PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return .failed }
        let deadline = Date().addingTimeInterval(wallSeconds)
        while process.isRunning {
            let used = usage(of: process.processIdentifier)
            if used.cpu > cpuSeconds || used.bytes > bytes {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                return .overLimit
            }
            if Date() > deadline {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                return .failed
            }
            usleep(25_000)
        }
        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: destination) ? .finished : .failed
    }

    private static func usage(of pid: pid_t) -> (cpu: Double, bytes: UInt64) {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard result == 0 else { return (0, 0) }
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        // In the machine's own ticks, not nanoseconds.
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        return (ticks * Double(base.numer) / Double(base.denom) / 1e9, info.ri_phys_footprint)
    }
}
