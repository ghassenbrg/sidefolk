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
    /// Sidefolk may save its results beside a file the person hands over (`tools.<name>.outputs`, D140).
    public var placesFiles: Bool
    /// The graphics hardware and media decoders (`permissions.media`).
    public var media: Bool
    /// The clipboard, read and changed (`permissions.clipboard`, D63).
    public var clipboard: Bool
    /// Power assertions: the Mac kept awake, the person kept active (`permissions.power`, D63).
    public var power: Bool
    /// The screen and the Mac's sound, recorded and compressed to video (`permissions.screen`, D69).
    public var screen: Bool
    /// May temporarily mute the default output device, affecting every app.
    public var outputMute: Bool
    /// UDP received from anyone who can reach the Mac, for live audio and video (`permissions.udp`, D69).
    public var udp: Bool
    /// What the extension says it uses the network for (`permissions.network_purpose`, D69): one cleaned line.
    public var networkPurpose: String?
    /// Asking the person's AI to write something (`permissions.ai`, D100).
    public var ai: ExtensionAIAccess?
    /// May ask for the person's place (`permissions.place`, D106), for this purpose.
    public var place: ExtensionPurpose?
    /// May ask to schedule reminders (`permissions.schedule`, D107), for this purpose.
    public var schedule: ExtensionPurpose?
    /// Asking Sidefolk to use its tools through Guard (`permissions.act`, D110).
    public var act: ExtensionPurpose?
    /// Hearing what happens in Sidefolk (`permissions.events`, D129).
    public var events: ExtensionPurpose?

    public init(network: Bool = false, read: [String] = [], write: [String] = [], exec: [String] = [],
                programs: [ResolvedProgram] = [], folders: ExtensionManifest.FolderUse? = nil, media: Bool = false,
                clipboard: Bool = false, power: Bool = false, screen: Bool = false, udp: Bool = false, networkPurpose: String? = nil,
                outputMute: Bool = false, ai: ExtensionAIAccess? = nil, place: ExtensionPurpose? = nil, schedule: ExtensionPurpose? = nil, act: ExtensionPurpose? = nil, events: ExtensionPurpose? = nil,
                placesFiles: Bool = false) {
        self.events = events
        self.act = act
        self.placesFiles = placesFiles
        self.place = place
        self.schedule = schedule
        self.ai = ai
        self.act = act
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
        self.outputMute = outputMute
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
        placesFiles = try c.decodeIfPresent(Bool.self, forKey: .placesFiles) ?? false
        media = try c.decodeIfPresent(Bool.self, forKey: .media) ?? false
        clipboard = try c.decodeIfPresent(Bool.self, forKey: .clipboard) ?? false
        power = try c.decodeIfPresent(Bool.self, forKey: .power) ?? false
        screen = try c.decodeIfPresent(Bool.self, forKey: .screen) ?? false
        outputMute = try c.decodeIfPresent(Bool.self, forKey: .outputMute) ?? false
        udp = try c.decodeIfPresent(Bool.self, forKey: .udp) ?? false
        networkPurpose = try c.decodeIfPresent(String.self, forKey: .networkPurpose)
        ai = try c.decodeIfPresent(ExtensionAIAccess.self, forKey: .ai)
        place = try c.decodeIfPresent(ExtensionPurpose.self, forKey: .place)
        schedule = try c.decodeIfPresent(ExtensionPurpose.self, forKey: .schedule)
        act = try c.decodeIfPresent(ExtensionPurpose.self, forKey: .act)
        events = try c.decodeIfPresent(ExtensionPurpose.self, forKey: .events)
    }

    /// Exec entries that can run arbitrary code (shells, interpreters, `osascript`, `curl` …). Programs named
    /// without a path never count: Sidefolk found them itself, and the sandbox lets them start only their helpers.
    public var dangerousExec: [String] { exec.filter(Self.canRunAnything) }

    /// Raises every tool to at least medium risk: it can reach the internet, change files or run anything.
    /// The clipboard counts: what someone copied (a password, an address) is theirs alone. So does the screen.
    public var raisesRiskFloor: Bool { network || !write.isEmpty || folders == .write || placesFiles || !dangerousExec.isEmpty || clipboard || screen || outputMute }

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

