import SidefolkCore
import SwiftUI

/// A tree of cards that arranges itself (D125): where everything goes is `TreeLayout`'s, what a click means is the extension's tool. Native buttons, read top to bottom,
/// so the keyboard and VoiceOver go through it like any list. Zoom and the small map are only for looking: nothing here changes anything until a card or a + is pressed.
struct PageTreeView: View {
    var tree: ExtensionPage.Tree
    var model: ExtensionPageModel
    @State private var zoom: CGFloat?
    @State private var outline = false
    @FocusState private var boardFocused: Bool
    /// Cards folded and words looked for are the person's view of it, not the tree's: kept here, told to no one.
    @State private var folded: Set<String> = []
    @State private var finding = false
    @State private var words = ""
    @State private var found = 0
    @FocusState private var findFocused: Bool

    private static let zooms: ClosedRange<CGFloat> = 0.5...1.5

    var body: some View {
        if outline {
            TreeOutline(tree: tree, model: model)
                .overlay(alignment: .topLeading) { tools }
                .overlay(alignment: .bottomLeading) { boardOrOutline.padding(Theme.Space.m) }
                .background { DotGrid() }
                .clipped()
        } else {
            board
        }
    }

    private var boardOrOutline: some View {
        Button { outline.toggle() } label: {
            Image(systemName: outline ? "rectangle.connected.to.line.below" : "list.bullet.indent").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                .frame(width: Theme.Size.hitTarget, height: Theme.Size.hitTarget).contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .elevation(.e1)
        .help(outline ? Text("Show as a board", comment: "A tree of cards on an extension's page: the button that goes back from the plain list") : Text("Show as a list", comment: "A tree of cards on an extension's page: the button that shows it as a plain list"))
        .accessibilityLabel(outline ? Text("Show as a board", comment: "A tree of cards on an extension's page: the button that goes back from the plain list") : Text("Show as a list", comment: "A tree of cards on an extension's page: the button that shows it as a plain list"))
    }

    /// The arrows go through the cards in reading order, ⌘ and an arrow moves the selected one, Delete takes it away. Only while the board has the keyboard: a field being typed in keeps its keys.
    private func key(_ press: KeyPress) -> KeyPress.Result {
        let selected = tree.selected
        switch press.key {
        case .upArrow, .downArrow:
            let delta = press.key == .upArrow ? -1 : 1
            if press.modifiers.contains(.command) {
                guard let reorder = tree.reorder, let selected, let move = tree.move(selected, by: delta) else { return .ignored }
                Task { await model.run(tool: reorder.tool, input: reorder.input(move)) }
            } else {
                guard let select = tree.select, let next = tree.neighbour(of: selected, by: delta) else { return .ignored }
                Task { await model.run(tool: select.tool, input: select.input(.string(next))) }
            }
            return .handled
        case .delete, .deleteForward:
            guard let remove = tree.remove, let selected, tree.reading.first(where: { $0.id == selected })?.fixed == false else { return .ignored }
            Task { await model.run(tool: remove.tool, input: remove.input(.string(selected))) }
            return .handled
        default:
            return .ignored
        }
    }

    private var finder: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.inkMuted).accessibilityHidden(true)
            TextField(text: $words, prompt: Text("Find a step", comment: "A tree of cards on an extension's page: the search field")) {
                Text("Find a step", comment: "A tree of cards on an extension's page: the search field")
            }
            .textFieldStyle(.plain).frame(width: 150).focused($findFocused)
            let matches = tree.matching(words)
            if !words.isEmpty {
                Text(verbatim: "\(matches.isEmpty ? 0 : (found % matches.count) + 1)/\(matches.count)").font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.inkMuted)
            }
            Button { finding = false; words = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkFaint) }
                .buttonStyle(.sfBare).keyboardShortcut(.cancelAction)
                .accessibilityLabel(Text("Stop finding", comment: "A tree of cards on an extension's page"))
        }
        .padding(.horizontal, Theme.Space.s).frame(height: 32)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .elevation(.e1)
        .padding(Theme.Space.m)
        .onAppear { findFocused = true }
    }

    private var board: some View {
        let shown = tree.folding(folded)
        let layout = TreeLayout(shown, editable: tree.insert != nil)
        let matches = shown.matching(words)
        return GeometryReader { geo in
            let scale = zoom ?? min(1, max(Self.zooms.lowerBound, min(geo.size.width / max(1, layout.size.width), geo.size.height / max(1, layout.size.height))))
            ScrollViewReader { scroll in
                ScrollView([.horizontal, .vertical]) {
                    TreeCanvas(tree: shown, layout: layout, model: model, folded: $folded, marked: Set(matches))
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: layout.size.width * scale, height: layout.size.height * scale, alignment: .topLeading)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
                }
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) { tools }
                .overlay(alignment: .topTrailing) { if finding { finder.onSubmit { found += 1; if !matches.isEmpty { withAnimation(Theme.Motion.ease(0.25)) { scroll.scrollTo(matches[found % matches.count], anchor: .center) } } } } }
                .overlay(alignment: .bottomLeading) { zooming(scale, fit: { zoom = nil }) }
                .onChange(of: words) { _, _ in
                    found = 0
                    if let first = matches.first { withAnimation(Theme.Motion.ease(0.25)) { scroll.scrollTo(first, anchor: .center) } }
                }
                .background {
                    Button { finding = true; findFocused = true } label: { Text("Find a step", comment: "A tree of cards on an extension's page: the search field") }
                        .keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                }
                .overlay(alignment: .bottomTrailing) {
                    if layout.cards.count >= 4 {
                        TreeMap(layout: layout, line: TreeLine(tree.line)) { id in withAnimation(Theme.Motion.ease(0.25)) { scroll.scrollTo(id, anchor: .center) } }
                            .padding(Theme.Space.m)
                    }
                }
            }
        }
        .background { DotGrid() }
        .clipped()
        .focusable(tree.select != nil)
        .focusEffectDisabled()
        .focused($boardFocused)
        .onKeyPress(phases: .down, action: key)
        // Pressing a card leaves the keyboard here.
        .onChange(of: tree.selected) { _, new in if new != nil, !(NSApp.keyWindow?.firstResponder is NSTextView) { boardFocused = true } }
    }

    @ViewBuilder private var tools: some View {
        if !tree.tools.isEmpty {
            VStack(spacing: Theme.Space.xxs) {
                ForEach(Array(tree.tools.enumerated()), id: \.offset) { _, control in
                    Button { Task { await model.run(control, on: nil) } } label: {
                        Image(systemName: control.symbol ?? "circle").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                            .frame(width: Theme.Size.hitTarget + 4, height: Theme.Size.hitTarget + 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.sfBare)
                    .disabled(control.disabled)
                    .help(Text(ext: control.detail ?? control.label))
                    .accessibilityLabel(Text(ext: control.label))
                }
            }
            .padding(Theme.Space.xxs)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .elevation(.e1)
            .padding(Theme.Space.m)
        }
    }

    private func zooming(_ scale: CGFloat, fit: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Space.xs) {
            if tree.select != nil { boardOrOutline }
            Button(action: fit) { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: Theme.Size.hitTarget, height: Theme.Size.hitTarget).contentShape(Rectangle()) }
                .buttonStyle(.sfBare)
                .help(Text("Fit to the window", comment: "A tree of cards on an extension's page: the zoom button that fits it all in"))
                .accessibilityLabel(Text("Fit to the window", comment: "A tree of cards on an extension's page: the zoom button that fits it all in"))
            HStack(spacing: 0) {
                Button { zoom = max(Self.zooms.lowerBound, scale - 0.1) } label: { Image(systemName: "minus").frame(width: Theme.Size.hitTarget, height: Theme.Size.hitTarget).contentShape(Rectangle()) }
                    .buttonStyle(.sfBare).keyboardShortcut("-", modifiers: .command)
                    .accessibilityLabel(Text("Zoom out", comment: "A tree of cards on an extension's page"))
                Text(scale, format: .percent.precision(.fractionLength(0))).font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.inkMuted).frame(minWidth: 40)
                Button { zoom = min(Self.zooms.upperBound, scale + 0.1) } label: { Image(systemName: "plus").frame(width: Theme.Size.hitTarget, height: Theme.Size.hitTarget).contentShape(Rectangle()) }
                    .buttonStyle(.sfBare).keyboardShortcut("=", modifiers: .command)
                    .accessibilityLabel(Text("Zoom in", comment: "A tree of cards on an extension's page"))
            }
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.Space.xxs)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .elevation(.e1)
        .padding(Theme.Space.m)
    }
}

