import AppKit

/// Offscreen rendering of the same layer rigs the views use: icons, docs and visual tests.
public enum CharacterRenderer {
    /// A still frame of `state`, centered and scaled to fit `size` (points) at `scale` pixels per point.
    /// Busy sprite states show the first of their poses.
    @MainActor
    public static func image(state: CharacterState, size: CGSize, scale: CGFloat, badges: Set<CharacterBadge> = [],
                             gaze: CGVector? = nil, look: CharacterLook = .sidefolk(.aqua)) -> CGImage {
        let performer = look.performer(live: false)
        performer.show(state, animated: false)
        performer.setBadges(badges, animated: false)
        performer.setGaze(gaze)
        return render(performer.stage, canvas: Canvas.size, size: size, scale: scale)
    }

    @MainActor
    public static func folkImage(_ folk: Folk, size: CGSize, scale: CGFloat) -> CGImage {
        let rig = FolkRig(folk)
        let holder = Layers.canvas(FolkCanvas.size, anchor: pt(50, 50))
        holder.addSublayer(rig.root)
        return render(holder, canvas: FolkCanvas.size, size: size, scale: scale)
    }

    /// Vector fallback for the macOS app icon: a flat white tile and the companion family.
    /// Sizes of 32 px and under drop the folks so the face stays readable.
    @MainActor
    public static func appIcon(size: Int) -> CGImage {
        let scene = IconScene(detailed: size > 32).layer
        return render(scene, canvas: IconScene.canvas, size: CGSize(width: size, height: size), scale: 1)
    }

    /// The reference companion simplified for 18 pt: rounded shell, filled visor, cut-out smiles.
    /// A template must use alpha alone so macOS can tint it for any menu bar appearance.
    @MainActor
    public static func menuBarTemplate(size: CGSize, scale: CGFloat) -> CGImage {
        let context = bitmap(size, scale)
        context.scaleBy(x: scale, y: scale)
        drawMenuBar(in: context, size: size)
        return context.makeImage()!
    }

    /// Vector template for asset catalogs or other native clients.
    public static func menuBarPDF(size: CGSize) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        drawMenuBar(in: context, size: size)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private static func drawMenuBar(in context: CGContext, size: CGSize) {
        let fit = min(size.width, size.height) / 24
        context.translateBy(x: (size.width - 24 * fit) / 2, y: (size.height - 24 * fit) / 2)
        context.scaleBy(x: fit, y: fit)
        let black = CGColor(gray: 0, alpha: 1)
        context.setStrokeColor(black)
        context.setFillColor(black)
        context.setLineWidth(1.8)
        context.setLineJoin(.round)
        let shell = CGMutablePath()
        shell.move(to: CGPoint(x: 12, y: 21.5))
        shell.addCurve(to: CGPoint(x: 22, y: 9), control1: CGPoint(x: 19, y: 21.5), control2: CGPoint(x: 22, y: 16))
        shell.addCurve(to: CGPoint(x: 17, y: 3), control1: CGPoint(x: 22, y: 4), control2: CGPoint(x: 20, y: 3))
        shell.addLine(to: CGPoint(x: 7, y: 3))
        shell.addCurve(to: CGPoint(x: 2, y: 9), control1: CGPoint(x: 4, y: 3), control2: CGPoint(x: 2, y: 4))
        shell.addCurve(to: CGPoint(x: 12, y: 21.5), control1: CGPoint(x: 2, y: 16), control2: CGPoint(x: 5, y: 21.5))
        shell.closeSubpath()
        context.addPath(shell)
        context.strokePath()
        let visor = CGMutablePath()
        visor.addPath(CGPath(roundedRect: CGRect(x: 4.6, y: 7.2, width: 14.8, height: 10),
                             cornerWidth: 4.8, cornerHeight: 4.8, transform: nil))
        for x in [7.0, 13.0] {
            let eye = CGMutablePath()
            eye.move(to: CGPoint(x: x, y: 11))
            eye.addCurve(to: CGPoint(x: x + 4, y: 11),
                         control1: CGPoint(x: x + 1, y: 13.6), control2: CGPoint(x: x + 3, y: 13.6))
            visor.addPath(eye.copy(strokingWithWidth: 1.5, lineCap: .round, lineJoin: .round, miterLimit: 1))
        }
        context.addPath(visor)
        context.drawPath(using: .eoFill)
    }

    // MARK: Plumbing

    static func bitmap(_ size: CGSize, _ scale: CGFloat) -> CGContext {
        CGContext(data: nil, width: Int((size.width * scale).rounded()), height: Int((size.height * scale).rounded()),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Draws `layer` (whose bounds are `canvas`) aspect-fit into a new bitmap.
    ///
    /// The scale goes on a holder layer, not on the context: `render(in:)` sizes shadows in
    /// context pixels but does honor layer transforms, so this keeps glows proportional.
    @MainActor
    static func render(_ layer: CALayer, canvas: CGSize, size: CGSize, scale: CGFloat) -> CGImage {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let fit = min(pixels.width / canvas.width, pixels.height / canvas.height)
        let holder = CALayer()
        holder.bounds = CGRect(origin: .zero, size: pixels)
        Motion.still {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: pixels.width / 2, y: pixels.height / 2)
            layer.setAffineTransform(CGAffineTransform(scaleX: fit, y: fit))
        }
        holder.addSublayer(layer)
        let context = bitmap(size, scale)
        holder.render(in: context)
        layer.removeFromSuperlayer()
        return context.makeImage()!
    }
}

/// The app icon's composition in a 1024 canvas (Apple's macOS grid: an 824 tile inset by 100).
@MainActor
private struct IconScene {
    static let canvas = CGSize(width: 1024, height: 1024)
    let layer = Layers.canvas(IconScene.canvas, anchor: pt(512, 512))

    init(detailed: Bool) {
        let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = Paths.roundedRect(tileRect, 185)
        layer.addSublayer(Layers.shape(tilePath, fill: RGB.white.cg()))

        let character = Director(live: false)
        character.show(.idle, animated: false)

        if detailed {
            for a in [0.5, 0.82] {
                let dir = pt(cos(a), sin(a))
                let c = pt(512, 470)
                layer.addSublayer(Layers.shape(Paths.polyline([c + dir * 335, c + dir * 392]), stroke: Palette.aqua.cg(), lineWidth: 26))
            }
            place(.byte, center: pt(318, 560), scale: 3.7, mirrored: false)
            place(.tempo, center: pt(712, 508), scale: 3.6, mirrored: true)
            place(.pip, center: pt(588, 738), scale: 3.6, mirrored: false)
            place(.seed, center: pt(262, 330), scale: 3.5, mirrored: false)
            place(character.rig.stage, floor: pt(512, 168), scale: 3.3)
        } else {
            place(character.rig.stage, floor: pt(512, 112), scale: 5.0)
        }
    }

    private func place(_ folk: Folk, center: CGPoint, scale: CGFloat, mirrored: Bool) {
        let rig = FolkRig(folk, plain: true)
        let holder = Layers.canvas(FolkCanvas.size, anchor: FolkCanvas.center)
        holder.position = center
        holder.setAffineTransform(CGAffineTransform(scaleX: mirrored ? -scale : scale, y: scale))
        holder.addSublayer(rig.root)
        layer.addSublayer(holder)
    }

    private func place(_ stage: CALayer, floor: CGPoint, scale: CGFloat) {
        let holder = Layers.canvas(Canvas.size, anchor: Canvas.pivot)
        holder.position = floor
        holder.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        holder.addSublayer(stage)
        layer.addSublayer(holder)
    }
}
