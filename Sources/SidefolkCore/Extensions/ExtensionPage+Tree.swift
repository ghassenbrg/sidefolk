import Foundation

/// A tree of cards that arranges itself (`tree`, D118): steps one under another, branches that split and join again. For anything that goes one way or
/// another: a flow, a decision, a recipe with a choice, an onboarding. Read like any page part: what is off is dropped, nothing here reaches a model, and
/// each hook runs one of the extension's own tools as the person, through Guard. It holds no meaning of its own: cards, lines, and what a click means is the tool's.
extension ExtensionPage {
    public struct Tree: Sendable, Hashable {
        public struct Node: Sendable, Hashable, Identifiable {
            /// What it says of this card, drawn on the card and on the line into it, always with a word or a mark (D78).
            /// `pending`: not really done, dashed. `active`: happening now. `done`: a tick. `skipped`: a path not taken, faded. `attention`: needs the person.
            public enum State: String, Sendable, Hashable { case none, pending, active, done, skipped, attention }

            public var id: String
            /// A short word above the title: what kind of card it is.
            public var kind: String?
            public var title: String
            public var symbol: String?
            public var color: String?
            public var state: State
            public var pill: Badge?
            public var branches: [Branch]
        }

        public struct Branch: Sendable, Hashable, Identifiable {
            /// Comes back in `insert` for adding at the start of this branch.
            public var id: String
            public var label: String
            public var tone: Tone
            /// False: the path not taken, faded. Nil says nothing.
            public var taken: Bool?
            public var nodes: [Node]
        }

        /// A searchable list of what `insert` may add, opened from a + button.
        public struct Picker: Sendable, Hashable {
            public struct Category: Sendable, Hashable, Identifiable {
                public var id: String
                public var label: String
                public var symbol: String?
            }

            public struct Item: Sendable, Hashable, Identifiable {
                public var id: String
                public var title: String
                public var detail: String?
                /// A word at the trailing end: what kind of thing it is.
                public var meta: String?
                public var symbol: String?
                public var color: String?
                /// Listed under these; an item with none is under all of them.
                public var categories: [String]
            }

            public var placeholder: String?
            public var note: String?
            /// What the chosen item's id goes under in `insert`'s input.
            public var key: String
            public var categories: [Category]
            public var items: [Item]
        }

        public var nodes: [Node]
        public var selected: String?
        public var select: Steps.Hook?
        public var insert: Steps.Hook?
        public var reorder: Steps.Hook?
        public var picker: Picker?
        /// Small buttons floating beside it, each drawn as its symbol.
        public var tools: [Control]
        /// `#RRGGBB`, one or two: its line, running from one to the other.
        public var line: [String]

        /// Every card, top to bottom and each branch whole before the next: the order they are read in.
        public var reading: [Node] {
            func walk(_ nodes: [Node]) -> [Node] { nodes.flatMap { [$0] + $0.branches.flatMap { walk($0.nodes) } } }
            return walk(nodes)
        }

        /// The cards that move together with `id`: those beside it in one run of the tree.
        public func siblings(of id: String) -> [Node] {
            func find(_ nodes: [Node]) -> [Node]? {
                if nodes.contains(where: { $0.id == id }) { return nodes }
                for node in nodes { for branch in node.branches { if let found = find(branch.nodes) { return found } } }
                return nil
            }
            return find(nodes) ?? []
        }

        /// What moving `id` by one place among its own says: the id it now stands before, or `.null` at the end. Nil when it can't go there.
        public func move(_ id: String, by delta: Int) -> JSONValue? {
            let own = siblings(of: id)
            guard let at = own.firstIndex(where: { $0.id == id }), own.indices.contains(at + delta) else { return nil }
            if delta < 0 { return ["id": .string(id), "before": .string(own[at + delta].id)] }
            let next = at + delta + 1
            return ["id": .string(id), "before": own.indices.contains(next) ? .string(own[next].id) : .null]
        }
    }

    static let maxTreeNodes = 64
    static let maxTreeDepth = 4
    static let maxTreeBranches = 4
    static let maxPickerItems = 256
    private static let treeId = #"^[A-Za-z0-9_.:-]{1,64}$"#