/// A tree's line: its colours, or the app's action colour.
struct TreeLine {
    var from: Color
    var to: Color

    init(_ hexes: [String]) {
        let first = hexes.first.flatMap { Color(extensionHex: $0) } ?? Theme.accent
        from = first
        to = hexes.last.flatMap { Color(extensionHex: $0) } ?? first
    }
}

// MARK: The board

nonisolated private struct TreeFrameKey: LayoutValueKey { static let defaultValue = CGRect.zero }

/// Places each thing where the numbers say. A layout, so right to left mirrors it with everything else.
private struct TreeBoard: Layout {
    var size: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { size }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews {
            let frame = view[TreeFrameKey.self]
            view.place(at: CGPoint(x: bounds.minX + frame.midX, y: bounds.minY + frame.midY), anchor: .center, proposal: ProposedViewSize(frame.size))
        }
    }
}

private extension View {
    func treeFrame(_ frame: CGRect) -> some View { layoutValue(key: TreeFrameKey.self, value: frame) }
    func treeCenter(_ point: CGPoint, side: CGFloat) -> some View { treeFrame(CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)) }
}

private struct TreeCanvas: View {
    var tree: ExtensionPage.Tree
    var layout: TreeLayout
    var model: ExtensionPageModel
    @Binding var folded: Set<String>
    var marked: Set<String>

