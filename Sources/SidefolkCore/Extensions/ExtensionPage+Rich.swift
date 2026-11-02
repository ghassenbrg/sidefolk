import Foundation

/// A picture a page may show (D100). Addressed, never fetched: a file in the extension's own signed pack, one in its data
/// folder, or the person's companion or the person themselves, which Sidefolk places and the extension never reads.
public enum PagePicture: Sendable, Hashable {
    public enum Figure: String, Sendable, Hashable { case face, full }

    /// A path inside the pack's `assets` folder (D99), with another for dark mode.
    case pack(path: String, dark: String?)
    /// A file in its data folder (`ExtensionDataFile`), which its program made.
    case data(String)
    case companion(Figure)
    case person

    /// `{"pack": "cards/a.webp", "dark": "cards/a-night.webp"}`, `{"data": "cover.jpg"}`, `{"companion": "face"}` or `{"person": true}`. A
    /// bad one is left out, never the part it is on.
    static func parse(_ j: JSONValue?) -> PagePicture? {
        guard let j else { return nil }
        if let path = j["pack"]?.stringValue, let clean = PackAssets.picturePath(path) {
            return .pack(path: clean, dark: j["dark"]?.stringValue.flatMap(PackAssets.picturePath))
        }
        if let name = j["data"]?.stringValue, ExtensionDataFile.isValidName(name) { return .data(name) }
        if let figure = j["companion"]?.stringValue.flatMap(Figure.init(rawValue:)) { return .companion(figure) }
        if j["person"]?.boolValue == true { return .person }
        return nil
    }
}

extension ExtensionPage {
    public struct StatStrip: Sendable, Hashable {
        public struct Item: Sendable, Hashable {
            public var label: String
            public var value: String
            public var symbol: String?
            public var tone: Tone
            /// `#RRGGBB` for its symbol, where a tone would say something it doesn't mean: a trophy in gold (D101).
            public var color: String?
        }

        public var items: [Item]
    }

    public struct CardGrid: Sendable, Hashable {
        /// `large` has room for a wide picture and several lines; `small` is a tile of a line or two.
        public enum Size: String, Sendable, Hashable { case small, large }

        public struct Item: Sendable, Hashable {
            public var title: String
            public var detail: String?
            /// A line in plain ink: a record, a price.
            public var meta: String?
            /// When it last happened, as Sidefolk words it for the person.
            public var at: Date?
            public var picture: PagePicture?
            public var symbol: String?
            /// `#RRGGBB`, behind the symbol when there is no picture.
            public var color: String?
            public var badge: Badge?
            /// A tick, in the good outcome's colour with its symbol (D78): done for today.
            public var done: Bool
            /// Up to three buttons; the first is also what clicking the picture does.
            public var actions: [Control]
            /// A small menu beside them: "Level ▸ Easy, Fair, Hard".
            public var menu: Menu?
        }

        public struct Menu: Sendable, Hashable {
            public var label: String
            public var items: [Control]
        }

        public var size: Size
        public var items: [Item]
    }

    public struct Tabs: Sendable, Hashable {
        public struct Tab: Sendable, Hashable {
            public var id: String
            public var label: String
            public var symbol: String?
            public var badge: String?
            public var sections: [Section]
            /// Picking it changes the page's state and the page is read again (D105), rather than Sidefolk showing its sections.
            public var go: PageGo?
        }

        public var tabs: [Tab]
        /// Shown first; the person's click stays while Home is open. With `go` on the tabs, always the program's.
        public var selected: String
        /// Drawn under the tabs whichever is picked: what the program read for it (D105).
        public var sections: [Section] = []
        /// The picked tab's fill (D108).
        public var tint: PageDress.Pair?
    }

    public struct BadgeList: Sendable, Hashable {
        public struct Item: Sendable, Hashable {
            public var title: String
            public var detail: String?
            public var symbol: String?
            public var earned: Bool
            /// How far along: `value` of `goal`, for one not earned yet.
            public var value: Int?
            public var goal: Int?
        }

        public var title: String?
        public var items: [Item]
    }

    public struct RecentList: Sendable, Hashable {
        public struct Item: Sendable, Hashable {
            public var title: String
            public var detail: String?
            public var at: Date?
            public var tone: Tone
            public var symbol: String?
            public var picture: PagePicture?
        }

        public var title: String?
        public var items: [Item]
    }

