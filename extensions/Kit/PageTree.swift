import Foundation

/// A tree of cards that arranges itself (`tree`, D118): steps one under another, branches that split and join again. For anything that goes one way or another: a flow,
/// a decision, a recipe with a choice. Sidefolk lays it out and draws it, with zoom, a small map, keyboard and VoiceOver; what a click means is your tools'.
public struct CardTree {
    public struct Node {
        /// What the card says about itself, drawn on it and on the line into it. `pending`: not really done, dashed. `active`: happening now.
        /// `done`: a tick. `skipped`: a path not taken, faded. `attention`: needs the person.
        public enum State: String { case none, pending, active, done, skipped, attention }

        public var id: String
        /// A short word above the title: what kind of card it is.
        public var kind: String?
        public var title: String
        public var symbol: String?
        /// `#RRGGBB`: its tile. What kind of thing it is, never how it went.
        public var color: String?
        public var state: State
        public var pill: Badge?
        public var branches: [Branch]

        public init(_ id: String, _ title: String, kind: String? = nil, symbol: String? = nil, color: String? = nil, state: State = .none, pill: Badge? = nil, branches: [Branch] = []) {
            self.id = id
            self.title = title
            self.kind = kind
            self.symbol = symbol
            self.color = color
            self.state = state
            self.pill = pill
            self.branches = branches
        }

        var json: [String: Any] {
            var out: [String: Any] = ["id": id, "title": title, "state": state.rawValue]
            if let kind { out["kind"] = kind }
            if let symbol { out["symbol"] = symbol }
            if let color { out["color"] = color }
            if let pill { out["pill"] = ["text": pill.text, "tone": pill.tone.rawValue] }
            if !branches.isEmpty { out["branches"] = branches.map(\.json) }
            return out
        }
    }

    public struct Branch {
        /// Comes back in `insert` for adding at the start of this branch.
        public var id: String
        public var label: String
        public var tone: Tone
        /// False: the path not taken, faded.
        public var taken: Bool?
        public var nodes: [Node]

        public init(_ id: String, _ label: String, tone: Tone = .neutral, taken: Bool? = nil, nodes: [Node] = []) {
            self.id = id
            self.label = label
            self.tone = tone
            self.taken = taken
            self.nodes = nodes
        }

        var json: [String: Any] {
            var out: [String: Any] = ["id": id, "label": label, "tone": tone.rawValue, "nodes": nodes.map(\.json)]
            if let taken { out["taken"] = taken }
            return out
        }
    }

    /// A searchable list of what `insert` may add, opened from a + button. The chosen item's id goes under `key`.
    public struct Picker {
        public struct Item {
            public var id: String
            public var title: String
            public var detail: String?
            public var meta: String?
            public var symbol: String?
            public var color: String?
            public var categories: [String]

            public init(_ id: String, _ title: String, detail: String? = nil, meta: String? = nil, symbol: String? = nil, color: String? = nil, categories: [String] = []) {
                self.id = id
                self.title = title
                self.detail = detail
                self.meta = meta
                self.symbol = symbol
                self.color = color
                self.categories = categories
            }

            var json: [String: Any] {
                var out: [String: Any] = ["id": id, "title": title, "categories": categories]
                if let detail { out["detail"] = detail }
                if let meta { out["meta"] = meta }
                if let symbol { out["symbol"] = symbol }
                if let color { out["color"] = color }
                return out
            }
        }

        public var key: String
        public var placeholder: String?
        public var note: String?
        public var categories: [(id: String, label: String, symbol: String?)]
        public var items: [Item]

        public init(key: String, placeholder: String? = nil, note: String? = nil, categories: [(id: String, label: String, symbol: String?)] = [], items: [Item]) {
            self.key = key
            self.placeholder = placeholder
            self.note = note
            self.categories = categories
            self.items = items
        }

        var json: [String: Any] {
            var out: [String: Any] = ["key": key, "items": items.map(\.json), "categories": categories.map { c -> [String: Any] in
                var one: [String: Any] = ["id": c.id, "label": c.label]
                if let symbol = c.symbol { one["symbol"] = symbol }
                return one
            }]
            if let placeholder { out["placeholder"] = placeholder }
            if let note { out["note"] = note }
            return out
        }
    }

    public var nodes: [Node]
    public var selected: String?
    public var select: StepRail.Hook?
    public var insert: StepRail.Hook?
    public var reorder: StepRail.Hook?
    public var picker: Picker?
    public var tools: [Action]
    /// `#RRGGBB`, one or two: the line, running from one to the other.
    public var line: [String]

