import QuartzCore

/// How an arm looks: a mitten hanging from its shoulder (the origin), hand at the bottom.
struct ArmStyle {
    var shape: CGPath
    var shading: Shading
    /// A thin edge so white arms separate from a white body.
    var edge: (color: RGB, alpha: CGFloat)?
    /// A differently coloured hand over the end of the arm (Spark's dark mittens).
    var hand: (path: CGPath, shading: Shading)?

    /// The robot's stubby white mitten.
    @MainActor static let robot = ArmStyle(
        shape: Shapes.arm,
        shading: Shading(colors: Palette.shell, locations: [0, 0.3, 0.6, 0.85, 1],
                         center: CGPoint(x: 0.35, y: 0.7), reach: CGSize(width: 0.9, height: 0.9)),
        edge: (Palette.shellEdge, 0.35))
}

/// An arm: a mitten that rotates around its shoulder. The pose angle lives on `pose`, repeating
/// motion (typing, waving) on `loop`.
@MainActor
final class Limb {
    let pose: CALayer
    let loop: CALayer
    /// Things held in this hand: canvas units, drawn for the arm hanging at rest, turning with it.
    let grip = Layers.canvas()
    private let shoulder: CGPoint
    private let shape: CGPath
    private(set) var angle: CGFloat = 0

    init(shoulder: CGPoint, style: ArmStyle = .robot) {
        self.shoulder = shoulder
        shape = style.shape
        pose = Layers.canvas(anchor: shoulder)
        loop = Layers.canvas(anchor: shoulder)
        let mitten = SoftShape(Paths.translated(style.shape, shoulder.x, shoulder.y), shading: style.shading)
        mitten.shadow(radius: 2.5, opacity: 0.18, offset: CGSize(width: 0, height: -1))
        if let edge = style.edge { mitten.outline(edge.color, alpha: edge.alpha, width: 0.7) }
        pose.addSublayer(loop)
        loop.addSublayer(mitten.layer)
        if let hand = style.hand {
            loop.addSublayer(SoftShape(Paths.translated(hand.path, shoulder.x, shoulder.y), shading: hand.shading).layer)
        }
        loop.addSublayer(grip)
    }

    /// `raise` > 0 swings the hand outward and up; the left arm turns clockwise for that.
    func raise(_ raise: CGFloat, side: CGFloat, _ transit: Transit) {
        angle = raise * side
        Motion.set(pose, "transform", Motion.transform(CGAffineTransform(rotationAngle: angle)), transit)
    }

    /// The mitten's outline at its posed angle, in body coordinates.
    var outline: CGPath {
        Paths.transformed(shape, CGAffineTransform(translationX: shoulder.x, y: shoulder.y).rotated(by: angle))
    }
}