    var body: some View {
        let line = TreeLine(tree.line)
        ZStack(alignment: .topLeading) {
            TreeLines(lines: layout.lines, line: line, size: layout.size)
            TreeBoard(size: layout.size) {
                ForEach(layout.cards, id: \.node.id) { card in
                    TreeCard(node: card.node, tree: tree, line: line, model: model, folded: $folded, marked: marked.contains(card.node.id)).treeFrame(card.frame).id(card.node.id)
                }
                ForEach(layout.labels, id: \.branch.id) { label in
                    TreeBranchLabel(branch: label.branch).fixedSize().treeFrame(CGRect(x: label.point.x - 60, y: label.point.y - 11, width: 120, height: 22))
                }
                if let insert = tree.insert {
                    ForEach(layout.adds, id: \.target) { add in
                        TreeAddButton(add: add, hook: insert, picker: tree.picker, tree: tree, line: line, model: model)
                            .treeFrame(add.hint == nil ? CGRect(x: add.point.x - 18, y: add.point.y - 18, width: 36, height: 36) : CGRect(x: add.point.x - 75, y: add.point.y - 18, width: 150, height: 36))
                    }
                }
                if model.page?.companion == true, let active = layout.cards.first(where: { $0.node.state == .active }) {
                    TreeCompanion(model: model)
                        .treeFrame(CGRect(x: active.frame.minX - 8, y: active.frame.minY - 40, width: 48, height: 48))
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }
}

/// The lines, corners rounded; what's happening now moves along its line unless the person asked for less motion.
private struct TreeLines: View {
    var lines: [TreeLayout.Line]
    var line: TreeLine
    var size: CGSize
    var corner: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for one in lines { draw(one, in: &context, phase: nil) }
            }
            if !still, lines.contains(where: { $0.style == .live }) {
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { time in
                    Canvas { context, _ in
                        let phase = CGFloat(time.date.timeIntervalSinceReferenceDate * 24)
                        for one in lines where one.style == .live { draw(one, in: &context, phase: phase) }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .flipsForRightToLeftLayoutDirection(true)
        .accessibilityHidden(true)
    }

    private func draw(_ one: TreeLayout.Line, in context: inout GraphicsContext, phase: CGFloat?) {
        let path = Self.path(one.points, corner: corner)
        let ys = one.points.map(\.y)
        let paint = GraphicsContext.Shading.linearGradient(Gradient(colors: [line.from, line.to]), startPoint: CGPoint(x: 0, y: ys.min() ?? 0), endPoint: CGPoint(x: 0, y: max((ys.max() ?? 1), (ys.min() ?? 0) + 1)))
        if let phase {
            context.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 14], dashPhase: -phase))
            return
        }
        switch one.style {
        case .solid, .live: context.stroke(path, with: paint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        case .dashed: context.stroke(path, with: paint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 5]))
        case .faded: context.stroke(path, with: .color(Theme.inkFaint.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    static func path(_ points: [CGPoint], corner: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in points.indices.dropFirst().dropLast() {
            let room = min(hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y), hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)) / 2
            path.addArc(tangent1End: points[i], tangent2End: points[i + 1], radius: min(corner, room))
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }
}

// MARK: Its parts

private struct TreeCard: View {
    var node: ExtensionPage.Tree.Node
    var tree: ExtensionPage.Tree
    var line: TreeLine
    var model: ExtensionPageModel
    @Binding var folded: Set<String>
    var marked = false
    @State private var hovering = false
    @State private var dropping = false
    @Environment(\.pageSelected) private var chosen

    private var selected: Bool { tree.selected == node.id }
    private var hasActions: Bool { !node.fixed && (tree.remove != nil || (tree.reorder != nil && !tree.spots(for: node.id).isEmpty)) }
    /// One colour on a card's edge: the line alone runs from one to the other.
    private var edge: Color { chosen ?? line.to }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        Button {
            guard let select = tree.select else { return }
            Task { await model.run(tool: select.tool, input: select.input(.string(node.id))) }
        } label: {
            HStack(spacing: Theme.Space.m) {
                TreeTile(symbol: node.symbol, color: node.color, side: 40, tone: node.state == .attention ? .warn : nil)
                VStack(alignment: .leading, spacing: 1) {
                    if let kind = node.kind { Text(ext: kind).font(Theme.Font.headline).foregroundStyle(Theme.ink).lineLimit(1) }
                    Text(ext: node.title).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(node.kind == nil ? 3 : 2)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardFill, in: shape)
            .overlay { outline }
            .contentShape(shape)
        }
        .buttonStyle(.sfBare)
        // Nothing to press on a tree that only shows, without looking pressed-out.
        .allowsHitTesting(tree.select != nil)
        .opacity(node.state == .skipped ? 0.55 : 1)
        .elevation(node.state == .pending || node.state == .skipped ? .e0 : (hovering ? .e2 : .e1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(ext: spoken))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityActions { actions }
        // Beside the card's button, not in it: a control inside a button's label isn't sure to get its click.
        .overlay(alignment: .trailing) { menu }
        .overlay { if dropping { shape.strokeBorder(line.to, style: StrokeStyle(lineWidth: 2, dash: [5, 4])) } }
        .overlay { if marked { shape.strokeBorder(line.from, lineWidth: 3) } }
        .overlay(alignment: .bottom) { foldButton }
        .onHover { hovering = $0 }
        .contextMenu { actions }
        .modifier(TreeCardDrag(node: node, tree: tree, model: model, dropping: $dropping))
    }

    /// Its kind, what it does and its state: what the card shows, said in that order.
    private var spoken: String { [node.kind, node.title, node.pill?.text].compactMap(\.self).joined(separator: ", ") }

    private var cardFill: Color {
        if node.state == .attention { return ExtensionPage.Tone.warn.soft }
        return node.state == .pending ? Theme.surfaceRaised.opacity(0.75) : Theme.surfaceRaised
    }

    @ViewBuilder private var outline: some View {
        if selected {
            shape.strokeBorder(edge, lineWidth: 2)
        } else if node.state == .attention {
            shape.strokeBorder(ExtensionPage.Tone.warn.color, lineWidth: 1.5)
        } else if node.state == .pending {
            shape.strokeBorder(edge.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        } else if node.state == .active {
            shape.strokeBorder(edge, lineWidth: 2)
        } else {
            shape.strokeBorder(Theme.line)
        }
    }

    @ViewBuilder private var trailing: some View {
        if let pill = node.pill {
            TreePill(badge: pill)
        } else if node.state == .done {
            Image(systemName: ExtensionPage.Tone.good.symbol).font(.system(size: 18)).foregroundStyle(ExtensionPage.Tone.good.color)
                .accessibilityLabel(Text("Done", comment: "A card on an extension's page: what it is about is done for today"))
        }
        // Room for the menu, so a pill doesn't run under it.
        if hasActions { Color.clear.frame(width: 16, height: 1) }
    }

    /// Folds what hangs from a card, or brings it back. The board's alone: nothing about the tree changes.
    @ViewBuilder private var foldButton: some View {
        if !node.branches.isEmpty || node.folded != nil {
            Button { if node.folded != nil { folded.remove(node.id) } else { folded.insert(node.id) } } label: {
                HStack(spacing: 3) {
                    Image(systemName: node.folded != nil ? "chevron.down" : "chevron.up").font(.system(size: 9, weight: .bold))
                    if let held = node.folded { Text("\(held) inside", comment: "A folded card on a tree: how many cards it holds out of sight").font(Theme.Font.caption) }
                }
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 7).frame(height: 18)
                .background(Theme.surfaceRaised, in: Capsule()).overlay(Capsule().strokeBorder(Theme.line))
                .contentShape(Capsule())
            }
            .buttonStyle(.sfBare)
            .offset(y: 9)
            .accessibilityLabel(node.folded != nil ? Text("Show what's inside", comment: "A folded card on a tree") : Text("Fold what's inside", comment: "A card with branches on a tree"))
        }
    }

    @ViewBuilder private var menu: some View {
        if hasActions, hovering || selected {
            Menu { actions } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted).frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .tint(Theme.inkMuted)
                .padding(.trailing, Theme.Space.xs)
                .help(Text("More", comment: "A card on an extension's page: its menu"))
                .accessibilityLabel(Text("More", comment: "A card on an extension's page: its menu"))
        }
    }

    private var actions: some View { TreeCardActions(node: node, tree: tree, model: model) }
}

/// What can be done to a card, the same on its menu, under a right click, in the outline and for VoiceOver.
struct TreeCardActions: View {
    var node: ExtensionPage.Tree.Node
    var tree: ExtensionPage.Tree
    var model: ExtensionPageModel

    var body: some View {
        if let reorder = tree.reorder, !node.fixed {
            if let up = tree.move(node.id, by: -1) {
                Button { Task { await model.run(tool: reorder.tool, input: reorder.input(up)) } } label: { Text("Move up", comment: "A row or card on an extension's page: its menu") }
            }
            if let down = tree.move(node.id, by: 1) {
                Button { Task { await model.run(tool: reorder.tool, input: reorder.input(down)) } } label: { Text("Move down", comment: "A row or card on an extension's page: its menu") }
            }
            let spots = tree.spots(for: node.id)
            if !spots.isEmpty {
                Menu {
                    ForEach(spots) { spot in
                        Button {
                            guard let place = tree.place(node.id, after: spot.id) else { return }
                            Task { await model.run(tool: reorder.tool, input: reorder.input(place)) }
                        } label: { Text(verbatim: Self.words(spot)) }
                    }
                } label: { Text("Move to", comment: "A card on an extension's page: its menu, listing everywhere it can go") }
            }
        }
        if let remove = tree.remove, !node.fixed {
            Button(role: .destructive) { Task { await model.run(tool: remove.tool, input: remove.input(.string(node.id))) } } label: { Text("Remove", comment: "A card on an extension's page: its menu") }
        }
    }

    private static func words(_ spot: ExtensionPage.Tree.Spot) -> String {
        let indent = String(repeating: "    ", count: spot.depth)
        switch spot.place {
        case .after(let title): return indent + String(localized: "After “\(title.clipped(40))”", comment: "Where a card can move to, in a list of the cards it can follow")
        case .start(let branch, let of): return indent + String(localized: "First under “\(branch)” of “\(of.clipped(30))”", comment: "Where a card can move to: the start of a path that splits from another card")
        }
    }
}

/// The same tree as a plain list: every card with its place in the structure, for reading through, moving precisely and VoiceOver. Nothing here means anything of its own.
struct TreeOutline: View {
    var tree: ExtensionPage.Tree
    var model: ExtensionPageModel
    @Environment(\.pageSelected) private var chosen

    private enum Row: Identifiable {
        case card(ExtensionPage.Tree.Node, depth: Int)
        case branch(ExtensionPage.Tree.Branch, depth: Int)
        var id: String {
            switch self {
            case .card(let n, _): "card-\(n.id)"
            case .branch(let b, _): "branch-\(b.id)"
            }
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        func walk(_ nodes: [ExtensionPage.Tree.Node], _ depth: Int) {
            for node in nodes {
                out.append(.card(node, depth: depth))
                for branch in node.branches {
                    out.append(.branch(branch, depth: depth + 1))
                    walk(branch.nodes, depth + 2)
                }
            }
        }
        walk(tree.nodes, 0)
        return out
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xxs) {
                ForEach(rows) { row in
                    switch row {
                    case .card(let node, let depth): card(node).padding(.leading, CGFloat(depth) * 18)
                    case .branch(let branch, let depth):
                        Text(ext: branch.label).font(Theme.Font.caption.weight(.semibold)).foregroundStyle(branch.tone == .neutral ? Theme.inkMuted : branch.tone.color)
                            .padding(.leading, CGFloat(depth) * 18).padding(.top, Theme.Space.xs)
                    }
                }
            }
            .padding(EdgeInsets(top: Theme.Space.m, leading: 64, bottom: Theme.Space.xxl, trailing: Theme.Space.l))
        }
    }

    private func card(_ node: ExtensionPage.Tree.Node) -> some View {
        Button {
            guard let select = tree.select else { return }
            Task { await model.run(tool: select.tool, input: select.input(.string(node.id))) }
        } label: {
            HStack(spacing: Theme.Space.s) {
                TreeTile(symbol: node.symbol, color: node.color, side: 26, tone: node.state == .attention ? .warn : nil)
                if let kind = node.kind { Text(ext: kind).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1) }
                Text(ext: node.title).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                if let pill = node.pill { TreePill(badge: pill) }
            }
            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xxs + 2)
            .background(tree.selected == node.id ? (chosen ?? Theme.accent).opacity(0.12) : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .contextMenu { TreeCardActions(node: node, tree: tree, model: model) }
        .accessibilityActions { TreeCardActions(node: node, tree: tree, model: model) }
        .accessibilityAddTraits(tree.selected == node.id ? .isSelected : [])
    }
}

/// Picks a card up, and takes one dropped on it to stand right after it. The system's own drag: the words carried are only the card's id, and only a card of this tree lands.
private struct TreeCardDrag: ViewModifier {
    var node: ExtensionPage.Tree.Node
    var tree: ExtensionPage.Tree
    var model: ExtensionPageModel
    @Binding var dropping: Bool

    /// Marks a drag as a card's, so words dragged in from elsewhere land nowhere.
    static let carrying = "sidefolk.tree.card:"
    static func card(in dragged: [String]) -> String? { dragged.first?.hasPrefix(carrying) == true ? dragged.first.map { String($0.dropFirst(carrying.count)) } : nil }

    func body(content: Content) -> some View {
        if let reorder = tree.reorder {
            content
                .treeDraggable(node.fixed ? nil : TreeCardDrag.carrying + node.id)
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = TreeCardDrag.card(in: ids), let place = tree.place(id, after: node.id) else { return false }
                    Task { await model.run(tool: reorder.tool, input: reorder.input(place)) }
                    return true
                } isTargeted: { dropping = $0 }
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder func treeDraggable(_ id: String?) -> some View {
        if let id { draggable(id) } else { self }
    }
}

/// A symbol on its soft tile: the colour says what kind of thing it is, never how it went.
struct TreeTile: View {
    var symbol: String?
    var color: String?
    var side: CGFloat
    var tone: ExtensionPage.Tone?

    var body: some View {
        let tint = tone?.color ?? color.flatMap { Color(extensionHex: $0) } ?? Theme.accent
        Image(systemName: symbol ?? "circle").font(.system(size: side * 0.42, weight: .medium)).foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: side * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A word and its colour, soft (D78).
struct TreePill: View {
    var badge: ExtensionPage.Badge
    @Environment(\.pageSelected) private var accent
    @Environment(\.colorScheme) private var scheme

    /// "Info" says nothing good or bad: on a page with its own accent, it's in that, not a second brand colour beside it.
    private var selection: PageSelection? { badge.tone == .info && accent != nil ? PageSelection(accent: accent, dark: scheme == .dark) : nil }

    var body: some View {
        Text(ext: badge.text).font(Theme.Font.caption.weight(.medium)).lineLimit(1)
            .foregroundStyle(selection?.ink ?? (badge.tone == .neutral ? Theme.inkMuted : badge.tone.color))
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
            .background(selection?.soft ?? (badge.tone == .neutral ? Theme.well : badge.tone.soft), in: Capsule())
            .fixedSize()
    }
}

private struct TreeBranchLabel: View {
    var branch: ExtensionPage.Tree.Branch

    var body: some View {
        Text(ext: branch.label).font(Theme.Font.caption.weight(.semibold)).lineLimit(1)
            .foregroundStyle(branch.taken == false ? Theme.inkMuted : (branch.tone == .neutral ? Theme.ink : branch.tone.color))
            .padding(.horizontal, Theme.Space.s + 2).padding(.vertical, 3)
            .background(branch.taken == false ? Theme.well : (branch.tone == .neutral ? Theme.surfaceRaised : branch.tone.soft), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))
    }
}

/// The person's own companion in its light, standing by what's happening now.
private struct TreeCompanion: View {
    var model: ExtensionPageModel

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.glow.opacity(0.55), Theme.glow.opacity(0)], center: .center, startRadius: 2, endRadius: 30)).frame(width: 60, height: 60)
            PagePictureView(picture: .companion(.full), model: model, side: 96, fill: false).frame(width: 44, height: 44)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TreeAddButton: View {
    var add: TreeLayout.Add
    var hook: ExtensionPage.Steps.Hook
    var picker: ExtensionPage.Tree.Picker?
    var tree: ExtensionPage.Tree
    var line: TreeLine
    var model: ExtensionPageModel
    @State private var hovering = false
    @State private var picking = false
    @State private var dropping = false
    private var reorder: ExtensionPage.Steps.Hook? { tree.reorder }
    @FocusState private var focused: Bool
    // A popover has an environment of its own.
    @Environment(\.pageSelected) private var accent

    var body: some View {
        Button {
            if picker == nil {
                Task { await model.run(tool: hook.tool, input: hook.input(.string(add.target))) }
            } else {
                picking = true
            }
        } label: {
            if let hint = add.hint {
                Label { Text(ext: hint).lineLimit(1) } icon: { Image(systemName: "plus") }
                    .font(Theme.Font.callout).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Space.m)
                    .frame(height: 30)
                    .background(Theme.surfaceRaised, in: Capsule())
                    .overlay(Capsule().strokeBorder(hovering || dropping ? line.to : Theme.line, style: StrokeStyle(lineWidth: dropping ? 2 : 1, dash: [4, 3])))
                    .contentShape(Capsule())
            } else {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 22, height: 22)
                    .background(Theme.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(hovering || dropping ? line.to : Theme.line, lineWidth: dropping ? 2 : 1))
                    .scaleEffect(dropping ? 1.4 : 1)
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.sfBare)
        .focused($focused)
        .onHover { hovering = $0 }
        .opacity(add.quiet && !hovering && !focused && !picking && !dropping ? 0 : 1)
        .help(Text(ext: hook.label ?? ""))
        .accessibilityLabel(Text(ext: hook.label ?? ""))
        // A card dragged here lands at this spot: on either side of the +, so it needn't be hit exactly.
        .frame(minWidth: 36, minHeight: 36)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            guard let reorder, let id = TreeCardDrag.card(in: ids), let place = tree.place(id, after: add.target) else { return false }
            Task { await model.run(tool: reorder.tool, input: reorder.input(place)) }
            return true
        } isTargeted: { dropping = $0 }
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            if let picker {
                TreePicker(picker: picker, accent: accent) { id in
                    picking = false
                    Task { await model.run(tool: hook.tool, input: hook.input(.string(add.target)).setting(picker.key, .string(id))) }
                }
            }
        }
    }
}

