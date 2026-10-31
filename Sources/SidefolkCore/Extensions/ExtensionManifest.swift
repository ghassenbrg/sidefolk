import Foundation

/// `sidefolk-extension.json`, decoded strictly: unknown keys anywhere are an error, so a typo such as
/// `"netwrok": true` can never silently mean something else (SECURITY T13).
public struct ExtensionManifest: Sendable, Hashable, Decodable {
    public static let fileName = "sidefolk-extension.json"
    public static let maxBytes = 64 * 1024

    public var id: String
    public var name: String
    public var version: String
    /// Sidefolk versions it works with, e.g. ">=0.1".
    public var sidefolk: String?
    /// What it does, in full: Settings shows it under Details and the install preview shows it whole.
    public var description: String?
    /// One short line under its name in Settings (at most 60 characters), so a list of many stays readable.
    public var tagline: String?
    /// The folk that appears when it works.
    public var folk: String?
    public var author: String?
    /// An image inside the folder (`icon.png` or `icon.pdf`), shown wherever the extension is named.
    public var icon: String?
    public var run: Run
    public var permissions: Permissions
    public var tools: [String: ToolMeta]
    public var watchers: [String: WatcherMeta]
    /// Word lists its commands' slots can take (`{from:unit}` with `"unit": ["km", "miles", …]`) (D50).
    public var words: [String: [String]]
    /// Pages it adds to Home, drawn by Sidefolk from what `sidefolk/page.render` returns (D62).
    public var pages: [String: PageMeta]
    /// Keeps running while it is on, instead of starting for each request and stopping when idle (D63).
    public var background: Bool
    /// Pop-up lists on a keyboard shortcut, filled by `sidefolk/palette.query` (D63).
    public var palettes: [String: PaletteMeta]
    /// Games played in the Play panel beside the companion, over `sidefolk/game.*` (D75).
    public var games: [String: GameMeta]

    public struct Run: Sendable, Hashable, Decodable {
        /// `python3`, `node`, `sh`, or a program inside the folder (`bin/server`).
        public var command: String
        public var args: [String]

        public init(command: String, args: [String] = []) {
            self.command = command
            self.args = args
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["command", "args"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            command = try c.decode(String.self, forKey: "command")
            args = try c.decodeIfPresent([String].self, forKey: "args") ?? []
        }
    }

    public struct Permissions: Sendable, Hashable, Decodable {
        public var network: Bool
        public var files: Files
        /// Absolute paths of programs it may run.
        public var exec: [String]
        /// The Mac's graphics hardware and media decoders, which modern image code needs (resizing a photo,
        /// rendering a QR code). No files or network come with it.
        public var media: Bool
        /// What the person copies: reading and changing the clipboard (D63).
        public var clipboard: Bool
        /// Keeping the Mac awake and telling macOS the person is active (D63).
        public var power: Bool
        /// Recording the screen and the sound the Mac plays (ScreenCaptureKit) and compressing it to video; macOS
        /// still asks the person to allow Sidefolk in Screen Recording (D69).
        public var screen: Bool
        /// Receiving UDP, which live audio and video (WebRTC) needs; only with `network` (D69).
        public var udp: Bool
        /// What the network is for, in the author's words ("to find and stream to TVs on your local network"). The
        /// sandbox can't fence off the internet, so the sheet still says it can reach it, and adds this (D69).
        public var networkPurpose: String?

        public init(network: Bool = false, files: Files = Files(), exec: [String] = [], media: Bool = false, clipboard: Bool = false,
                    power: Bool = false, screen: Bool = false, udp: Bool = false, networkPurpose: String? = nil) {
            self.network = network
            self.networkPurpose = networkPurpose
            self.files = files
            self.exec = exec
            self.media = media
            self.clipboard = clipboard
            self.power = power
            self.screen = screen
            self.udp = udp
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["network", "files", "exec", "media", "clipboard", "power", "screen", "udp", "network_purpose"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            network = try c.decodeIfPresent(Bool.self, forKey: "network") ?? false
            files = try c.decodeIfPresent(Files.self, forKey: "files") ?? Files()
            exec = try c.decodeIfPresent([String].self, forKey: "exec") ?? []
            media = try c.decodeIfPresent(Bool.self, forKey: "media") ?? false
            clipboard = try c.decodeIfPresent(Bool.self, forKey: "clipboard") ?? false
            power = try c.decodeIfPresent(Bool.self, forKey: "power") ?? false
            screen = try c.decodeIfPresent(Bool.self, forKey: "screen") ?? false
            udp = try c.decodeIfPresent(Bool.self, forKey: "udp") ?? false
            networkPurpose = try c.decodeIfPresent(String.self, forKey: "network_purpose")
        }
    }

    public struct Files: Sendable, Hashable, Decodable {
        public var read: [String]
        public var write: [String]

