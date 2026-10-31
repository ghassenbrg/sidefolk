import Foundation

/// Where an installed extension came from. Nil (not stored) means a folder the person chose, or an MCP server.
public enum ExtensionOrigin: String, Codable, Sendable, Hashable {
    /// Shipped inside Sidefolk and installed by it: first-party code, updated with the app (D39).
    case bundled
    /// Written by Sidefolk's AI for the person in the drafts folder, installed once they approved it (D39).
    case draft
    /// Sidefolk's own, from the add-on gallery: signed by Sidefolk's developer, checked, and installed once the
    /// person approved it (D55). First-party like a built-in, but theirs to remove.
    case official

    /// Sidefolk's own code: its descriptions and translated words are used, and its services trusted (D39, D47).
    public var firstParty: Bool { self == .bundled || self == .official }
}

/// What Sidefolk pinned when the user installed an extension or added an MCP server. Stored as JSON in
/// `ExtensionRecord.granted`; only the host writes it.
public struct ExtensionPin: Codable, Sendable, Hashable {
    public var name: String
    public var description: String?
    /// The manifest's one line for Settings; pins written before it have none.
    public var tagline: String?
    public var folk: String?
    public var author: String?
    public var origin: ExtensionOrigin?
    /// Sidefolk extensions: how it starts, what it may touch, and the hash of every file.
    public var launch: ExtensionLaunch?
    public var permissions: ExtensionPermissions?
    public var files: [ExtensionFilePin]
    /// Plain MCP servers: the command the user added.
    public var server: MCPServerCommand?
    /// Tool definitions the user approved, by the server's own tool name.
    public var tools: [String: MCPToolDefinition]
    /// Changed or new definitions waiting for the user; those tools can't run (quarantine).
    public var pending: [String: MCPToolDefinition]

    public init(name: String, description: String? = nil, tagline: String? = nil, folk: String? = nil, author: String? = nil, origin: ExtensionOrigin? = nil,
                launch: ExtensionLaunch? = nil, permissions: ExtensionPermissions? = nil, files: [ExtensionFilePin] = [],
                server: MCPServerCommand? = nil, tools: [String: MCPToolDefinition] = [:], pending: [String: MCPToolDefinition] = [:]) {
        self.name = name
        self.description = description
        self.tagline = tagline
        self.folk = folk
        self.author = author
        self.origin = origin
        self.launch = launch
        self.permissions = permissions
        self.files = files
        self.server = server
        self.tools = tools
        self.pending = pending
    }
}

/// A user-added MCP server: runs unsandboxed with the user's rights (SECURITY T16).
public struct MCPServerCommand: Codable, Sendable, Hashable {
    /// Absolute path, resolved when the server was added.
    public var command: String
    public var arguments: [String]
    /// Names of environment variables whose values the app supplies from the Keychain.
    public var environmentKeys: [String]

    public var commandLine: String { ([command] + arguments).joined(separator: " ") }
}

/// A page an enabled extension adds to Home (D62).
public struct ExtensionPageInfo: Sendable, Hashable, Identifiable {
    public var extensionId: String
    public var extensionName: String
    public var page: String
    public var title: String
    public var symbol: String?
    /// Seconds between reads while it is open.
    public var refresh: Int
    /// Read once a minute in the background, so its charts reach back a day.
    public var history: Bool
    /// Its summary is a tile on Today.
    public var widget: Bool
    public var iconPath: String?
    /// Its extension pastes or keeps the person active, which needs Accessibility for Sidefolk (D63).
    public var needsAccessibility: Bool
    /// The extension's one line, for its card in All Extensions (D67).
    public var tagline: String?

    public var id: String { "\(extensionId)/\(page)" }

    public init(extensionId: String, extensionName: String, page: String, title: String, symbol: String? = nil, refresh: Int = 5,
                history: Bool = false, widget: Bool = false, iconPath: String? = nil, needsAccessibility: Bool = false, tagline: String? = nil) {
        self.tagline = tagline
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.page = page
        self.title = title
        self.symbol = symbol
        self.refresh = refresh
        self.history = history
        self.widget = widget
        self.iconPath = iconPath
        self.needsAccessibility = needsAccessibility
    }
}

/// A palette an enabled extension offers on a keyboard shortcut (D63).
public struct ExtensionPaletteInfo: Sendable, Hashable, Identifiable {
    public var extensionId: String
    public var extensionName: String
    public var palette: String
    public var title: String
    public var hotkey: String?
    public var placeholder: String?
    public var iconPath: String?
    public var id: String { "\(extensionId)/\(palette)" }