/// What can be added, found by typing or by category, and picked with the arrows and Return.
struct TreePicker: View {
    var picker: ExtensionPage.Tree.Picker
    var accent: Color?
    var choose: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var words = ""
    @State private var category: String?
    @State private var at = 0
    @FocusState private var typing: Bool

    private var selection: PageSelection { PageSelection(accent: accent, dark: scheme == .dark) }

    private var shown: [ExtensionPage.Tree.Picker.Item] {
        let wanted = words.trimmingCharacters(in: .whitespaces).lowercased()
        return picker.items.filter { item in
            if !wanted.isEmpty { return "\(item.title) \(item.detail ?? "") \(item.meta ?? "")".lowercased().contains(wanted) }
            guard let category = category ?? picker.categories.first?.id else { return true }
            return item.categories.isEmpty || item.categories.contains(category)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
                TextField(text: $words, prompt: Text(verbatim: "")) { Text(ext: picker.placeholder ?? "") }
                    .fieldHint(Text(ext: picker.placeholder ?? ""), showing: words.isEmpty, spoken: false)
                    .textFieldStyle(.plain).font(Theme.Font.body).focused($typing)
                    .onSubmit { if shown.indices.contains(at) { choose(shown[at].id) } }
                    .onKeyPress(.downArrow) { at = min(at + 1, shown.count - 1); return .handled }
                    .onKeyPress(.upArrow) { at = max(at - 1, 0); return .handled }
                    .onChange(of: words) { at = 0 }
            }
            .padding(Theme.Space.m)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                if !picker.categories.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(picker.categories) { c in
                            let on = (category ?? picker.categories.first?.id) == c.id && words.isEmpty
                            Button {
                                category = c.id
                                words = ""
                                at = 0
                            } label: {
                                Label { Text(ext: c.label).lineLimit(1) } icon: { Image(systemName: c.symbol ?? "circle") }
                                    .font(Theme.Font.callout).foregroundStyle(on ? selection.ink : Theme.ink)
                                    .padding(.horizontal, Theme.Space.s).padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(on ? selection.soft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.sfBare)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(Theme.Space.s)
                    .frame(width: 150)
                    Divider()
                }
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                                row(item, on: index == at).id(item.id)
                            }
                        }
                        .padding(Theme.Space.s)
                    }
                    .onChange(of: at) { if shown.indices.contains(at) { scroll.scrollTo(shown[at].id) } }
                }
            }
            .frame(height: 320)
            if let note = picker.note {
                Divider()
                Text(ext: note).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).padding(Theme.Space.s).frame(maxWidth: .infinity)
            }
        }
        .frame(width: 520)
        .onAppear { typing = true }
    }

    private func row(_ item: ExtensionPage.Tree.Picker.Item, on: Bool) -> some View {
        Button { choose(item.id) } label: {
            HStack(spacing: Theme.Space.s) {
                TreeTile(symbol: item.symbol, color: item.color, side: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(ext: item.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                    if let detail = item.detail { Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if let meta = item.meta { TreePill(badge: ExtensionPage.Badge(text: meta, tone: .neutral)) }
            }
            .padding(Theme.Space.xs)
            .background(on ? selection.soft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
    }
}

/// The whole tree small: a click goes there.
private struct TreeMap: View {
    var layout: TreeLayout
    var line: TreeLine
    var go: (String) -> Void

    private static let side: CGFloat = 104

    var body: some View {
        let scale = min((Self.side - 12) / max(1, layout.size.width), (Self.side - 12) / max(1, layout.size.height))
        let inset = CGPoint(x: (Self.side - layout.size.width * scale) / 2, y: (Self.side - layout.size.height * scale) / 2)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                func place(_ p: CGPoint) -> CGPoint { CGPoint(x: inset.x + p.x * scale, y: inset.y + p.y * scale) }
                for one in layout.lines {
                    let path = TreeLines.path(one.points.map(place), corner: 3)
                    context.stroke(path, with: .color(one.style == .faded ? Theme.inkFaint.opacity(0.4) : line.to.opacity(0.7)), lineWidth: 1)
                }
            }
            ForEach(layout.cards, id: \.node.id) { card in
                Button { go(card.node.id) } label: {
                    RoundedRectangle(cornerRadius: 2).fill(line.to.opacity(card.node.state == .skipped ? 0.12 : 0.3)).contentShape(Rectangle())
                }
                .buttonStyle(.sfBare)
                .frame(width: max(8, card.frame.width * scale), height: max(4, card.frame.height * scale))
                .offset(x: inset.x + card.frame.minX * scale, y: inset.y + card.frame.minY * scale)
                .accessibilityHidden(true)
            }
        }
        .frame(width: Self.side, height: Self.side, alignment: .topLeading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .elevation(.e1)
        .flipsForRightToLeftLayoutDirection(true)
    }
}

/// A tree's small drawing of itself at a card's foot (`Card.tree`): its shape, for recognising it.
struct TreeMini: View {
    var tree: ExtensionPage.Tree

    var body: some View {
        let layout = TreeLayout(tree, editable: false, metrics: .mini)
        let line = TreeLine(tree.line)
        ZStack(alignment: .topLeading) {
            TreeLines(lines: layout.lines, line: line, size: layout.size, corner: 4)
            TreeBoard(size: layout.size) {
                ForEach(layout.cards, id: \.node.id) { card in
                    let tint = card.node.color.flatMap { Color(extensionHex: $0) } ?? line.to
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(card.node.state == .pending ? Color.clear : tint.opacity(0.16))
                        .overlay {
                            if card.node.state == .pending {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            }
                        }
                        .overlay { Image(systemName: card.node.symbol ?? "circle").font(.system(size: 8, weight: .semibold)).foregroundStyle(card.node.state == .pending ? Theme.inkFaint : tint) }
                        .treeFrame(card.frame)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// A tree small enough for a card in Ask (D125), with its words: what was just made, where it was asked for. Fits the width it's given.
struct TreeCompact: View {
    var tree: ExtensionPage.Tree

    var body: some View {
        let layout = TreeLayout(tree, editable: false, metrics: .compact)
        let line = TreeLine(tree.line)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                TreeLines(lines: layout.lines, line: line, size: layout.size, corner: 8)
                TreeBoard(size: layout.size) {
                    ForEach(layout.cards, id: \.node.id) { card in
                        HStack(spacing: Theme.Space.xs) {
                            TreeTile(symbol: card.node.symbol, color: card.node.color, side: 24, tone: card.node.state == .attention ? .warn : nil)
                            Text(ext: card.node.title).font(Theme.Font.caption).foregroundStyle(Theme.ink).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.Space.xs)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .strokeBorder(card.node.state == .pending ? line.to.opacity(0.7) : Theme.line, style: StrokeStyle(lineWidth: 1, dash: card.node.state == .pending ? [4, 3] : []))
                        }
                        .treeFrame(card.frame)
                    }
                    ForEach(layout.labels, id: \.branch.id) { label in
                        TreeBranchLabel(branch: label.branch).fixedSize().treeFrame(CGRect(x: label.point.x - 40, y: label.point.y - 9, width: 80, height: 18))
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            .scaleEffect(min(1, geo.size.width / max(1, layout.size.width), geo.size.height / max(1, layout.size.height)), anchor: .topLeading)
            .frame(width: geo.size.width, alignment: .leading)
        }
        .aspectRatio(layout.size.width / max(1, layout.size.height), contentMode: .fit)
        // However long the tree: what's under it stays in reach.
        .frame(maxWidth: layout.size.width, maxHeight: min(layout.size.height, 280))
        .accessibilityElement(children: .combine)
    }
}

/// A page's faint dots: paper for the tree to stand on.
struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.6, height: 1.6))
            let tone = GraphicsContext.Shading.color(Theme.inkFaint.opacity(0.28))
            var y: CGFloat = 8
            while y < size.height {
                var x: CGFloat = 8
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: tone)
                    x += 18
                }
                y += 18
            }
        }
        .accessibilityHidden(true)
    }
}