        public init(read: [String] = [], write: [String] = []) {
            self.read = read
            self.write = write
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["read", "write"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            read = try c.decodeIfPresent([String].self, forKey: "read") ?? []
            write = try c.decodeIfPresent([String].self, forKey: "write") ?? []
        }
    }

    public struct ToolMeta: Sendable, Hashable, Decodable {
        public var title: String?
        /// Can raise the tool's risk above Sidefolk's floor, never lower it. Missing means medium.
        public var risk: Risk?
        public var category: ToolCategory?
        /// Whether it changes anything; missing means it might.
        public var mutates: Bool?
        /// Parameters that name a file or folder the person chooses, and what the tool does there. Guard
        /// checks each against the folders the person shared, and the sandbox opens it for that call only.
        public var paths: [String: FolderUse]
        /// Seconds one call may take, for slow work such as cloning; missing means 30.
        public var timeout: Int?
        /// Whether Sidefolk's AI may use it; missing means yes. False leaves it to its `commands` (D50), and the
        /// model never sees it, so it costs no tokens.
        public var ai: Bool?
        /// Whole sentences that call it at once, without the AI (D50).
        public var commands: [Command]
        /// `paired`: the call reaches only a device the person paired, which the program confirms before Guard
        /// decides (`sidefolk/paired.check`, D72). Honoured for Sidefolk's own extensions only.
        public var reach: Reach?
        /// With `reach`: the parameter naming the device; missing means the device in use now.
        public var device: String?

        public init(title: String? = nil, risk: Risk? = nil, category: ToolCategory? = nil, mutates: Bool? = nil,
                    paths: [String: FolderUse] = [:], timeout: Int? = nil, ai: Bool? = nil, commands: [Command] = [],
                    reach: Reach? = nil, device: String? = nil) {
            self.title = title
            self.risk = risk
            self.category = category
            self.mutates = mutates
            self.paths = paths
            self.timeout = timeout
            self.ai = ai
            self.commands = commands
            self.reach = reach
            self.device = device
        }

        /// What the AI is offered: everything, unless the author said only commands reach it.
        public var offeredToModel: Bool { ai ?? true }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["title", "risk", "category", "mutates", "paths", "timeout", "ai", "commands", "reach", "device"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            title = try c.decodeIfPresent(String.self, forKey: "title")
            risk = try c.decodeIfPresent(Risk.self, forKey: "risk")
            category = try c.decodeIfPresent(ToolCategory.self, forKey: "category")
            mutates = try c.decodeIfPresent(Bool.self, forKey: "mutates")
            paths = try c.decodeIfPresent([String: FolderUse].self, forKey: "paths") ?? [:]
            timeout = try c.decodeIfPresent(Int.self, forKey: "timeout")
            ai = try c.decodeIfPresent(Bool.self, forKey: "ai")
            commands = try c.decodeIfPresent([Command].self, forKey: "commands") ?? []
            reach = try c.decodeIfPresent(Reach.self, forKey: "reach")
            device = try c.decodeIfPresent(String.self, forKey: "device")
        }
    }

    /// Where a tool's calls go, when its program can say better than Sidefolk (D72).
    public enum Reach: String, Sendable, Hashable, Codable { case paired }

    /// What a tool does in a folder the person names in a call.
    public enum FolderUse: String, Sendable, Hashable, Codable { case read, write }

    public struct WatcherMeta: Sendable, Hashable, Decodable {
        public var title: String
        public var description: String?
        public var config: [String: ConfigField]

        public init(title: String, description: String? = nil, config: [String: ConfigField] = [:]) {
            self.title = title
            self.description = description
            self.config = config
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["title", "description", "config"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            title = try c.decode(String.self, forKey: "title")
            description = try c.decodeIfPresent(String.self, forKey: "description")
            config = try c.decodeIfPresent([String: ConfigField].self, forKey: "config") ?? [:]
        }
    }

    /// A page in Home's sidebar (D62). The extension says what is on it; Sidefolk draws it with its own parts, so a
    /// page can't look like anything else in the app (an approval card, say).
    public struct PageMeta: Sendable, Hashable, Decodable {
        public var title: String
        /// An SF Symbol for the sidebar and the Today tile, e.g. `gauge.with.dots.needle.67percent`.
        public var symbol: String?
        /// Seconds between reads while the page is open; missing means 5.
        public var refresh: Int?
        /// Also read once a minute while Sidefolk runs, so its charts reach back a day. The install preview says so.
        public var history: Bool?
        /// Its summary is also a tile on Today.
        public var widget: Bool?

        public static let refreshes = 2...3600
        public static let defaultRefresh = 5

