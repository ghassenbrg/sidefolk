import AppKit
import QuartzCore
import SidefolkCore

/// The layers of one node: its main layer (place, transform, opacity), what it draws, and where its children go. Each
/// draws once and keeps the result, so a scene that changes little costs little, and a still one nothing.
final class SceneLayers {
    /// No implicit animation, unless a scene's `transition` asks for one on these.
    static let still: [String: CAAction] = ["contents": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull(), "sublayers": NSNull(), "bounds": NSNull(),
                                            "hidden": NSNull(), "path": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "shadowColor": NSNull(),
                                            "backgroundColor": NSNull(), "cornerRadius": NSNull(), "zPosition": NSNull()]

    let main: CALayer
    private var node: SceneNode
    private var drawnKey: AnyHashable?
    private var shape: CAShapeLayer?
    /// A flip's two faces, on a plate that squashes as it turns.
    private var plate: CALayer?
    private var faces: [CALayer] = []
    private var base: (x: CGFloat, y: CGFloat, sx: CGFloat, sy: CGFloat, rotate: CGFloat, opacity: Float) = (0, 0, 1, 1, 0, 1)
    private var look: SceneStyle?
    private var ghostShift: (dx: CGFloat, dy: CGFloat)?
    private var ghostFrame: CGRect?

    init(_ node: SceneNode) {
        self.node = node
        main = node.isShape ? CAShapeLayer() : CALayer()
        shape = main as? CAShapeLayer
        main.actions = Self.still
        if case .flip = node.kind {
            let plate = CALayer()
            plate.actions = Self.still
            main.addSublayer(plate)
            self.plate = plate
            for _ in 0..<2 {
                let face = CALayer()
                face.actions = Self.still
                plate.addSublayer(face)
                faces.append(face)
            }
        }
    }

    /// Whether this node's layers can show `next`: a node keeps its layers while it stays the same kind of thing.
    func matches(_ next: SceneNode) -> Bool { next.isShape == node.isShape && next.isFlip == node.isFlip }

    var childHost: CALayer { main }
    func face(_ i: Int) -> CALayer { faces[i] }
    var pixelSide: Int { Int(max(node.width, node.height) * 2) }

    /// Forgets what was drawn, so the next `apply` draws again in the new colours.
    func reset() { drawnKey = nil }

    func apply(_ node: SceneNode, in view: SceneView) {
        self.node = node
        let w = CGFloat(node.width), h = CGFloat(node.height)
        main.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        main.anchorPoint = CGPoint(x: node.anchorX, y: node.anchorY)
        main.zPosition = node.z
        main.masksToBounds = node.clips
        main.cornerRadius = node.isShape ? 0 : node.corner
        base = (node.x, node.y, node.scaleX, node.scaleY, node.rotate, Float(node.opacity))
        place()
        if let s = node.shadow {
            main.shadowColor = SceneColors.cg(s.color, appearance: view.effectiveAppearance)
            main.shadowRadius = s.radius
            // The canvas is flipped, as a shadow's offset isn't.
            main.shadowOffset = CGSize(width: s.dx, height: -s.dy)
            main.shadowOpacity = 1
        } else {
            main.shadowOpacity = 0
        }
        if let plate, case .flip(let flip) = node.kind {
            plate.bounds = main.bounds
            plate.position = CGPoint(x: w / 2, y: h / 2)
            for face in faces {
                face.bounds = main.bounds
                face.position = CGPoint(x: w / 2, y: h / 2)
            }
            let state = SceneFlipKeys.state(flip.turns)
            plate.setAffineTransform(flip.axis == .y ? CGAffineTransform(scaleX: state.squash, y: 1) : CGAffineTransform(scaleX: 1, y: state.squash))
            faces[0].opacity = state.back ? 0 : 1
            faces[1].opacity = state.back ? 1 : 0
        }
        draw(node, in: view)
    }

    /// Place and transform from the node's values, plus a hover or press look, plus a ghost's drag.
    private func place() {
        let dx = CGFloat(look?.dx ?? 0) + (ghostShift?.dx ?? 0), dy = CGFloat(look?.dy ?? 0) + (ghostShift?.dy ?? 0)
        let w = main.bounds.width, h = main.bounds.height
        main.position = CGPoint(x: base.x + w * main.anchorPoint.x + dx, y: base.y + h * main.anchorPoint.y + dy)
        let scale = CGFloat(look?.scale ?? 1)
        var t = CATransform3DMakeScale(base.sx * scale, base.sy * scale, 1)
        t = CATransform3DRotate(t, base.rotate * .pi / 180, 0, 0, 1)
        main.transform = t
        main.opacity = look?.opacity.map { Float($0) * base.opacity } ?? base.opacity
    }

    func look(_ style: SceneStyle?) {
        look = style
        place()
    }

    // MARK: Drawing