    /// What a part says to run with what the person pointed at under `key`.
    static func hook(_ h: JSONValue?) -> Steps.Hook? {
        guard let h, let tool = toolName(h["tool"]), let input = smallInput(h["input"]), let key = h["key"]?.stringValue,
              key.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil, key != "on" else { return nil }
        return Steps.Hook(tool: tool, input: input, key: key, label: text(h["label"], 30))
    }

    static func parseTree(_ j: JSONValue) -> Tree? {
        var seen = Set<String>()
        var left = maxTreeNodes
        func fresh(_ v: JSONValue?) -> String? {
            guard let id = v?.stringValue, id.range(of: treeId, options: .regularExpression) != nil, seen.insert(id).inserted else { return nil }
            return id
        }
        func nodes(_ list: JSONValue?, depth: Int) -> [Tree.Node] {
            (list?.arrayValue ?? []).compactMap { n -> Tree.Node? in
                guard left > 0, let id = fresh(n["id"]), let title = text(n["title"], 240) else { return nil }
                left -= 1
                var pill: Badge?
                if let p = n["pill"], let t = text(p["text"], 24) { pill = Badge(text: t, tone: tone(p["tone"])) }
                let branches = depth >= maxTreeDepth ? [] : (n["branches"]?.arrayValue ?? []).prefix(maxTreeBranches).compactMap { b -> Tree.Branch? in
                    guard let bid = fresh(b["id"]), let label = text(b["label"], 24) else { return nil }
                    return Tree.Branch(id: bid, label: label, tone: tone(b["tone"]), taken: b["taken"]?.boolValue, nodes: nodes(b["nodes"], depth: depth + 1))
                }
                return Tree.Node(id: id, kind: text(n["kind"], 30), title: title, symbol: symbol(n["symbol"]), color: color(n["color"]),
                                 state: n["state"]?.stringValue.flatMap(Tree.Node.State.init(rawValue:)) ?? .none, pill: pill, branches: Array(branches))
            }
        }
        let list = nodes(j["nodes"], depth: 0)
        guard !list.isEmpty else { return nil }
        var picker: Tree.Picker?
        if let p = j["picker"], let key = stateKey(p["key"]), key != "on" {
            let categories = (p["categories"]?.arrayValue ?? []).prefix(16).compactMap { c -> Tree.Picker.Category? in
                guard let id = c["id"]?.stringValue, id.range(of: treeId, options: .regularExpression) != nil, let label = text(c["label"], 30) else { return nil }
                return Tree.Picker.Category(id: id, label: label, symbol: symbol(c["symbol"]))
            }
            let items = (p["items"]?.arrayValue ?? []).prefix(maxPickerItems).compactMap { i -> Tree.Picker.Item? in
                guard let id = i["id"]?.stringValue, id.range(of: #"^[A-Za-z0-9_.:-]{1,96}$"#, options: .regularExpression) != nil, let title = text(i["title"], 60) else { return nil }
                return Tree.Picker.Item(id: id, title: title, detail: text(i["detail"], 80), meta: text(i["meta"], 24), symbol: symbol(i["symbol"]), color: color(i["color"]),
                                        categories: (i["categories"]?.arrayValue ?? []).prefix(4).compactMap(\.stringValue))
            }
            if !items.isEmpty { picker = Tree.Picker(placeholder: text(p["placeholder"], 60), note: text(p["note"], 120), key: key, categories: categories, items: items) }
        }
        return Tree(nodes: list, selected: j["selected"]?.stringValue, select: hook(j["select"]), insert: hook(j["insert"]), reorder: hook(j["reorder"]), picker: picker,
                    tools: (j["tools"]?.arrayValue ?? []).prefix(6).compactMap { button($0, characters: 30) },
                    line: Array((j["line"]?.arrayValue ?? []).compactMap { color($0) }.prefix(2)))
    }
}

/// Where a tree's cards, lines and + buttons go: only numbers, so it is tested without a window. Top to bottom and each run centred on its line; branches side by side,
/// spaced by what each holds, joining again under the longest.
///
/// The way branches are measured and spaced (`extent`, `offsets`) is ported from Activepieces, `packages/core/execution/src/lib/flows/util/flow-canvas-util.ts`
/// at commit 8611a90d, MIT, Copyright (c) 2020-2024 Activepieces Inc.: see THIRD_PARTY_NOTICES.md.
public struct TreeLayout: Sendable {
    public struct Metrics: Sendable {
        public var card = CGSize(width: 288, height: 72)
        /// Between one card and the next.
        public var gap: CGFloat = 54
        /// Between branches side by side.
        public var gutter: CGFloat = 28
        /// From a card that splits down to the line running across.
        public var split: CGFloat = 24
        /// From that line down to the first card of a branch: the branch's label sits here.
        public var drop: CGFloat = 52
        /// From the longest branch's end to where they join.
        public var join: CGFloat = 26
        /// How wide an empty branch is.
        public var empty: CGFloat = 148
        public var margin: CGFloat = 32

