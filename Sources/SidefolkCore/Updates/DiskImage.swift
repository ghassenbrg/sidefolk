import Foundation

/// Mounts and unmounts a downloaded disk image.
public protocol DiskImageMounting: Sendable {
    /// Mounts `image` read-only, out of sight (no Finder window, not in the sidebar), under `folder`.
    func attach(_ image: URL, under folder: URL) async throws -> URL
    func detach(_ mountPoint: URL) async
}

/// `hdiutil`, the system's own tool for disk images.
public struct DiskImages: DiskImageMounting {
    public init() {}

    public func attach(_ image: URL, under folder: URL) async throws -> URL {
        let out = try await SystemTool.run("/usr/bin/hdiutil", ["attach", "-plist", "-readonly", "-nobrowse", "-noautoopen",
                                                                "-mountrandom", folder.path, image.path], timeout: 120)
        guard out.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: out.output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.lazy.compactMap({ $0["mount-point"] as? String }).first else {
            throw UserFacingError("The downloaded disk image wouldn't open.", detail: "hdiutil attach exited \(out.status)")
        }
        return URL(fileURLWithPath: mount, isDirectory: true)
    }

    public func detach(_ mountPoint: URL) async {
        let first = try? await SystemTool.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"], timeout: 60)
        if first?.status != 0 { _ = try? await SystemTool.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"], timeout: 60) }
    }
}

/// Runs one of macOS's own command-line tools with a clean environment and waits for it, keeping its output.
enum SystemTool {
    struct Output: Sendable {
        var status: Int32
        var output: Data
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try runBlocking(executable, arguments, timeout: timeout) })
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> Output {
        let process = Process()
        let pipe = SpawnLock.withLock { Pipe() }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        try SpawnLock.withLock { try process.run() }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        defer { timer.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(status: process.terminationStatus, output: data)
    }
}
