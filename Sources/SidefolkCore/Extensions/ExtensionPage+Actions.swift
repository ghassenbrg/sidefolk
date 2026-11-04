import Foundation

/// What a page's control may do other than run a tool (D105). None of these changes anything of the person's, so none needs a
/// tool: moving around a page and holding a draft aren't things to audit, and a click on a tool still goes through Guard.
public enum PageAct: Sendable, Hashable {
    /// Changes the page's state and draws it again.
    case go(PageGo)
    /// Words the person can see, onto the clipboard on their click.
    case copy(String)
    /// The system's open panel, then a tool of its own with the file the person chose.
    case file(PageFileAsk)
    /// The system's open panel, then Sidefolk's own drop card for what was chosen: the person picks there, as for a drop.
    case dropCard
    /// Asks the person, in Sidefolk's words, to let this extension have something (D106, D107).
    case allow(PageConsent)
    /// Asks the person, in Sidefolk's words, to share the folder a path is in with Sidefolk (D180).
    case share(PageShareAsk)
    /// One of Sidefolk's or the Mac's settings panes.
    case settings(PageSettingsPane)
    /// Opens one of this extension's own palettes, as its shortcut does. The button shows that shortcut.
    case palette(String)
    /// Reads the page again now.
    case refresh

    /// The control's own: `go`, `copy`, `file`, `allow`, `share` or `settings`. Exactly one, or it isn't drawn as one.
    static func parse(_ j: JSONValue) -> PageAct? {
        if let go = PageGo.parse(j["go"]) { return .go(go) }
        if let words = j["copy"]?.stringValue, !words.isEmpty { return .copy(String(ExtensionText.clean(words).prefix(60_000))) }
        if let file = PageFileAsk.parse(j["file"]) { return .file(file) }
        if j["drop_card"]?.boolValue == true { return .dropCard }
        if let consent = j["allow"]?.stringValue.flatMap(PageConsent.init(rawValue:)) { return .allow(consent) }
        if let share = PageShareAsk.parse(j["share"]) { return .share(share) }
        if let pane = j["settings"]?.stringValue.flatMap(PageSettingsPane.init(rawValue:)) { return .settings(pane) }
        if let palette = j["palette"]?.stringValue, palette.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil { return .palette(palette) }
        if j["refresh"]?.boolValue == true { return .refresh }
        return nil
    }
}

/// `{"set": {…}, "push": true}` or `{"back": true}`.
public struct PageGo: Sendable, Hashable {
    /// Merged into the state; null takes a key out.
    public var set: [String: JSONValue]
    /// Keeps the state from before this on the back stack.
    public var push: Bool
    /// Goes back to the state on top of the stack instead.
    public var back: Bool

    public init(set: [String: JSONValue] = [:], push: Bool = false, back: Bool = false) {
        self.set = set
        self.push = push
        self.back = back
    }

    static func parse(_ j: JSONValue?) -> PageGo? {
        guard let j, j.objectValue != nil else { return nil }
        return PageGo(set: j["set"]?.objectValue ?? [:], push: j["push"]?.boolValue ?? false, back: j["back"]?.boolValue ?? false)
    }
}

public struct PageFileAsk: Sendable, Hashable {
    public var tool: String
    /// Which of the tool's parameters takes the path. Guard reads it from the manifest's `paths`, as for any tool.
    public var param: String
    /// File name extensions the panel offers.
    public var types: [String]
    public var input: JSONValue

