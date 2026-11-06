import SidefolkCore
import SwiftUI

/// A tree of cards that arranges itself (D125): where everything goes is `TreeLayout`'s, what a click means is the extension's tool. Native buttons, read top to bottom,
/// so the keyboard and VoiceOver go through it like any list. Zoom and the small map are only for looking: nothing here changes anything until a card or a + is pressed.
/// It handles like a whiteboard (D233): pinch or ⌘+ ⌘− to zoom around the pointer, two fingers to move about, ⌘0 to fit; a carried card shows every place it can go.
struct PageTreeView: View {
    var tree: ExtensionPage.Tree
    var model: ExtensionPageModel
    @State private var zoom: CGFloat?
    @State private var pinchStart: CGFloat?
    @State private var position = ScrollPosition(idType: String.self)
    @State private var offset = CGPoint.zero
    @State private var pointer: CGPoint?
    /// The card being dragged, while it is, and the tree it was picked up from: every place it can go shows, and only it lands.
    @State private var carried: ExtensionPage.Tree.Carry?
    /// The edge a carried card is held at, which the board scrolls toward.
    @State private var edge: CGRectEdge?
    @State private var outline = false
    @FocusState private var boardFocused: Bool
    /// Cards folded and words looked for are the person's view of it, not the tree's: kept here, told to no one.
    @State private var folded: Set<String> = []
    @State private var finding = false
    @State private var words = ""
    @State private var found = 0
    @FocusState private var findFocused: Bool

    #if DEBUG
    /// A dev command's carry, with no mouse button to let go of.
    @State private var held = false
    @Environment(\.treeSnapshot) private var snapshot
    private var carrying: String? { carried?.id ?? snapshot.carrying }
    #else
    private var carrying: String? { carried?.id }
    #endif

    /// A card let go at a spot: it moves only if it's the one this board picked up, on the tree as it was then. The board forgets it either way.
    private func land(_ words: [String], after target: String, on shown: ExtensionPage.Tree) -> Bool {
        defer { carried = nil; edge = nil }
        guard let id = shown.dropped(words, carried: carried) else { return false }
        return TreeCardDrag.move(id, after: target, tree: shown, model: model)
    }

    /// A card let go on the board's empty space (D234): the extension is told where it now stands, its top left corner, centred on the pointer.
    /// Only for looking: nothing about what follows what changes, and the same rule as `land` says which card it is.
    private func put(_ words: [String], at point: CGPoint, layout: TreeLayout, on shown: ExtensionPage.Tree) -> Bool {
        defer { carried = nil; edge = nil }
        guard let placed = shown.placed, let id = shown.dropped(words, carried: carried), let card = layout.cards.first(where: { $0.node.id == id }) else { return false }
        let x = (point.x - card.frame.width / 2 - layout.origin.x).rounded(), y = (point.y - card.frame.height / 2 - layout.origin.y).rounded()
        Task { await model.run(tool: placed.tool, input: placed.input(["id": .string(id), "x": .number(Double(x)), "y": .number(Double(y))])) }
        return true
    }

