import AppKit
import QuartzCore
import SidefolkCore

/// Draws a scene with Core Animation layers (D99). The layers hold each node's final state and the animations, handed
/// over whole, run in the render server: nothing here wakes for a frame, so a surface at rest costs nothing, and with
/// Reduce Motion the end simply shows. A new scene changes only what differs, by node id.
final class SceneView: NSView {
    /// The person pressed or dragged on an area, or chose in a field. Whether it was offered is the session's to say.
    var onMove: ((SurfaceMove) -> Void)?
    /// A press's own sound, before the extension answers.
    var onPressSound: ((String) -> Void)?
    var assets = SceneImages(reader: nil)
    var figures = SceneFigures()
    /// While false (an approval is waiting) nothing here takes a click or a field's Return.
    var takesInput = true

    private let canvas = CALayer()
    private(set) var scene: SurfaceScene?
    private var layers: [String: SceneLayers] = [:]
    private var runningRuns: [String: (run: SceneRun, keys: [(CALayer, String)])] = [:]
    private var fields: [String: SceneField] = [:]
    private var reduceMotion = false
    private var mirrored = false
    private var scale: CGFloat = 1
    /// When this scene showed, on the clock input events use, for a press timed from a moment of it.
    private(set) var shownAt: TimeInterval = 0
    private var hovered: AreaHit?
    private var pressed: AreaHit?
    private var dragging: DragState?
    private var clockTask: Task<Void, Never>?
    private var clockSince = Date()
    private var tracking: NSTrackingArea?
    private var axElements: [NSAccessibilityElement]?
    /// How far each scroll box is moved, kept by node id across scenes; nothing about it reaches the extension.
    private var scrolled: [String: CGFloat] = [:]
    /// The last place each scroll box was told to keep in view: only a new one moves it.
    private var scrollTargets: [String: String] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        canvas.anchorPoint = .zero
        canvas.masksToBounds = true
        canvas.actions = SceneLayers.still
        layer?.addSublayer(canvas)
        setAccessibilityElement(false)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { tabsThroughAreas && !keyAreas.isEmpty }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var wantsUpdateLayer: Bool { true }

    // MARK: Showing a scene

    /// Shows `scene`, sized to fit at `scale`. A run named and unchanged since the last scene carries on; everything else
    /// starts now. Under Reduce Motion only essential curves play.
    func show(_ next: SurfaceScene, scale: CGFloat, rtl appRTL: Bool, reduceMotion: Bool) {
        // A scene in another language than the app's reads in that language's direction.
        let rtl = next.rightToLeft ?? appRTL
        self.reduceMotion = reduceMotion
        self.scale = scale
        mirrored = rtl && next.mirrors
        let drawn = (rtl ? next.mirrored() : next)
        let settled = drawn.settled()
        let previous = scene
        scene = next
        axElements = nil

        CATransaction.begin()
        let eased = next.transition > 0 && previous != nil && !reduceMotion
        CATransaction.setDisableActions(!eased)
        if eased {
            CATransaction.setAnimationDuration(next.transition)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        }
        layer?.backgroundColor = nil
        canvas.bounds = CGRect(x: 0, y: 0, width: next.size.width, height: next.size.height)
        canvas.position = .zero
        canvas.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        canvas.backgroundColor = next.background.map(color)
        var seen = Set<String>()
        place(settled.nodes, in: canvas, seen: &seen)
        for (id, stale) in layers where !seen.contains(id) {
            stale.main.removeFromSuperlayer()
            layers[id] = nil
        }
        shownAt = ProcessInfo.processInfo.systemUptime
        start(drawn.runs)
        applyScrolls(settled)
        layoutFields(settled)
        dimEmptySubmits()
        CATransaction.commit()
        takeFocusIfAsked(settled)
        restyleHover()
        runClocks()
        NSAccessibility.post(element: self, notification: .layoutChanged)
        // The ring stays with the keyboard through a new drawing, on the same place in the list.
        if let keyFocus { moveKeyFocus(to: min(keyFocus, max(0, keyAreas.count - 1))) }
    }

