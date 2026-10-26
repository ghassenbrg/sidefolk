import Darwin
import Foundation

/// A program an extension names in `permissions.exec` without a path (`"git"`), found on this Mac and
/// pinned at install like an interpreter: its real path, the helper programs it starts itself, and the
/// read-only folders it loads from. The extension finds it in `SIDEFOLK_EXEC_<NAME>`.
public struct ResolvedProgram: Codable, Sendable, Hashable {
    public var name: String
    public var path: String
    /// Programs it runs itself (git's https transport), allowed to run inside the same sandbox.
    public var helpers: [String]
    /// Opened read-only (and loadable) in the sandbox: its own installation.
    public var runtime: [String]

    public init(name: String, path: String, helpers: [String] = [], runtime: [String] = []) {
        self.name = name
        self.path = path
        self.helpers = helpers
        self.runtime = runtime
    }

    /// The environment variable that tells the extension where it is: `SIDEFOLK_EXEC_GIT`.
    public var environmentKey: String { "SIDEFOLK_EXEC_" + name.uppercased().replacingOccurrences(of: "-", with: "_") }
}

/// Finds the programs Sidefolk knows by name in fixed, trusted places. `/usr/bin/git` is an xcrun shim
/// that fails inside the sandbox (as `/usr/bin/python3` does), so Apple's copy is taken from the
/// developer folder `xcode-select` points at, read from its link rather than by running xcrun (which
/// can offer to install the developer tools on a Mac without them).
public struct ProgramResolver: Sendable {
    /// What Sidefolk needs to know to run each program: its helpers, relative to its installation.
    public struct Known: Sendable {
        var helpers: [String]
    }

    public static let known: [String: Known] = [
        // `git clone https://…` hands the transfer to these; they are part of git, not other programs.
        "git": Known(helpers: ["libexec/git-core/git-remote-https", "libexec/git-core/git-remote-http"]),
    ]

    private let candidates: @Sendable (String) -> [String]

    /// - Parameter candidates: paths to try for a program name, best first.
    public init(candidates: @escaping @Sendable (String) -> [String]) {
        self.candidates = candidates
    }

    public static let system = ProgramResolver(candidates: systemCandidates)

    public func resolve(_ name: String) -> ResolvedProgram? {
        guard let known = Self.known[name] else { return nil }
        for candidate in candidates(name) {
            guard let real = ExtensionFS.realpath(candidate), !real.hasPrefix("/usr/bin/"), InterpreterResolver.isTrusted(real),
                  real.split(separator: "/").count >= 3 else { continue } // <prefix>/bin/<name>, never the root as prefix
            return Self.describe(name: name, path: real, known: known)
        }
        return nil
    }

    static func systemCandidates(_ name: String) -> [String] {
        var developer: [String] = []
        if let selected = try? FileManager.default.destinationOfSymbolicLink(atPath: "/private/var/db/xcode_select_link") {
            developer.append(selected)
        }
        developer += ["/Library/Developer/CommandLineTools", "/Applications/Xcode.app/Contents/Developer"]
        return developer.map { "\($0)/usr/bin/\(name)" } + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
    }

    /// `<prefix>/bin/<name>`: helpers live under the same prefix; Homebrew's need its shared libraries.
    static func describe(name: String, path: String, known: Known) -> ResolvedProgram {
        let prefix = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        // git-remote-https is a link to git-remote-http: the sandbox allows the file a link leads to.
        var seen = Set<String>()
        let helpers = known.helpers.compactMap { ExtensionFS.realpath(prefix + "/" + $0) }
            .filter { InterpreterResolver.isTrusted($0) && seen.insert($0).inserted }
        var runtime = [prefix]
        for brew in ["/opt/homebrew", "/usr/local"] where path.hasPrefix(brew + "/Cellar/") {
            runtime = ["Cellar", "opt", "lib"].compactMap { ExtensionFS.realpath("\(brew)/\($0)") }
        }
        return ResolvedProgram(name: name, path: path, helpers: helpers, runtime: runtime)
    }
}