    /// Back to the board laying itself out: every place the person chose is forgotten, by the extension, in one call.
    private func tidy(_ shown: ExtensionPage.Tree) {
        guard let placed = shown.placed else { return }
        Task { await model.run(tool: placed.tool, input: placed.input(["clear": true])) }
    }

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
        let layout = TreeLayout(shown, editable: tree.insert != nil, free: true)
        let matches = shown.matching(words)
        return GeometryReader { geo in
            let scale = zoom ?? startZoom ?? TreeZoom.fit(layout.size, in: geo.size)
            let rescale = { (wanted: CGFloat, anchor: CGPoint?) in self.rescale(to: wanted, around: anchor, from: scale, view: geo.size) }
            ScrollViewReader { scroll in
                ScrollView([.horizontal, .vertical]) {
                    TreeCanvas(tree: shown, layout: layout, model: model, folded: $folded, marked: Set(matches), carried: carrying,
                               carry: { id in carried = id.map { ExtensionPage.Tree.Carry(id: $0, on: shown) } },
                               land: { land($0, after: $1, on: shown) }, put: { put($0, at: $1, layout: layout, on: shown) })
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: layout.size.width * scale, height: layout.size.height * scale, alignment: .topLeading)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
                }
                .scrollContentBackground(.hidden)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, new in offset = new }
                .onContinuousHover { phase in if case .active(let at) = phase { pointer = at } else { pointer = nil } }
                // A pinch zooms around where it started, as on any board; scrolling goes on beside it.
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? scale
                        if pinchStart == nil { pinchStart = scale }
                        rescale(start * value.magnification, value.startLocation)
                    }
                    .onEnded { _ in pinchStart = nil })
                .overlay { if carrying != nil { edges } }
                #if DEBUG
                .onReceive(NotificationCenter.default.publisher(for: Self.devZoom)) { note in
                    guard let (factor, at) = note.object as? (CGFloat, CGPoint?) else { return }
                    rescale(scale * factor, at)
                }
                .onReceive(NotificationCenter.default.publisher(for: Self.devDrop)) { note in
                    // As a drop by hand, through the same door: only the card `treeCarry:` picked up moves.
                    guard let pair = note.object as? [String], pair.count == 2 else { return }
                    let moved = land([ExtensionPage.Tree.dragPrefix + pair[0]], after: pair[1], on: shown)
                    NSLog("treeDrop: %@ after %@ → %@", pair[0], pair[1], moved ? "moved" : "refused")
                    held = false
                }
                #endif
                .overlay(alignment: .topLeading) { tools }
                .overlay(alignment: .topTrailing) { if finding { finder.onSubmit { found += 1; if !matches.isEmpty { withAnimation(Theme.Motion.ease(0.25)) { scroll.scrollTo(matches[found % matches.count], anchor: .center) } } } } }
                .overlay(alignment: .bottomLeading) { zooming(scale, fit: { zoom = nil }, by: { rescale(scale + $0, pointer) }, tidy: layout.placed && shown.placed != nil ? (layout.nudged, { tidy(shown) }) : nil) }
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
        // A drop forgets the carried card as it lands. A drag let go anywhere else (Esc is the drag's own way out) is forgotten a second
        // after the button comes up: long enough that the drop that comes with letting go still finds it.
        .task(id: carried) {
            guard carried != nil else { return }
            var up = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                #if DEBUG
                if held { continue }
                #endif
                up = NSEvent.pressedMouseButtons & 1 == 0 ? up + 1 : 0
                if up >= 7 {
                    carried = nil
                    edge = nil
                    return
                }
            }
        }
        .task(id: edge) {
            guard let edge else { return }
            while !Task.isCancelled {
                position.scrollTo(point: TreeZoom.nudged(offset, toward: edge))
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: Self.devCarry)) { note in
            // `<id>` stays carried until a drop; `<id>:loose` is let go of at once, as a drag whose button came up.
            let words = (note.object as? String)?.split(separator: ":").map(String.init) ?? []
            carried = words.first.map { ExtensionPage.Tree.Carry(id: $0, on: tree.folding(folded)) }
            held = carried != nil && words.last != "loose"
        }
        #endif
        // Pressing a card leaves the keyboard here.
        .onChange(of: tree.selected) { _, new in if new != nil, !(NSApp.keyWindow?.firstResponder is NSTextView) { boardFocused = true } }
    }

    #if DEBUG
    /// `treeZoom:`, `treeCarry:` and `treeDrop:` in scripts/dev.swift: a pinch, a card picked up, a card let go, as the person's would.
    static let devZoom = Notification.Name("sidefolk.dev.treeZoom")
    static let devCarry = Notification.Name("sidefolk.dev.treeCarry")
    static let devDrop = Notification.Name("sidefolk.dev.treeDrop")
    #endif

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

    /// Zooms, keeping what's under `anchor` (the pointer, or else the middle) where it is. Only the view changes.
    private func rescale(to wanted: CGFloat, around anchor: CGPoint?, from old: CGFloat, view: CGSize) {
        let new = TreeZoom.clamped(wanted)
        guard new != old else { return }
        let target = TreeZoom.offset(offset, keeping: anchor ?? CGPoint(x: view.width / 2, y: view.height / 2), from: old, to: new)
        zoom = new
        // Once the board has its new size: before, the scroll would stop at the old one's end.
        Task { @MainActor in position.scrollTo(point: target) }
    }

    private var startZoom: CGFloat? {
        #if DEBUG
        snapshot.zoom
        #else
        nil
        #endif
    }

    /// Thin bands at the edges while a card is carried: held over one, the board scrolls that way, as under a dragged sticky note.
    private var edges: some View {
        func band(_ side: CGRectEdge) -> some View {
            let across = side == .minYEdge || side == .maxYEdge
            return Color.clear.contentShape(Rectangle())
                .frame(width: across ? nil : 28, height: across ? 28 : nil)
                .dropDestination(for: String.self) { _, _ in false } isTargeted: { over in
                    if over { edge = side } else if edge == side { edge = nil }
                }
        }
        return ZStack {
            VStack(spacing: 0) { band(.minYEdge); Spacer(minLength: 0); band(.maxYEdge) }
            HStack(spacing: 0) { band(.minXEdge); Spacer(minLength: 0); band(.maxXEdge) }
        }
        // The scroll's offset is the board's own, not the reading direction's.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// `tidy`: some cards stand where the person put them; true when one had to be moved off another, which makes the button stand out.
    private func zooming(_ scale: CGFloat, fit: @escaping () -> Void, by: @escaping (CGFloat) -> Void, tidy: (nudged: Bool, run: () -> Void)?) -> some View {
        HStack(spacing: Theme.Space.xs) {
            if tree.select != nil { boardOrOutline }
            if let tidy {
                Button(action: tidy.run) {
                    Label { Text("Tidy up", comment: "A board of cards on an extension's page: puts every card back where the board lays it out") } icon: { Image(systemName: "rectangle.3.group") }
                        .font(Theme.Font.caption.weight(.semibold)).padding(.horizontal, Theme.Space.s).frame(height: Theme.Size.hitTarget)
                        .foregroundStyle(tidy.nudged ? Theme.onAccent : Theme.ink)
                        .background(tidy.nudged ? Theme.accent : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.sfBare)
            }
            Button(action: fit) { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: Theme.Size.hitTarget, height: Theme.Size.hitTarget).contentShape(Rectangle()) }
                .buttonStyle(.sfBare).keyboardShortcut("0", modifiers: .command)
                .help(Text("Fit to the window", comment: "A tree of cards on an extension's page: the zoom button that fits it all in"))
                .accessibilityLabel(Text("Fit to the window", comment: "A tree of cards on an extension's page: the zoom button that fits it all in"))
            HStack(spacing: 0) {
                Button { by(-TreeZoom.step) } label: { Image(systemName: "minus").frame(width: Theme.Size.hitTarget, height: Theme.Size.hitTarget).contentShape(Rectangle()) }
                    .buttonStyle(.sfBare).keyboardShortcut("-", modifiers: .command)
                    .accessibilityLabel(Text("Zoom out", comment: "A tree of cards on an extension's page"))
                Text(scale, format: .percent.precision(.fractionLength(0))).font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.inkMuted).frame(minWidth: 40)
                Button { by(TreeZoom.step) } label: { Image(systemName: "plus").frame(width: Theme.Size.hitTarget, height: Theme.Size.hitTarget).contentShape(Rectangle()) }
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
    var carried: String?
    var carry: (String?) -> Void
    var land: ([String], String) -> Bool
    var put: ([String], CGPoint) -> Bool = { _, _ in false }

    var body: some View {
        let line = TreeLine(tree.line)
        // Once cards stand where the person put them, each says its place in the order, which the lines also follow.
        let numbers = layout.placed ? Dictionary(tree.reading.enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { a, _ in a }) : [:]
        ZStack(alignment: .topLeading) {
            // The board's empty space takes a card let go there, as a place to stand (D234); a card or a + spot over it takes it first.
            Color.clear.contentShape(Rectangle())
                .dropDestination(for: String.self) { words, at in put(words, at) }
            TreeLines(lines: layout.lines, line: line, size: layout.size)
            TreeBoard(size: layout.size) {
                ForEach(layout.cards, id: \.node.id) { card in
                    TreeCard(node: card.node, tree: tree, line: line, model: model, folded: $folded, marked: marked.contains(card.node.id), carried: carried, carry: carry, land: land)
                        .overlay(alignment: .topLeading) { if let n = numbers[card.node.id] { TreeStepNumber(number: n, line: line) } }
                        .treeFrame(card.frame).id(card.node.id)
                }
                ForEach(layout.labels, id: \.branch.id) { label in
                    TreeBranchLabel(branch: label.branch).fixedSize().treeFrame(CGRect(x: label.point.x - 60, y: label.point.y - 11, width: 120, height: 22))
                }
                if let insert = tree.insert {
                    ForEach(layout.adds, id: \.target) { add in
                        TreeAddButton(add: add, hook: insert, picker: tree.picker, tree: tree, line: line, model: model, carried: carried, land: land)
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
    var carried: String?
    var carry: (String?) -> Void
    var land: ([String], String) -> Bool
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
        // The card being carried stays faint where it was, so it's clear what's moving.
        .opacity(carried == node.id ? 0.35 : (node.state == .skipped ? 0.55 : 1))
        .elevation(node.state == .pending || node.state == .skipped ? .e0 : (hovering ? .e2 : .e1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(ext: spoken))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityActions { actions }
        // Beside the card's button, not in it: a control inside a button's label isn't sure to get its click.
        .overlay(alignment: .trailing) { menu }
        // Where a card let go here lands: a line under this one, as it will stand right after it.
        .overlay(alignment: .bottom) {
            if dropping, let carried, tree.place(carried, after: node.id) != nil {
                Capsule().fill(line.to).frame(height: 4).padding(.horizontal, Theme.Space.l).offset(y: 12).allowsHitTesting(false)
            }
        }
        .overlay { if marked { shape.strokeBorder(line.from, lineWidth: 3) } }
        .overlay(alignment: .bottom) { foldButton }
        .onHover { hovering = $0 }
        .contextMenu { actions }
        .modifier(TreeCardDrag(node: node, tree: tree, carry: carry, land: land, dropping: $dropping))
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

#if DEBUG
/// How a snapshot shows a board, as it can't pinch or drag: at a zoom, or with a card carried.
struct TreeSnapshot {
    var zoom: CGFloat?
    var carrying: String?
}

extension EnvironmentValues {
    @Entry var treeSnapshot = TreeSnapshot()
}
#endif
