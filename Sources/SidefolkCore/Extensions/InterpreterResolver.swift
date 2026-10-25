import Darwin
import Foundation

/// An interpreter found on this Mac and pinned at install: its real path, the binary it re-executes
/// (framework Pythons start `Python.app`), and the read-only runtime folders the sandbox must open.
public struct ResolvedInterpreter: Codable, Sendable, Hashable {
    public var name: String
    public var path: String
    public var reexec: String?
    public var runtime: [String]
    /// Arguments placed before the script (`-I -B` for Python: isolated mode, no bytecode writes).
    public var flags: [String]

    public init(name: String, path: String, reexec: String? = nil, runtime: [String], flags: [String] = []) {
        self.name = name
        self.path = path
        self.reexec = reexec
        self.runtime = runtime
        self.flags = flags
    }
}

/// Finds `python3`, `node` and `sh` in fixed, trusted places. `/usr/bin/python3` is an xcrun shim that
/// fails inside the sandbox, so Python is located with `xcrun --find python3` and `realpath` (SECURITY §3).
public struct InterpreterResolver: Sendable {
    public static let supported: Set<String> = ["python3", "node", "sh"]

    private let candidates: @Sendable (String) -> [String]

    /// - Parameter candidates: paths to try for an interpreter name, best first.
    public init(candidates: @escaping @Sendable (String) -> [String]) {
        self.candidates = candidates
    }

    public static let system = InterpreterResolver(candidates: systemCandidates)

    public func resolve(_ name: String) -> ResolvedInterpreter? {
        guard Self.supported.contains(name) else { return nil }
        for candidate in candidates(name) {
            guard let real = ExtensionFS.realpath(candidate), real != "/usr/bin/python3", Self.isTrusted(real) else { continue }
            return Self.describe(name: name, path: real)
        }
        return nil
    }

    static func systemCandidates(_ name: String) -> [String] {
        switch name {
        case "python3":
            return [xcrunFind("python3"), "/opt/homebrew/bin/python3", "/usr/local/bin/python3",
                    "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"].compactMap { $0 }
        case "node": return ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        case "sh": return ["/bin/sh"]
        default: return []
        }
    }

    /// Owned by root or the user, a regular executable file, and not writable by group or others.
    static func isTrusted(_ path: String) -> Bool {
        guard let st = ExtensionFS.lstat(path), ExtensionFS.isRegular(st) else { return false }
        return (st.st_uid == 0 || st.st_uid == getuid()) && st.st_mode & 0o022 == 0 && st.st_mode & 0o111 != 0
    }

    static func describe(name: String, path: String) -> ResolvedInterpreter {
        var runtime: [String] = []
        var reexec: String?
        if let range = path.range(of: #"^.*?\.framework(?=/Versions/)"#, options: .regularExpression) {
            let framework = String(path[range])
            runtime.append(framework)
            let rest = path[range.upperBound...].split(separator: "/")
            if rest.count > 1 {
                let app = "\(framework)/Versions/\(rest[1])/Resources/Python.app/Contents/MacOS/Python"
                reexec = ExtensionFS.realpath(app)
            }
        }
        for prefix in ["/opt/homebrew", "/usr/local"] where path.hasPrefix(prefix + "/Cellar/") {
            runtime += ["Cellar", "opt", "lib"].compactMap { ExtensionFS.realpath("\(prefix)/\($0)") }
        }
        if name == "sh" {
            // /bin/sh reads /private/var/select/sh and execs the shell it names (bash by default).
            reexec = ExtensionFS.realpath("/private/var/select/sh")
        } else if runtime.isEmpty {
            runtime = [path] // a standalone binary needs only itself
        }
        var seen = Set<String>()
        runtime = runtime.filter { seen.insert($0).inserted }
        return ResolvedInterpreter(name: name, path: path, reexec: reexec, runtime: runtime,
                                   flags: name == "python3" ? ["-I", "-B"] : [])
    }

    /// `xcrun --find <tool>`; nil when developer tools are missing.
    static func xcrunFind(_ tool: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["--find", tool]
        p.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? path : nil
    }
}