        public init() {}
        /// A card's small drawing of itself (`Card.tree`).
        public static var mini: Metrics {
            var m = Metrics()
            m.card = CGSize(width: 44, height: 16)
            m.gap = 8
            m.gutter = 6
            m.split = 5
            m.drop = 6
            m.join = 5
            m.empty = 44
            m.margin = 0
            return m
        }
    }

    public enum LineStyle: Sendable, Hashable {
        case solid, dashed, faded
        /// Leading to what is happening now.
        case live
    }

    public struct Card: Sendable, Hashable {
        public var node: ExtensionPage.Tree.Node
        public var frame: CGRect
    }

    public struct Line: Sendable, Hashable {
        /// Square corners; whoever draws it rounds them.
        public var points: [CGPoint]
        public var style: LineStyle
    }

    public struct Add: Sendable, Hashable {
        /// Goes back in `insert`: a card to add after, or a branch to add at the start of.
        public var target: String
        public var point: CGPoint
        /// Only shown when the pointer or the keyboard is on it: the start of a branch that has cards.
        public var quiet: Bool
    }

    public struct Label: Sendable, Hashable {
        public var branch: ExtensionPage.Tree.Branch
        public var point: CGPoint
    }

    public var cards: [Card] = []
    public var lines: [Line] = []
    public var adds: [Add] = []
    public var labels: [Label] = []
    public var size: CGSize = .zero

