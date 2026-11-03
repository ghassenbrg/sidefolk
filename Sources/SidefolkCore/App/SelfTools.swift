import Foundation

/// What the companion can say and do about Sidefolk itself (D120): a companion that can't tell you its own version or
/// whether there's an update feels broken, however much else it can do. The app holds the answers; these tools reach
/// them, for Sidefolk's own AI and the person. Other agents have `status`.
public struct SelfAbout: Sendable {
    public var version: String
    /// "development build" for a copy nobody published.
    public var published: Bool
    public var companion: String
    public var ai: String?
    public var theme: String
    public var appearance: String
    public var language: String
    public var extensions: [String]
    public var extensionsOff: [String]

    public init(version: String, published: Bool, companion: String, ai: String?, theme: String, appearance: String, language: String,
                extensions: [String], extensionsOff: [String]) {
        self.version = version
        self.published = published
        self.companion = companion
        self.ai = ai
        self.theme = theme
        self.appearance = appearance
        self.language = language
        self.extensions = extensions
        self.extensionsOff = extensionsOff
    }
}

public struct SelfUpdates: Sendable {
    public var running: String
    public var published: Bool
    /// The newest version waiting, nil when this is the newest.
    public var newest: String?
    /// Downloaded and waiting to restart.
    public var ready: Bool
    /// Add-ons with a newer version; nil when the gallery couldn't be reached, which isn't none.
    public var addons: [String]?

    public init(running: String, published: Bool, newest: String?, ready: Bool, addons: [String]?) {
        self.running = running
        self.published = published
        self.newest = newest
        self.ready = ready
        self.addons = addons
    }
}

/// What asking to install came to, each said as it is: only the first has started anything new.
public enum SelfInstall: Sendable, Equatable {
    case downloading(String)
    /// Downloaded already: the window is showing, and restarting is the person's click.
    case readyToRestart(String)
    /// An update is already under way.
    case underWay
    case nothingNewer
}

/// Where the companion can take the person.
public enum SelfPlace: String, CaseIterable, Sendable {
    case updates, general, companion, attention, brain, trust, connections, addons, appearance
    case today, calendar, notebook, onDuty = "on_duty", history, gallery
}

/// The app's side of it: Core has no updater or windows.
public protocol SelfReporting: Sendable {
    func about() async -> SelfAbout
    func lookForUpdates() async throws -> SelfUpdates
    /// Brings the newest version in, in the update window where the person sees it. Never restarts by itself.
    func installUpdate() async -> SelfInstall
    func open(_ place: SelfPlace) async
    /// Sets the app's Light or Dark, or `system`; returns what it was.
    func setAppearance(_ appearance: AppAppearance) async -> AppAppearance
    /// Sets the theme by name, returning its name and what it was; nil if there's none called that.
    func setTheme(_ name: String) async -> (name: String, was: String)?
    /// Whether the companion and its small notices show over full-screen apps (D138); returns what it was.
    func setShowsOverFullScreen(_ shows: Bool) async -> Bool
    /// What happens when something needs the person in a full-screen app it stays off (D138); returns what it was.
    func setFullScreenNotice(_ notice: FullScreenNotice) async -> FullScreenNotice
}

public enum SelfTools {
    public static func make(app: any SelfReporting, softwareUpdates: any SoftwareUpdateListing = SoftwareUpdateTool.System()) -> [any Tool] {
        [SelfAboutTool(app: app), SelfUpdatesTool(app: app), SelfInstallUpdateTool(app: app), SelfOpenTool(app: app), SelfLookTool(app: app),
         SoftwareUpdateTool(lister: softwareUpdates)]
    }
}

struct SelfAboutTool: Tool {
    let app: any SelfReporting

