import AppKit
import QuartzCore

/// Small layer builders shared by the character, the folks and the effects.
@MainActor
enum Layers {
    /// An empty layer covering a whole canvas, rotating and scaling around `anchor` (canvas units).
    static func canvas(_ size: CGSize = Canvas.size, anchor: CGPoint = Canvas.pivot) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.anchorPoint = CGPoint(x: anchor.x / size.width, y: anchor.y / size.height)
        layer.position = anchor
        return layer
    }

    /// A shape layer framed tightly around `path` (given in parent units), so the render server
    /// only rasterizes the area the shape covers.
    static func shape(_ path: CGPath, fill: CGColor? = nil, stroke: CGColor? = nil, lineWidth: CGFloat = 0,
                      pad: CGFloat = 2) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let box = path.boundingBoxOfPath.insetBy(dx: -(pad + lineWidth / 2), dy: -(pad + lineWidth / 2))
        layer.frame = box
        layer.path = Paths.translated(path, -box.minX, -box.minY)
        layer.fillColor = fill
        layer.strokeColor = stroke
        layer.lineWidth = lineWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    /// A linear gradient (top to bottom by default) clipped to `path`, framed tightly around it.
    static func gradient(_ path: CGPath, _ colors: [RGB], from start: CGPoint = CGPoint(x: 0.5, y: 1),
                         to end: CGPoint = CGPoint(x: 0.5, y: 0)) -> CAGradientLayer {
        let layer = CAGradientLayer()
        let box = path.boundingBoxOfPath
        layer.frame = box
        layer.colors = colors.map { $0.cg() }
        layer.startPoint = start
        layer.endPoint = end
        let mask = CAShapeLayer()
        mask.path = Paths.translated(path, -box.minX, -box.minY)
        layer.mask = mask
        return layer
    }

    /// A glowing round-capped stroke: the glow is a shadow in the light's own color.
    static func glow(_ layer: CALayer, _ color: RGB, radius: CGFloat, opacity: Float = 1) {
        layer.shadowColor = color.cg()
        layer.shadowOffset = .zero
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
    }

    /// Soft drop shadow, cheap because it follows a known path.
    static func dropShadow(_ layer: CALayer, path: CGPath?, radius: CGFloat, opacity: Float,
                           offset: CGSize = CGSize(width: 0, height: -2), color: RGB = Palette.ink) {
        layer.shadowColor = color.cg()
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
        layer.shadowPath = path
    }

    /// Text drawn with the rounded system face.
    static func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: RGB) -> CATextLayer {
        let layer = CATextLayer()
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        layer.font = font
        layer.fontSize = size
        layer.string = string
        layer.foregroundColor = color.cg()
        layer.alignmentMode = .center
        return layer
    }

    /// Sets contentsScale through a subtree so vector content stays crisp at the drawn size.
    static func setContentsScale(_ scale: CGFloat, in layer: CALayer) {
        layer.contentsScale = scale
        layer.mask.map { setContentsScale(scale, in: $0) }
        layer.sublayers?.forEach { setContentsScale(scale, in: $0) }
    }
}

/// Radial shading for a soft 3D look: light from the upper left, core shadow lower right.
struct Shading: Sendable {
    var colors: [RGB]
    var locations: [CGFloat]
    /// Light center and reach, in unit coordinates of the shape's bounding box (y up).
    var center = CGPoint(x: 0.36, y: 0.72)
    var reach = CGSize(width: 0.95, height: 1.0)

    static let shell = Shading(colors: Palette.shell, locations: [0, 0.3, 0.58, 0.82, 1])

    /// Shading for a colored blob (folks): lit tint, body color, shaded edge.
    static func tinted(_ color: RGB) -> Shading {
        Shading(colors: [color.lighter(0.42), color.lighter(0.12), color, color.darker(0.14), color.darker(0.26)],
                locations: [0, 0.3, 0.58, 0.84, 1])
    }
}

/// A filled shape with radial shading: a gradient masked by the path, inside a container that
/// carries an optional drop shadow (shadows on masked layers would be clipped).
@MainActor
final class SoftShape {
    let layer = CALayer()
    private let gradient = CAGradientLayer()
    private let mask = CAShapeLayer()

    init(_ path: CGPath, shading: Shading = .shell) {
        let box = path.boundingBoxOfPath
        layer.frame = box
        gradient.frame = layer.bounds
        gradient.type = .radial
        gradient.colors = shading.colors.map { $0.cg() }
        gradient.locations = shading.locations.map { NSNumber(value: Double($0)) }
        gradient.startPoint = shading.center
        gradient.endPoint = CGPoint(x: shading.center.x + shading.reach.width,
                                    y: shading.center.y + shading.reach.height)
        mask.path = Paths.translated(path, -box.minX, -box.minY)
        gradient.mask = mask
        layer.addSublayer(gradient)
    }

    func shadow(radius: CGFloat, opacity: Float, offset: CGSize = CGSize(width: 0, height: -2)) {
        Layers.dropShadow(layer, path: mask.path, radius: radius, opacity: opacity, offset: offset)
    }

    /// A thin outline on top of the shading, so white parts separate from white backgrounds.
    func outline(_ color: RGB, alpha: CGFloat, width: CGFloat) {
        let line = CAShapeLayer()
        line.frame = layer.bounds
        line.path = mask.path
        line.fillColor = nil
        line.strokeColor = color.cg(alpha)
        line.lineWidth = width
        layer.addSublayer(line)
    }
}