    public struct SettingsRows: Sendable, Hashable {
        public var title: String?
        /// Which of its settings, in this order; empty means all of them. The values and words are never the page's: the host
        /// holds them, and a change goes through `extensions.setting`.
        public var keys: [String]
        /// Its use of the AI gets its switch here too.
        public var ai: Bool
        /// Its own words for that switch. Believed only for packs Sidefolk signed, like a tool's `summary` (D98): anyone else's could call it something it isn't.
        public var aiTitle: String?
        public var aiDetail: String?
        /// Each in a small card of its own, in a grid, with its picture from `pictures` (D101): one choice per thing it has many of.
        public var grid = false
        public var pictures: [String: PagePicture] = [:]
    }

    static let maxTabs = 6
    static let maxCards = 48
    static let maxBadges = 32
    static let maxRecent = 20
    static let maxStats = 6

    static func richBlock(_ j: JSONValue) -> Block? {
        switch j["type"]?.stringValue {
        case "stats":
            let items = (j["items"]?.arrayValue ?? []).prefix(maxStats).compactMap { i -> StatStrip.Item? in
                guard let label = text(i["label"], 40), let value = text(i["value"], 24) else { return nil }
                return StatStrip.Item(label: label, value: value, symbol: symbol(i["symbol"]), tone: tone(i["tone"]), color: color(i["color"]))
            }
            return items.isEmpty ? nil : .stats(StatStrip(items: items))
        case "cards":
            let items = (j["items"]?.arrayValue ?? []).prefix(maxCards).compactMap(card)
            return items.isEmpty ? nil : .cards(CardGrid(size: j["size"]?.stringValue.flatMap(CardGrid.Size.init(rawValue:)) ?? .large, items: items))
        case "tabs":
            return tabs(j)
        case "badges":
            let items = (j["items"]?.arrayValue ?? []).prefix(maxBadges).compactMap { i -> BadgeList.Item? in
                guard let title = text(i["title"], 40) else { return nil }
                let goal = i["goal"]?.intValue.flatMap { $0 > 0 ? $0 : nil }
                return BadgeList.Item(title: title, detail: text(i["detail"], 120), symbol: symbol(i["symbol"]), earned: i["earned"]?.boolValue ?? false,
                                      value: goal == nil ? nil : i["value"]?.intValue.map { max(0, min($0, goal ?? 0)) }, goal: goal)
            }
            return items.isEmpty ? nil : .badges(BadgeList(title: text(j["title"], 60), items: items))
        case "recent":
            let items = (j["items"]?.arrayValue ?? []).prefix(maxRecent).compactMap { i -> RecentList.Item? in
                guard let title = text(i["title"], 80) else { return nil }
                return RecentList.Item(title: title, detail: text(i["detail"], 120), at: date(i["at"]), tone: tone(i["tone"]), symbol: symbol(i["symbol"]),
                                       picture: PagePicture.parse(i["picture"]))
            }
            return items.isEmpty ? nil : .recent(RecentList(title: text(j["title"], 60), items: items))
        case "scene":
            // The same reader, caps and budget as a surface's; pictures are checked against the pack's pins when they are drawn.
            guard let json = j["scene"], let scene = try? SurfaceScene.parse(json, within: SceneSize(width: PageScene.maxWidth, height: PageScene.maxHeight)) else { return nil }
            var actions: [String: PageScene.Action] = [:]
            for (area, action) in j["actions"]?.objectValue ?? [:] {
                // An area has no words of its own to show, so it may move around the page and no more: what is copied, opened or asked
                // for hangs on a button that says so (D105).
                if let go = PageGo.parse(action["go"]) {
                    actions[area] = PageScene.Action(tool: "", input: .object([:]), act: .go(go))
                } else if let tool = toolName(action["tool"]), let input = smallInput(action["input"]) {
                    actions[area] = PageScene.Action(tool: tool, input: input)
                }
            }
            return .scene(PageScene(scene: scene, actions: actions))
        case "settings":
            let keys = (j["keys"]?.arrayValue ?? []).prefix(ExtensionAbilityRules.maxSettings).compactMap { k -> String? in
                k.stringValue.flatMap { $0.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil ? $0 : nil }
            }
            var pictures: [String: PagePicture] = [:]
            for key in keys { pictures[key] = PagePicture.parse(j["pictures"]?[key]) }
            return .settings(SettingsRows(title: text(j["title"], 60), keys: keys, ai: j["ai"]?.boolValue ?? false, aiTitle: text(j["ai_title"], 60), aiDetail: text(j["ai_detail"], 240),
                                          grid: j["grid"]?.boolValue ?? false, pictures: pictures))
        default:
            return nil
        }
    }