        public init(title: String, symbol: String? = nil, refresh: Int? = nil, history: Bool? = nil, widget: Bool? = nil) {
            self.title = title
            self.symbol = symbol
            self.refresh = refresh
            self.history = history
            self.widget = widget
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["title", "symbol", "refresh", "history", "widget"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            title = try c.decode(String.self, forKey: "title")
            symbol = try c.decodeIfPresent(String.self, forKey: "symbol")
            refresh = try c.decodeIfPresent(Int.self, forKey: "refresh")
            history = try c.decodeIfPresent(Bool.self, forKey: "history")
            widget = try c.decodeIfPresent(Bool.self, forKey: "widget")
        }
    }

    /// A list that pops up over any app on a keyboard shortcut (D63): the extension fills it as the person types,
    /// and says what choosing an item does (paste it, copy it).
    public struct PaletteMeta: Sendable, Hashable, Decodable {
        public var title: String
        /// The shortcut it starts with, like `shift+cmd+v`; the person can change it.
        public var hotkey: String?
        /// The search field's hint.
        public var placeholder: String?

        public init(title: String, hotkey: String? = nil, placeholder: String? = nil) {
            self.title = title
            self.hotkey = hotkey
            self.placeholder = placeholder
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["title", "hotkey", "placeholder"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            title = try c.decode(String.self, forKey: "title")
            hotkey = try c.decodeIfPresent(String.self, forKey: "hotkey")
            placeholder = try c.decodeIfPresent(String.self, forKey: "placeholder")
        }
    }

    /// A game in the Play panel (D75): Sidefolk draws its boards from what `sidefolk/game.start` and `game.move` return.
    public struct GameMeta: Sendable, Hashable, Decodable {
        public var title: String
        /// An SF Symbol for the Play menu and the panel's header.
        public var symbol: String?
        /// Whole sentences that open it at once, without the AI ("let's play trivia").
        public var say: [String]
        /// Levels the game offers, easiest first; the person picks one on its page or in its set-up.
        public var levels: [String]
        /// Offered to Sidefolk's AI through `games.open`; missing means yes.
        public var ai: Bool?

        public init(title: String, symbol: String? = nil, say: [String] = [], levels: [String] = [], ai: Bool? = nil) {
            self.title = title
            self.symbol = symbol
            self.say = say
            self.levels = levels
            self.ai = ai
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["title", "symbol", "say", "levels", "ai"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            title = try c.decode(String.self, forKey: "title")
            symbol = try c.decodeIfPresent(String.self, forKey: "symbol")
            say = try c.decodeIfPresent([String].self, forKey: "say") ?? []
            levels = try c.decodeIfPresent([String].self, forKey: "levels") ?? []
            ai = try c.decodeIfPresent(Bool.self, forKey: "ai")
        }
    }

    /// One setting of a watcher, filled in by whoever creates the watcher.
    public struct ConfigField: Sendable, Hashable, Codable {
        public enum FieldType: String, Sendable, Hashable, Codable { case integer, number, string, boolean }
        public var type: FieldType
        public var description: String?
        public var required: Bool?
        public var `default`: JSONValue?
        public var minimum: Double?
        public var maximum: Double?

        public init(type: FieldType, description: String? = nil, required: Bool? = nil, default: JSONValue? = nil,
                    minimum: Double? = nil, maximum: Double? = nil) {
            self.type = type
            self.description = description
            self.required = required
            self.default = `default`
            self.minimum = minimum
            self.maximum = maximum
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["type", "description", "required", "default", "minimum", "maximum"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            type = try c.decode(FieldType.self, forKey: "type")
            description = try c.decodeIfPresent(String.self, forKey: "description")
            required = try c.decodeIfPresent(Bool.self, forKey: "required")
            self.default = try c.decodeIfPresent(JSONValue.self, forKey: "default")
            minimum = try c.decodeIfPresent(Double.self, forKey: "minimum")
            maximum = try c.decodeIfPresent(Double.self, forKey: "maximum")
        }
    }