    public init(extensionId: String, extensionName: String, palette: String, title: String, hotkey: String? = nil, placeholder: String? = nil,
                iconPath: String? = nil) {
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.palette = palette
        self.title = title
        self.hotkey = hotkey
        self.placeholder = placeholder
        self.iconPath = iconPath
    }
}

/// What a palette lists: `{items: [{id, title, detail, kind, pinned, actions, image, color, section}], note, preview,
/// actions}`. Every text is the extension's, cleaned and clipped; at most 200 items.
public struct ExtensionPaletteList: Sendable, Hashable {
    public struct Item: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable { case text, link, image, file, color, code }
        public var id: String
        public var title: String
        public var detail: String?
        public var kind: Kind
        public var pinned: Bool
        /// Besides choosing it: `plain`, `alternate`, `pin`, `delete`.
        public var actions: [String]
        /// A picture in the extension's data folder (`ExtensionDataFile`), drawn small.
        public var image: String?
        /// `#RRGGBB`, drawn as a swatch.
        public var color: String?
        /// A heading over this item when it differs from the item before.
        public var section: String?

        public init(id: String, title: String, detail: String? = nil, kind: Kind = .text, pinned: Bool = false, actions: [String] = [],
                    image: String? = nil, color: String? = nil, section: String? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
            self.kind = kind
            self.pinned = pinned
            self.actions = actions
            self.image = image
            self.color = color
            self.section = section
        }
    }

    public static let itemActions = ["plain", "alternate", "pin", "delete"]
    /// What the palette as a whole can do, chosen with an empty item: ⌥⌘⌫ and ⇧⌥⌘⌫.
    public static let listActions = ["clear", "clear_all"]

    public var items: [Item]
    /// One line under the list, like "Paused" or "312 items".
    public var note: String?
    /// The extension answers `sidefolk/palette.preview`: the picked item is shown in full beside the list.
    public var preview: Bool
    public var actions: [String]

    public init(items: [Item], note: String? = nil, preview: Bool = false, actions: [String] = []) {
        self.items = items
        self.note = note
        self.preview = preview
        self.actions = actions
    }

    public static func parse(_ j: JSONValue) -> ExtensionPaletteList {
        let items = (j["items"]?.arrayValue ?? []).prefix(200).compactMap { i -> Item? in
            guard let id = i["id"]?.stringValue, !id.isEmpty, id.count <= 128,
                  let raw = i["title"]?.stringValue else { return nil }
            let title = ExtensionText.line(raw, characters: 300).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            let actions = (i["actions"]?.arrayValue ?? []).compactMap(\.stringValue).filter { itemActions.contains($0) }
            return Item(id: id, title: title, detail: i["detail"]?.stringValue.map { ExtensionText.line($0, characters: 120) },
                        kind: i["kind"]?.stringValue.flatMap(Item.Kind.init(rawValue:)) ?? .text, pinned: i["pinned"]?.boolValue ?? false,
                        actions: actions, image: ExtensionPage.dataFile(i["image"]), color: ExtensionPage.color(i["color"]),
                        section: ExtensionPage.text(i["section"], 40))
        }
        return ExtensionPaletteList(items: Array(items), note: j["note"]?.stringValue.map { ExtensionText.line($0, characters: 120) },
                                    preview: j["preview"]?.boolValue ?? false,
                                    actions: (j["actions"]?.arrayValue ?? []).compactMap(\.stringValue).filter { listActions.contains($0) })
    }
}

/// The picked palette item in full (`sidefolk/palette.preview`): up to 20,000 characters of its text, a bigger picture,
/// and facts. The extension's text, cleaned, and only ever drawn.
public struct ExtensionPalettePreview: Sendable, Hashable {
    public var title: String?
    public var text: String?
    public var code: Bool
    public var image: String?
    public var facts: [ExtensionPage.Fact]

    public init(title: String? = nil, text: String? = nil, code: Bool = false, image: String? = nil, facts: [ExtensionPage.Fact] = []) {
        self.title = title
        self.text = text
        self.code = code
        self.image = image
        self.facts = facts
    }

    public static func parse(_ j: JSONValue) -> ExtensionPalettePreview? {
        let text = j["text"]?.stringValue.map { String(ExtensionText.clean($0).prefix(20_000)) }.flatMap { $0.isEmpty ? nil : $0 }
        let facts = (j["facts"]?.arrayValue ?? []).prefix(12).compactMap { f -> ExtensionPage.Fact? in
            guard let label = ExtensionPage.text(f["label"], 30), let value = ExtensionPage.text(f["value"], 300) else { return nil }
            return ExtensionPage.Fact(label: label, value: value)
        }
        let preview = ExtensionPalettePreview(title: ExtensionPage.text(j["title"], 200), text: text, code: j["code"]?.boolValue ?? false,
                                              image: ExtensionPage.dataFile(j["image"]), facts: facts)
        return preview.title == nil && text == nil && preview.image == nil && facts.isEmpty ? nil : preview
    }
}

