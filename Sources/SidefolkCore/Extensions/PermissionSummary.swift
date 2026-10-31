import Foundation

/// What an extension may do once installed, with every path canonical (`realpath`).
public struct ExtensionPermissions: Codable, Sendable, Hashable {
    public var network: Bool
    public var read: [String]
    public var write: [String]
    public var exec: [String]
    /// Programs named without a path (`git`), found on this Mac at install.
    public var programs: [ResolvedProgram]
    /// The most any tool does in a folder the person names in a call (`tools.<name>.paths`); nil when none does.
    public var folders: ExtensionManifest.FolderUse?
    /// The graphics hardware and media decoders (`permissions.media`).
    public var media: Bool
    /// The clipboard, read and changed (`permissions.clipboard`, D63).
    public var clipboard: Bool
    /// Power assertions: the Mac kept awake, the person kept active (`permissions.power`, D63).
    public var power: Bool
    /// The screen and the Mac's sound, recorded and compressed to video (`permissions.screen`, D69).
    public var screen: Bool
    /// UDP received from anyone who can reach the Mac, for live audio and video (`permissions.udp`, D69).
    public var udp: Bool
    /// What the extension says it uses the network for (`permissions.network_purpose`, D69): one cleaned line.
    public var networkPurpose: String?

    public init(network: Bool = false, read: [String] = [], write: [String] = [], exec: [String] = [],
                programs: [ResolvedProgram] = [], folders: ExtensionManifest.FolderUse? = nil, media: Bool = false,
                clipboard: Bool = false, power: Bool = false, screen: Bool = false, udp: Bool = false, networkPurpose: String? = nil) {
        self.network = network
        self.read = read
        self.write = write
        self.exec = exec
        self.programs = programs
        self.folders = folders
        self.media = media
        self.clipboard = clipboard
        self.power = power
        self.screen = screen
        self.udp = udp
        self.networkPurpose = networkPurpose
    }

    /// Pins saved before programs, per-call folders, media, clipboard, power, screen and UDP existed have none of them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        network = try c.decode(Bool.self, forKey: .network)
        read = try c.decode([String].self, forKey: .read)
        write = try c.decode([String].self, forKey: .write)
        exec = try c.decode([String].self, forKey: .exec)
        programs = try c.decodeIfPresent([ResolvedProgram].self, forKey: .programs) ?? []
        folders = try c.decodeIfPresent(ExtensionManifest.FolderUse.self, forKey: .folders)
        media = try c.decodeIfPresent(Bool.self, forKey: .media) ?? false
        clipboard = try c.decodeIfPresent(Bool.self, forKey: .clipboard) ?? false
        power = try c.decodeIfPresent(Bool.self, forKey: .power) ?? false
        screen = try c.decodeIfPresent(Bool.self, forKey: .screen) ?? false
        udp = try c.decodeIfPresent(Bool.self, forKey: .udp) ?? false
        networkPurpose = try c.decodeIfPresent(String.self, forKey: .networkPurpose)
    }

    /// Exec entries that can run arbitrary code (shells, interpreters, `osascript`, `curl` …). Programs named
    /// without a path never count: Sidefolk found them itself, and the sandbox lets them start only their helpers.
    public var dangerousExec: [String] { exec.filter(Self.canRunAnything) }

    /// Raises every tool to at least medium risk: it can reach the internet, change files or run anything.
    /// The clipboard counts: what someone copied (a password, an address) is theirs alone. So does the screen.
    public var raisesRiskFloor: Bool { network || !write.isEmpty || folders == .write || !dangerousExec.isEmpty || clipboard || screen }

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
        public enum Kind: String, Sendable, Hashable { case network, read, write, exec, media, clipboard, power, screen, udp, none, unsandboxed }
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
        if p.network {
            // The sandbox knows only "network or not" (an address can be any host or localhost, measured), so an extension
            // that means the local network still can reach the internet: say both, the reach first (D69).
            if let purpose = p.networkPurpose {
                lines.append(Line(kind: .network, text: String(localized: "Can use the network, the internet included. It says it uses it \(purpose)."), caution: true))
            } else {
                lines.append(Line(kind: .network, text: String(localized: "Can use the internet"), caution: true))
            }
        }
        for path in p.read where !p.write.contains(path) {
            lines.append(Line(kind: .read, text: String(localized: "Can read \(show(path))"), caution: false))
        }
        for path in p.write {
            lines.append(Line(kind: .write, text: String(localized: "Can read and change files in \(show(path))"), caution: true))
        }
        switch p.folders {
        case .write?:
            lines.append(Line(kind: .write, text: String(localized: "Can read and change files in a folder you name, for that request only, once you approve it"),
                              caution: true))
        case .read?:
            lines.append(Line(kind: .read, text: String(localized: "Can read a folder you name, for that request only, once you approve it"), caution: false))
        case nil:
            break
        }
        let dangerous = Set(p.dangerousExec)
        for path in p.exec {
            let anything = dangerous.contains(path)
            lines.append(Line(kind: .exec, text: anything ? String(localized: "Can run \(path), which can run anything") : String(localized: "Can run \(path)"),
                              caution: anything))
        }
        for program in p.programs {
            lines.append(Line(kind: .exec, text: String(localized: "Can run \(program.name) (\(show(program.path)))"), caution: false))
        }
        if p.media {
            lines.append(Line(kind: .media, text: String(localized: "Can use the Mac's graphics hardware for pictures"), caution: false))
        }
        if p.clipboard {
            lines.append(Line(kind: .clipboard, text: String(localized: "Can read and change what you copy (the clipboard)"), caution: true))
        }
        if p.power {
            lines.append(Line(kind: .power, text: String(localized: "Can keep your Mac awake and tell macOS you're active"), caution: false))
        }
        if p.screen {
            lines.append(Line(kind: .screen, text: String(localized: "Can record your screen and the sound your Mac plays, once you allow Sidefolk in Screen Recording"),
                              caution: true))
        }
        if p.udp {
            lines.append(Line(kind: .udp, text: String(localized: "Can receive live audio and video traffic (UDP) from any device that can reach your Mac"),
                              caution: true))
        }
        if !p.network && p.read.isEmpty && p.write.isEmpty && p.folders == nil {
            lines.append(Line(kind: .none, text: String(localized: "No access to your files or the internet"), caution: false))
        }

        var warnings: [String] = []
        let folders = (p.read + p.write).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if p.network, !folders.isEmpty {
            warnings.append(String(localized: "It can read \(list(folders.map(show))) and use the internet, so it could upload those files."))
        }
        if p.network, p.folders != nil {
            warnings.append(String(localized: "It can use the internet while it works in a folder you name, so it could upload what's in that folder."))
        }
        if let first = p.dangerousExec.first {
            warnings.append(p.network
                ? String(localized: "It can use the internet and run \(first), so it could download and run other code.")
                : String(localized: "It can run \(first), which can run any code its sandbox allows."))
        }
        if p.network, p.clipboard {
            warnings.append(String(localized: "It can read what you copy and use the internet, so it could send what you copy elsewhere."))
        }
        if p.network, p.screen {
            warnings.append(String(localized: "It can record your screen and use the internet, so it could send what's on your screen elsewhere."))
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
