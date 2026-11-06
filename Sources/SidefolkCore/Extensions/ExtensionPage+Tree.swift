import Foundation

/// A tree of cards that arranges itself (`tree`, D125): steps one under another, branches that split and join again. For anything that goes one way or
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
            /// Stays where it is, first in its run: what sets the rest off. Nothing moves or removes it.
            public var fixed = false
            /// Folded by the person: how many cards it's holding out of sight.
            public var folded: Int?
            /// Where the person put it on the board, its top left corner (D234): only where it's drawn, never what runs or in what order.
            public var at: CGPoint?
        }

        public struct Branch: Sendable, Hashable, Identifiable {
            /// Comes back in `insert` for adding at the start of this branch.
            public var id: String
            public var label: String
            public var tone: Tone
            /// False: the path not taken, faded. Nil says nothing.
            public var taken: Bool?
            public var nodes: [Node]
            /// On its + while it's empty: what goes here, so the place to add it can't be missed.
            public var hint: String?
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
        /// Gets `{"id", "x", "y"}` when a card is let go on the board's empty space, and `{"clear": true}` from Tidy up (D234). Only where cards are drawn.
        public var placed: Steps.Hook?
        /// Takes a card away: its id goes under the hook's key. On a card's menu.
        public var remove: Steps.Hook?
        public var picker: Picker?
        /// Small buttons floating beside it, each drawn as its symbol.
        public var tools: [Control]
        /// `#RRGGBB`, one or two: its line, running from one to the other.
        public var line: [String]

        init(nodes: [Node]) {
            self.init(nodes: nodes, selected: nil, select: nil, insert: nil, reorder: nil, remove: nil, picker: nil, tools: [], line: [])
        }

        public init(nodes: [Node], selected: String?, select: Steps.Hook?, insert: Steps.Hook?, reorder: Steps.Hook?, remove: Steps.Hook?, picker: Picker?, tools: [Control], line: [String]) {
            (self.nodes, self.selected, self.select, self.insert, self.reorder, self.remove, self.picker, self.tools, self.line) = (nodes, selected, select, insert, reorder, remove, picker, tools, line)
        }

        /// Every card, top to bottom and each branch whole before the next: the order they are read in.
        public var reading: [Node] {
            func walk(_ nodes: [Node]) -> [Node] { nodes.flatMap { [$0] + $0.branches.flatMap { walk($0.nodes) } } }
            return walk(nodes)
        }

        /// The cards that move together with `id`: those beside it in one run of the tree.
        public func siblings(of id: String) -> [Node] {
            func find(_ nodes: [Node]) -> [Node]? {
                if nodes.contains(where: { $0.id == id }) { return nodes.filter { !$0.fixed } }
                for node in nodes { for branch in node.branches { if let found = find(branch.nodes) { return found } } }
                return nil
            }
            return find(nodes) ?? []
        }

        /// The card and all that hangs from it. A card can't be put inside itself.
        public func family(of id: String) -> Set<String> {
            guard let node = reading.first(where: { $0.id == id }) else { return [] }
            func walk(_ node: Node) -> [String] { [node.id] + node.branches.flatMap { [$0.id] + $0.nodes.flatMap(walk) } }
            return Set(walk(node))
        }

        /// What putting `id` at a + spot says: `{"id", "after"}`, with the spot's own target. Nil when it stands there already, or the spot is inside it.
        public func place(_ id: String, after target: String) -> JSONValue? {
            guard reorder != nil, let node = reading.first(where: { $0.id == id }), !node.fixed, !family(of: id).contains(target), spot(of: id) != target else { return nil }
            return ["id": .string(id), "after": .string(target)]
        }

        /// The + spot a card comes straight after: the card before it, or the start of its branch.
        func spot(of id: String) -> String? {
            func find(_ nodes: [Node], first: String?) -> String? {
                for (at, node) in nodes.enumerated() {
                    if node.id == id { return at == 0 ? first : nodes[at - 1].id }
                    for branch in node.branches { if let found = find(branch.nodes, first: branch.id) { return found } }
                }
                return nil
            }
            return find(nodes, first: nil)
        }

        /// The tree with what hangs from these cards folded away: only what's looked at, never what it is. Each says how many it's holding, and stays a card to press.
        public func folding(_ ids: Set<String>) -> Tree {
            guard !ids.isEmpty else { return self }
            func walk(_ nodes: [Node]) -> [Node] {
                nodes.map { node in
                    var node = node
                    if ids.contains(node.id), !node.branches.isEmpty {
                        let held = node.branches.reduce(0) { $0 + Tree(nodes: $1.nodes).reading.count }
                        node.folded = held
                        node.branches = []
                    } else {
                        node.branches = node.branches.map { var b = $0; b.nodes = walk(b.nodes); return b }
                    }
                    return node
                }
            }
            var out = self
            out.nodes = walk(nodes)
            return out
        }

        /// The cards whose words have these in them, as they're read.
        public func matching(_ words: String) -> [String] {
            let wanted = words.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wanted.isEmpty else { return [] }
            return reading.filter { n in [n.kind, n.title, n.pill?.text].compactMap(\.self).contains { $0.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }.map(\.id)
        }

        /// Everywhere a card can be put, as a list says it, for moving it without dragging. Top to bottom, as the + spots are.
        public struct Spot: Sendable, Hashable, Identifiable {
            public enum Place: Sendable, Hashable {
                /// Right after this card.
                case after(String)
                /// First in this branch of that card.
                case start(branch: String, of: String)
            }

            public var id: String
            public var place: Place
            public var depth: Int
        }

        public func spots(for id: String) -> [Spot] {
            var out: [Spot] = []
            func walk(_ nodes: [Node], depth: Int) {
                for node in nodes {
                    if place(id, after: node.id) != nil { out.append(Spot(id: node.id, place: .after(node.title), depth: depth)) }
                    for branch in node.branches {
                        if place(id, after: branch.id) != nil { out.append(Spot(id: branch.id, place: .start(branch: branch.label, of: node.title), depth: depth + 1)) }
                        walk(branch.nodes, depth: depth + 1)
                    }
                }
            }
            walk(nodes, depth: 0)
            return out
        }

        /// The card before or after this one, as the tree is read: what the arrow keys go to.
        public func neighbour(of id: String?, by delta: Int) -> String? {
            let all = reading
            guard let id, let at = all.firstIndex(where: { $0.id == id }) else { return all.first?.id }
            return all.indices.contains(at + delta) ? all[at + delta].id : nil
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

    static let maxTreeNodes = 128
    static let maxTreeDepth = 4
    static let maxTreeBranches = 8
    static let maxPickerItems = 256
    private static let treeId = #"^[A-Za-z0-9_.:-]{1,64}$"#

    /// What a part says to run with what the person pointed at under `key`.
    static func hook(_ h: JSONValue?) -> Steps.Hook? {
        guard let h, let tool = toolName(h["tool"]), let input = smallInput(h["input"]), let key = h["key"]?.stringValue,
              key.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil, key != "on" else { return nil }
        return Steps.Hook(tool: tool, input: input, key: key, label: text(h["label"], 30))
    }

    /// A tree a tool's reply showed on its card.
    public static func tree(from j: JSONValue) -> Tree? { parseTree(j) }

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
                    return Tree.Branch(id: bid, label: label, tone: tone(b["tone"]), taken: b["taken"]?.boolValue, nodes: nodes(b["nodes"], depth: depth + 1), hint: text(b["hint"], 40))
                }
                var node = Tree.Node(id: id, kind: text(n["kind"], 30), title: title, symbol: symbol(n["symbol"]), color: color(n["color"]),
                                     state: n["state"]?.stringValue.flatMap(Tree.Node.State.init(rawValue:)) ?? .none, pill: pill, branches: Array(branches), fixed: n["fixed"]?.boolValue ?? false)
                node.at = place(n["at"])
                return node
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
        var tree = Tree(nodes: list, selected: j["selected"]?.stringValue, select: hook(j["select"]), insert: hook(j["insert"]), reorder: hook(j["reorder"]), remove: hook(j["remove"]), picker: picker,
                        tools: (j["tools"]?.arrayValue ?? []).prefix(6).compactMap { button($0, characters: 30) },
                        line: Array((j["line"]?.arrayValue ?? []).compactMap { color($0) }.prefix(2)))
        tree.placed = hook(j["placed"])
        return tree
    }

    /// The farthest a card is put from the board's start, either way (D234).
    public static let farthestPlace: CGFloat = 4_000

    /// `{"x", "y"}`, plain numbers only, kept within reach (a board of 128 cards stays a size that draws): anything else leaves the card where the tree lays it.
    static func place(_ j: JSONValue?) -> CGPoint? {
        guard case .number(let x)? = j?["x"], case .number(let y)? = j?["y"], x.isFinite, y.isFinite else { return nil }
        let reach = Double(farthestPlace)
        return CGPoint(x: min(reach, max(-reach, x)), y: min(reach, max(-reach, y)))
    }
}