    var spec: ToolSpec {
        ToolSpec(name: "sidefolk.about", title: String(localized: "About Sidefolk"),
                 description: "What you are running on: Sidefolk's version, the companion, the AI in use, theme, appearance, language, and the extensions installed. For any question about the app itself.",
                 inputSchema: Schema.object([:]), risk: .low, capabilities: [], category: .system, mutates: false)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Read what Sidefolk is running") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let a = await app.about()
        var lines = ["Sidefolk \(a.version)" + (a.published ? "" : " (a development build, which doesn't update itself)") + ".",
                     "Companion: \(a.companion).", "AI: \(a.ai ?? "none set up").",
                     "Theme: \(a.theme). Appearance: \(a.appearance). Language: \(a.language)."]
        lines.append(a.extensions.isEmpty ? "No extensions installed." : "Extensions: \(a.extensions.joined(separator: ", ")).")
        if !a.extensionsOff.isEmpty { lines.append("Switched off: \(a.extensionsOff.joined(separator: ", ")).") }
        return ToolResult(text: lines.joined(separator: "\n"),
                          card: ResultCard(kind: .info, title: String(localized: "Sidefolk \(a.version)"),
                                           subtitle: [a.companion, a.ai].compactMap { $0 }.joined(separator: " · ")))
    }
}

struct SelfUpdatesTool: Tool {
    let app: any SelfReporting

    var spec: ToolSpec {
        ToolSpec(name: "sidefolk.updates", title: String(localized: "Look for Sidefolk updates"),
                 description: "Look now for a newer Sidefolk, and for add-ons with a newer version. Sidefolk itself is never installed by this; add-ons follow the user's own automatic-update setting. For \"any updates?\", also look with mac.software_updates unless they mean only Sidefolk.",
                 inputSchema: Schema.object([:]), risk: .low, capabilities: [], category: .system, mutates: false)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Look for Sidefolk updates") }
    func scope(for input: JSONValue) -> ToolScope { ToolScope(reach: .service("GitHub")) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let u = try await app.lookForUpdates()
        var text: String
        let title: String
        if let newest = u.newest {
            text = u.ready ? "Sidefolk \(newest) is downloaded and waiting for a restart; this is \(u.running)."
                : "Sidefolk \(newest) is available; this is \(u.running). sidefolk.install_update installs it when the user wants."
            title = u.ready ? String(localized: "Sidefolk \(newest) is ready to restart into") : String(localized: "Sidefolk \(newest) is available")
        } else if u.published {
            text = "Sidefolk \(u.running) is the newest."
            title = String(localized: "Sidefolk \(u.running) is the newest")
        } else {
            text = "This is a development build (\(u.running)), which doesn't update itself."
            title = String(localized: "A development build doesn't update itself")
        }
        switch u.addons {
        case nil: text += " The add-on gallery couldn't be reached, so add-ons weren't checked."
        case let addons? where addons.isEmpty: text += " No add-on has a newer version."
        case let addons?: text += " Add-ons with a newer version: \(addons.joined(separator: ", "))."
        }
        return ToolResult(text: text, card: ResultCard(kind: .info, title: title, subtitle: u.addons.flatMap { $0.isEmpty ? nil : Wording.list($0) }))
    }
}

/// Medium: it restarts the app in the end, and the person says yes first.
struct SelfInstallUpdateTool: Tool {
    let app: any SelfReporting

    var spec: ToolSpec {
        ToolSpec(name: "sidefolk.install_update", title: String(localized: "Update Sidefolk"),
                 description: "Download and install the newest Sidefolk, only when the user asks. It shows the update window, checks the download's signature and asks before restarting.",
                 inputSchema: Schema.object([:]), risk: .medium, capabilities: [], category: .system, mutates: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Update Sidefolk") }
    func scope(for input: JSONValue) -> ToolScope { ToolScope(reach: .service("GitHub")) }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        switch await app.installUpdate() {
        case .downloading(let version):
            return ToolResult(text: "The update window is downloading Sidefolk \(version). It isn't installed yet: the user sees its progress there, and it asks before restarting.",
                              card: ResultCard(kind: .info, title: String(localized: "Downloading Sidefolk \(version)")))
        case .readyToRestart(let version):
            return ToolResult(text: "Sidefolk \(version) is already downloaded. The update window is showing, and it installs when the user clicks to restart there.",
                              card: ResultCard(kind: .info, title: String(localized: "Sidefolk \(version) is ready to restart into")))
        case .underWay:
            return ToolResult(text: "An update is already under way; the update window shows how far it has got.",
                              card: ResultCard(kind: .info, title: String(localized: "An update is already under way")))
        case .nothingNewer:
            return ToolResult(text: "There's no newer Sidefolk to install.", card: ResultCard(kind: .info, title: String(localized: "There's no newer Sidefolk")))
        }
    }
}

struct SelfOpenTool: Tool {
    let app: any SelfReporting

