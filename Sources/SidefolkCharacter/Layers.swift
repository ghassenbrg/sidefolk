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

    /// What `layer`'s subtree draws, in `space` coordinates (model values: the pose at rest):
    /// shapes by their paths, gradients by their frames; hidden and transparent parts left out.
    static func visibleBounds(_ layer: CALayer, in space: CALayer) -> CGRect {
        guard !layer.isHidden, layer.opacity > 0.01 else { return .null }
        var box = CGRect.null
        if let shape = layer as? CAShapeLayer, let path = shape.path, shape.fillColor != nil || shape.strokeColor != nil {
            let half = shape.strokeColor == nil ? 0 : shape.lineWidth / 2
            box = layer.convert(path.boundingBoxOfPath.insetBy(dx: -half, dy: -half), to: space)
        } else if layer is CAGradientLayer || layer.contents != nil {
            box = layer.convert(layer.bounds, to: space)
        }
        for sublayer in layer.sublayers ?? [] { box = box.union(visibleBounds(sublayer, in: space)) }
        return box
    }

    /// Sets contentsScale through a subtree so vector content stays crisp at the drawn size.
    static func setContentsScale(_ scale: CGFloat, in layer: CALayer) {
        layer.contentsScale = scale
        if layer.shouldRasterize { layer.rasterizationScale = scale }
        layer.mask.map { setContentsScale(scale, in: $0) }
        let inner = scale * ((layer as? Magnifier)?.factor ?? 1)
        layer.sublayers?.forEach { setContentsScale(inner, in: $0) }
    }
}

/// Shows drawings made for another canvas `factor` times bigger (the on-duty folks' accessories on
/// a full-size folk), telling `setContentsScale` to rasterize them that much finer so they stay sharp.
final class Magnifier: CALayer {
    let factor: CGFloat

    init(_ factor: CGFloat) {
        self.factor = factor
        super.init()
        bounds = CGRect(origin: .zero, size: Canvas.size)
        anchorPoint = .zero
        position = .zero
        setAffineTransform(CGAffineTransform(scaleX: factor, y: factor))
    }

    override init(layer: Any) {
        factor = (layer as? Magnifier)?.factor ?? 1
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Magnifier is created in code") }
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

    /// Drawn as a 2D cartoon instead (`Flat`): the 2D companions don't imitate their 3D selves.
    var flat: Flat?

    /// A flat cel-shaded fill in `color`: one hard shadow tone, a thin light rim, an outline.
    static func flat(_ color: RGB, shade: RGB? = nil, line: RGB? = nil, light: CGFloat = 0.5) -> Shading {
        var shading = Shading.tinted(color)
        shading.flat = Flat(fill: color, shade: shade ?? Flat.shade(color), line: line ?? Flat.line(color), light: light)
        return shading
    }
}

/// The 2D companions' look, like an animated series: a flat fill, one hard-edged shadow along the
/// lower right, a thin light rim along the upper left and a smooth outline a darker tone of the
/// fill (never black). No gradients and no blurred drop shadows: those are the 3D look's.
struct Flat: Sendable {
    var fill: RGB
    var shade: RGB
    var line: RGB
    /// How strong the light rim is, 0 for none (small or dark parts).
    var light: CGFloat
    var lineWidth: CGFloat = 2

    /// Shadows lean cool and violet, as painted shadows do, rather than just darker.
    static func shade(_ color: RGB) -> RGB { color.mix(RGB(0x4A3F78), 0.2) }
    static func line(_ color: RGB) -> RGB { color.mix(RGB(0x2A2140), 0.62) }
}

/// A filled shape with radial shading: a gradient masked by the path, inside a container that
/// carries an optional drop shadow (shadows on masked layers would be clipped).
@MainActor
final class SoftShape {
    let layer = CALayer()
    private let gradient = CAGradientLayer()
    private let mask = CAShapeLayer()
    private let flat: Bool

    init(_ path: CGPath, shading: Shading = .shell) {
        let box = path.boundingBoxOfPath
        layer.frame = box
        flat = shading.flat != nil
        if let style = shading.flat {
            mask.path = Paths.translated(path, -box.minX, -box.minY)
            Self.cel(mask.path!, style, size: box.size).forEach(layer.addSublayer)
            return
        }
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
        guard !flat else { return }
        Layers.dropShadow(layer, path: mask.path, radius: radius, opacity: opacity, offset: offset)
    }

    /// A thin outline on top of the shading, so white parts separate from white backgrounds.
    func outline(_ color: RGB, alpha: CGFloat, width: CGFloat) {
        guard !flat else { return }
        let line = CAShapeLayer()
        line.frame = layer.bounds
        line.path = mask.path
        line.fillColor = nil
        line.strokeColor = color.cg(alpha)
        line.lineWidth = width
        layer.addSublayer(line)
    }

    /// The flat look's layers for `path`: fill, the shadow (the shape minus itself moved up and
    /// left, a crescent along the lower right), the light rim (the same the other way, thinner) and
    /// the outline. The offsets follow the part's size so small parts get small crescents.
    static func cel(_ path: CGPath, _ style: Flat, size: CGSize) -> [CALayer] {
        let k = min(max(min(size.width, size.height) * 0.15, 1.6), 9)
        var layers = [Self.fill(path, style.fill)]
        layers.append(Self.fill(path.subtracting(Paths.translated(path, -0.55 * k, k)), style.shade))
        if style.light > 0, min(size.width, size.height) > 14 {
            let rim = path.subtracting(Paths.translated(path, 0.3 * k, -0.42 * k))
            layers.append(Self.fill(rim, style.fill.lighter(0.55), alpha: style.light))
        }
        let line = CAShapeLayer()
        line.path = path
        line.fillColor = nil
        line.strokeColor = style.line.cg()
        line.lineWidth = style.lineWidth
        line.lineJoin = .round
        layers.append(line)
        return layers
    }

    private static func fill(_ path: CGPath, _ color: RGB, alpha: CGFloat = 1) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = color.cg(alpha)
        return layer
    }
}