/// Where a tree's cards, lines and + buttons go: only numbers, so it is tested without a window. Top to bottom and each run centred on its line; branches side by side,
/// spaced by what each holds, joining again under the longest.
///
/// The way branches are measured and spaced (`extent`, `offsets`) is ported from Activepieces, `packages/core/execution/src/lib/flows/util/flow-canvas-util.ts`
/// at commit 8611a90d, MIT, Copyright (c) 2020-2024 Activepieces Inc.: see THIRD_PARTY_NOTICES.md.
public struct TreeLayout: Sendable {
    public struct Metrics: Sendable {
        public var card = CGSize(width: 324, height: 72)
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
        /// With words on its cards, small: a card in Ask.
        public static var compact: Metrics {
            var m = Metrics()
            m.card = CGSize(width: 216, height: 40)
            m.gap = 14
            m.gutter = 10
            m.split = 8
            m.drop = 22
            m.join = 8
            m.empty = 60
            m.margin = 2
            return m
        }

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
        /// Words on it, for the start of an empty branch.
        public var hint: String?
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
    /// Some cards stand where the person put them (D234).
    public var placed = false
    /// One of them would have covered another card, and was moved down to the first free place: the board suggests tidying up.
    public var nudged = false
    /// Where a place the person chose is drawn: the board grows so that every card is on it, so a place is drawn this much further on.
    public var origin = CGPoint.zero