    /// The theme or the appearance changed: the same scene in its new colours, without restarting anything.
    func restyle() {
        guard let scene else { return }
        for item in layers.values { item.reset() }
        let settled = (mirrored ? scene.mirrored() : scene).settled()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.backgroundColor = scene.background.map(color)
        var seen = Set<String>()
        place(settled.nodes, in: canvas, seen: &seen)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }

    private func color(_ c: SceneColor) -> CGColor { SceneColors.cg(c, appearance: effectiveAppearance) }

    private func place(_ nodes: [SceneNode], in parent: CALayer, seen: inout Set<String>) {
        var ordered: [CALayer] = []
        for node in nodes {
            seen.insert(node.id)
            let item: SceneLayers
            if let existing = layers[node.id], existing.matches(node) {
                item = existing
            } else {
                layers[node.id]?.main.removeFromSuperlayer()
                item = SceneLayers(node)
                layers[node.id] = item
            }
            item.apply(node, in: self)
            ordered.append(item.main)
            if case .flip = node.kind {
                for (i, face) in node.children.prefix(2).enumerated() {
                    place([face], in: item.face(i), seen: &seen)
                }
            } else {
                place(node.children, in: item.childHost, seen: &seen)
            }
        }
        // Their order as the scene gives it; only touched when it changed.
        let current = parent.sublayers?.filter { sub in layers.values.contains { $0.main === sub } } ?? []
        if current.count != ordered.count || !zip(current, ordered).allSatisfy({ $0 === $1 }) {
            let others = parent.sublayers?.filter { sub in !ordered.contains { $0 === sub } && !layers.values.contains { $0.main === sub } } ?? []
            parent.sublayers = others + ordered
        }
    }

    /// Stops the animations where they are, on the same clock as Sidefolk's timers: put away with 5 s left, it comes back with 5 s left.
    func setPaused(_ paused: Bool) {
        guard (canvas.speed == 0) != paused else { return }
        if paused {
            let now = canvas.convertTime(CACurrentMediaTime(), from: nil)
            canvas.speed = 0
            canvas.timeOffset = now
        } else {
            let stopped = canvas.timeOffset
            canvas.speed = 1
            canvas.timeOffset = 0
            canvas.beginTime = 0
            canvas.beginTime = canvas.convertTime(CACurrentMediaTime(), from: nil) - stopped
        }
    }

    private func start(_ runs: [SceneRun]) {
        let kept = Set(runs.compactMap { run -> String? in
            guard let id = run.id, runningRuns[id]?.run == run else { return nil }
            return id
        })
        for (id, running) in runningRuns where !kept.contains(id) {
            for (layer, key) in running.keys { layer.removeAnimation(forKey: key) }
            runningRuns[id] = nil
        }
        let now = canvas.convertTime(CACurrentMediaTime(), from: nil)
        for run in runs {
            let name = run.id ?? "scene"
            guard !kept.contains(name) else { continue }
            var keys: [(CALayer, String)] = []
            for curve in run.curves where !reduceMotion || curve.essential {
                guard let item = layers[curve.target] else { continue }
                keys += item.animate(curve, run: name, at: now)
            }
            for frames in run.frames where !reduceMotion || frames.essential {
                guard let item = layers[frames.target], let last = frames.times.last else { continue }
                let animation = CAKeyframeAnimation(keyPath: "contents")
                animation.calculationMode = .discrete
                let total = max(last + 0.001, 0.01)
                animation.duration = total
                animation.keyTimes = (frames.times + [total]).map { NSNumber(value: $0 / total) }
                animation.values = frames.paths.map { assets.image($0, side: item.pixelSide) as Any }
                animation.beginTime = now
                animation.fillMode = .backwards
                let key = "\(name).frames"
                item.main.add(animation, forKey: key)
                keys.append((item.main, key))
            }
            runningRuns[name] = (run, keys)
        }
    }

    // MARK: Clocks

