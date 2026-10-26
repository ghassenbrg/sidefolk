import CoreGraphics
import Foundation

/// Smooth, authored curves following the supplied monochrome rabbit detail. PNG, PDF, SVG
/// and the resource-free fallback share this geometry; the face remains negative space.
public enum RabbitBrandMark {
    private static let shell = """
        M60 137 C44 114 27 84 29 58 C30 35 46 24 63 29
        C91 34 113 66 121 110 L139 110 C146 69 169 31 193 26
        C213 20 227 32 228 52 C230 79 212 111 200 134
        C220 149 229 171 226 191 C224 211 210 222 190 226
        C157 234 112 235 77 228 C48 225 32 215 32 195
        C30 172 42 151 60 137 Z
        """
    private static let caps = """
        M0 0 L132 0 L132 84 C98 75 71 84 45 113 L0 113 Z
        M132 0 L286 0 L286 112 L208 112 C189 86 171 78 146 82 L132 82 Z
        """
    private static let paw = """
        M224 188 C238 184 241 197 241 208 C240 222 225 234 211 240
        L201 216 C214 209 223 201 224 188 Z
        """
    // A narrow transparent gap separates the hanging scarf from its wrap, as in the reference.
    private static let scarf = """
        M47 219 C75 228 116 229 146 222 C151 232 154 247 154 261
        C122 267 88 263 63 255 C47 251 39 243 45 229 C46 225 47 222 47 219 Z
        M158 218 L189 212 C193 211 197 214 198 218 L210 272
        C212 281 209 285 200 286 L178 288 C169 289 165 286 164 278
        L160 245 C160 235 157 229 154 225 C152 221 154 219 158 218 Z
        """
    private static let scarfGap = """
        M146 222 C153 232 154 246 154 264 L162 264 C162 245 160 231 153 219 Z
        """
    private static let outsideScarfGap = "M0 0 L286 0 L286 320 L0 320 Z " + scarfGap
    private static let rays = "M235 126 L256 104 M247 152 L270 142"
    private static let outside = "M0 0 L286 0 L286 320 L0 320 Z " + shell

