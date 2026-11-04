import Foundation

// What an extension declares beyond tools and pages (D100): settings the host keeps for it, entries in Sidefolk's menus,
// drop actions, its use of the person's AI, and the words its commands are built from. All of it is data: Sidefolk draws
// it, keeps it and removes it with the extension, and none of it reaches a model.
extension ExtensionManifest {
    /// One setting: the host stores its value per extension, passes it with every request, and draws its row.
    public struct SettingMeta: Sendable, Hashable, Decodable {
        public enum Kind: String, Sendable, Hashable, Codable { case `switch`, choice, number, text }

        public struct Option: Sendable, Hashable, Decodable {
            public var value: String
            public var title: String

            public init(value: String, title: String) {
                self.value = value
                self.title = title
            }

            public init(from decoder: Decoder) throws {
                try decoder.rejectUnknownKeys(["value", "title"])
                let c = try decoder.container(keyedBy: AnyKey.self)
                value = try c.decode(String.self, forKey: "value")
                title = try c.decode(String.self, forKey: "title")
            }
        }

        public var key: String
        public var type: Kind
        public var title: String
        public var detail: String?
        /// A choice's options, in the order they are shown.
        public var options: [Option]
        public var minimum: Double?
        public var maximum: Double?
        public var step: Double?
        /// A text's longest value; missing means 200 characters.
        public var length: Int?
        /// Missing means off, the first option, the minimum, or empty.
        public var `default`: JSONValue?
        /// False: kept and passed like any other, but shown only where the extension names it (a `settings` part's `keys`, the frame's
        /// speaker), not under Settings › Add-ons or in its search. For what an extension holds per thing it has many of.
        public var listed: Bool
        /// Another setting this one reads until it has a value of its own; a change to that one clears the value (one choice for all, and a change for one thing).
        public var follows: String?
        /// A choice of a few short options, all shown side by side rather than behind a menu (D101).
        public var segmented: Bool

        public static let longestText = 500

        public init(key: String, type: Kind, title: String, detail: String? = nil, options: [Option] = [], minimum: Double? = nil,
                    maximum: Double? = nil, step: Double? = nil, length: Int? = nil, default: JSONValue? = nil, listed: Bool = true, follows: String? = nil, segmented: Bool = false) {
            self.segmented = segmented
            self.listed = listed
            self.follows = follows
            self.key = key
            self.type = type
            self.title = title
            self.detail = detail
            self.options = options
            self.minimum = minimum
            self.maximum = maximum
            self.step = step
            self.length = length
            self.default = `default`
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["key", "type", "title", "detail", "options", "minimum", "maximum", "step", "length", "default", "listed", "follows", "segmented"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            key = try c.decode(String.self, forKey: "key")
            type = try c.decode(Kind.self, forKey: "type")
            title = try c.decode(String.self, forKey: "title")
            detail = try c.decodeIfPresent(String.self, forKey: "detail")
            options = try c.decodeIfPresent([Option].self, forKey: "options") ?? []
            minimum = try c.decodeIfPresent(Double.self, forKey: "minimum")
            maximum = try c.decodeIfPresent(Double.self, forKey: "maximum")
            step = try c.decodeIfPresent(Double.self, forKey: "step")
            length = try c.decodeIfPresent(Int.self, forKey: "length")
            self.default = try c.decodeIfPresent(JSONValue.self, forKey: "default")
            listed = try c.decodeIfPresent(Bool.self, forKey: "listed") ?? true
            follows = try c.decodeIfPresent(String.self, forKey: "follows")
            segmented = try c.decodeIfPresent(Bool.self, forKey: "segmented") ?? false
        }

        /// What it holds until the person changes it.
        public var fallback: JSONValue {
            if let value = checked(`default`) { return value }
            switch type {
            case .switch: return .bool(false)
            case .choice: return .string(options.first?.value ?? "")
            case .number: return .number(minimum ?? 0)
            case .text: return .string("")
            }
        }

        /// `value` as this setting holds it, or nil when it isn't one: a number within its bounds, a choice it has, one
        /// line of text within its length. A step snaps the number, so what is stored is what the row shows.
        public func checked(_ value: JSONValue?) -> JSONValue? {
            switch (type, value) {
            case (.switch, .bool(let on)?): return .bool(on)
            case (.choice, .string(let s)?): return options.contains { $0.value == s } ? .string(s) : nil
            case (.number, .number(let n)?):
                guard n.isFinite, n >= (minimum ?? -.infinity), n <= (maximum ?? .infinity) else { return nil }
                guard let step, step > 0 else { return .number(n) }
                let from = minimum ?? 0
                return .number(Swift.min(from + ((n - from) / step).rounded() * step, maximum ?? .infinity))
            case (.text, .string(let s)?):
                // Bytes as well as characters: marks stack without limit on one character, and each value is a row in History.
                let most = length ?? 200
                guard s.count <= most, s.utf8.count <= most * 8, ExtensionText.clean(s) == s, !s.contains(where: \.isNewline) else { return nil }
                return .string(s)
            default: return nil
            }
        }
    }