    static func parse(_ j: JSONValue?) -> PageFileAsk? {
        guard let j, let tool = ExtensionPage.toolName(j["tool"]), let param = j["param"]?.stringValue,
              param.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil,
              let input = ExtensionPage.smallInput(j["input"]) else { return nil }
        let types = (j["types"]?.arrayValue ?? []).prefix(8).compactMap { $0.stringValue }.filter { $0.range(of: #"^[a-z0-9]{1,12}$"#, options: .regularExpression) != nil }
        return PageFileAsk(tool: tool, param: param, types: Array(types), input: input)
    }
}

/// `{"path": "~/ws/report.txt", "write": false}`. The extension names a path; Sidefolk works out the folder, says it, and the person answers.
public struct PageShareAsk: Sendable, Hashable {
    public var path: String
    public var write: Bool

    public init(path: String, write: Bool = false) {
        self.path = path
        self.write = write
    }

    /// The folder as the question says it: a name on disk, kept to one short line.
    public static func shown(_ folder: String) -> String { FolderAccess.displayPath(folder).displaySafe.clipped(120) }

    /// The folder to ask about, or why there's nothing to ask.
    public func folder() -> Result<String, UserFacingError> {
        let path = (path as NSString).expandingTildeInPath
        if let why = FolderAccess.forbiddenReason([path]) { return .failure(UserFacingError(verbatim: why)) }
        guard let folder = FolderAccess.suggestedFolder(for: path) else {
            return .failure(UserFacingError("That location is too broad to share. Add a specific folder in Settings › Trust."))
        }
        // Only what's really there gets a question: the extension wrote this path, and it shows in Sidefolk's own words.
        guard FileFacts.read(folder)?.isDirectory == true else { return .failure(UserFacingError("That folder isn't there.")) }
        return .success(folder)
    }

    static func parse(_ j: JSONValue?) -> PageShareAsk? {
        guard let j, let path = j["path"]?.stringValue, !path.isEmpty, path.utf8.count <= 1024 else { return nil }
        return PageShareAsk(path: path, write: j["write"]?.boolValue ?? false)
    }
}

public enum PageConsent: String, Sendable, Hashable { case place, schedule }

public enum PageSettingsPane: String, Sendable, Hashable { case notifications, attention, place }

/// A page's state while Home is open (D105): what it was told to remember, and the states Back returns to. The program gets it with
/// each reading and keeps nothing of it, so it holds what is on screen (a tab, a draft), never anything that must last.
public struct PageState: Sendable, Hashable {
    public static let maxBytes = 4096
    public static let maxStack = 16

    public private(set) var values: [String: JSONValue]
    public private(set) var stack: [[String: JSONValue]] = []

    public init(_ values: [String: JSONValue] = [:]) { self.values = values }

    public var json: JSONValue { .object(values) }
    public var canGoBack: Bool { !stack.isEmpty }

    /// Whether it changed. State that wouldn't fit is refused whole, so a page never reads half of what it was told.
    @discardableResult
    public mutating func apply(_ go: PageGo) -> Bool {
        if go.back {
            guard let last = stack.popLast() else { return false }
            values = last
            return true
        }
        var next = values
        for (key, value) in go.set {
            if case .null = value { next[key] = nil } else { next[key] = value }
        }
        guard JSONValue.object(next).jsonString.utf8.count <= Self.maxBytes else { return false }
        if go.push {
            stack.append(values)
            if stack.count > Self.maxStack { stack.removeFirst() }
        }
        let changed = next != values || go.push
        values = next
        return changed
    }
}

/// How a page dresses itself (D108): its ground, the cards on it and, behind them, a picture from the pack. Always a pair, so its ink,
/// controls and focus rings, which stay the theme's, read the way they do everywhere in that appearance.
public struct PageDress: Sendable, Hashable {
    public struct Pair: Sendable, Hashable {
        public var light: String
        public var dark: String

        static func parse(_ j: JSONValue?) -> Pair? {
            guard let light = ExtensionPage.color(j?["light"]), let dark = ExtensionPage.color(j?["dark"]) else { return nil }
            return Pair(light: light, dark: dark)
        }

        /// Can the theme's ink be read on it? Text and controls stay the theme's, so a dark "light" colour would hide them. Near-white for
        /// light, near-black for dark, whatever the hue.
        /// At or below `holdsWhite`, for each appearance.
        public var lightHoldsWhite: Bool { Self.luminance(light) <= Self.holdsWhite }
        public var darkHoldsWhite: Bool { Self.luminance(dark) <= Self.holdsWhite }

        /// A colour that fills what's on or picked, seen against what it stands on: holding white, or at 3:1, in each appearance. White on a white card would hide whether a switch is on.
        func shows(on ground: Pair) -> Bool {
            func contrast(_ a: String, _ b: String) -> Double {
                let la = Self.luminance(a), lb = Self.luminance(b)
                return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
            }
            return (lightHoldsWhite || contrast(light, ground.light) >= 3) && (darkHoldsWhite || contrast(dark, ground.dark) >= 3)
        }

        var readable: Bool { Self.luminance(light) >= 0.6 && Self.luminance(dark) <= 0.12 }

        /// At or below this, white words read at 4.5:1.
        static let holdsWhite = 0.183

        static func luminance(_ hex: String) -> Double {
            guard let value = UInt32(hex.dropFirst(), radix: 16) else { return 0.5 }
            func channel(_ shift: UInt32) -> Double {
                let c = Double((value >> shift) & 0xFF) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
    }

    public var ground: Pair
    public var card: Pair?
    public var line: Pair?
    /// Filled buttons and switches on this page. Too light to hold white words, it holds near-black ones.
    public var accent: Pair?
    /// What's selected on this page, and the soft tint under it.
    public var selected: Pair?
    /// Soft wells on this page's cards: a neutral note, a bar's track.
    public var well: Pair?
    public var picture: PagePicture?
    /// The picture repeats rather than filling the page.
    public var tile = false

    static func parse(_ j: JSONValue?) -> PageDress? {
        guard let ground = Pair.parse(j?["ground"]), ground.readable else { return nil }
        let card = Pair.parse(j?["card"]).flatMap { $0.readable ? $0 : nil }
        return PageDress(ground: ground, card: card, line: Pair.parse(j?["line"]), accent: Pair.parse(j?["accent"]).flatMap { $0.shows(on: card ?? ground) ? $0 : nil },
                         selected: Pair.parse(j?["selected"]).flatMap { $0.shows(on: card ?? ground) ? $0 : nil }, well: Pair.parse(j?["well"]).flatMap { $0.readable ? $0 : nil }, picture: PagePicture.parse(j?["picture"]),
                         tile: j?["picture"]?["tile"]?.boolValue ?? false)
    }
}

/// What a reply's `open_page` asks of a page: where it goes, with what it should show (D105).
public struct PageMove: Sendable, Hashable {
    public var page: String
    public var state: [String: JSONValue]?
    public var push: Bool

    public init(page: String, state: [String: JSONValue]? = nil, push: Bool = false) {
        self.page = page
        self.state = state
        self.push = push
    }

    /// A name alone, or `{"page", "state", "push"}`.
    static func parse(_ j: JSONValue?) -> PageMove? {
        if let name = j?.stringValue { return PageMove(page: name) }
        guard let j, let name = j["page"]?.stringValue else { return nil }
        let state = j["state"]?.objectValue
        guard JSONValue.object(state ?? [:]).jsonString.utf8.count <= PageState.maxBytes else { return PageMove(page: name) }
        return PageMove(page: name, state: state, push: j["push"]?.boolValue ?? false)
    }

    public var go: PageGo? { state.map { PageGo(set: $0, push: push) } }
}

extension ExtensionPage {
    /// A key that runs one of the extension's tools as the person, through Guard, while its page is showing. From a short list, so a page can't take the keys that close
    /// a window or quit, or hear what's typed. Each is what it is everywhere on a Mac.
    public struct Shortcut: Sendable, Hashable {
        public enum Key: String, Sendable, Hashable, CaseIterable {
            case save = "cmd+s", undo = "cmd+z", redo = "shift+cmd+z", duplicate = "cmd+d", run = "cmd+return", find = "cmd+f"

            /// While text is being typed these are the field's own.
            public var belongsToText: Bool { self == .undo || self == .redo }
        }

        public var key: Key
        /// What it does, for the page's list of keys and VoiceOver.
        public var label: String
        public var tool: String
        public var input: JSONValue

        static func parse(_ j: JSONValue) -> Shortcut? {
            guard let key = j["key"]?.stringValue.flatMap(Key.init(rawValue:)), let label = text(j["label"], 40), let tool = toolName(j["tool"]), let input = smallInput(j["input"]) else { return nil }
            return Shortcut(key: key, label: label, tool: tool, input: input)
        }
    }
}
