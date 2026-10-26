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
    private static let box: CGFloat = 60

    /// A glowing mark, coloured by `tint(_:)`.
    init(center: CGPoint, core hasCore: Bool) {
        layer = Self.frame(center)
        core = hasCore ? CAShapeLayer() : nil
        shine = nil
        for stroke in [line, core].compactMap(\.self) { Self.add(stroke, to: layer) }
        Layers.glow(line, Palette.aqua, radius: 4.5, opacity: 0.95)
    }

    /// An ink mark; eyes get a catchlight sized for `scale`.
    init(center: CGPoint, ink: RGB, shine glint: Bool, scale: CGFloat) {
        layer = Self.frame(center)
        core = nil
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
    }
}