    /// `free`: cards the person put somewhere stand there (a board, D234); a card's small drawing ignores where they were put.
    public init(_ tree: ExtensionPage.Tree, editable: Bool, metrics: Metrics = Metrics(), free: Bool = false) {
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
                        if editable { adds.append(Add(target: branch.id, point: CGPoint(x: cx, y: under + 12), quiet: false, hint: branch.hint)) }
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
        self.adds = adds.map { Add(target: $0.target, point: moved($0.point), quiet: $0.quiet, hint: $0.hint) }
        self.labels = labels.map { Label(branch: $0.branch, point: moved($0.point)) }
        size = CGSize(width: reach.max - reach.min + m.margin * 2, height: end.y + m.margin)
        if free, tree.reading.contains(where: { $0.at != nil }) { place(tree, metrics: m, editable: editable, style: style, style: style) }
    }

    /// Where a card let go at `point` is kept: its top left corner in the tree's own numbers, centred on the pointer, within reach. `point` is on the
    /// board as drawn, from its left edge; right to left the board is drawn mirrored, so the point is mirrored back.
    public func corner(forDropAt point: CGPoint, of id: String, rightToLeft: Bool) -> CGPoint? {
        guard let card = cards.first(where: { $0.node.id == id }) else { return nil }
        let x = (rightToLeft ? size.width - point.x : point.x) - card.frame.width / 2 - origin.x
        let y = point.y - card.frame.height / 2 - origin.y
        let reach = ExtensionPage.farthestPlace
        return CGPoint(x: min(reach, max(-reach, x.rounded())), y: min(reach, max(-reach, y.rounded())))
    }