    var spec: ToolSpec {
        ToolSpec(name: "sidefolk.open", title: String(localized: "Open a place in Sidefolk"),
                 description: "Show the user a place in the app: the update window, a page of Settings (general, companion, attention, brain, trust, connections, addons, appearance), or a place in Home (today, calendar, notebook, on_duty, history, gallery).",
                 inputSchema: Schema.object(["place": Schema.string("Where.", enum: SelfPlace.allCases.map(\.rawValue))], required: ["place"]),
                 risk: .low, capabilities: [], category: .system, mutates: false)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Open a place in Sidefolk") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let place = input.string("place").flatMap(SelfPlace.init(rawValue:)) else {
            throw ToolError.invalidInput(String(localized: "“place” isn't one of the places."))
        }
        await app.open(place)
        return ToolResult(text: "Opened \(place.rawValue).")
    }
}

/// The app's look, which the person can ask for in words. Harmless and undoable, so it runs without asking.
struct SelfLookTool: Tool {
    let app: any SelfReporting

    var spec: ToolSpec {
        ToolSpec(name: "sidefolk.look", title: String(localized: "Change how Sidefolk looks"),
                 description: "Change the app's appearance (system, light or dark), its theme, by name (Sidefolk, Harbor, or one the user added or got from the gallery), whether the companion shows over full-screen apps, or how it reaches them there when it doesn't.",
                 inputSchema: Schema.object([
                     "appearance": Schema.string("Light, dark or following the Mac.", enum: AppAppearance.allCases.map(\.rawValue)),
                     "theme": Schema.string("The theme's name."),
                     "over_full_screen": Schema.boolean("Whether the companion shows over other apps' full-screen spaces. Off, it stays on ordinary desktops."),
                     "full_screen_notice": Schema.string("With it off, how something that needs them reaches them in a full-screen app: the companion comes and goes back, a notification from the menu bar, or nothing until they leave.",
                                                         enum: FullScreenNotice.allCases.map(\.rawValue)),
                 ]),
                 risk: .low, capabilities: [], category: .system, mutates: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Change how Sidefolk looks") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        var said: [String] = []
        var undoing: [@Sendable () async -> Void] = []
        if let raw = input.string("appearance") {
            guard let appearance = AppAppearance(rawValue: raw) else { throw ToolError.invalidInput(String(localized: "“appearance” must be system, light or dark.")) }
            let was = await app.setAppearance(appearance)
            said.append("appearance \(appearance.rawValue)")
            let app = self.app
            undoing.append { _ = await app.setAppearance(was) }
        }
        if let name = input.string("theme") {
            guard let set = await app.setTheme(name) else { throw ToolError.notFound(String(localized: "a theme called “\(name.clipped(40))”")) }
            said.append("theme \(set.name)")
            let app = self.app
            undoing.append { _ = await app.setTheme(set.was) }
        }
        if let shows = input["over_full_screen"]?.boolValue {
            let was = await app.setShowsOverFullScreen(shows)
            said.append(shows ? "the companion shows over full-screen apps" : "the companion stays off full-screen apps")
            let app = self.app
            undoing.append { _ = await app.setShowsOverFullScreen(was) }
        }
        if let raw = input.string("full_screen_notice") {
            guard let notice = FullScreenNotice(rawValue: raw) else { throw ToolError.invalidInput(String(localized: "“full_screen_notice” must be companion, menuBar or silent.")) }
            let was = await app.setFullScreenNotice(notice)
            said.append("in full-screen apps it reaches them by \(notice.rawValue)")
            let app = self.app
            undoing.append { _ = await app.setFullScreenNotice(was) }
        }
        guard !said.isEmpty else { throw ToolError.invalidInput(String(localized: "nothing to change. Give an appearance or a theme.")) }
        let steps = undoing
        return ToolResult(text: "Changed: \(said.joined(separator: ", ")).",
                          card: ResultCard(kind: .info, title: String(localized: "Changed how Sidefolk looks")),
                          undo: UndoAction(label: String(localized: "Changed it back")) { for step in steps { await step() } })
    }
}

// MARK: The Mac's own updates

public struct SoftwareUpdateItem: Sendable, Equatable {
    public var title: String
    public var version: String?
    public var restart: Bool
}

public protocol SoftwareUpdateListing: Sendable {
    /// What `softwareupdate --list` says, both its streams.
    func list() async throws -> String
}

/// macOS's own list of updates, the same as System Settings looks at. It only lists: installing stays in System Settings.
public struct SoftwareUpdateTool: Tool {
    let lister: any SoftwareUpdateListing

