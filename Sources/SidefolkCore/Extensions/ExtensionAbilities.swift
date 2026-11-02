import Foundation
import Synchronization

/// What the host keeps for one extension (D100), in the database so a backup carries it and an uninstall removes it: its
/// settings' values, the person's switch for its use of the AI and how many requests it made today, and which sections of
/// Sidefolk's own settings it has already received. Nothing here is the extension's to write.
public struct ExtensionPreferences: Codable, Sendable, Equatable {
    public var values: [String: JSONValue] = [:]
    /// Nil is on: the person saw `permissions.ai` on the install sheet.
    public var aiOn: Bool?
    public var aiDay: String?
    public var aiCalls = 0
    public var carried: [String] = []
    /// The frame's speaker, by surface, when it isn't one of its settings. Goes with the extension.
    public var speakers: [String: Bool] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        values = (try? c.decode([String: JSONValue].self, forKey: .values)) ?? [:]
        aiOn = try? c.decodeIfPresent(Bool.self, forKey: .aiOn)
        aiDay = try? c.decodeIfPresent(String.self, forKey: .aiDay)
        aiCalls = (try? c.decode(Int.self, forKey: .aiCalls)) ?? 0
        carried = (try? c.decode([String].self, forKey: .carried)) ?? []
        speakers = (try? c.decode([String: Bool].self, forKey: .speakers)) ?? [:]
    }

    static func key(_ id: String) -> String { "extension.preferences.\(id)" }

    /// Requests made on `day`: yesterday's don't count.
    func calls(on day: String) -> Int { aiDay == day ? aiCalls : 0 }

    /// What each declared setting holds now: its value, or its default for one never changed or no longer valid.
    func resolved(_ settings: [ExtensionManifest.SettingMeta]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for s in settings { out[s.key] = s.checked(values[s.key]) ?? s.fallback }
        return out
    }
}

/// A setting as it is shown: its words in the person's language and what it holds now (D100).
public struct ExtensionSettingRow: Sendable, Hashable, Identifiable {
    public struct Option: Sendable, Hashable {
        public var value: String
        public var title: String

        public init(value: String, title: String) {
            self.value = value
            self.title = title
        }
    }

    public var extensionId: String
    public var key: String
    public var type: ExtensionManifest.SettingMeta.Kind
    public var title: String
    public var detail: String?
    public var options: [Option]
    public var minimum: Double?
    public var maximum: Double?
    public var step: Double?
    public var length: Int
    public var value: JSONValue

    public var id: String { "\(extensionId)/\(key)" }
    /// The tool every change goes through (`ExtensionSettingTool`).
    public static let tool = "extensions.setting"

    public init(extensionId: String, key: String, type: ExtensionManifest.SettingMeta.Kind, title: String, detail: String? = nil,
                options: [Option] = [], minimum: Double? = nil, maximum: Double? = nil, step: Double? = nil, length: Int = 200, value: JSONValue) {
        self.extensionId = extensionId
        self.key = key
        self.type = type
        self.title = title
        self.detail = detail
        self.options = options
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.length = length
        self.value = value
    }

    /// What Settings' search reads of it.
    public var searchEntry: SettingsSearch.Entry {
        SettingsSearch.Entry(id: id, title: title, detail: detail ?? "", section: options.map(\.title).joined(separator: " "))
    }

    /// The value in words, for History and a search: the option's title, on or off, the number, the text.
    public var valueWords: String {
        switch value {
        case .bool(let on): on ? String(localized: "On", comment: "An extension's setting: a switch that is on")
            : String(localized: "Off", comment: "An extension's setting: a switch that is off")
        case .string(let s): options.first { $0.value == s }?.title ?? s
        case .number(let n): n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        default: ""
        }
    }
}

/// An extension's use of the person's AI, for its row in Settings and its page (D100).
public struct ExtensionAIStatus: Sendable, Hashable {
    public var purpose: String
    public var dailyCap: Int
    public var usedToday: Int
    /// The person's switch.
    public var on: Bool
    /// Why nothing will be asked for now, whatever the switch says.
    public var heldBack: String?

    public init(purpose: String, dailyCap: Int, usedToday: Int, on: Bool, heldBack: String? = nil) {
        self.purpose = purpose
        self.dailyCap = dailyCap
        self.usedToday = usedToday
        self.on = on
        self.heldBack = heldBack
    }
}

/// An item an extension put in Sidefolk's menus or Ask's tabs (D100). It lives as long as the extension is on: uninstalling
/// takes it away, because it is read from the extension's manifest every time, never copied anywhere.
public struct ExtensionEntry: Sendable, Hashable, Identifiable {
    public enum Action: Sendable, Hashable {
        /// One of its own tools, run as the person, through Guard.
        case tool(name: String, input: JSONValue)
        /// One of its own pages in Home.
        case page(String)
        /// One of its own surfaces, opened through `surfaces.open` as the person.
        case surface(id: String, arguments: JSONValue)
        /// A submenu of `items`.
        case menu
    }