    public init(id: String, name: String, version: String, sidefolk: String? = nil, description: String? = nil,
                tagline: String? = nil, folk: String? = nil, author: String? = nil, icon: String? = nil, run: Run, permissions: Permissions = Permissions(),
                tools: [String: ToolMeta] = [:], watchers: [String: WatcherMeta] = [:], words: [String: [String]] = [:],
                pages: [String: PageMeta] = [:], background: Bool = false, palettes: [String: PaletteMeta] = [:],
                games: [String: GameMeta] = [:]) {
        self.id = id
        self.name = name
        self.version = version
        self.sidefolk = sidefolk
        self.description = description
        self.tagline = tagline
        self.folk = folk
        self.author = author
        self.icon = icon
        self.run = run
        self.permissions = permissions
        self.tools = tools
        self.watchers = watchers
        self.words = words
        self.pages = pages
        self.background = background
        self.palettes = palettes
        self.games = games
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(["id", "name", "version", "sidefolk", "description", "tagline", "folk", "author", "icon", "run",
                                       "permissions", "tools", "watchers", "words", "pages", "background", "palettes", "games"])
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try c.decode(String.self, forKey: "id")
        name = try c.decode(String.self, forKey: "name")
        version = try c.decode(String.self, forKey: "version")
        sidefolk = try c.decodeIfPresent(String.self, forKey: "sidefolk")
        description = try c.decodeIfPresent(String.self, forKey: "description")
        tagline = try c.decodeIfPresent(String.self, forKey: "tagline")
        folk = try c.decodeIfPresent(String.self, forKey: "folk")
        author = try c.decodeIfPresent(String.self, forKey: "author")
        icon = try c.decodeIfPresent(String.self, forKey: "icon")
        run = try c.decode(Run.self, forKey: "run")
        permissions = try c.decodeIfPresent(Permissions.self, forKey: "permissions") ?? Permissions()
        tools = try c.decodeIfPresent([String: ToolMeta].self, forKey: "tools") ?? [:]
        watchers = try c.decodeIfPresent([String: WatcherMeta].self, forKey: "watchers") ?? [:]
        words = try c.decodeIfPresent([String: [String]].self, forKey: "words") ?? [:]
        pages = try c.decodeIfPresent([String: PageMeta].self, forKey: "pages") ?? [:]
        background = try c.decodeIfPresent(Bool.self, forKey: "background") ?? false
        palettes = try c.decodeIfPresent([String: PaletteMeta].self, forKey: "palettes") ?? [:]
        games = try c.decodeIfPresent([String: GameMeta].self, forKey: "games") ?? [:]
    }

    /// The last part of the id (`dev.sidefolk.system-vitals` → `system-vitals`), used in tool names.
    public var shortName: String { String(id.split(separator: ".").last ?? Substring(id)) }

    /// Decodes manifest bytes, turning decoding failures into a message that names the field.
    public static func decode(_ data: Data) throws(ValidationIssue) -> ExtensionManifest {
        guard data.count <= maxBytes else {
            throw ValidationIssue(field: fileName, message: "is \(data.count / 1024) KiB; the limit is 64 KiB.")
        }
        do {
            try JSONValue.checkDepth(data)
            return try JSONDecoder().decode(ExtensionManifest.self, from: data)
        } catch is JSONDepthError {
            throw ValidationIssue(field: fileName, message: "is nested more than \(JSONValue.maxDepth) levels deep.")
        } catch let error as DecodingError {
            throw ValidationIssue(decoding: error)
        } catch {
            throw ValidationIssue(field: fileName, message: "isn't valid JSON.")
        }
    }
}

/// One problem found in a manifest, named by its JSON path (`permissions.files.read[0]`).
public struct ValidationIssue: Error, Sendable, Hashable, CustomStringConvertible {
    public var field: String
    public var message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }

    init(decoding error: DecodingError) {
        func path(_ keys: [CodingKey]) -> String {
            var out = ""
            for k in keys {
                if let i = k.intValue { out += "[\(i)]" } else { out += (out.isEmpty ? "" : ".") + k.stringValue }
            }
            return out.isEmpty ? ExtensionManifest.fileName : out
        }
        switch error {
        case .keyNotFound(let key, let ctx):
            self.init(field: path(ctx.codingPath + [key]), message: "is required.")
        case .typeMismatch(let type, let ctx):
            self.init(field: path(ctx.codingPath), message: "should be \(Self.typeName(type)).")
        case .valueNotFound(let type, let ctx):
            self.init(field: path(ctx.codingPath), message: "should be \(Self.typeName(type)), not null.")
        case .dataCorrupted(let ctx):
            let isSyntax = ctx.underlyingError != nil && ctx.codingPath.isEmpty
            self.init(field: path(ctx.codingPath), message: isSyntax ? "isn't valid JSON." : ctx.debugDescription)
        @unknown default:
            self.init(field: ExtensionManifest.fileName, message: "couldn't be read.")
        }
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "a string"
        case is Bool.Type: "true or false"
        case is Double.Type, is Int.Type: "a number"
        case is [String].Type, is [Any].Type: "a list"
        default: "an object"
        }
    }

    public var description: String { "\(field) \(message)" }
}

/// A coding key for any string, so decoders can see every key and refuse unknown ones.
struct AnyKey: CodingKey, ExpressibleByStringLiteral {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
    init(stringLiteral value: String) { stringValue = value }
}

extension Decoder {
    /// Throws when the object has a key outside `allowed`.
    func rejectUnknownKeys(_ allowed: Set<String>) throws {
        let c = try container(keyedBy: AnyKey.self)
        if let unknown = c.allKeys.map(\.stringValue).filter({ !allowed.contains($0) }).sorted().first {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath + [AnyKey(stringValue: unknown)],
                                                    debugDescription: "isn't a known key."))
        }
    }
}