    /// An item in Sidefolk's menus, or a tab in Ask (D100): what it says, and the extension's own page or tool it opens,
    /// run as the person through Guard. A top-level entry names its `places`; `items` makes it a submenu.
    public struct EntryMeta: Sendable, Hashable, Decodable {
        public enum Place: String, Sendable, Hashable, Codable, CaseIterable { case companion, pocket, ask }

        public var id: String
        public var title: String
        public var symbol: String?
        public var places: [Place]
        public var tool: String?
        public var input: [String: JSONValue]?
        public var page: String?
        /// What the page shows when this opens it (D105).
        public var state: [String: JSONValue]?
        /// One of its surfaces, opened as the person's own click opens it; `input` is what it starts with.
        public var surface: String?
        public var items: [EntryMeta]

        public init(id: String, title: String, symbol: String? = nil, places: [Place] = [], tool: String? = nil, input: [String: JSONValue]? = nil,
                    page: String? = nil, state: [String: JSONValue]? = nil, surface: String? = nil, items: [EntryMeta] = []) {
            self.state = state
            self.id = id
            self.title = title
            self.symbol = symbol
            self.places = places
            self.tool = tool
            self.input = input
            self.page = page
            self.surface = surface
            self.items = items
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["id", "title", "symbol", "places", "tool", "input", "page", "state", "surface", "items"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            id = try c.decode(String.self, forKey: "id")
            title = try c.decode(String.self, forKey: "title")
            symbol = try c.decodeIfPresent(String.self, forKey: "symbol")
            places = try c.decodeIfPresent([Place].self, forKey: "places") ?? []
            tool = try c.decodeIfPresent(String.self, forKey: "tool")
            input = try c.decodeIfPresent([String: JSONValue].self, forKey: "input")
            page = try c.decodeIfPresent(String.self, forKey: "page")
            surface = try c.decodeIfPresent(String.self, forKey: "surface")
            items = try c.decodeIfPresent([EntryMeta].self, forKey: "items") ?? []
        }
    }

    /// A thing an extension offers to do with what is dropped on the companion (D100): which kinds, which links or file
    /// names, and its own tool, run through Guard with the dropped thing as `{value}` in `input`.
    public struct DropMeta: Sendable, Hashable, Decodable {
        public enum Kind: String, Sendable, Hashable, Codable, CaseIterable { case file, folder, link, text }

        public var id: String
        public var title: String
        public var detail: String?
        public var symbol: String?
        public var kinds: [Kind]
        /// Globs (`*` and `?`), ignoring case: a link's address without its query, or a file's name.
        public var patterns: [String]
        public var tool: String
        public var input: [String: JSONValue]
        /// More choices in one menu on the same card, since what was dropped is only readable for the one call a choice makes (D141).
        public var menu: [MenuItem] = []
        /// What it makes, in a few letters on the card ("JPEG"): the format's name, so it needs no translation (D150).
        public var tag: String?
        /// A picture from its pack for the small sheet when a file has no colourful picture of its own (D150).
        public var mark: String?
        /// What the card's menu is called ("Another format"), in place of Sidefolk's own "Another choice".
        public var menuTitle: String?

        public struct MenuItem: Sendable, Hashable, Decodable {
            public var title: String
            public var input: [String: JSONValue]
            /// A format's name for the ring, as a drop's `tag`, and one plain line of what it's for.
            public var tag: String?
            public var detail: String?
            /// Names this choice is pointless for, like the format the file is already in. Globs, as `patterns`.
            public var skip: [String] = []

            public init(title: String, input: [String: JSONValue], tag: String? = nil, detail: String? = nil, skip: [String] = []) {
                self.title = title
                self.input = input
                self.tag = tag
                self.detail = detail
                self.skip = skip
            }

            public init(from decoder: Decoder) throws {
                try decoder.rejectUnknownKeys(["title", "input", "tag", "detail", "skip"])
                let c = try decoder.container(keyedBy: AnyKey.self)
                title = try c.decode(String.self, forKey: "title")
                input = try c.decode([String: JSONValue].self, forKey: "input")
                tag = try c.decodeIfPresent(String.self, forKey: "tag")
                detail = try c.decodeIfPresent(String.self, forKey: "detail")
                skip = try c.decodeIfPresent([String].self, forKey: "skip") ?? []
            }
        }

