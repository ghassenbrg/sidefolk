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

        public init(network: Bool = false, files: Files = Files(), exec: [String] = [], media: Bool = false) {
            self.network = network
            self.files = files
            self.exec = exec
            self.media = media
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["network", "files", "exec", "media"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            network = try c.decodeIfPresent(Bool.self, forKey: "network") ?? false
            files = try c.decodeIfPresent(Files.self, forKey: "files") ?? Files()
            exec = try c.decodeIfPresent([String].self, forKey: "exec") ?? []
            media = try c.decodeIfPresent(Bool.self, forKey: "media") ?? false
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

        public init(title: String? = nil, risk: Risk? = nil, category: ToolCategory? = nil, mutates: Bool? = nil,
                    paths: [String: FolderUse] = [:], timeout: Int? = nil, ai: Bool? = nil, commands: [Command] = []) {
            self.title = title
            self.risk = risk
            self.category = category
            self.mutates = mutates
            self.paths = paths
            self.timeout = timeout
            self.ai = ai
            self.commands = commands
        }

        /// What the AI is offered: everything, unless the author said only commands reach it.
        public var offeredToModel: Bool { ai ?? true }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["title", "risk", "category", "mutates", "paths", "timeout", "ai", "commands"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            title = try c.decodeIfPresent(String.self, forKey: "title")
            risk = try c.decodeIfPresent(Risk.self, forKey: "risk")
            category = try c.decodeIfPresent(ToolCategory.self, forKey: "category")
            mutates = try c.decodeIfPresent(Bool.self, forKey: "mutates")
            paths = try c.decodeIfPresent([String: FolderUse].self, forKey: "paths") ?? [:]
            timeout = try c.decodeIfPresent(Int.self, forKey: "timeout")
            ai = try c.decodeIfPresent(Bool.self, forKey: "ai")
            commands = try c.decodeIfPresent([Command].self, forKey: "commands") ?? []
        }
    }

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
                pages: [String: PageMeta] = [:]) {
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
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(["id", "name", "version", "sidefolk", "description", "tagline", "folk", "author", "icon", "run",
                                       "permissions", "tools", "watchers", "words", "pages"])
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
