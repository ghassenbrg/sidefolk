import CryptoKit
import Darwin
import Foundation

/// An extension's PDF icon, as a picture Sidefolk can draw without running the PDF. A few kilobytes of PDF can take minutes or gigabytes
/// to draw, and no reading of the file can tell (SECURITY). So macOS's own `sips` draws it once, in a process of its own, sandboxed,
/// watched and killed past its limits, and everything else draws only that bitmap.
public enum ExtensionIconBitmap {
    public static let side = 256
    static let seconds: TimeInterval = 3
    static let bytes: UInt64 = 300 * 1024 * 1024
    private static let lock = NSLock()

    /// The folder for bitmaps: named by what they were drawn from, so one is only ever used for those very bytes.
    public static var folder: String { NSTemporaryDirectory() + "sidefolk-icon-bitmaps" }

    /// The bitmap for this PDF, drawn now if it hasn't been. Nil if it's too costly to draw: remembered, so it costs that only once.
    /// Blocks while it draws, one at a time: call it off the main thread.
    public static func path(forPDF path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path), data.count <= ExtensionIcon.maxBytes else { return nil }
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let done = folder + "/" + name + ".png", refused = folder + "/" + name + ".refused"
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: done) { return done }
        if FileManager.default.fileExists(atPath: refused) { return nil }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let drawing = folder + "/" + UUID().uuidString + ".png"
        defer { try? FileManager.default.removeItem(atPath: drawing) }
        guard draw(path, to: drawing), (try? FileManager.default.moveItem(atPath: drawing, toPath: done)) != nil else {
            FileManager.default.createFile(atPath: refused, contents: nil)
            return nil
        }
        return done
    }

    private static func draw(_ source: String, to destination: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        let profile = """
        (version 1)(allow default)(deny network*)(deny file-write*)
        (allow file-write* (subpath (param "OUT")) (subpath (param "TMP")) (literal "/dev/null"))
        """
        // The sandbox matches real paths: the temporary folder's usual name goes through a link.
        let real = (folder as NSString).resolvingSymlinksInPath, temporary = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
        process.arguments = ["-p", profile, "-D", "OUT=\(FolderAccess.canonical(real) ?? real)", "-D", "TMP=\(FolderAccess.canonical(temporary) ?? temporary)",
                             "/usr/bin/sips", "-s", "format", "png", "-z", "\(side)", "\(side)", source, "--out", destination]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning {
            if Date() > deadline || footprint(of: process.processIdentifier) > bytes {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                return false
            }
            usleep(25_000)
        }
        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: destination)
    }

    private static func footprint(of pid: pid_t) -> UInt64 {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? usage.ri_phys_footprint : 0
    }
}