/// What choosing a palette item did: close the palette, and paste into the app that was in front.
public struct ExtensionPaletteChoice: Sendable, Hashable {
    public var close: Bool
    public var paste: Bool
    public var message: String?

    public init(close: Bool, paste: Bool, message: String? = nil) {
        self.close = close
        self.paste = paste
        self.message = message
    }
}

/// A watcher kind an extension contributes, for the watcher engine and the "new watcher" UI.
public struct ExtensionWatcherKind: Sendable, Hashable {
    public var extensionId: String
    public var watcher: String
    public var title: String
    public var description: String
    public var config: [String: ExtensionManifest.ConfigField]

    public init(extensionId: String, watcher: String, title: String, description: String, config: [String: ExtensionManifest.ConfigField]) {
        self.extensionId = extensionId
        self.watcher = watcher
        self.title = title
        self.description = description
        self.config = config
    }
}

public struct ExtensionToolInfo: Sendable, Hashable {
    /// Name in the tool registry, e.g. `ext.system-vitals.battery`.
    public var name: String
    public var title: String
    public var risk: Risk
    /// Changed or new since the user approved it; it can't run until approved.
    public var quarantined: Bool
    /// Sentences that call it without the AI, as people see them ("time in …") (D50).
    public var commands: [String] = []
    /// Offered to Sidefolk's AI; false when its author left it to its commands.
    public var forAI = true
}

/// Everything Settings › Extensions shows for one installed extension or MCP server.
public struct ExtensionInfo: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var version: String
    public var kind: ExtensionRecord.Kind
    public var enabled: Bool
    public var running: Bool
    public var lastError: String?
    public var description: String?
    /// One line under its name: the manifest's tagline, or the description's first sentence when it has none.
    public var tagline: String? = nil
    public var folk: String?
    public var author: String?
    public var origin: ExtensionOrigin?
    /// The installed copy's icon file, checked at install and on every load; nil means the default tile.
    public var iconPath: String?
    public var summary: PermissionSummary
    /// For MCP servers, the command line as added.
    public var command: String?
    public var tools: [ExtensionToolInfo]
    public var watchers: [ExtensionWatcherKind]
    /// Where the manifest's `tools` and the program's `tools/list` disagree (a typo, a forgotten entry).
    public var toolWarnings: [String] = []
    /// The extension that does all this one does and is on, so this one rests (D67): its name.
    public var restingFor: String? = nil

    public var hasPendingToolChanges: Bool { tools.contains(where: \.quarantined) }
}

/// What installing a folder would do, for the install sheet. `update` is set when an older version is
/// installed: the sheet shows what it gains and loses.
public struct InstallPreview: Sendable {
    public var report: ValidationReport
    public var update: ExtensionUpdateDiff?
    /// Why it can't be installed even though the manifest is valid (an id or name already in use).
    public var conflict: String?

    public var canInstall: Bool { report.isValid && conflict == nil }
}

public struct ExtensionUpdateDiff: Sendable, Hashable {
    public var fromVersion: String
    public var toVersion: String
    public var addedPermissions: [String]
    public var removedPermissions: [String]
    public var addedTools: [String]
    public var removedTools: [String]

    public var changesPermissions: Bool { !addedPermissions.isEmpty || !removedPermissions.isEmpty }
}

/// What adding an MCP server would do, for the confirmation sheet.
public struct MCPServerPreview: Sendable, Hashable {
    public var id: String
    public var name: String
    public var resolvedCommand: String?
    public var arguments: [String]
    public var summary: PermissionSummary
    public var errors: [String]

    public var canAdd: Bool { errors.isEmpty && resolvedCommand != nil }
}

/// The one line Settings shows under an extension's name (D39, amended 2026-10-28): its tagline, or the first sentence
/// of its description for one written before taglines, so a long description never runs off the row.
public enum ExtensionTagline {
    public static func line(tagline: String?, description: String?) -> String {
        if let tagline = tagline?.trimmingCharacters(in: .whitespacesAndNewlines), !tagline.isEmpty { return tagline }
        guard let text = description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "" }
        // The system's sentences, so a number like 3.5 doesn't end one.
        var first: String?
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, stop in
            first = sentence?.trimmingCharacters(in: .whitespacesAndNewlines)
            stop = true
        }
        return first.flatMap { $0.isEmpty ? nil : $0 } ?? text
    }
}
