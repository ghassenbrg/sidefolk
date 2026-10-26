import QuartzCore

/// An ear, antenna or sprout, rotating around its base. Three nested layers keep its motions
/// apart: `root` holds its pose (rest tilt plus droop, and the fold of soft ears), `trail` one-shot
/// follow-through and `sway` the gentle repeating swing.
@MainActor
final class Appendage {
    let root: CALayer
    let sway: CALayer
    /// One-shot follow-through; antics move it too (its model transform stays the identity).
    let trail: CALayer
    private let art: CALayer
    let spec: AppendageSpec
    private(set) var angle: CGFloat
    /// Where it sits and how it is stretched beyond its rotation: folded back, an ear seen from the
    /// front hangs from the head's edge, shorter and a little narrower.
    private var shift = CGPoint.zero
    private var scale = CGSize(width: 1, height: 1)

    init(_ spec: AppendageSpec) {
        self.spec = spec
        angle = spec.angle
        root = Layers.canvas(anchor: spec.base)
        trail = Layers.canvas(anchor: spec.base)
        sway = Layers.canvas(anchor: spec.base)
        art = Layers.canvas()
        root.addSublayer(trail)
        trail.addSublayer(sway)
        sway.addSublayer(art)
        Motion.still { root.setAffineTransform(CGAffineTransform(rotationAngle: angle)) }
    }

    /// Redraws it (the style colour changed); the motion layers stay.
    func draw(_ accent: RGB) {
        art.sublayers?.forEach { $0.removeFromSuperlayer() }
        let placed = Layers.canvas()
        placed.setAffineTransform(CGAffineTransform(translationX: spec.base.x, y: spec.base.y))
        placed.addSublayer(spec.layers(accent))
        art.addSublayer(placed)
    }

    /// Positive `droop` turns it outward and down, negative perks it up. A soft ear folding back
    /// (`fold` 1) lies down along the head: turned further out, foreshortened, a little narrower.
    func pose(_ droop: CGFloat, fold: CGFloat, _ transit: Transit) {
        let folding = spec.fold
        let f = folding == nil ? 0 : fold
        angle = spec.angle - spec.side * (droop + f * (folding?.turn ?? 0))
        shift = pt(spec.side * f * (folding?.shift.x ?? 0), f * (folding?.shift.y ?? 0))
        scale = CGSize(width: 1 - f * 0.1, height: 1 - f * (1 - (folding?.length ?? 1)))
        Motion.set(root, "transform", Motion.transform(placement), transit)
    }

    /// Pose transform around the base: stretch, turn, then slide.
    private var placement: CGAffineTransform {
        CGAffineTransform(translationX: shift.x, y: shift.y).rotated(by: angle).scaledBy(x: scale.width, y: scale.height)
    }

    /// A damped flop outward and back, as when the body jumps and lands.
    func flop(_ amount: CGFloat, duration: CFTimeInterval) {
        let a = -spec.side * amount * spec.floppiness
        trail.add(Motion.keyframes("transform.rotation.z", [0, a, -0.5 * a, 0.22 * a, -0.08 * a, 0], duration: duration),
                  forKey: "trail")
    }

    /// A damped swing to one side and back (the head shook), the same way for both ears.
    func swing(_ amount: CGFloat, duration: CFTimeInterval) {
        let a = amount * spec.floppiness
        trail.add(Motion.keyframes("transform.rotation.z", [0, a, -0.8 * a, 0.45 * a, -0.15 * a, 0], duration: duration),
                  forKey: "trail")
    }

    /// The idle swing, out of step between the two ears.
    func swayLoop(fast: Bool, phase: CFTimeInterval) -> Loop {
        let reach = (fast ? 0.12 : 0.035) * spec.floppiness
        let animation = Motion.loop("transform.rotation.z", from: -reach, to: reach, duration: fast ? 0.45 : 2.7, phase: phase)
        return Loop(layer: sway, key: "sway", animation: animation)
    }

    /// Its outline at the current pose, in the coordinates of the layer it hangs from.
    var outline: CGPath {
        Paths.transformed(spec.outline, placement.concatenating(CGAffineTransform(translationX: spec.base.x, y: spec.base.y)))
    }
}