    private func draw(_ node: SceneNode, in view: SceneView) {
        let dark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        switch node.kind {
        case .group, .flip, .entry: main.contents = nil
        case .image(let image):
            let path = dark ? (image.dark ?? image.path) : image.path
            let key: AnyHashable = [path, "\(node.width)x\(node.height)", "\(String(describing: image.tint))", image.fit.rawValue, "\(dark)"]
            guard key != drawnKey else { return }
            drawnKey = key
            var picture = view.assets.image(path, side: pixelSide)
            if let tint = image.tint, let plain = picture { picture = SceneDrawing.tinted(plain, SceneColors.cg(tint, appearance: view.effectiveAppearance)) }
            main.contents = picture
            main.contentsGravity = switch image.fit {
            case .fill: .resize
            case .contain: .resizeAspect
            case .cover: .resizeAspectFill
            }
            if image.fit == .cover { main.masksToBounds = true }
        case .text(let text):
            setText(view.figures.fill(text.text), style: text, in: view)
        case .clock(let clock):
            setClock(clock, elapsed: 0, in: view)
        case .symbol(let symbol):
            let key: AnyHashable = [symbol.name, "\(node.width)x\(node.height)", "\(symbol.color)", "\(dark)"]
            guard key != drawnKey else { return }
            drawnKey = key
            main.contents = SceneDrawing.symbol(symbol.name, side: max(node.width, node.height), color: SceneColors.ns(symbol.color, appearance: view.effectiveAppearance))
            main.contentsGravity = .resizeAspect
            main.contentsScale = 2
        case .shape(let form):
            drawShape(form, node, in: view)
        case .companion(let pose):
            let key: AnyHashable = ["companion", pose.rawValue, "\(node.width)x\(node.height)"]
            guard key != drawnKey else { return }
            drawnKey = key
            main.contents = view.figures.companion(pose, Int(max(node.width, node.height)))
            main.contentsGravity = .resizeAspect
        case .person:
            let key: AnyHashable = ["person", "\(node.width)x\(node.height)"]
            guard key != drawnKey else { return }
            drawnKey = key
            main.contents = view.figures.person(Int(max(node.width, node.height)))
            main.contentsGravity = .resizeAspectFill
            main.masksToBounds = true
        }
    }

    private func setText(_ words: String, style: SceneText, in view: SceneView) {
        let dark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key: AnyHashable = [words, "\(style)", "\(node.width)x\(node.height)", "\(dark)"]
        guard key != drawnKey else { return }
        drawnKey = key
        main.contents = SceneDrawing.text(words, style: style, size: CGSize(width: node.width, height: node.height),
                                          color: SceneColors.ns(style.color, appearance: view.effectiveAppearance))
        main.contentsGravity = .resize
        main.contentsScale = 2
    }

    func setClock(_ clock: SceneClock, elapsed: TimeInterval, in view: SceneView) {
        let total = clock.running ? (clock.down ? max(clock.seconds - elapsed, 0) : clock.seconds + elapsed) : clock.seconds
        let whole = Int(total.rounded(clock.down ? .up : .down))
        let words = String(format: "%d:%02d", whole / 60, whole % 60)
        var style = clock.style
        style.text = words
        setText(words, style: style, in: view)
    }

    private func drawShape(_ form: SceneShape, _ node: SceneNode, in view: SceneView) {
        guard let shape else { return }
        let appearance = view.effectiveAppearance
        let box = CGRect(x: 0, y: 0, width: node.width, height: node.height)
        let path = SceneDrawing.path(form.form, box: box, corner: node.corner)
        shape.path = path
        shape.lineWidth = form.lineWidth
        shape.lineDashPattern = form.dash.isEmpty ? nil : form.dash.map { NSNumber(value: $0) }
        shape.strokeColor = form.stroke.map { SceneColors.cg($0, appearance: appearance) }
        if let gradient = form.gradient {
            // Baked into the layer rather than a gradient masked by the shape, which `render(in:)` wouldn't draw.
            let key: AnyHashable = ["\(gradient)", "\(node.width)x\(node.height)", "\(form.form)", "\(node.corner)", "\(appearance.name.rawValue)"]
            if key != drawnKey {
                drawnKey = key
                shape.contents = SceneDrawing.gradient(gradient, path: path, size: box.size, appearance: appearance)
                shape.contentsGravity = .resize
                shape.contentsScale = 2
            }
            shape.fillColor = nil
        } else {
            shape.contents = nil
            shape.fillColor = form.fill.map { SceneColors.cg($0, appearance: appearance) }
        }
    }

    // MARK: Animating