/// What `permissions.ai` grants, as pinned at install (D100): the author's purpose, and the most requests a day.
public struct ExtensionAIAccess: Codable, Sendable, Hashable {
    public var purpose: String
    public var dailyCap: Int

    public init(purpose: String, dailyCap: Int) {
        self.purpose = purpose
        self.dailyCap = dailyCap
    }
}

/// One thing an extension says it wants something for, as pinned at install (D106, D107).
public struct ExtensionPurpose: Codable, Sendable, Hashable {
    public var purpose: String

    public init(purpose: String) { self.purpose = purpose }
}

/// Plain-language permission lines for the install sheet, plus warnings about dangerous combinations
/// (SECURITY T13, T16). Deterministic: built from the manifest, never from model text.
public struct PermissionSummary: Sendable, Hashable {
    public struct Line: Sendable, Hashable {
        public enum Kind: String, Sendable, Hashable { case network, read, write, exec, media, clipboard, power, screen, outputMute, udp, ai, place, schedule, act, events, none, unsandboxed }
        public var kind: Kind
        public var text: String
        /// Worth drawing attention to on the install sheet.
        public var caution: Bool
        /// What keeps it in check, said beside it on the install sheet (D71): only guards Sidefolk or macOS
        /// really enforce, never the extension's own promise.
        public var note: String?