    public init(_ tree: ExtensionPage.Tree, editable: Bool, metrics: Metrics = Metrics()) {
        let m = metrics

        func style(_ node: ExtensionPage.Tree.Node?) -> LineStyle {
            switch node?.state {
            case .pending: .dashed
            case .skipped: .faded
            case .active: .live
            default: .solid
            }
        }

        func style(_ branch: ExtensionPage.Tree.Branch) -> LineStyle {
            if branch.taken == false { return .faded }
            return branch.nodes.first.map { style($0) == .live ? .solid : style($0) } ?? (branch.taken == true ? .solid : .dashed)
        }

        /// How far a run reaches to each side of its line.
        func extent(_ nodes: [ExtensionPage.Tree.Node]) -> (min: CGFloat, max: CGFloat) {
            var low = -m.card.width / 2, high = m.card.width / 2
            for node in nodes where !node.branches.isEmpty {
                let parts = node.branches.map(extent)
                for (part, x) in zip(parts, offsets(parts)) {
                    low = min(low, x + part.min)
                    high = max(high, x + part.max)
                }
            }
            return (low, high)
        }

        func extent(_ branch: ExtensionPage.Tree.Branch) -> (min: CGFloat, max: CGFloat) {
            branch.nodes.isEmpty ? (-m.empty / 2, m.empty / 2) : extent(branch.nodes)
        }

        /// Where each branch's line goes, left of the parent's and right of it, the first and last the same distance out.
        func offsets(_ parts: [(min: CGFloat, max: CGFloat)]) -> [CGFloat] {
            guard let first = parts.first, let last = parts.last else { return [] }
            let total = parts.reduce(0) { $0 + $1.max - $1.min } + m.gutter * CGFloat(parts.count - 1)
            var left = -(total + first.min - last.max) / 2 + first.min
            return parts.map { part in
                let x = left - part.min
                left += part.max - part.min + m.gutter
                return x
            }
        }

        var cards: [Card] = [], lines: [Line] = [], adds: [Add] = [], labels: [Label] = []

        /// Lays a run down from `y`, joined to `from`; says where its line ends. `tail` leaves room for a + after the last card.
        func lay(_ nodes: [ExtensionPage.Tree.Node], x: CGFloat, y: CGFloat, from: (y: CGFloat, id: String?)?, tail: Bool) -> (y: CGFloat, id: String?) {
            var previous = from, top = y
            for node in nodes {
                if let previous {
                    lines.append(Line(points: [CGPoint(x: x, y: previous.y), CGPoint(x: x, y: top)], style: style(node)))
                    if editable, let id = previous.id { adds.append(Add(target: id, point: CGPoint(x: x, y: (previous.y + top) / 2), quiet: false)) }
                }
                cards.append(Card(node: node, frame: CGRect(x: x - m.card.width / 2, y: top, width: m.card.width, height: m.card.height)))
                let bottom = top + m.card.height
                guard !node.branches.isEmpty else {
                    previous = (bottom, node.id)
                    top = bottom + m.gap
                    continue
                }
                let across = bottom + m.split, under = across + m.drop
                let places = offsets(node.branches.map(extent)).map { x + $0 }
                var ends: [(x: CGFloat, y: CGFloat, style: LineStyle)] = []
                for (branch, cx) in zip(node.branches, places) {
                    let line = style(branch)
                    lines.append(Line(points: [CGPoint(x: x, y: bottom), CGPoint(x: x, y: across), CGPoint(x: cx, y: across), CGPoint(x: cx, y: under)], style: line))
                    labels.append(Label(branch: branch, point: CGPoint(x: cx, y: across + m.drop / 2)))
                    if branch.nodes.isEmpty {
                        if editable { adds.append(Add(target: branch.id, point: CGPoint(x: cx, y: under + 12), quiet: false)) }
                        ends.append((cx, under + (editable ? 24 : 0), line))
                    } else {
                        if editable { adds.append(Add(target: branch.id, point: CGPoint(x: cx, y: across + m.drop - 8), quiet: true)) }
                        let end = lay(branch.nodes, x: cx, y: under, from: nil, tail: editable)
                        ends.append((cx, end.y, line))
                    }
                }
                let joined = (ends.map(\.y).max() ?? under) + m.join
                for end in ends {
                    lines.append(Line(points: [CGPoint(x: end.x, y: end.y), CGPoint(x: end.x, y: joined), CGPoint(x: x, y: joined)], style: end.style))
                }
                previous = (joined, node.id)
                top = joined + m.gap
            }
            guard tail, let last = previous else { return previous ?? (y, nil) }
            let end = last.y + m.gap / 2
            lines.append(Line(points: [CGPoint(x: x, y: last.y), CGPoint(x: x, y: end)], style: .dashed))
            if let id = last.id { adds.append(Add(target: id, point: CGPoint(x: x, y: end), quiet: false)) }
            return (end, last.id)
        }

        let end = lay(tree.nodes, x: 0, y: m.margin, from: nil, tail: editable)
        let reach = extent(tree.nodes)
        let shift = m.margin - reach.min
        func moved(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + shift, y: p.y) }
        self.cards = cards.map { Card(node: $0.node, frame: $0.frame.offsetBy(dx: shift, dy: 0)) }
        self.lines = lines.map { Line(points: $0.points.map(moved), style: $0.style) }
        self.adds = adds.map { Add(target: $0.target, point: moved($0.point), quiet: $0.quiet) }
        self.labels = labels.map { Label(branch: $0.branch, point: moved($0.point)) }
        size = CGSize(width: reach.max - reach.min + m.margin * 2, height: end.y + m.margin)
    }
}
