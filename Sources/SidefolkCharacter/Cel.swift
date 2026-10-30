import QuartzCore

/// Small builders for the 2D companions' flat drawings (D59), in the look of `Flat`: parts with their
/// outline and cel shadow, lines and groups. Most of what they wear is painted (`Painted`).
@MainActor
enum Cel {
    /// A part in its own colour, outlined and cel-shaded.
    static func part(_ path: CGPath, _ color: RGB, line: RGB? = nil, light: CGFloat = 0.5) -> CALayer {
        SoftShape(path, shading: .flat(color, line: line, light: light)).layer
    }

    /// A line drawn in ink (whiskers, creases, a glasses frame).
    static func line(_ path: CGPath, _ color: RGB, width: CGFloat) -> CAShapeLayer {
        Layers.shape(path, stroke: color.cg(), lineWidth: width)
    }

    /// Several layers as one drawing.
    static func group(_ layers: [CALayer]) -> CALayer {
        let root = Layers.canvas()
        layers.forEach(root.addSublayer)
        return root
    }
}
