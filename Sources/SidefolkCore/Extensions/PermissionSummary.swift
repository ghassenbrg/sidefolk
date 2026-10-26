import Foundation

/// What an extension may do once installed, with every path canonical (`realpath`).
public struct ExtensionPermissions: Codable, Sendable, Hashable {
    public var network: Bool
    public var read: [String]
    public var write: [String]
    public var exec: [String]

    public init(network: Bool = false, read: [String] = [], write: [String] = [], exec: [String] = []) {
        self.network = network
        self.read = read
        self.write = write
        self.exec = exec
    }

    /// Exec entries that can run arbitrary code (shells, interpreters, `osascript`, `curl` …).
    public var dangerousExec: [String] { exec.filter(Self.canRunAnything) }

    /// Raises every tool to at least medium risk: it can reach the internet, change files or run anything.
    public var raisesRiskFloor: Bool { network || !write.isEmpty || !dangerousExec.isEmpty }

    static let anythingRunners: Set<String> = [
        "sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "fish", "env", "xargs", "nohup", "sudo", "su", "login",
        "osascript", "open", "launchctl", "security", "sqlite3", "curl", "wget", "nc", "ssh", "scp", "sftp", "rsync",
        "python", "python3", "perl", "perl5", "ruby", "node", "php", "lua", "tclsh", "wish", "swift", "osacompile",
        "awk", "nawk", "gawk", "find", "xcrun", "script", "expect", "screen", "tmux", "git", "make",
    ]

    static func canRunAnything(_ path: String) -> Bool {
        let base = (path as NSString).lastPathComponent
        if anythingRunners.contains(base) { return true }
        // python3.12, perl5.34, ruby3.3 …
        return ["python", "perl", "ruby", "node", "php", "lua"].contains { base.hasPrefix($0) }
    }
}

/// Plain-language permission lines for the install sheet, plus warnings about dangerous combinations
/// (SECURITY T13, T16). Deterministic: built from the manifest, never from model text.
public struct PermissionSummary: Sendable, Hashable {
    public struct Line: Sendable, Hashable {
        public enum Kind: String, Sendable, Hashable { case network, read, write, exec, none, unsandboxed }
        public var kind: Kind
        public var text: String
        /// Worth drawing attention to on the install sheet.
        public var caution: Bool
    }

    public var lines: [Line]
    public var warnings: [String]
    public var sandboxed: Bool

    public var texts: [String] { lines.map(\.text) }

    public static func forExtension(_ p: ExtensionPermissions) -> PermissionSummary {
        var lines: [Line] = []
        let show = FolderAccess.displayPath
        if p.network { lines.append(Line(kind: .network, text: String(localized: "Can use the internet"), caution: true)) }
        for path in p.read where !p.write.contains(path) {
            lines.append(Line(kind: .read, text: String(localized: "Can read \(show(path))"), caution: false))
        }
        for path in p.write {
            lines.append(Line(kind: .write, text: String(localized: "Can read and change files in \(show(path))"), caution: true))
        }
        let dangerous = Set(p.dangerousExec)
        for path in p.exec {
            let anything = dangerous.contains(path)
            lines.append(Line(kind: .exec, text: anything ? String(localized: "Can run \(path), which can run anything") : String(localized: "Can run \(path)"),
                              caution: anything))
        }
        if !p.network && p.read.isEmpty && p.write.isEmpty {
            lines.append(Line(kind: .none, text: String(localized: "No access to your files or the internet"), caution: false))
        }

        var warnings: [String] = []
        let folders = (p.read + p.write).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if p.network, !folders.isEmpty {
            warnings.append(String(localized: "It can read \(list(folders.map(show))) and use the internet, so it could upload those files."))
        }
        if let first = p.dangerousExec.first {
            warnings.append(p.network
                ? String(localized: "It can use the internet and run \(first), so it could download and run other code.")
                : String(localized: "It can run \(first), which can run any code its sandbox allows."))
        }
        if p.network, !p.write.isEmpty {
            warnings.append(String(localized: "It can save what it downloads into \(list(p.write.map(show)))."))
        }
        return PermissionSummary(lines: lines, warnings: warnings, sandboxed: true)
    }

    /// A plain MCP server runs with the user's own rights; say so, and warn about code that changes every launch.
    public static func forMCPServer(command: String, arguments: [String]) -> PermissionSummary {
        var warnings: [String] = []
        if let note = unpinnedLauncherWarning(command: command, arguments: arguments) { warnings.append(note) }
        return PermissionSummary(
            lines: [Line(kind: .unsandboxed,
                         text: String(localized: "Runs with your full permissions: it can read and change your files, use the internet and run programs"),
                         caution: true)],
            warnings: warnings, sandboxed: false)
    }

    /// `npx -y pkg` and `uvx pkg` without a version fetch whatever was published last, at every launch.
    static func unpinnedLauncherWarning(command: String, arguments: [String]) -> String? {
        let base = (command as NSString).lastPathComponent
        let package = arguments.first { !$0.hasPrefix("-") }
        switch base {
        case "npx", "bunx", "pnpx":
            guard let package else { return nil }
            let pinned = package.range(of: #"^(@[^/@]+/)?[^@]+@\d"#, options: .regularExpression) != nil
            return pinned ? nil : String(localized: "It downloads the latest \(package) every time it starts. Pin a version, like \(package)@1.2.3.")
        case "uvx":
            guard let package else { return nil }
            let pinned = package.contains("==") || package.range(of: #"@\d"#, options: .regularExpression) != nil
            return pinned ? nil : String(localized: "It downloads the latest \(package) every time it starts. Pin a version, like \(package)==1.2.3.")
        default:
            return nil
        }
    }

    /// "~/Documents, ~/Notes and ~/Desktop", in the app's language.
    private static func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and).locale(Wording.locale))
    }
}