    /// One curve as Core Animation animations from `now`. The model already holds the end, so a finished animation
    /// is simply gone.
    func animate(_ curve: SceneCurve, run: String, at now: CFTimeInterval) -> [(CALayer, String)] {
        guard let total = curve.times.last, total > 0, curve.times.count >= 2 else { return [] }
        let key = "\(run).\(curve.property.rawValue)"
        if curve.property == .flip { return animateFlip(curve, key: key, total: total, now: now) }
        let animation = CAKeyframeAnimation(keyPath: Self.keyPath(curve.property))
        let w = main.bounds.width, h = main.bounds.height
        let offset: CGFloat = curve.property == .x ? w * main.anchorPoint.x : curve.property == .y ? h * main.anchorPoint.y : 0
        animation.values = curve.values.map { value -> NSNumber in
            switch curve.property {
            case .rotate: NSNumber(value: value * .pi / 180)
            case .x, .y: NSNumber(value: value + Double(offset))
            default: NSNumber(value: value)
            }
        }
        animation.keyTimes = curve.times.map { NSNumber(value: $0 / total) }
        if curve.property == .z {
            animation.calculationMode = .discrete
            animation.values = Array(curve.values.dropLast()).map { NSNumber(value: $0) }
        } else {
            animation.timingFunctions = curve.eases.map(Self.timing)
        }
        animation.duration = total
        animation.beginTime = now
        animation.fillMode = .backwards
        main.add(animation, forKey: key)
        return [(main, key)]
    }

    /// A flip is the plate squashing to its edge and back, with the face changing at the edge, as a coin in the air reads.
    private func animateFlip(_ curve: SceneCurve, key: String, total: Double, now: CFTimeInterval) -> [(CALayer, String)] {
        guard let plate, case .flip(let flip) = node.kind else { return [] }
        let keys = SceneFlipKeys(curve)
        let squash = CAKeyframeAnimation(keyPath: flip.axis == .y ? "transform.scale.x" : "transform.scale.y")
        squash.values = keys.squash.map { NSNumber(value: $0) }
        squash.keyTimes = keys.times.map { NSNumber(value: $0 / total) }
        squash.duration = total
        squash.beginTime = now
        squash.fillMode = .backwards
        plate.add(squash, forKey: key)
        var out: [(CALayer, String)] = [(plate, key)]
        for (i, face) in faces.enumerated() {
            let shows = CAKeyframeAnimation(keyPath: "opacity")
            shows.calculationMode = .discrete
            shows.values = keys.faceTimes.map { NSNumber(value: ($0.back == (i == 1)) ? 1 : 0) }
            shows.keyTimes = (keys.faceTimes.map(\.t) + [total]).map { NSNumber(value: $0 / total) }
            shows.duration = total
            shows.beginTime = now
            shows.fillMode = .backwards
            let faceKey = "\(key).\(i)"
            face.add(shows, forKey: faceKey)
            out.append((face, faceKey))
        }
        return out
    }

    private static func keyPath(_ p: SceneProperty) -> String {
        switch p {
        case .x: "position.x"
        case .y: "position.y"
        case .scale: "transform.scale"
        case .scaleX: "transform.scale.x"
        case .scaleY: "transform.scale.y"
        case .rotate: "transform.rotation.z"
        case .opacity: "opacity"
        case .z: "zPosition"
        case .flip: "transform.scale.x"
        }
    }

    private static func timing(_ ease: SceneEase) -> CAMediaTimingFunction {
        switch ease {
        case .linear, .step: CAMediaTimingFunction(name: .linear)
        case .easeIn: CAMediaTimingFunction(name: .easeIn)
        case .easeOut: CAMediaTimingFunction(name: .easeOut)
        case .easeInOut: CAMediaTimingFunction(name: .easeInEaseOut)
        case .spring: CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
        }
    }

    // MARK: A ghost under a drag

    func shiftGhost(dx: CGFloat, dy: CGFloat) {
        ghostShift = (dx, dy)
        place()
    }

    func placeGhost(_ frame: CGRect, in canvas: CALayer) {
        // A ghost is drawn in canvas coordinates: it lives directly under the canvas, or its parent's box is its offset.
        let origin = main.superlayer.map { canvas.convert(CGPoint.zero, from: $0) } ?? .zero
        let local = frame.offsetBy(dx: -origin.x, dy: -origin.y)
        ghostFrame = main.frame
        main.bounds = CGRect(origin: .zero, size: local.size)
        main.position = CGPoint(x: local.minX + local.width * main.anchorPoint.x, y: local.minY + local.height * main.anchorPoint.y)
        main.opacity = 1
        if case .shape(let form) = node.kind {
            shape?.path = SceneDrawing.path(form.form, box: CGRect(origin: .zero, size: local.size), corner: node.corner)
        }
    }

    func clearGhost() {
        ghostShift = nil
        if ghostFrame != nil {
            ghostFrame = nil
            main.bounds = CGRect(x: 0, y: 0, width: node.width, height: node.height)
            if case .shape(let form) = node.kind {
                shape?.path = SceneDrawing.path(form.form, box: main.bounds, corner: node.corner)
            }
        }
        place()
    }
}

extension SceneNode {
    var isShape: Bool { if case .shape = kind { true } else { false } }
    var isFlip: Bool { if case .flip = kind { true } else { false } }
}
