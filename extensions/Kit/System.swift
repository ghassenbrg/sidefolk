import Foundation

/// Where things are inside the sandbox. `HOME` is the extension's data folder there, so the person's own home
/// comes from the user database, and `~` in a path the model passes means theirs.
public enum Paths {
    public static let home: String = {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: dir)
    }()

    /// The extension's own folder for what it keeps between calls (scores, last readings).
    public static var data: String { ProcessInfo.processInfo.environment["SIDEFOLK_DATA_DIR"] ?? NSTemporaryDirectory() }

    /// A path the person named, made full: Sidefolk passes full paths, "~/…" is for trying an extension by hand.
    public static func full(_ raw: String) throws -> String {
        let path = raw == "~" || raw.hasPrefix("~/") ? home + raw.dropFirst() : raw
        guard path.hasPrefix("/") else { throw Problem(L("Give the full path, like ~/Downloads/photo.jpg.")) }
        return (path as NSString).standardizingPath
    }

    /// "~/Pictures/cat.jpg" instead of "/Users/ada/Pictures/cat.jpg".
    public static func show(_ path: String) -> String {
        path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    public static func exists(_ path: String, folder: Bool? = nil) -> Bool {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return false }
        return folder.map { $0 == isFolder.boolValue } ?? true
    }

    /// A name for a new file beside the others that doesn't replace one: "photo.jpg", then "photo 2.jpg".
    public static func free(_ path: String) -> String {
        guard exists(path) else { return path }
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        for n in 2... {
            let candidate = url.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)").path
            if !exists(candidate) { return candidate }
        }
        return path
    }
}

/// What a program printed and how it ended.
public struct Output {
    public let status: Int32
    public let out: String
    public let err: String
}

/// Runs one of the programs the manifest lists (the sandbox refuses any other), its output read as it comes so
/// a long one never blocks on a full pipe.
public func run(_ program: String, _ arguments: [String], environment: [String: String]? = nil, in folder: String? = nil,
                timeout: TimeInterval = 60) throws -> Output {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: program)
    process.arguments = arguments
    if let environment { process.environment = environment }
    if let folder { process.currentDirectoryURL = URL(fileURLWithPath: folder) }
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    process.standardInput = FileHandle.nullDevice
    try process.run()
    let collected = (out: Collected(), err: Collected())
    let reading = DispatchGroup()
    for (handle, box) in [(out.fileHandleForReading, collected.out), (err.fileHandleForReading, collected.err)] {
        DispatchQueue.global().async(group: reading) { box.data = handle.readDataToEndOfFile() }
    }
    if reading.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        throw Problem(L("{program} took longer than {seconds} seconds, so it was stopped.",
                         ["program": (program as NSString).lastPathComponent, "seconds": Int(timeout)]))
    }
    process.waitUntilExit()
    return Output(status: process.terminationStatus, out: String(decoding: collected.out.data, as: UTF8.self),
                  err: String(decoding: collected.err.data, as: UTF8.self))
}

/// Written once by the reader, read once it is done.
private final class Collected: @unchecked Sendable {
    var data = Data()
}

/// The internet, for extensions the manifest gives it to: JSON or text from an https address.
public enum Web {
    public static func data(_ url: URL, timeout: TimeInterval = 15) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Sidefolk/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Problem(L("Couldn't reach {host} ({error}). Check the internet connection.",
                             ["host": url.host ?? L("the server"), "error": error.localizedDescription]))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Problem(L("{host} answered with HTTP {status}.", ["host": url.host ?? L("The server"), "status": String(status)]))
        }
        return data
    }

    public static func json(_ url: URL, timeout: TimeInterval = 15) async throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: try await data(url, timeout: timeout)) as? [String: Any] else {
            throw Problem(L("{host} sent something that isn't JSON.", ["host": url.host ?? L("The server")]))
        }
        return object
    }

    /// An address with its query, the values encoded.
    public static func url(_ base: String, _ query: [(String, String)]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url!
    }
}
