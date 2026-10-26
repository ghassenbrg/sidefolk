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

    /// Resource-free brand fallback. The original robot remains a separate selectable performer.
    @MainActor
    public static func appIcon(size: Int) -> CGImage {
        let c = bitmap(CGSize(width: size, height: size), 1)
        let fit = CGFloat(size) / 1024
        c.scaleBy(x: fit, y: fit)
        c.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                         cornerWidth: 185, cornerHeight: 185, transform: nil))
        c.clip()
        c.setFillColor(CGColor(srgbRed: 147/255, green: 197/255, blue: 253/255, alpha: 1))
        c.fill(CGRect(x: 100, y: 100, width: 824, height: 824))
        c.translateBy(x: 195, y: 130)
        RabbitBrandMark.draw(in: c, size: CGSize(width: 634, height: 760),
                             ink: CGColor(srgbRed: 15/255, green: 45/255, blue: 91/255, alpha: 1), color: true)
        return c.makeImage()!
    }

    public static func mascotMark(size: CGSize, scale: CGFloat, ink: CGColor) -> CGImage {
        let c = bitmap(size, scale)
        c.scaleBy(x: scale, y: scale)
        RabbitBrandMark.draw(in: c, size: size, ink: ink)
        return c.makeImage()!
    }

    public static func mascotPDF(size: CGSize, ink: CGColor) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let c = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        c.beginPDFPage(nil); RabbitBrandMark.draw(in: c, size: size, ink: ink)
        c.endPDFPage(); c.closePDF()
        return data as Data
    }

    /// Mochi's rabbit ears, face and scarf simplified for an 18 pt macOS template.
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
        RabbitBrandMark.draw(in: context, size: size, ink: CGColor(gray: 0, alpha: 1))
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