    /// Only these four SVG commands are used by the authored master. No raster tracing.
    private static func path(_ source: String) -> CGPath {
        let expression = try! NSRegularExpression(pattern: #"[MLCZ]|[-+]?[0-9]*\.?[0-9]+"#)
        let tokens = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .map { String(source[Range($0.range, in: source)!]) }
        let p = CGMutablePath()
        var i = 0
        func point() -> CGPoint {
            let value = CGPoint(x: Double(tokens[i])!, y: Double(tokens[i + 1])!)
            i += 2
            return value
        }
        while i < tokens.count {
            let command = tokens[i]; i += 1
            switch command {
            case "M": p.move(to: point())
            case "L": p.addLine(to: point())
            case "C":
                let first = point(), second = point(), end = point()
                p.addCurve(to: end, control1: first, control2: second)
            case "Z": p.closeSubpath()
            default: preconditionFailure("Unsupported mascot path command")
            }
        }
        return p
    }

    public static func draw(in c: CGContext, size: CGSize, ink: CGColor, color: Bool = false) {
        c.saveGState()
        let fit = min(size.width / 260, size.height / 280)
        c.translateBy(x: (size.width - 260 * fit) / 2, y: (size.height + 280 * fit) / 2)
        c.scaleBy(x: fit, y: -fit)
        c.translateBy(x: -18, y: -16)
        c.addPath(path(outsideScarfGap)); c.clip(using: .evenOdd)
        let head = path(shell)
        c.setFillColor(ink)
        // The paw sits behind the face. Clip its hidden part so a transparent template has
        // the same silhouette as a white face, rather than showing ink through the cheek.
        c.saveGState(); c.addPath(path(outside)); c.clip(using: .evenOdd)
        c.addPath(path(paw)); c.fillPath(); c.restoreGState()
        if color { c.setFillColor(CGColor(gray: 1, alpha: 1)); c.addPath(head); c.fillPath() }
        c.setStrokeColor(ink); c.setLineWidth(8.3); c.setLineJoin(.round)
        c.addPath(head); c.strokePath()
        c.setFillColor(ink)
        c.saveGState(); c.addPath(head); c.clip(); c.addPath(path(caps)); c.fillPath(); c.restoreGState()
        c.fillEllipse(in: CGRect(x: 84.5, y: 164, width: 24, height: 30))
        c.fillEllipse(in: CGRect(x: 155, y: 161.5, width: 24.5, height: 30))
        c.fillEllipse(in: CGRect(x: 126, y: 180, width: 16.5, height: 9))
        c.setFillColor(color ? CGColor(srgbRed: 46/255, green: 212/255, blue: 217/255, alpha: 1) : ink)
        c.addPath(path(scarf)); c.fillPath()
        c.setLineWidth(11); c.setLineCap(.round)
        c.addPath(path(rays)); c.strokePath()
        c.restoreGState()
    }

    public static func svg(ink: String = "#0F2D5B") -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="260" height="280" viewBox="18 16 260 280">
        <title>Sidefolk Mochi rabbit mascot</title>
        <defs>
        <clipPath id="rabbit-shell"><path d="\(shell)"/></clipPath>
        <clipPath id="outside-shell"><path d="\(outside)" clip-rule="evenodd"/></clipPath>
        <clipPath id="outside-scarf-gap"><path d="\(outsideScarfGap)" clip-rule="evenodd"/></clipPath>
        </defs>
        <g fill="\(ink)" clip-path="url(#outside-scarf-gap)">
        <path d="\(paw)" clip-path="url(#outside-shell)"/>
        <path d="\(shell)" fill="none" stroke="\(ink)" stroke-width="8.3" stroke-linejoin="round"/>
        <path d="\(caps)" clip-path="url(#rabbit-shell)"/>
        <ellipse cx="96.5" cy="179" rx="12" ry="15"/>
        <ellipse cx="167.25" cy="176.5" rx="12.25" ry="15"/>
        <ellipse cx="134.25" cy="184.5" rx="8.25" ry="4.5"/>
        <path d="\(scarf)"/>
        <path d="\(rays)" fill="none" stroke="\(ink)" stroke-width="11" stroke-linecap="round"/>
        </g>
        </svg>
        """
    }
}

/// Mochi's head reduced to what reads in the menu bar (D31): a 1.5 pt outline of the head and ears,
/// the ear tips filled like the brand's navy tips, two eyes and the nose. No rays, paw or scarf: at
/// 18 pt they turned the large mark into noise. Drawn in an 18 pt box with the eyes and nose on the
/// 2x pixel grid; it is one alpha shape, so macOS tints it as a template in any menu bar.
public enum MochiMenuGlyph {
    /// The glyph in its 18 × 18 pt box, y down. Built on each call: it is drawn a handful of times.
    public static var path: CGPath {
        func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, angle: Double = 0) -> CGPath {
            var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle * .pi / 180)
            return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &t)
        }
        let head = ellipse(9, 11.2, 6.6, 5.3)
        let ears = [(x: 5.8, angle: -16.0), (x: 12.2, angle: 16.0)]
        let earShapes = ears.map { ellipse($0.x, 5.2, 2.05, 4.1, angle: $0.angle) }
        let outline = earShapes.reduce(head) { $0.union($1) }
            .copy(strokingWithWidth: 1.5, lineCap: .round, lineJoin: .round, miterLimit: 10)
        // The upper part of each ear, cut square to the ear's own axis.
        let tips = zip(earShapes, ears).map { shape, ear -> CGPath in
            var t = CGAffineTransform(translationX: ear.x, y: 5.2).rotated(by: ear.angle * .pi / 180)
            return shape.intersection(CGPath(rect: CGRect(x: -4, y: -6, width: 8, height: 5.4), transform: &t))
        }
        let face = [ellipse(6, 11.75, 1, 1.25), ellipse(12, 11.75, 1, 1.25), ellipse(9, 13, 1, 0.5)]
        return (tips + face).reduce(outline) { $0.union($1) }
    }

    /// Fills the glyph in black, scaled to `size`, in a y-up context (bitmaps and PDF pages).
    public static func draw(in c: CGContext, size: CGSize) {
        c.saveGState()
        c.translateBy(x: 0, y: size.height)
        c.scaleBy(x: size.width / 18, y: -size.height / 18)
        c.setFillColor(CGColor(gray: 0, alpha: 1))
        c.addPath(path)
        c.fillPath()
        c.restoreGState()
    }

    public static func svg() -> String {
        func n(_ v: CGFloat) -> String { String(format: "%.3f", Double(v)) }
        var d: [String] = []
        path.applyWithBlock { element in
            let e = element.pointee
            let count = switch e.type { case .addQuadCurveToPoint: 2; case .addCurveToPoint: 3; case .closeSubpath: 0; default: 1 }
            let p = (0..<count).map { "\(n(e.points[$0].x)) \(n(e.points[$0].y))" }
            switch e.type {
            case .moveToPoint: d.append("M \(p[0])")
            case .addLineToPoint: d.append("L \(p[0])")
            case .addQuadCurveToPoint: d.append("Q \(p[0]) \(p[1])")
            case .addCurveToPoint: d.append("C \(p[0]) \(p[1]) \(p[2])")
            case .closeSubpath: d.append("Z")
            @unknown default: break
            }
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
        <title>Sidefolk menu bar template</title>
        <path fill="#000000" d="\(d.joined(separator: " "))"/>
        </svg>

        """
    }
}
