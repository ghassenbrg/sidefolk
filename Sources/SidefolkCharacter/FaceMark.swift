import QuartzCore

/// One morphing facial stroke (an eye, a brow, the mouth). Light marks glow, with an optional hot
/// core (the robot's visor, Spark's screen); ink marks are solid strokes, eyes with a catchlight
/// (Mochi and the folks).
@MainActor
final class FaceMark {
    let layer: CALayer
    private let line = CAShapeLayer()
    private let core: CAShapeLayer?
    /// The white glint in an open ink eye, up and to the right of its middle.
    private let shine: CAShapeLayer?
    /// A 2D eye's coloured lower half: a gradient seen through a copy of the stroke.
    private let iris: CAShapeLayer?
    private static let box: CGFloat = 60

    /// A glowing mark, coloured by `tint(_:)`.
    init(center: CGPoint, core hasCore: Bool) {
        layer = Self.frame(center)
        core = hasCore ? CAShapeLayer() : nil
        shine = nil
        iris = nil
        for stroke in [line, core].compactMap(\.self) { Self.add(stroke, to: layer) }
        Layers.glow(line, Palette.aqua, radius: 4.5, opacity: 0.95)
    }

    /// An ink mark; eyes get a catchlight sized for `scale`.
    init(center: CGPoint, ink: RGB, shine glint: Bool, scale: CGFloat) {
        layer = Self.frame(center)
        core = nil
        iris = nil
        Self.add(line, to: layer)
        line.strokeColor = ink.cg()
        if glint {
            let dot = Layers.shape(Paths.circle(pt(Self.box / 2 + 2.3 * scale, Self.box / 2 + 3 * scale), 1.8 * scale),
                                   fill: RGB.white.cg())
            layer.addSublayer(dot)
            shine = dot
        } else {
            shine = nil
        }
    }

    /// A 2D cartoon eye (`Flat`): the ink fades into `color` toward its bottom, and an open eye
    /// carries a big catchlight up on the side of the light (`side`) and a small one low on the other.
    init(center: CGPoint, ink: RGB, iris color: RGB, scale: CGFloat, side: CGFloat, size: CGFloat = 1) {
        layer = Self.frame(center)
        // Bigger than the face's other marks, as cartoon eyes are: the whole mark grows around its middle.
        layer.setAffineTransform(CGAffineTransform(scaleX: size, y: size))
        core = nil
        Self.add(line, to: layer)
        line.strokeColor = ink.cg()
        let tint = CAShapeLayer()
        Self.add(tint, to: layer)
        tint.strokeColor = RGB.white.cg()
        let gradient = CAGradientLayer()
        gradient.frame = layer.bounds
        // Unit coordinates of the 60-unit box, y up: the colour rises from the eye's bottom to its middle.
        let mid = 0.5, reach = 7.5 * scale / Self.box
        gradient.startPoint = CGPoint(x: 0.5, y: mid - reach)
        gradient.endPoint = CGPoint(x: 0.5, y: mid + reach * 0.1)
        gradient.colors = [color.lighter(0.25).cg(), color.cg(), ink.cg()]
        gradient.locations = [0, 0.3, 1]
        gradient.mask = tint
        layer.addSublayer(gradient)
        iris = tint
        let glints = CALayer()
        glints.frame = layer.bounds
        let c = Self.box / 2
        glints.addSublayer(Layers.shape(Paths.ellipse(pt(c + side * 1.9 * scale, c + 2.6 * scale), 2.5 * scale, 2.8 * scale),
                                        fill: RGB.white.cg()))
        glints.addSublayer(Layers.shape(Paths.circle(pt(c - side * 2.2 * scale, c - 3 * scale), 1.1 * scale),
                                        fill: RGB.white.cg(0.9)))
        layer.addSublayer(glints)
        shine = nil
        glintLayer = glints
    }

    /// The 2D eye's two catchlights, shown like `shine`.
    private var glintLayer: CALayer?

    private static func frame(_ center: CGPoint) -> CALayer {
        let half = box / 2
        let layer = CALayer()
        layer.frame = CGRect(x: center.x - half, y: center.y - half, width: box, height: box)
        return layer
    }

    private static func add(_ stroke: CAShapeLayer, to layer: CALayer) {
        stroke.frame = layer.bounds
        stroke.fillColor = nil
        stroke.lineCap = .round
        stroke.lineJoin = .round
        layer.addSublayer(stroke)
    }

    func tint(_ accent: Light) {
        line.strokeColor = accent.line.cg()
        line.shadowColor = accent.glow.cg()
        core?.strokeColor = accent.core.cg(0.85)
    }

    func show(_ stroke: Stroke, _ transit: Transit, shine amount: CGFloat = 0) {
        let local = pt(FaceMark.box / 2, FaceMark.box / 2)
        let path = stroke.path(at: local)
        Motion.set(line, "path", path, transit)
        Motion.set(line, "lineWidth", stroke.width, transit)
        if let core {
            Motion.set(core, "path", path, transit)
            Motion.set(core, "lineWidth", stroke.width * 0.4, transit)
        }
        if let shine { Motion.set(shine, "opacity", Float(amount), transit) }
        if let iris {
            Motion.set(iris, "path", path, transit)
            Motion.set(iris, "lineWidth", stroke.width, transit)
            // Only an open eye shows its colour: closed and happy arcs are plain ink.
            Motion.set(iris, "opacity", Float(amount), transit)
        }
        if let glintLayer { Motion.set(glintLayer, "opacity", Float(amount), transit) }
    }
}