    /// A running clock's text changes once a second, by a task that exists only while a clock runs and the view is shown.
    private func runClocks() {
        clockTask?.cancel()
        clockSince = Date()
        guard let scene, window != nil else { return }
        var running: [(String, SceneClock)] = []
        func visit(_ node: SceneNode) {
            if case .clock(let c) = node.kind, c.running { running.append((node.id, c)) }
            node.children.forEach(visit)
        }
        scene.nodes.forEach(visit)
        guard !running.isEmpty else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let gone = Date().timeIntervalSince(self.clockSince)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for (id, clock) in running { self.layers[id]?.setClock(clock, elapsed: gone, in: self) }
                CATransaction.commit()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clockTask?.cancel() } else { runClocks() }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // Only moves over the panel wake this: at rest no pointer means no work.
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private struct AreaHit: Equatable {
        var id: String
        var area: SceneArea
        var frame: CGRect
        static func == (a: AreaHit, b: AreaHit) -> Bool { a.id == b.id }
    }

    /// The topmost area under the point, on the layers as they are drawn this moment, moving ones included.
    private func hit(_ point: CGPoint) -> AreaHit? {
        guard let scene, takesInput else { return nil }
        var best: AreaHit?
        var bestZ = -Double.infinity
        var order = 0.0
        let canvasPoint = CGPoint(x: point.x / scale, y: point.y / scale)
        let origin = canvas.presentation() ?? canvas
        func visit(_ node: SceneNode, _ z: Double, inside: CGRect?) {
            guard let item = layers[node.id] else { return }
            let here = z + node.z * 1000
            order += 0.001
            let shown = item.main.presentation() ?? item.main
            let frame = shown.convert(shown.bounds, to: origin)
            if let area = node.area, !area.disabled, area.submits.map({ fields[$0]?.stringValue.isEmpty == false }) ?? true {
                // Where it rests, whatever its own hover look is doing; and only what a clipping parent lets show.
                let rest = item.atRest(frame)
                if rest.contains(canvasPoint), inside?.contains(canvasPoint) ?? true, here + order >= bestZ, shown.opacity > 0.01 {
                    best = AreaHit(id: node.id, area: area, frame: rest)
                    bestZ = here + order
                }
            }
            let clip = node.clips ? (inside.map { $0.intersection(frame) } ?? frame) : inside
            for child in node.children { visit(child, here, inside: clip) }
        }
        scene.nodes.forEach { visit($0, 0, inside: nil) }
        return best
    }

    // MARK: Scrolling

    override func scrollWheel(with event: NSEvent) {
        guard takesInput, let (node, box) = scrollBox(at: convert(event.locationInWindow, from: nil)) else { return super.scrollWheel(with: event) }
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        let most = max(CGFloat(box.contentHeight - node.height), 0)
        let next = min(max((scrolled[node.id] ?? 0) - step, 0), most)
        guard next != scrolled[node.id] ?? 0 else { return }
        scrolled[node.id] = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layers[node.id]?.scroll(to: next)
        if let scene { layoutFields((mirrored ? scene.mirrored() : scene).settled()) }
        CATransaction.commit()
        setHover(hit(convert(event.locationInWindow, from: nil)))
        axElements = nil
    }

    /// The innermost scroll box under the point.
    private func scrollBox(at point: CGPoint) -> (SceneNode, SceneScroll)? {
        guard let scene else { return nil }
        let canvasPoint = CGPoint(x: point.x / scale, y: point.y / scale)
        var found: (SceneNode, SceneScroll)?
        func visit(_ node: SceneNode) {
            if case .scroll(let box) = node.kind, let item = layers[node.id], item.main.convert(item.main.bounds, to: canvas).contains(canvasPoint) { found = (node, box) }
            node.children.forEach(visit)
        }
        scene.nodes.forEach(visit)
        return found
    }

    /// Each scroll box where it was, within what the new scene holds, moved only as far as a newly named node needs to be in view.
    private func applyScrolls(_ settled: SurfaceScene) {
        func visit(_ node: SceneNode) {
            if case .scroll(let box) = node.kind, let item = layers[node.id] {
                let most = max(CGFloat(box.contentHeight - node.height), 0)
                var offset = min(scrolled[node.id] ?? 0, most)
                if let to = box.to, scrollTargets[node.id] != to, let target = layers[to] {
                    // In the box's own coordinates: where it is now, plus how far the box is already moved.
                    let place = target.main.convert(target.main.bounds, to: item.main)
                    if place.minY < offset { offset = place.minY } else if place.maxY > offset + CGFloat(node.height) { offset = place.maxY - CGFloat(node.height) }
                    offset = min(max(offset, 0), most)
                }
                scrollTargets[node.id] = box.to
                scrolled[node.id] = offset
                item.scroll(to: offset)
            }
            node.children.forEach(visit)
        }
        settled.nodes.forEach(visit)
    }