    public var extensionId: String
    public var extensionName: String
    public var key: String
    public var title: String
    public var symbol: String?
    public var places: [ExtensionManifest.EntryMeta.Place]
    public var action: Action
    public var items: [ExtensionEntry]
    /// One of Sidefolk's own extensions: anyone else's item carries its name, so it can't pass for Sidefolk's.
    public var firstParty: Bool

    public var id: String { "\(extensionId)/\(key)" }

    public init(extensionId: String, extensionName: String, key: String, title: String, symbol: String? = nil,
                places: [ExtensionManifest.EntryMeta.Place] = [], action: Action, items: [ExtensionEntry] = [], firstParty: Bool = false) {
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.key = key
        self.title = title
        self.symbol = symbol
        self.places = places
        self.action = action
        self.items = items
        self.firstParty = firstParty
    }

    /// As a menu shows it.
    public var shownTitle: String { firstParty ? title : "\(title) (\(extensionName))" }
}

/// What an extension offers to do with something dropped on the companion (D100).
public struct ExtensionDropAction: Sendable, Hashable, Identifiable {
    public var extensionId: String
    public var extensionName: String
    public var key: String
    public var title: String
    public var detail: String?
    public var symbol: String?
    public var kinds: [ExtensionManifest.DropMeta.Kind]
    public var patterns: [String]
    /// The tool's name in the registry.
    public var tool: String
    public var input: [String: JSONValue]

    public var id: String { "\(extensionId)/\(key)" }

    public init(extensionId: String, extensionName: String, key: String, title: String, detail: String? = nil, symbol: String? = nil,
                kinds: [ExtensionManifest.DropMeta.Kind], patterns: [String] = [], tool: String, input: [String: JSONValue]) {
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.key = key
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.kinds = kinds
        self.patterns = patterns
        self.tool = tool
        self.input = input
    }

    /// Whether it applies to what was dropped: its kind, and a pattern for the link's address (without its query) or the file's
    /// name. No pattern means anything of that kind.
    public func matches(kind: ExtensionManifest.DropMeta.Kind, value: String) -> Bool {
        guard kinds.contains(kind) else { return false }
        guard !patterns.isEmpty else { return true }
        let subject: String
        switch kind {
        case .link:
            guard var parts = URLComponents(string: value) else { return false }
            parts.query = nil
            parts.fragment = nil
            guard parts.host?.isEmpty == false else { return false }
            subject = parts.string ?? value
        case .file, .folder:
            subject = (value as NSString).lastPathComponent
        case .text:
            subject = value
        }
        return patterns.contains { Self.glob($0, matches: subject) }
    }

    /// The tool's arguments, with what was dropped in place of `{value}`.
    public func input(for value: String) -> JSONValue {
        .object(input.mapValues { $0 == .string("{value}") ? .string(value) : $0 })
    }

    /// `*` any run of characters and `?` one, ignoring case. By hand, in linear-ish time: an author's pattern never becomes a
    /// regular expression a dropped link could make slow.
    static func glob(_ pattern: String, matches text: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(text.lowercased())
        var i = 0, j = 0, star = -1, mark = 0
        while j < t.count {
            if i < p.count, p[i] == "?" || p[i] == t[j] {
                i += 1
                j += 1
            } else if i < p.count, p[i] == "*" {
                star = i
                mark = j
                i += 1
            } else if star >= 0 {
                i = star + 1
                mark += 1
                j = mark
            } else {
                return false
            }
        }
        while i < p.count, p[i] == "*" { i += 1 }
        return i == p.count
    }
}

/// What switched-on extensions put in Sidefolk's menus and offer for drops, readable without waiting on the host: menus are
/// built on the spot.
public final class ExtensionShelf: Sendable {
    private let state = Mutex<(entries: [ExtensionEntry], drops: [ExtensionDropAction], settings: [ExtensionSettingRow], names: [String: String])>(([], [], [], [:]))

    public init() {}

    public var entries: [ExtensionEntry] { state.withLock { $0.entries } }
    public var drops: [ExtensionDropAction] { state.withLock { $0.drops } }
    /// Every setting of every extension that is on, as Settings' search and the tools word them.
    public var settings: [ExtensionSettingRow] { state.withLock { $0.settings } }

    /// Every extension that is on, by id, in the person's language: for History's rows.
    public var names: [String: String] { state.withLock { $0.names } }

    public func entries(in place: ExtensionManifest.EntryMeta.Place) -> [ExtensionEntry] { entries.filter { $0.places.contains(place) } }

    func set(entries: [ExtensionEntry], drops: [ExtensionDropAction], settings: [ExtensionSettingRow], names: [String: String]) {
        state.withLock { $0 = (entries, drops, settings, names) }
    }
}