    /// Puts the cards the person placed where they put them, none over another card or its controls, and draws the lines between all of
    /// them again in the tree's order: where a card stands never changes what follows what. Branch labels and + spots go with their card.
    private mutating func place(_ tree: ExtensionPage.Tree, metrics m: Metrics, editable: Bool,
                                style: (ExtensionPage.Tree.Node?) -> LineStyle, style branchStyle: (ExtensionPage.Tree.Branch) -> LineStyle) {
        placed = true
        let auto = Dictionary(cards.map { ($0.node.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
        var frames = auto
        var holder: [String: String] = [:]
        for node in tree.reading { for branch in node.branches { holder[branch.id] = node.id } }
        // A card's own controls reach past it: its menu inside, its fold button under it, the + spot over the card after it.
        func reach(_ r: CGRect) -> CGRect { CGRect(x: r.minX - 12, y: r.minY - 12, width: r.width + 24, height: r.height + 64) }
        // Its branches' labels and the + spot or words under each, which go where the card goes.
        func branchRoom(of id: String, at frame: CGRect) -> [CGRect] {
            guard let was = auto[id] else { return [] }
            return labels.filter { holder[$0.branch.id] == id }.map { label in
                CGRect(x: label.point.x - was.minX + frame.minX - 75, y: label.point.y - was.minY + frame.minY - 11, width: 150, height: 74)
            }
        }
        func room(_ id: String, _ frame: CGRect) -> [CGRect] { [reach(frame)] + branchRoom(of: id, at: frame) }
        var taken = cards.filter { $0.node.at == nil }.flatMap { room($0.node.id, $0.frame) }
        let farthest = ExtensionPage.farthestPlace
        for card in cards {
            guard let at = card.node.at else { continue }
            var frame = CGRect(origin: at, size: card.frame.size)
            for _ in 0..<(ExtensionPage.maxTreeNodes * 4) {
                let mine = room(card.node.id, frame)
                guard let hit = taken.first(where: { t in mine.contains { $0.intersects(t) } }) else { break }
                nudged = true
                frame.origin.y = hit.maxY + 16
                // Past the farthest place, the next column along: however many cards are let go on one spot, the board stays bounded.
                if frame.minY > farthest { frame.origin = CGPoint(x: frame.maxX + 40, y: at.y) }
            }
            frames[card.node.id] = frame
            taken += room(card.node.id, frame)
        }
        func moved(_ id: String) -> CGVector {
            guard let now = frames[id], let was = auto[id] else { return .zero }
            return CGVector(dx: now.minX - was.minX, dy: now.minY - was.minY)
        }
        // Each branch's label stays where it was beside the card it splits from, wherever that card went.
        var labelAt: [String: CGPoint] = [:]
        for label in labels {
            let d = holder[label.branch.id].map(moved) ?? .zero
            labelAt[label.branch.id] = CGPoint(x: label.point.x + d.dx, y: label.point.y + d.dy)
        }

        var paths: [Line] = [], spots: [Add] = [], names: [Label] = []
        func top(_ id: String) -> CGPoint { frames[id].map { CGPoint(x: $0.midX, y: $0.minY) } ?? .zero }
        func bottom(_ id: String) -> CGPoint { frames[id].map { CGPoint(x: $0.midX, y: $0.maxY) } ?? .zero }
        func join(_ p: CGPoint, _ q: CGPoint, _ style: LineStyle) {
            guard q.y < p.y else {
                let mid = (p.y + q.y) / 2
                paths.append(Line(points: p.x == q.x ? [p, q] : [p, CGPoint(x: p.x, y: mid), CGPoint(x: q.x, y: mid), q], style: style))
                return
            }
            // Up to a card placed higher: round it on the side it's coming from and in from above, so the line never runs through it.
            let side = q.x + (p.x <= q.x ? -1 : 1) * (m.card.width / 2 + 20)
            paths.append(Line(points: [p, CGPoint(x: p.x, y: p.y + 16), CGPoint(x: side, y: p.y + 16), CGPoint(x: side, y: q.y - 16),
                                       CGPoint(x: q.x, y: q.y - 16), q], style: style))
        }
        /// Lines from where the run is entered to each card in turn; says where its last card is left from.
        func walk(_ nodes: [ExtensionPage.Tree.Node], from entries: [CGPoint]) -> [CGPoint] {
            var exits = entries, previous: String?
            for node in nodes {
                for exit in exits { join(exit, top(node.id), style(node)) }
                if editable, let previous { spots.append(Add(target: previous, point: CGPoint(x: top(node.id).x, y: top(node.id).y - 18), quiet: false)) }
                if node.branches.isEmpty {
                    exits = [bottom(node.id)]
                } else {
                    var ends: [CGPoint] = []
                    for branch in node.branches {
                        let at = labelAt[branch.id] ?? bottom(node.id)
                        join(bottom(node.id), at, branchStyle(branch))
                        names.append(Label(branch: branch, point: at))
                        if branch.nodes.isEmpty {
                            if editable { spots.append(Add(target: branch.id, point: CGPoint(x: at.x, y: at.y + 34), quiet: false, hint: branch.hint)) }
                            ends.append(CGPoint(x: at.x, y: at.y + (editable ? 52 : 14)))
                        } else {
                            if editable { spots.append(Add(target: branch.id, point: CGPoint(x: at.x, y: at.y + 18), quiet: true)) }
                            ends += walk(branch.nodes, from: [CGPoint(x: at.x, y: at.y + 12)])
                        }
                    }
                    exits = ends
                }
                previous = node.id
            }
            if editable, let previous {
                let below = (exits.map(\.y).max() ?? bottom(previous).y) + m.gap / 2
                spots.append(Add(target: previous, point: CGPoint(x: bottom(previous).x, y: below), quiet: false))
            }
            return exits
        }
        _ = walk(tree.nodes, from: [])

        // The board takes in every card, label and + spot, a margin all round.
        let points = frames.values.flatMap { [$0.origin, CGPoint(x: $0.maxX, y: $0.maxY)] } + names.map(\.point) + spots.map(\.point)
        let low = CGPoint(x: points.map(\.x).min() ?? 0, y: points.map(\.y).min() ?? 0)
        let high = CGPoint(x: points.map(\.x).max() ?? 0, y: points.map(\.y).max() ?? 0)
        origin = CGPoint(x: max(0, m.margin - low.x), y: max(0, m.margin - low.y))
        let shift = CGVector(dx: origin.x, dy: origin.y)
        func shifted(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + shift.dx, y: p.y + shift.dy) }
        self.cards = cards.map { Card(node: $0.node, frame: (frames[$0.node.id] ?? $0.frame).offsetBy(dx: shift.dx, dy: shift.dy)) }
        self.lines = paths.map { Line(points: $0.points.map(shifted), style: $0.style) }
        self.adds = spots.map { Add(target: $0.target, point: shifted($0.point), quiet: $0.quiet, hint: $0.hint) }
        self.labels = names.map { Label(branch: $0.branch, point: shifted($0.point)) }
        size = CGSize(width: high.x + shift.dx + m.margin, height: high.y + shift.dy + m.margin)
    }
}

extension ExtensionPage.Tree {
    /// What a card's drag says it carries, for the system's drag. Only a label: which card a drop moves is the board's own record (D233).
    public static let dragPrefix = "sidefolk.tree.card:"

    /// A card a board picked up as its drag started, with the tree's cards as they were then.
    public struct Carry: Sendable, Hashable {
        public var id: String
        public var cards: [String]

        public init(id: String, on tree: ExtensionPage.Tree) {
            self.id = id
            cards = tree.reading.map(\.id)
        }
    }

    /// The card a drop moves: the one this board picked up itself, while the tree still has the same cards, and only when the dropped words
    /// name it. Words alone, from another app, window or tree, move nothing.
    public func dropped(_ words: [String], carried: Carry?) -> String? {
        guard let carried, words.first == Self.dragPrefix + carried.id, carried.cards == reading.map(\.id) else { return nil }
        return carried.id
    }
}