        public init(id: String, title: String, detail: String? = nil, symbol: String? = nil, kinds: [Kind], patterns: [String] = [], tool: String,
                    input: [String: JSONValue]) {
            self.id = id
            self.title = title
            self.detail = detail
            self.symbol = symbol
            self.kinds = kinds
            self.patterns = patterns
            self.tool = tool
            self.input = input
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["id", "title", "detail", "symbol", "kinds", "patterns", "tool", "input", "menu", "tag", "mark", "menu_title"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            id = try c.decode(String.self, forKey: "id")
            title = try c.decode(String.self, forKey: "title")
            detail = try c.decodeIfPresent(String.self, forKey: "detail")
            symbol = try c.decodeIfPresent(String.self, forKey: "symbol")
            kinds = try c.decode([Kind].self, forKey: "kinds")
            patterns = try c.decodeIfPresent([String].self, forKey: "patterns") ?? []
            tool = try c.decode(String.self, forKey: "tool")
            input = try c.decode([String: JSONValue].self, forKey: "input")
            tag = try c.decodeIfPresent(String.self, forKey: "tag")
            mark = try c.decodeIfPresent(String.self, forKey: "mark")
            menuTitle = try c.decodeIfPresent(String.self, forKey: "menu_title")
            menu = try c.decodeIfPresent([MenuItem].self, forKey: "menu") ?? []
        }
    }

    /// `permissions.ai` (D100): the extension may ask the person's AI to write something, for this purpose and at most this
    /// many times a day. It gets words back and nothing else: no tools, none of the person's data.
    /// `{"purpose": "to show the weather where you are"}`, what the person is told it is for (D106, D107).
    public struct PurposeMeta: Sendable, Hashable, Decodable {
        public var purpose: String

        public init(purpose: String) { self.purpose = purpose }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["purpose"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            purpose = try c.decode(String.self, forKey: "purpose")
        }
    }

    public struct AIMeta: Sendable, Hashable, Decodable {
        public static let defaultCap = 20
        public static let caps = 1...200

        public var purpose: String
        public var dailyCap: Int?

        public init(purpose: String, dailyCap: Int? = nil) {
            self.purpose = purpose
            self.dailyCap = dailyCap
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["purpose", "daily_cap"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            purpose = try c.decode(String.self, forKey: "purpose")
            dailyCap = try c.decodeIfPresent(Int.self, forKey: "daily_cap")
        }
    }

    /// A part of a sentence that may come anywhere around a command's `names` (D100): "on {level:level}", "{count:integer}
    /// questions", or fixed words with fixed arguments ("with a friend" → `{"players": 2}`). Commands share them by name.
    public struct PartMeta: Sendable, Hashable, Decodable {
        public var say: [String]
        public var input: [String: JSONValue]?

        public init(say: [String], input: [String: JSONValue]? = nil) {
            self.say = say
            self.input = input
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["say", "input"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            say = try c.decode([String].self, forKey: "say")
            input = try c.decodeIfPresent([String: JSONValue].self, forKey: "input")
        }
    }

    /// Words that only carry a sentence, so a command's name can stand among them (D100): "let's play a round of …" comes
    /// down to the name. `lead` says a name is meant (a bare "memory" may be another extension's word), `inside` words are
    /// taken out wherever they are (languages written without spaces), `endings` off a word's end (Korean particles).
    public struct CarryMeta: Sendable, Hashable, Decodable {
        public var words: [String]
        public var lead: [String]
        public var inside: [String]
        public var endings: [String]

        public init(words: [String] = [], lead: [String] = [], inside: [String] = [], endings: [String] = []) {
            self.words = words
            self.lead = lead
            self.inside = inside
            self.endings = endings
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(["words", "lead", "inside", "endings"])
            let c = try decoder.container(keyedBy: AnyKey.self)
            words = try c.decodeIfPresent([String].self, forKey: "words") ?? []
            lead = try c.decodeIfPresent([String].self, forKey: "lead") ?? []
            inside = try c.decodeIfPresent([String].self, forKey: "inside") ?? []
            endings = try c.decodeIfPresent([String].self, forKey: "endings") ?? []
        }

        var isEmpty: Bool { words.isEmpty && lead.isEmpty && inside.isEmpty && endings.isEmpty }

        var all: [String] { words + lead + inside + endings }
    }
}