    static func card(_ i: JSONValue) -> CardGrid.Item? {
        guard let title = text(i["title"], 60) else { return nil }
        var badge: Badge?
        if let b = i["badge"], let t = text(b["text"], 20) { badge = Badge(text: t, tone: tone(b["tone"])) }
        var menu: CardGrid.Menu?
        if let m = i["menu"], let label = text(m["label"], 24) {
            let items = (m["items"]?.arrayValue ?? []).prefix(8).compactMap { button($0, characters: 30) }
            if !items.isEmpty { menu = CardGrid.Menu(label: label, items: items) }
        }
        return CardGrid.Item(title: title, detail: text(i["detail"], 120), meta: text(i["meta"], 120), at: date(i["at"]), picture: PagePicture.parse(i["picture"]),
                             symbol: symbol(i["symbol"]), color: color(i["color"]), badge: badge, done: i["done"]?.boolValue ?? false,
                             actions: (i["actions"]?.arrayValue ?? []).prefix(3).compactMap { button($0, characters: 30) }, menu: menu)
    }

    /// Tabs hold sections, but no tabs within tabs: the page's caps still hold, its size being checked whole.
    static func tabs(_ j: JSONValue) -> Block? {
        let tabs = (j["tabs"]?.arrayValue ?? []).prefix(maxTabs).compactMap { t -> Tabs.Tab? in
            guard let id = t["id"]?.stringValue, id.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil, let label = text(t["label"], 30) else { return nil }
            let sections = (t["sections"]?.arrayValue ?? []).prefix(maxSections).compactMap { s -> Section? in
                guard !(s["blocks"]?.arrayValue ?? []).contains(where: { $0["type"]?.stringValue == "tabs" }) else { return nil }
                return section(s)
            }
            let go = PageGo.parse(t["go"])
            return sections.isEmpty && go == nil ? nil : Tabs.Tab(id: id, label: label, symbol: symbol(t["symbol"]), badge: text(t["badge"], 8), sections: sections, go: go)
        }
        guard tabs.count >= 2 else { return nil }
        let selected = j["selected"]?.stringValue.flatMap { s in tabs.contains { $0.id == s } ? s : nil } ?? tabs[0].id
        let under = (j["sections"]?.arrayValue ?? []).prefix(maxSections).compactMap { s -> Section? in
            guard !(s["blocks"]?.arrayValue ?? []).contains(where: { $0["type"]?.stringValue == "tabs" }) else { return nil }
            return section(s)
        }
        return .tabs(Tabs(tabs: tabs, selected: selected, sections: under, tint: PageDress.Pair.parse(j["tint"])))
    }

    static func date(_ j: JSONValue?) -> Date? {
        j?.stringValue.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

/// A scene inside a page: `actions` says which of the extension's own tools each of its areas runs, as the person, through Guard. It
/// has no session: nothing goes to the program but those tool calls, and a page's scene takes no keys and keeps no clocks of its own.
public struct PageScene: Sendable, Hashable {
    /// As wide as a page may grow and tall enough for one whole screen of it (D108).
    public static let maxWidth = 1320.0
    public static let maxHeight = 1600.0

    public struct Action: Sendable, Hashable {
        public var tool: String
        public var input: JSONValue
        /// What it does instead of running `tool` (D105).
        public var act: PageAct?
    }

    public var scene: SurfaceScene
    public var actions: [String: Action]

    /// What a click on an area runs: its tool, with the area's own value as `value`.
    public func action(area: String, value: String?) -> (tool: String, input: JSONValue)? {
        guard let action = actions[area], action.act == nil else { return nil }
        guard let value else { return (action.tool, action.input) }
        return (action.tool, action.input.setting("value", .string(value)))
    }

    /// What a click on an area does that isn't a tool: the area's `value`, for `go`, goes into the state as `value` (D105).
    public func act(area: String, value: String?) -> PageAct? {
        guard let act = actions[area]?.act else { return nil }
        guard let value, case .go(var go) = act else { return act }
        go.set["value"] = .string(value)
        return .go(go)
    }
}