        public init(kind: Kind, text: String, caution: Bool, note: String? = nil) {
            self.kind = kind
            self.text = text
            self.caution = caution
            self.note = note
        }
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
        // Guard lets a call name only a folder the person shared or allows on a card (extensions and other agents
        // can't ask: refused), and the call's own process opens just that one (ExtensionTool, SECURITY T15, T27).
        let perCall = String(localized: "Only a folder you've shared with Sidefolk or allow on a card. Its sandbox opens it for that one request.")
        switch p.folders {
        case .write?:
            lines.append(Line(kind: .write, text: String(localized: "Can read and change files in a folder you name, for that request only"),
                              caution: true, note: perCall))
        case .read?:
            lines.append(Line(kind: .read, text: String(localized: "Can read a folder you name, for that request only"), caution: false, note: perCall))
        case nil:
            break
        }
        if p.placesFiles {
            lines.append(Line(kind: .write, text: String(localized: "Can have Sidefolk save new files beside a file you give it"), caution: false,
                              note: String(localized: "Sidefolk saves them itself and never replaces a file. The extension can't write in that folder.")))
        }
        let dangerous = Set(p.dangerousExec)
        for path in p.exec {
            let anything = dangerous.contains(path)
            lines.append(Line(kind: .exec, text: anything ? String(localized: "Can run \(path), which can run anything") : String(localized: "Can run \(path)"),
                              caution: anything))
        }
        for program in p.programs {
            // Resolved by Sidefolk, and the sandbox lets it start only its fixed helpers (ProgramResolver, T13).
            lines.append(Line(kind: .exec, text: String(localized: "Can run \(program.name) (\(show(program.path)))"), caution: false,
                              note: String(localized: "Sidefolk found it on this Mac, and it may start only its own helper programs.")))
        }
        if p.media {
            lines.append(Line(kind: .media, text: String(localized: "Can use the Mac's graphics hardware for pictures"), caution: false))
        }
        if p.clipboard {
            lines.append(Line(kind: .clipboard, text: String(localized: "Can read and change what you copy (the clipboard), and see which app you copied in"), caution: true))
        }
        if p.power {
            lines.append(Line(kind: .power, text: String(localized: "Can keep your Mac awake and tell macOS you're active"), caution: false))
        }
        if p.screen {
            // macOS attributes the recording to Sidefolk and keeps it off until the person switches Sidefolk on; the
            // switch is Sidefolk's, not this extension's (SECURITY T36).
            lines.append(Line(kind: .screen, text: String(localized: "Can record your screen and the sound your Mac plays"), caution: true,
                              note: String(localized: "Only once you switch Sidefolk on in Screen & System Audio Recording (System Settings › Privacy & Security). That switch covers every extension that records.")))
        }
        if p.outputMute {
            lines.append(Line(kind: .outputMute, text: String(localized: "Can temporarily mute the Mac’s default sound output, including other apps"), caution: true,
                              note: String(localized: "Sidefolk restores its previous mute state when the extension stops.")))
        }
        if p.udp {
            lines.append(Line(kind: .udp, text: String(localized: "Can receive live audio and video traffic (UDP) from any device that can reach your Mac"),
                              caution: true))
        }
        if let ai = p.ai {
            // Sidefolk's guards, all enforced by the host: the frame, no tools, the cap, the switch, History (D100, T41).
            lines.append(Line(kind: .ai, text: String(localized: "Can ask your AI to write something, up to \(ai.dailyCap) times a day. It says it uses it \(ai.purpose).",
                                                      comment: "Install sheet: permissions.ai; the daily limit, then the author's purpose, “to write quiz questions”"),
                              caution: true,
                              note: String(localized: "It counts toward your AI's usage. The AI gets only the words the extension sends: no tools, nothing of yours. Each request is in History, and a switch in Settings › Add-ons turns it off.")))
        }
        if let place = p.place {
            lines.append(Line(kind: .place, text: String(localized: "Can ask for your place. It says it uses it \(place.purpose).",
                                                         comment: "Install sheet: permissions.place; the author's purpose, “to show the weather where you are”"),
                              caution: false,
                              note: p.network ? String(localized: "Off until you say yes. With its internet access it could send your town and coordinates anywhere. A switch in Settings › Add-ons takes it back.")
                                  : String(localized: "Off until you say yes. A switch in Settings › Add-ons takes it back.")))
        }
        if let schedule = p.schedule {
            lines.append(Line(kind: .schedule, text: String(localized: "Can ask to send you reminders at moments it plans. It says it uses them \(schedule.purpose).",
                                                            comment: "Install sheet: permissions.schedule; the author's purpose, “to remind you of the moments you choose”"),
                              caution: false,
                              note: String(localized: "Off until you say yes. They follow your Focus, Quiet and Attention settings. A switch in Settings › Add-ons takes it back.")))
        }
        if let act = p.act {
            // Sidefolk's guards, all enforced by the host: the closed list, a card each time, plans read in full, History (D110, T44).
            lines.append(Line(kind: .act, text: String(localized: "Can ask Sidefolk to use its tools and other extensions' tools. It says it uses them \(act.purpose).",
                                                       comment: "Install sheet: permissions.act; the author's purpose, “to run the steps you set up”"),
                              caution: true,
                              note: String(localized: "Each use asks you first, unless you read and allowed a plan for exactly that. A plan can search your notes unattended, with words it fills in. Every use is in History.")))
        }
        if let events = p.events {
            let contained = !p.network && p.exec.isEmpty && p.programs.isEmpty && p.write.isEmpty && p.folders != .write && !p.clipboard && !p.screen && !p.udp
            lines.append(Line(kind: .events, text: String(localized: "Hears when things happen in Sidefolk: a reminder fires, a note is saved, a meeting is about to start, an agent finishes. It says it uses that \(events.purpose).",
                                                          comment: "Install sheet: permissions.events; the author's purpose, “to start what you set up”"),
                              caution: true,
                              note: contained ? String(localized: "It hears their titles too, without a card each time. It can't reach the internet by itself; anything it passes on goes through Sidefolk.")
                                  : String(localized: "It hears their titles too, without a card each time, and it can reach beyond this Mac, so it could send them on.")))
        }
        if !p.network && p.media {
            // HEIC and AVIF need the certificate service, which can fetch from an address (SandboxProfile.mediaRules).
            lines.append(Line(kind: .media, text: String(localized: "Can't connect to the internet directly, but a Mac service it uses could carry data out"), caution: true))
        } else if !p.network && p.read.isEmpty && p.write.isEmpty && p.folders == nil {
            // With `act` it may reach both through a tool, on a card: it is only its own reach that is none.
            lines.append(Line(kind: .none, text: p.act != nil ? String(localized: "No access of its own to your files or the internet")
                : String(localized: "No access to your files or the internet"), caution: false))
        } else if !p.network {
            // What it can't do matters as much beside files: the sandbox has no network rule at all (SandboxProfile).
            lines.append(Line(kind: .none, text: p.act != nil ? String(localized: "Can't use the internet by itself") : String(localized: "Can't use the internet"), caution: false))
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
        if p.act != nil, p.network || !p.exec.isEmpty || !p.programs.isEmpty {
            warnings.append(String(localized: "It can use Sidefolk's tools and reach beyond this Mac by itself, so what they return could leave it. It gets no plans: every use asks you."))
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