/// The shared accessories, fitted to each body by its `Collar`.
@MainActor
enum Wardrobe {
    /// A knitted scarf: a band around the neck, sagging a little, with one end hanging in front.
    static func scarf(_ collar: Collar, _ color: RGB) -> CALayer {
        let root = Layers.canvas()
        let shape = ScarfShape(collar)
        let shading = Shading(colors: [color.lighter(0.32), color.lighter(0.12), color, color.darker(0.09), color.darker(0.18)],
                              locations: [0, 0.3, 0.58, 0.84, 1], center: CGPoint(x: 0.32, y: 0.8),
                              reach: CGSize(width: 1.0, height: 1.2))
        let wrap = SoftShape(shape.band, shading: shading)
        wrap.shadow(radius: 2.5, opacity: 0.16, offset: CGSize(width: 0, height: -1.5))
        root.addSublayer(wrap.layer)
        let hanging = SoftShape(shape.tail, shading: shading)
        hanging.shadow(radius: 2.5, opacity: 0.2, offset: CGSize(width: 0.5, height: -1.5))
        root.addSublayer(hanging.layer)
        // The fold where the end comes out from under the wrap.
        root.addSublayer(Layers.shape(Paths.ellipse(shape.knot + pt(0, -1), shape.tailWidth * 0.46, collar.height * 0.3),
                                      fill: color.darker(0.14).cg(0.5)))
        // Knit ribs: faint darker lines across the band and down the end.
        let c = collar.center, w = collar.halfWidth, h = collar.height
        let ribs = CGMutablePath()
        for i in stride(from: -w + 6, through: w - 5, by: 5.5) {
            let sagHere = collar.sag * 2 * (1 - (i / w) * (i / w))
            ribs.move(to: pt(c.x + i, c.y + h / 2 - sagHere * 0.5 - 2.5))
            ribs.addLine(to: pt(c.x + i, c.y - h / 2 - sagHere * 0.5 + 2.5))
        }
        for dx in [-shape.tailWidth * 0.22, shape.tailWidth * 0.22] {
            ribs.move(to: shape.onTail(pt(dx, -3)))
            ribs.addLine(to: shape.onTail(pt(dx * 1.15, -shape.tailLength + 4)))
        }
        root.addSublayer(Layers.shape(ribs, stroke: color.darker(0.2).cg(0.14), lineWidth: 1.3))
        return root
    }

    /// The scarf's outline, for clicks.
    static func scarfOutline(_ collar: Collar) -> CGPath {
        let shape = ScarfShape(collar)
        return shape.band.union(shape.tail)
    }
}

/// A scarf's geometry: the wrap and the loose end hanging from the knot on the companion's left
/// (our right), a little askew and flaring toward its end.
private struct ScarfShape {
    let band: CGPath
    let tail: CGPath
    let knot: CGPoint
    let tailWidth: CGFloat
    let tailLength: CGFloat
    private let hang: CGAffineTransform

    init(_ collar: Collar) {
        let c = collar.center, w = collar.halfWidth, h = collar.height
        let band = CGMutablePath()
        band.move(to: pt(c.x - w, c.y + h / 2))
        band.addQuadCurve(to: pt(c.x + w, c.y + h / 2), control: pt(c.x, c.y + h / 2 - collar.sag * 2))
        band.addQuadCurve(to: pt(c.x + w, c.y - h / 2), control: pt(c.x + w + h * 0.55, c.y))
        band.addQuadCurve(to: pt(c.x - w, c.y - h / 2), control: pt(c.x, c.y - h / 2 - collar.sag * 2))
        band.addQuadCurve(to: pt(c.x - w, c.y + h / 2), control: pt(c.x - w - h * 0.55, c.y))
        band.closeSubpath()
        self.band = band
        knot = pt(c.x + w * 0.4, c.y - h * 0.1)
        tailWidth = h * 1.05
        tailLength = h * collar.tail
        hang = CGAffineTransform(translationX: knot.x, y: knot.y).rotated(by: 0.26)
        let top = tailWidth * 0.42, bottom = tailWidth * 0.56, round = tailWidth * 0.3
        let end = CGMutablePath()
        end.move(to: pt(-top, 0))
        end.addLine(to: pt(top, 0))
        end.addLine(to: pt(bottom, -tailLength + round))
        end.addQuadCurve(to: pt(bottom - round, -tailLength), control: pt(bottom, -tailLength))
        end.addLine(to: pt(-bottom + round, -tailLength))
        end.addQuadCurve(to: pt(-bottom, -tailLength + round), control: pt(-bottom, -tailLength))
        end.closeSubpath()
        tail = Paths.transformed(end, hang)
    }

    /// A point given along the hanging end (x across, y down from the knot) in canvas units.
    func onTail(_ p: CGPoint) -> CGPoint { p.applying(hang) }
}
