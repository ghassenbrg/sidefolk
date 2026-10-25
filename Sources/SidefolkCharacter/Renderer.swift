import AppKit

/// Offscreen rendering of the same layer rigs the views use: icons, docs and visual tests.
public enum CharacterRenderer {
    /// A still frame of `state`, centered and scaled to fit `size` (points) at `scale` pixels per point.
    @MainActor
    public static func image(state: CharacterState, size: CGSize, scale: CGFloat,
                             badges: Set<CharacterBadge> = [], gaze: CGVector? = nil) -> CGImage {
        let director = Director(live: false)
        director.show(state, animated: false)
        director.setBadges(badges, animated: false)
        director.setGaze(gaze)
        return render(director.rig.stage, canvas: Canvas.size, size: size, scale: scale)
    }

    @MainActor
    public static func folkImage(_ folk: Folk, size: CGSize, scale: CGFloat) -> CGImage {
        let rig = FolkRig(folk)
        let holder = Layers.canvas(FolkCanvas.size, anchor: pt(50, 50))
        holder.addSublayer(rig.root)
        return render(holder, canvas: FolkCanvas.size, size: size, scale: scale)
    }

    /// The macOS app icon: a soft white tile with the companion in front and folks peeking out.
    /// Sizes of 32 px and under drop the folks so the face stays readable.
    @MainActor
    public static func appIcon(size: Int) -> CGImage {
        let scene = IconScene(detailed: size > 32).layer
        return render(scene, canvas: IconScene.canvas, size: CGSize(width: size, height: size), scale: 1)
    }

    /// Black-on-transparent face for the menu bar (set `isTemplate` on the NSImage): the head as an
    /// outline, the visor filled, and the happy eyes cut out of it.
    @MainActor
    public static func menuBarTemplate(size: CGSize, scale: CGFloat) -> CGImage {
        let context = bitmap(size, scale)
        // Frame the head: ears to ears, chin to fin tip.
        let head = CGRect(x: 16, y: 22, width: 168, height: 162)
        let fit = min(size.width / head.width, size.height / head.height)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: (size.width - head.width * fit) / 2, y: (size.height - head.height * fit) / 2)
        context.scaleBy(x: fit, y: fit)
        context.translateBy(x: -head.minX, y: -head.minY)

        let black = CGColor(gray: 0, alpha: 1)
        context.setStrokeColor(black)
        context.setFillColor(black)
        context.setLineWidth(12)
        context.setLineJoin(.round)
        context.addPath(Shapes.body.union(Shapes.fin).union(Shapes.earPod(Canvas.earL)).union(Shapes.earPod(Canvas.earR)))
        context.strokePath()
        context.addPath(Paths.roundedRect(Canvas.visor.insetBy(dx: -2, dy: -2), 27))
        context.fillPath()
        context.setBlendMode(.clear)
        context.setLineCap(.round)
        for center in [Canvas.eyeL, Canvas.eyeR] {
            let eye = Stroke.arc(width: 22, rise: 9, thickness: 10)
            context.setLineWidth(eye.width)
            context.addPath(eye.path(at: center))
            context.strokePath()
        }
        return context.makeImage()!
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
        let shadow = Layers.shape(tilePath, fill: RGB.white.cg())
        Layers.dropShadow(shadow, path: shadow.path, radius: 18, opacity: 0.28, offset: CGSize(width: 0, height: -10),
                          color: RGB(0x0B1A33))
        layer.addSublayer(shadow)
        layer.addSublayer(Layers.gradient(tilePath, [RGB(0xFFFFFF), RGB(0xF4F7FC), RGB(0xE4ECF8)]))
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.frame = CGRect(x: 212, y: 230, width: 600, height: 520)
        glow.colors = [Palette.lightBlue.cg(0.28), Palette.lightBlue.cg(0)]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(glow)
        layer.addSublayer(Layers.shape(Paths.roundedRect(tileRect.insetBy(dx: 2, dy: 2), 183), stroke: RGB.white.cg(0.9), lineWidth: 3))

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