    public var spec: ToolSpec {
        ToolSpec(name: "mac.software_updates", title: String(localized: "Look for Mac updates"),
                 description: "Look for macOS and Apple software updates for this Mac, as System Settings does. It only lists them and can take a minute; installing is in System Settings (open.app can bring it forward).",
                 inputSchema: Schema.object([:]), risk: .low, capabilities: [], category: .system, mutates: false, timeout: 150)
    }

    public func summary(for input: JSONValue) -> String { String(localized: "Look for Mac updates") }
    public func scope(for input: JSONValue) -> ToolScope { ToolScope(reach: .service("Apple")) }

    public func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let output = try await lister.list()
        let items = Self.parse(output)
        guard !items.isEmpty else {
            // Offline, managed or anything else unexpected says something else: only this means there's nothing.
            guard output.contains("No new software available") else {
                throw UserFacingError("macOS didn't give me an answer about updates. Nothing was changed.", recovery: "System Settings › General › Software Update can look.",
                                      detail: output.clipped(300))
            }
            return ToolResult(text: "This Mac has no software updates waiting.", card: ResultCard(kind: .info, title: String(localized: "This Mac is up to date")))
        }
        // "macOS 27.2", whose title already says its version, not "macOS 27.2 27.2".
        let names = items.map { item in item.version.flatMap { item.title.contains($0) ? nil : "\(item.title) \($0)" } ?? item.title }
        let restart = items.contains { $0.restart }
        return ToolResult(text: "Waiting for this Mac: \(names.joined(separator: "; "))." + (restart ? " Installing needs a restart." : "") + " They install from System Settings › General › Software Update.",
                          card: ResultCard(kind: .info, title: String(localized: "\(items.count) Mac updates waiting"), subtitle: Wording.list(items.map(\.title))))
    }

    /// `softwareupdate --list`: a "* Label:" line, then "Title: …, Version: …, Size: …, Recommended: YES, Action: restart,".
    static func parse(_ output: String) -> [SoftwareUpdateItem] {
        output.components(separatedBy: .newlines).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("Title: ") else { return nil }
            var fields: [String: String] = [:]
            for part in text.components(separatedBy: ", ") {
                let pair = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ,")) }
                if pair.count == 2 { fields[pair[0]] = pair[1] }
            }
            guard let title = fields["Title"] else { return nil }
            return SoftwareUpdateItem(title: title.displaySafe.clipped(80), version: fields["Version"]?.displaySafe.clipped(30), restart: fields["Action"] == "restart")
        }
    }

    public init(lister: any SoftwareUpdateListing) { self.lister = lister }

    /// The real command. It reaches Apple's servers by itself, which is why it can take so long.
    public struct System: SoftwareUpdateListing {
        public init() {}

        public func list() async throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["--list"]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = out
            let running = RunningProcess(process)
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    // Read while it runs: a full pipe would stop it, and it would never end.
                    DispatchQueue.global().async {
                        do {
                            try running.process.run()
                            let data = out.fileHandleForReading.readDataToEndOfFile()
                            running.process.waitUntilExit()
                            continuation.resume(returning: String(decoding: data, as: UTF8.self))
                        } catch {
                            continuation.resume(throwing: UserFacingError("I couldn't look for Mac updates. Nothing was changed.", detail: String(describing: error)))
                        }
                    }
                }
            } onCancel: {
                if running.process.isRunning { running.process.terminate() }
            }
        }

        /// `Process` isn't Sendable; this one is started once on one queue and only asked to stop elsewhere.
        private final class RunningProcess: @unchecked Sendable {
            let process: Process
            init(_ process: Process) { self.process = process }
        }
    }
}