    public init(_ nodes: [Node], selected: String? = nil, select: StepRail.Hook? = nil, insert: StepRail.Hook? = nil, reorder: StepRail.Hook? = nil, picker: Picker? = nil, tools: [Action] = [], line: [String] = []) {
        self.nodes = nodes
        self.selected = selected
        self.select = select
        self.insert = insert
        self.reorder = reorder
        self.picker = picker
        self.tools = tools
        self.line = line
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "tree", "nodes": nodes.map(\.json), "tools": tools.map(\.json), "line": line]
        if let selected { out["selected"] = selected }
        if let select { out["select"] = select.json }
        if let insert { out["insert"] = insert.json }
        if let reorder { out["reorder"] = reorder.json }
        if let picker { out["picker"] = picker.json }
        return out
    }
}

/// A compact head for a page that draws its own (D119): the way back comes from `Page.back`.
public struct PageBar {
    public var title: String
    public var pill: Badge?
    public var detail: String?
    public var actions: [Action]
    public var menu: [Action]

    public init(_ title: String, pill: Badge? = nil, detail: String? = nil, actions: [Action] = [], menu: [Action] = []) {
        self.title = title
        self.pill = pill
        self.detail = detail
        self.actions = actions
        self.menu = menu
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "bar", "title": title, "actions": actions.map(\.json), "menu": menu.map(\.json)]
        if let pill { out["pill"] = ["text": pill.text, "tone": pill.tone.rawValue] }
        if let detail { out["detail"] = detail }
        return out
    }
}

/// A column of places to go (D119). `brand` heads it with your icon and name, as Sidefolk knows them.
public struct PageNav {
    public struct Item {
        public var id: String
        public var title: String
        public var status: String?
        public var tone: Tone
        public var symbol: String?
        /// `#RRGGBB`: draws the symbol on a tile.
        public var color: String?
        public var selected: Bool
        public var press: Action

        public init(_ id: String, _ title: String, status: String? = nil, tone: Tone = .neutral, symbol: String? = nil, color: String? = nil, selected: Bool = false, press: Action) {
            self.id = id
            self.title = title
            self.status = status
            self.tone = tone
            self.symbol = symbol
            self.color = color
            self.selected = selected
            self.press = press
        }

        var json: [String: Any] {
            var out: [String: Any] = ["id": id, "title": title, "tone": tone.rawValue, "selected": selected, "press": press.json]
            if let status { out["status"] = status }
            if let symbol { out["symbol"] = symbol }
            if let color { out["color"] = color }
            return out
        }
    }

    public var brand: Bool
    public var title: String?
    public var add: Action?
    public var filters: [Item]
    public var items: [Item]
    public var empty: String?

    public init(brand: Bool = false, title: String? = nil, add: Action? = nil, filters: [Item] = [], items: [Item] = [], empty: String? = nil) {
        self.brand = brand
        self.title = title
        self.add = add
        self.filters = filters
        self.items = items
        self.empty = empty
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "nav", "brand": brand, "filters": filters.map(\.json), "items": items.map(\.json)]
        if let title { out["title"] = title }
        if let add { out["add"] = add.json }
        if let empty { out["empty"] = empty }
        return out
    }
}

/// What a person will receive, drawn as it will arrive (D119). `placeholder`: nothing to show yet.
public struct PageNotice {
    public var title: String?
    public var body: String?
    public var time: String?
    public var footer: String?
    public var forming: Bool
    public var placeholder: String?

    public init(title: String? = nil, body: String? = nil, time: String? = nil, footer: String? = nil, forming: Bool = false, placeholder: String? = nil) {
        self.title = title
        self.body = body
        self.time = time
        self.footer = footer
        self.forming = forming
        self.placeholder = placeholder
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "notice", "forming": forming]
        if let title { out["title"] = title }
        if let body { out["body"] = body }
        if let time { out["time"] = time }
        if let footer { out["footer"] = footer }
        if let placeholder { out["placeholder"] = placeholder }
        return out
    }
}

/// A row of recent results (D119): each a mark, its word on hover and to VoiceOver.
public struct PageTicks {
    public struct Item {
        public var tone: Tone
        public var label: String
        public var hollow: Bool

        public init(_ label: String, tone: Tone = .good, hollow: Bool = false) {
            self.label = label
            self.tone = tone
            self.hollow = hollow
        }
    }

    public var title: String?
    public var caption: String?
    public var items: [Item]

    public init(_ title: String? = nil, caption: String? = nil, items: [Item]) {
        self.title = title
        self.caption = caption
        self.items = items
    }

    var json: [String: Any] {
        var out: [String: Any] = ["type": "ticks", "items": items.map { ["tone": $0.tone.rawValue, "label": $0.label, "hollow": $0.hollow] as [String: Any] }]
        if let title { out["title"] = title }
        if let caption { out["caption"] = caption }
        return out
    }
}