    private func hitIsOpen(_ area: SceneArea) -> Bool { inputOpen?() != false || area.always }
    /// The session's own word on whether animations still hold moves.
    var inputOpen: (() -> Bool)?

    override func mouseMoved(with event: NSEvent) {
        let found = hit(convert(event.locationInWindow, from: nil))
        guard found != hovered else { return }
        setHover(found)
    }

    override func mouseExited(with event: NSEvent) { setHover(nil) }

    private func setHover(_ next: AreaHit?) {
        if let hovered { styleHover(hovered, on: false) }
        hovered = next
        if let next {
            styleHover(next, on: true)
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func styleHover(_ hit: AreaHit, on: Bool) {
        let look = on ? hit.area.hover : nil
        restyleNode(hit.id, look: look)
        for id in hit.area.highlight { restyleNode(id, look: look) }
        for (id, own) in hit.area.looks { restyleNode(id, look: on ? own : nil) }
    }

    private func restyleHover() {
        guard let hovered else { return }
        // The scene changed under a still pointer: the area may have gone or moved.
        self.hovered = nil
        if scene?.areas.contains(where: { $0.id == hovered.area.id && $0.value == hovered.area.value }) == true, let window {
            setHover(hit(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
        } else {
            NSCursor.arrow.set()
        }
    }

    private func restyleNode(_ id: String, look: SceneStyle?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduceMotion ? 0 : 0.1)
        CATransaction.setDisableActions(reduceMotion)
        layers[id]?.look(look)
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let found = hit(point), hitIsOpen(found.area) else { return }
        pressed = found
        restyleNode(found.id, look: pressLook(found.area))
        if let sound = found.area.sound { onPressSound?(sound) }
        if let drag = found.area.drag { dragging = DragState(drag: drag, startPoint: point, hit: found) }
        // A timed press counts when it goes down: it is a reaction, not a choice.
        if let moment = found.area.timedFrom, found.area.drag == nil {
            onMove?(.click(area: found.area.id, value: found.area.value, ms: ms(event.timestamp, from: moment)))
            pressed = nil
            restyleNode(found.id, look: found.area.hover)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var state = dragging else { return }
        state.moved = true
        state.lastPoint = convert(event.locationInWindow, from: nil)
        dragging = state
        drawGhost(state)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer {
            if let pressed { restyleNode(pressed.id, look: nil) }
            pressed = nil
            dragging = nil
            setHover(hit(point))
        }
        if var state = dragging {
            state.lastPoint = point
            clearGhost(state)
            if let move = dragMove(state) { onMove?(move) }
            return
        }
        guard let pressed, let up = hit(point), up.id == pressed.id else { return }
        if !submit(pressed.area) { onMove?(.click(area: pressed.area.id, value: pressed.area.value, ms: nil)) }
    }

    /// What a press looks like. Under Reduce Motion it dims rather than moves.
    private func pressLook(_ area: SceneArea) -> SceneStyle? {
        let look = area.press ?? area.hover
        return reduceMotion ? look.map { SceneStyle(opacity: $0.opacity ?? 0.8) } : look
    }

    /// An area that sends a field's words: as Return would. True when it is one.
    private func submit(_ area: SceneArea) -> Bool {
        guard let name = area.submits else { return false }
        if let field = fields[name] { field.onSubmit?(field.stringValue) }
        return true
    }

    private func ms(_ timestamp: TimeInterval, from moment: Double) -> Int {
        Int(((timestamp - shownAt) - moment) * 1000)
    }

    // MARK: Dragging

    private struct DragState {
        var drag: SceneDrag
        var startPoint: CGPoint
        var lastPoint: CGPoint?
        var moved = false
        var hit: AreaHit
    }

    private func cell(_ point: CGPoint, _ state: DragState) -> (row: Int, column: Int)? {
        guard case .grid(let rows, let columns) = state.drag.mode, state.hit.frame.width > 0, state.hit.frame.height > 0 else { return nil }
        let p = CGPoint(x: point.x / scale, y: point.y / scale)
        let r = Int((p.y - state.hit.frame.minY) / state.hit.frame.height * CGFloat(rows))
        var c = Int((p.x - state.hit.frame.minX) / state.hit.frame.width * CGFloat(columns))
        if mirrored, scene?.isMirrored(state.hit.id) == true { c = columns - 1 - c }
        return (min(max(r, 0), rows - 1), min(max(c, 0), columns - 1))
    }

    private func dragMove(_ s: DragState) -> SurfaceMove? {
        let end = s.lastPoint ?? s.startPoint
        switch s.drag.mode {
        case .grid:
            guard let a = cell(s.startPoint, s), let b = cell(end, s) else { return nil }
            return .dragGrid(area: s.hit.area.id, value: s.hit.area.value, fromRow: a.row, fromColumn: a.column, toRow: b.row, toColumn: b.column)
        case .free:
            func point(_ p: CGPoint) -> CGPoint {
                let x = p.x / scale, y = p.y / scale
                return CGPoint(x: mirrored ? (scene?.size.width ?? 0) - x : x, y: y)
            }
            let (a, b) = (point(s.startPoint), point(end))
            return .dragFree(area: s.hit.area.id, value: s.hit.area.value, fromX: a.x, fromY: a.y, toX: b.x, toY: b.y)
        }
    }

    /// The ghost node follows as the pointer goes, drawn here so a drag never waits on the extension: stretched over the
    /// cells on a grid, moved by the distance when free.
    private func drawGhost(_ s: DragState) {
        guard let ghost = s.drag.ghost, let item = layers[ghost], let end = s.lastPoint else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch s.drag.mode {
        case .grid(let rows, let columns):
            guard let a = cell(s.startPoint, s), let b = cell(end, s) else { break }
            let cw = s.hit.frame.width / CGFloat(columns), ch = s.hit.frame.height / CGFloat(rows)
            func x(_ c: Int) -> CGFloat { mirrored && scene?.isMirrored(s.hit.id) == true ? CGFloat(columns - 1 - c) : CGFloat(c) }
            let left = min(x(a.column), x(b.column)), right = max(x(a.column), x(b.column))
            let inset = CGFloat(s.drag.inset)
            item.placeGhost(CGRect(x: s.hit.frame.minX + left * cw, y: s.hit.frame.minY + CGFloat(min(a.row, b.row)) * ch,
                                   width: (right - left + 1) * cw, height: CGFloat(abs(a.row - b.row) + 1) * ch).insetBy(dx: inset, dy: inset), in: canvas)
        case .free:
            item.shiftGhost(dx: (end.x - s.startPoint.x) / scale, dy: (end.y - s.startPoint.y) / scale)
        }
        CATransaction.commit()
    }

    private func clearGhost(_ s: DragState) {
        guard let ghost = s.drag.ghost, let item = layers[ghost] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        item.clearGhost()
        CATransaction.commit()
    }

    // MARK: Keys from the panel

    /// A key tied to an area presses it with its look and sound, then its move; otherwise the key's own move.
    func press(_ key: SceneKey, character: String?, timestamp: TimeInterval) -> SurfaceMove? {
        let timed = key.timedFrom.map { ms(timestamp, from: $0) }
        guard let id = key.area else { return .key(id: key.id, character: character, ms: timed) }
        guard let scene, let (nodeId, area) = areaNode(scene, id: id, value: key.value), !area.disabled else { return nil }
        restyleNode(nodeId, look: pressLook(area))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            self?.restyleNode(nodeId, look: nil)
        }
        if let sound = area.sound { onPressSound?(sound) }
        if submit(area) { return nil }
        return .click(area: area.id, value: area.value, ms: timed)
    }

    private func areaNode(_ scene: SurfaceScene, id: String, value: String?) -> (String, SceneArea)? {
        var found: (String, SceneArea)?
        func visit(_ node: SceneNode) {
            if found == nil, let a = node.area, a.id == id, a.value == value { found = (node.id, a) }
            node.children.forEach(visit)
        }
        scene.nodes.forEach(visit)
        return found
    }

    // MARK: Fields

    private func layoutFields(_ settled: SurfaceScene) {
        var wanted: [String: (SceneEntry, CGRect)] = [:]
        func visit(_ node: SceneNode, _ origin: CGPoint, inside: CGRect?) {
            let here = CGPoint(x: origin.x + node.x, y: origin.y + node.y)
            let box = CGRect(origin: here, size: CGSize(width: node.width, height: node.height))
            if case .entry(let e) = node.kind {
                let seen = inside.map { $0.intersection(box) } ?? box
                // Inside the canvas or nowhere: only the frame's own words stand above it (T40).
                if let frame = SurfacePolicy.fieldFrame(seen, canvas: CGSize(width: settled.size.width, height: settled.size.height)) { wanted[e.id] = (e, frame) }
            }
            var within = here
            var clip = inside
            if case .scroll = node.kind {
                within.y -= scrolled[node.id] ?? 0
                clip = inside.map { $0.intersection(box) } ?? box
            }
            for child in node.children { visit(child, within, inside: clip) }
        }
        settled.nodes.forEach { visit($0, .zero, inside: nil) }
        for (id, field) in fields where wanted[id] == nil {
            field.removeFromSuperview()
            fields[id] = nil
        }
        for (id, (entry, rect)) in wanted {
            let field = fields[id] ?? SceneField()
            if fields[id] == nil {
                addSubview(field)
                fields[id] = field
                field.onSubmit = { [weak self, weak field] text in
                    guard let self, let field, self.takesInput else { return }
                    guard let clean = SurfaceMove.typed(text) else { return }
                    self.onMove?(.entry(id: id, text: clean))
                    field.stringValue = ""
                    self.dimEmptySubmits()
                }
                field.onChange = { [weak self] in self?.dimEmptySubmits() }
            }
            field.configure(entry, placeholder: entry.placeholder.map(figures.fill))
            field.frame = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        }
    }

    /// An area that sends a field's words looks dim while there is nothing to send, when it takes no press either.
    private func dimEmptySubmits() {
        guard let nodes = scene?.nodes else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        func visit(_ node: SceneNode) {
            if let name = node.area?.submits, let field = fields[name], let item = layers[node.id] {
                item.main.opacity = Float(SurfacePolicy.submitOpacity(node, typed: field.stringValue))
            }
            node.children.forEach(visit)
        }
        nodes.forEach(visit)
        CATransaction.commit()
    }

    #if DEBUG
    /// Words in a field, as if typed: `surfaceEntry`. A click on what submits it, or Return, still sends it.
    func devType(_ text: String, in name: String) {
        fields[name]?.stringValue = text
        dimEmptySubmits()
    }

    func devSubmit(_ name: String) {
        if let field = fields[name] { field.onSubmit?(field.stringValue) }
    }
    #endif

    /// The keyboard's first stop, when the surface has it and the scene has a field.
    func focusField() {
        guard let field = fields.values.first(where: { $0.isEditable }) else { return }
        window?.makeFirstResponder(field)
    }

    /// A field that asks for the keyboard as it appears. Only if this surface already has it: a scene can't take it from anywhere (D75).
    private func takeFocusIfAsked(_ settled: SurfaceScene) {
        guard takesInput, window?.isKeyWindow == true, let wanted = settled.entries.first(where: { $0.focus && !$0.locked }), let field = fields[wanted.id],
              field.currentEditor() == nil else { return }
        window?.makeFirstResponder(field)
    }

    // MARK: The keyboard (D105)

    /// A page's scene has no session and takes no keys of its own, yet whoever works by keyboard must reach what it offers: Tab goes from area to area in reading
    /// order and on out of the scene; Space or Return presses the one with the ring.
    var tabsThroughAreas = false
    private var keyFocus: Int?
    private let keyRing = CAShapeLayer()

    private var keyAreas: [(id: String, area: SceneArea)] {
        guard let scene else { return [] }
        var out: [(String, SceneArea)] = []
        func visit(_ node: SceneNode) {
            if let area = node.area, !area.disabled { out.append((node.id, area)) }
            node.children.forEach(visit)
        }
        scene.nodes.forEach(visit)
        return out
    }

    override func becomeFirstResponder() -> Bool {
        guard acceptsFirstResponder else { return false }
        let backward = window?.currentEvent?.modifierFlags.contains(.shift) == true && window?.currentEvent?.type == .keyDown
        moveKeyFocus(to: backward ? keyAreas.count - 1 : 0)
        return true
    }

    override func resignFirstResponder() -> Bool {
        keyFocus = nil
        keyRing.removeFromSuperlayer()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard tabsThroughAreas, let at = keyFocus, takesInput else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 48: // Tab
            let next = at + (event.modifierFlags.contains(.shift) ? -1 : 1)
            if keyAreas.indices.contains(next) {
                moveKeyFocus(to: next)
            } else if event.modifierFlags.contains(.shift) {
                window?.selectPreviousKeyView(self)
            } else {
                window?.selectNextKeyView(self)
            }
        case 49, 36, 76: // Space, Return, Enter
            if keyAreas.indices.contains(at) { accessibilityPress(keyAreas[at].area) }
        default:
            super.keyDown(with: event)
        }
    }

    private func moveKeyFocus(to index: Int) {
        let areas = keyAreas
        guard areas.indices.contains(index) else { return }
        keyFocus = index
        showKeyRing(areas[index].id)
    }

    /// The system's own focus colour, around what would be pressed, and what scrolls brought into view.
    private func showKeyRing(_ id: String) {
        guard let item = layers[id] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrollIntoView(id)
        let box = item.main.convert(item.main.bounds, to: canvas).insetBy(dx: -3, dy: -3)
        keyRing.path = CGPath(roundedRect: box, cornerWidth: 8, cornerHeight: 8, transform: nil)
        keyRing.fillColor = nil
        keyRing.strokeColor = NSColor.keyboardFocusIndicatorColor.cgColor
        keyRing.lineWidth = 3
        keyRing.zPosition = 100_000
        if keyRing.superlayer == nil { canvas.addSublayer(keyRing) }
        CATransaction.commit()
    }

    private func scrollIntoView(_ id: String) {
        guard let scene else { return }
        func visit(_ node: SceneNode, inside: (SceneNode, SceneScroll)?) {
            var here = inside
            if case .scroll(let box) = node.kind { here = (node, box) }
            if node.id == id, let (box, content) = here, let item = layers[id] {
                let top = item.main.frame.minY, bottom = item.main.frame.maxY
                let now = scrolled[box.id] ?? 0
                let most = max(CGFloat(content.contentHeight - box.height), 0)
                var next = now
                if top < now { next = top } else if bottom > now + CGFloat(box.height) { next = bottom - CGFloat(box.height) }
                next = min(max(next, 0), most)
                if next != now {
                    scrolled[box.id] = next
                    layers[box.id]?.scroll(to: next)
                    axElements = nil
                }
            }
            for child in node.children { visit(child, inside: here) }
        }
        scene.nodes.forEach { visit($0, inside: nil) }
    }

    #if DEBUG
    /// Pressing keys in the debug app, where nobody sits: `pageKey` sends them here.
    func devKey(_ code: UInt16, shift: Bool = false) {
        if keyFocus == nil, window?.makeFirstResponder(self) != true { return }
        guard code != 0, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0, windowNumber: window?.windowNumber ?? 0,
                                                      context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) else { return }
        keyDown(with: event)
    }
    #endif

    // MARK: VoiceOver

    override func accessibilityChildren() -> [Any]? {
        if let axElements { return axElements }
        guard let scene else { return [] }
        var out: [NSAccessibilityElement] = []
        func visit(_ node: SceneNode) {
            let id = node.id
            if let area = node.area {
                out.append(SceneAXElement(parent: self, role: .button, label: figures.fill(area.label), value: nil, enabled: !area.disabled, selected: area.selected,
                                          place: { [weak self] in self?.screenFrame(of: id) ?? .zero },
                                          pressed: { [weak self] in self?.accessibilityPress(area) }))
            } else if let words = spoken(node) {
                out.append(SceneAXElement(parent: self, role: .staticText, label: nil, value: words, enabled: true,
                                          place: { [weak self] in self?.screenFrame(of: id) ?? .zero }, pressed: nil))
            }
            node.children.forEach(visit)
        }
        scene.nodes.forEach(visit)
        axElements = out
        return out
    }

    private func spoken(_ node: SceneNode) -> String? {
        if let label = node.label { return figures.fill(label) }
        if case .text(let t) = node.kind { return figures.fill(t.text) }
        return nil
    }

    /// Where a node is on screen now, for VoiceOver's cursor.
    func screenFrame(of id: String) -> NSRect {
        guard let item = layers[id], let window else { return .zero }
        let inView = item.main.convert(item.main.bounds, to: layer)
        return window.convertToScreen(convert(inView, to: nil))
    }

    func accessibilityPress(_ area: SceneArea) {
        guard takesInput, hitIsOpen(area), !submit(area) else { return }
        onMove?(.click(area: area.id, value: area.value, ms: area.timedFrom.map { ms(ProcessInfo.processInfo.systemUptime, from: $0) }))
    }

    // MARK: Filming (debug)

    #if DEBUG
    /// What is drawn this moment, animations included, for the debug app's films and the snapshots of a moment.
    func frameImage() -> CGImage? {
        guard let source = canvas.presentation() ?? Optional(canvas) else { return nil }
        let s: CGFloat = 2
        let w = Int(bounds.width * s), h = Int(bounds.height * s)
        guard w > 0, h > 0, let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.setFillColor(SceneColors.cg(.token(.surface), appearance: effectiveAppearance))
        c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.translateBy(x: 0, y: CGFloat(h))
        c.scaleBy(x: s, y: -s)
        source.render(in: c)
        return c.makeImage()
    }

    var layerCount: Int { layers.count }
    #endif
}

/// One area or piece of text as VoiceOver reaches it. NSAccessibilityElement isn't on the main actor, though VoiceOver
/// calls come on the main thread.
nonisolated final class SceneAXElement: NSAccessibilityElement, @unchecked Sendable {
    nonisolated(unsafe) private let place: @MainActor () -> NSRect
    nonisolated(unsafe) private let pressed: (@MainActor () -> Void)?

    nonisolated init(parent: Any, role: NSAccessibility.Role, label: String?, value: String?, enabled: Bool, selected: Bool = false, place: @escaping @MainActor () -> NSRect, pressed: (@MainActor () -> Void)?) {
        self.place = place
        self.pressed = pressed
        super.init()
        setAccessibilityParent(parent)
        setAccessibilityRole(role)
        setAccessibilityLabel(label)
        setAccessibilityValue(value)
        setAccessibilityEnabled(enabled)
        setAccessibilitySelected(selected)
    }

    nonisolated override func accessibilityFrame() -> NSRect {
        nonisolated(unsafe) let place = self.place
        return MainActor.assumeIsolated { place() }
    }

    nonisolated override func accessibilityPerformPress() -> Bool {
        nonisolated(unsafe) let pressed = self.pressed
        return MainActor.assumeIsolated {
            guard let pressed else { return false }
            pressed()
            return true
        }
    }
}

/// A scene's one-line field, typed with the person's input method.
final class SceneField: NSTextField, NSTextFieldDelegate {
    var onSubmit: ((String) -> Void)?
    /// What is typed changed.
    var onChange: (() -> Void)?
    private var max = 40

    init() {
        super.init(frame: .zero)
        delegate = self
        isBezeled = true
        bezelStyle = .roundedBezel
        focusRingType = .exterior
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ entry: SceneEntry, placeholder: String?) {
        max = entry.max
        placeholderString = placeholder
        isEditable = !entry.locked
        isEnabled = !entry.locked
        font = SceneDrawing.font(weight: entry.weight, design: entry.design, points: entry.size)
        isBezeled = !entry.plain
        drawsBackground = !entry.plain
        focusRingType = entry.plain ? .none : .exterior
    }

    func controlTextDidChange(_ note: Notification) {
        if stringValue.count > max { stringValue = String(stringValue.prefix(max)) }
        onChange?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        onSubmit?(stringValue)
        return true
    }
}
