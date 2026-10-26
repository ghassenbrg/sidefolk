import AppKit

/// The Folk Family: small helpers that appear beside the companion when their domain acts.
public enum Folk: String, CaseIterable, Sendable {
    case pip, byte, seed, melody, scout, tempo, play, guard_ = "guard", nova, brew

    public var displayName: String {
        switch self {
        case .pip: "Pip"
        case .byte: "Byte"
        case .seed: "Seed"
        case .melody: "Melody"
        case .scout: "Scout"
        case .tempo: "Tempo"
        case .play: "Play"
        case .guard_: "Guard"
        case .nova: "Nova"
        case .brew: "Brew"
        }
    }

    /// What the folk looks after, in the app's language (Settings' gallery, VoiceOver).
    public var role: String {
        switch self {
        case .pip: String(localized: "Ideas & notes")
        case .byte: String(localized: "Code, agents & extensions")
        case .seed: String(localized: "Learning & growth")
        case .melody: String(localized: "Music & focus")
        case .scout: String(localized: "Search & watching")
        case .tempo: String(localized: "Reminders & time")
        case .play: String(localized: "Fun & celebration")
        case .guard_: String(localized: "Security & approvals")
        case .nova: String(localized: "Design & creativity")
        case .brew: String(localized: "Rituals & breaks")
        }
    }

    public var color: NSColor { tint.ns }

    var tint: RGB {
        switch self {
        case .pip: Palette.coral
        case .byte: RGB(0x3B82F6)
        case .seed: Palette.mint
        case .melody: RGB(0xA77BF3)
        case .scout: Palette.yellow
        case .tempo: Palette.lightBlue
        case .play: RGB(0xFF5A5F)
        case .guard_: RGB(0x3CCFB0)
        case .nova: RGB(0xC6A8F8)
        case .brew: RGB(0xF4E1C1)
        }
    }
}

/// Folks are drawn in a 100×100 canvas (y up) standing on y = 10.
enum FolkCanvas {
    static let size = CGSize(width: 100, height: 100)
    static let floor = pt(50, 10)
    static let center = pt(50, 44)
    static let eyeL = pt(41, 47)
    static let eyeR = pt(59, 47)
    static let mouth = pt(50, 39)
}

/// One folk as layers. `plain` drops accessories (for the app icon, where they would be mush).
@MainActor
final class FolkRig {
    /// Scales and fades from the floor point; `body` breathes inside it.
    let root = Layers.canvas(FolkCanvas.size, anchor: FolkCanvas.floor)
    let body = Layers.canvas(FolkCanvas.size, anchor: FolkCanvas.floor)
    private let folk: Folk
    private let plain: Bool

    init(_ folk: Folk, plain: Bool = false) {
        self.folk = folk
        self.plain = plain
        root.addSublayer(body)
        build()
    }

    private var ink: CGColor { Palette.ink.cg() }

    private func build() {
        let ground = CAGradientLayer()
        ground.type = .radial
        ground.frame = CGRect(x: 24, y: 6, width: 52, height: 8)
        ground.colors = [Palette.ink.cg(0.22), Palette.ink.cg(0)]
        ground.startPoint = CGPoint(x: 0.5, y: 0.5)
        ground.endPoint = CGPoint(x: 1, y: 1)
        root.insertSublayer(ground, at: 0)

        let shade = folk.tint.darker(0.12)
        for x in [41.0, 59.0] {
            let foot = SoftShape(Paths.ellipse(pt(x, 13.5), 7.5, 5), shading: .tinted(shade))
            body.addSublayer(foot.layer)
        }
        if !plain { behindBody() }
        let blob = SoftShape(outline, shading: .tinted(folk.tint))
        blob.shadow(radius: 3, opacity: 0.18)
        body.addSublayer(blob.layer)
        arms()
        face()
        if !plain { inFront() }
    }

    // MARK: Body

    private struct Bump {
        var angle: CGFloat, width: CGFloat, height: CGFloat
    }

    private static func bumps(_ folk: Folk) -> [Bump] {
        let up = CGFloat.pi / 2
        switch folk {
        case .pip: return [Bump(angle: up - 0.1, width: 0.2, height: 5.5)]
        case .byte: return [Bump(angle: 0.75, width: 0.2, height: 2.5), Bump(angle: .pi - 0.75, width: 0.2, height: 2.5)]
        case .seed: return [Bump(angle: up, width: 0.18, height: -2.5)]
        case .melody: return [Bump(angle: up - 0.62, width: 0.12, height: 11), Bump(angle: up + 0.62, width: 0.12, height: 11)]
        case .scout: return [Bump(angle: up - 0.4, width: 0.11, height: 3.5), Bump(angle: up + 0.02, width: 0.11, height: 4.5),
                             Bump(angle: up + 0.42, width: 0.11, height: 3)]
        case .tempo: return stride(from: -0.35, through: .pi + 0.35, by: (.pi + 0.7) / 6).map { Bump(angle: $0, width: 0.2, height: 5) }
        case .play: return [Bump(angle: up, width: 0.1, height: 15), Bump(angle: up + 0.3, width: 0.09, height: 9),
                            Bump(angle: up - 0.32, width: 0.08, height: 7)]
        case .guard_, .nova, .brew: return []
        }
    }

    private var outline: CGPath { Self.outline(folk, center: FolkCanvas.center, scale: 1) }

    /// A chubby, slightly lumpy round body with its personality bumps (tuft, ears, cloud, flame),
    /// `scale` times the on-duty size (the companion-sized folk is twice as big).
    static func outline(_ folk: Folk, center: CGPoint, scale: CGFloat) -> CGPath {
        let n = 40
        let points = (0..<n).map { i -> CGPoint in
            let a = CGFloat(i) / CGFloat(n) * .pi * 2
            var push: CGFloat = 0
            for bump in bumps(folk) {
                var d = abs(a - bump.angle)
                d = min(d, .pi * 2 - d)
                push += bump.height * exp(-(d * d) / (2 * bump.width * bump.width))
            }
            let flatten: CGFloat = sin(a) < 0 ? 0.9 : 1
            return center + pt(cos(a) * (31 + push), sin(a) * (29 * flatten + push)) * scale
        }
        return Paths.blob(points)
    }

    private func arms() {
        let shade = folk.tint.mix(.white, 0.06)
        var poses: [(CGPoint, CGFloat)] = [(pt(19, 37), 0.55), (pt(81, 37), -0.55)]
        if !plain {
            switch folk {
            case .pip: poses[0] = (pt(17, 50), -0.6)
            case .byte, .tempo, .scout, .guard_, .nova: poses[1] = (pt(76, 30), -1.2)
            case .brew: poses[0] = (pt(26, 30), 1.1)
            case .play: poses = [(pt(31, 26), 1.25), (pt(69, 26), -1.25)]
            case .seed, .melody: break
            }
        }
        for (center, angle) in poses {
            let arm = SoftShape(Paths.transformed(Paths.ellipse(.zero, 6.5, 8.5),
                                                  CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)),
                                shading: .tinted(shade))
            arm.shadow(radius: 1.5, opacity: 0.15, offset: CGSize(width: 0, height: -0.5))
            body.addSublayer(arm.layer)
        }
    }

    // MARK: Face

    private enum Eyes { case dots, happy, content, squeeze, wink, stern }
    private enum Mouth { case smile, grin, cat, pout }

    private var eyes: Eyes {
        switch folk {
        case .pip, .seed, .tempo, .brew: .happy
        case .byte, .scout: .dots
        case .melody: .content
        case .play: .squeeze
        case .nova: .wink
        case .guard_: .stern
        }
    }

    private var mouth: Mouth {
        switch folk {
        case .pip, .play: .grin
        case .melody: .cat
        case .guard_: .pout
        default: .smile
        }
    }

    private func face() {
        for x in [32.0, 68.0] {
            body.addSublayer(Layers.shape(Paths.ellipse(pt(x, 40), 5.2, 3.2), fill: Palette.blush.cg(0.55)))
        }
        let happy = Stroke.arc(width: 9, rise: 3.8, thickness: 2.7)
        switch eyes {
        case .dots, .stern:
            [FolkCanvas.eyeL, FolkCanvas.eyeR].forEach(dotEye)
        case .happy:
            [FolkCanvas.eyeL, FolkCanvas.eyeR].forEach { stroke(happy, at: $0) }
        case .content:
            [FolkCanvas.eyeL, FolkCanvas.eyeR].forEach { stroke(Stroke.arc(width: 9, rise: -3.2, thickness: 2.5), at: $0) }
        case .squeeze:
            stroke(Stroke.polyline(pt(-4, 4), pt(4, 0), pt(-4, -4), width: 2.6), at: FolkCanvas.eyeL)
            stroke(Stroke.polyline(pt(4, 4), pt(-4, 0), pt(4, -4), width: 2.6), at: FolkCanvas.eyeR)
        case .wink:
            dotEye(FolkCanvas.eyeL)
            stroke(happy, at: FolkCanvas.eyeR)
        }
        if eyes == .stern {
            stroke(Stroke.line(pt(-5, 9), pt(4, 6), width: 2.4), at: FolkCanvas.eyeL)
            stroke(Stroke.line(pt(5, 9), pt(-4, 6), width: 2.4), at: FolkCanvas.eyeR)
        }

        let m = FolkCanvas.mouth
        switch mouth {
        case .smile:
            stroke(Stroke.arc(width: 7, rise: -2.6, thickness: 2.2), at: m)
        case .pout:
            stroke(Stroke.arc(width: 6, rise: 1.6, thickness: 2.2), at: m + pt(0, -1))
        case .cat:
            stroke(Stroke.arc(width: 4.5, rise: -2, thickness: 2), at: m + pt(-2.2, 0))
            stroke(Stroke.arc(width: 4.5, rise: -2, thickness: 2), at: m + pt(2.2, 0))
        case .grin:
            let open = CGMutablePath()
            open.move(to: m + pt(-5.5, 2))
            open.addLine(to: m + pt(5.5, 2))
            open.addCurve(to: m + pt(-5.5, 2), control1: m + pt(5.5, -6.5), control2: m + pt(-5.5, -6.5))
            open.closeSubpath()
            body.addSublayer(Layers.shape(open, fill: RGB(0x5B1A2A).cg()))
            body.addSublayer(Layers.shape(Paths.ellipse(m + pt(0, -2.6), 3, 1.6), fill: RGB(0xFF8FA3).cg()))
        }
    }

    private func dotEye(_ c: CGPoint) {
        body.addSublayer(Layers.shape(Paths.ellipse(c, 3.5, 4.5), fill: ink))
        body.addSublayer(Layers.shape(Paths.circle(c + pt(1.2, 1.7), 1.25), fill: RGB.white.cg()))
    }

    private func stroke(_ mark: Stroke, at center: CGPoint, color: CGColor? = nil) {
        body.addSublayer(Layers.shape(mark.path(at: center), stroke: color ?? ink, lineWidth: mark.width))
    }

    // MARK: Accessories

    private func behindBody() {
        switch folk {
        case .melody:
            body.addSublayer(FolkKit.headband())
        default:
            break
        }
    }

    private func inFront() {
        switch folk {
        case .pip:
            body.addSublayer(FolkKit.marks(at: pt(22, 70), angles: [2.0, 2.5, 3.0], color: RGB(0xFF8A3D)))
            body.addSublayer(FolkKit.sparkle(pt(82, 70), 5, Palette.yellow))
        case .byte:
            body.addSublayer(FolkKit.glasses())
            body.addSublayer(FolkKit.laptop(at: pt(66, 22)))
            body.addSublayer(FolkKit.marks(at: pt(76, 68), angles: [0.5, 1.0, 1.5], color: RGB(0x3B82F6)))
        case .seed:
            body.addSublayer(FolkKit.sprout())
        case .melody:
            body.addSublayer(FolkKit.headphones())
            body.addSublayer(FolkKit.note(at: pt(84, 76)))
        case .scout:
            body.addSublayer(FolkKit.magnifier(hand: folk.tint))
        case .tempo:
            body.addSublayer(FolkKit.calendar(at: pt(70, 24)))
        case .play:
            body.addSublayer(FolkKit.gamepad())
            body.addSublayer(FolkKit.marks(at: pt(24, 64), angles: [1.8, 2.4, 3.0], color: Palette.coral))
            body.addSublayer(FolkKit.marks(at: pt(76, 64), angles: [0.15, 0.75, 1.35], color: Palette.coral))
        case .guard_:
            body.addSublayer(FolkKit.cap())
            body.addSublayer(FolkKit.shield(at: pt(72, 24)))
        case .nova:
            body.addSublayer(FolkKit.beret())
            body.addSublayer(FolkKit.paintbrush(hand: folk.tint))
            body.addSublayer(FolkKit.sparkle(pt(18, 74), 4.5, RGB(0xA77BF3)))
            body.addSublayer(FolkKit.sparkle(pt(27, 84), 3, RGB(0xA77BF3)))
        case .brew:
            body.addSublayer(FolkKit.bowler())
            body.addSublayer(FolkKit.cup(at: pt(28, 24), hand: folk.tint))
        }
    }
}

/// The Folk Family's accessories and the things they hold, drawn in the 100×100 folk canvas. The
/// on-duty folks wear them as drawn; full-size folks show them twice as big through a `Magnifier`.
@MainActor
enum FolkKit {
    static var ink: CGColor { Palette.ink.cg() }

    /// Melody's headband, arching over the head behind the body.
    static func headband() -> CALayer {
        let band = CGMutablePath()
        band.addArc(center: FolkCanvas.center + pt(0, 2), radius: 34, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
        let root = Layers.canvas()
        root.addSublayer(Layers.shape(band, stroke: RGB(0x4A2B8A).cg(), lineWidth: 5))
        return root
    }

    /// A folk-canvas drawing shown on a full-size folk (twice as big), moved by `shift` folk units.
    static func companionSized(_ drawing: CALayer, shift: CGPoint = .zero, scale: CGFloat = 2) -> CALayer {
        let holder = Magnifier(scale)
        drawing.setAffineTransform(CGAffineTransform(translationX: shift.x, y: shift.y))
        holder.addSublayer(drawing)
        return holder
    }

    static func marks(at center: CGPoint, angles: [CGFloat], color: RGB) -> CALayer {
        let root = Layers.canvas()
        for a in angles {
            let dir = pt(cos(a), sin(a))
            root.addSublayer(Layers.shape(Paths.polyline([center + dir * 5, center + dir * 11]), stroke: color.cg(), lineWidth: 3))
        }
    
        return root
    }

    static func sparkle(_ c: CGPoint, _ r: CGFloat, _ color: RGB) -> CALayer {
        let root = Layers.canvas()
        root.addSublayer(Layers.shape(Paths.sparkle(c, r), fill: color.cg()))
    
        return root
    }

    static func glasses() -> CALayer {
        let root = Layers.canvas()
        for c in [FolkCanvas.eyeL, FolkCanvas.eyeR] {
            root.addSublayer(Layers.shape(Paths.circle(c, 8), fill: RGB.white.cg(0.18), stroke: ink, lineWidth: 2.6))
        }
        let bridge = CGMutablePath()
        bridge.move(to: pt(46, 49))
        bridge.addQuadCurve(to: pt(54, 49), control: pt(50, 52))
        root.addSublayer(Layers.shape(bridge, stroke: ink, lineWidth: 2.2))
        root.addSublayer(Layers.shape(Paths.polyline([pt(33, 49), pt(22, 51)]), stroke: ink, lineWidth: 2.2))
        root.addSublayer(Layers.shape(Paths.polyline([pt(67, 49), pt(78, 51)]), stroke: ink, lineWidth: 2.2))
    
        return root
    }

    static func laptop(at c: CGPoint) -> CALayer {
        let root = Layers.canvas()
        let lid = Paths.transformed(Paths.roundedRect(CGRect(x: -15, y: -10, width: 30, height: 20), 3),
                                    CGAffineTransform(translationX: c.x, y: c.y).rotated(by: -0.12))
        root.addSublayer(Layers.gradient(lid, [RGB(0x5A6272), RGB(0x2B313D)]))
        root.addSublayer(Layers.shape(Paths.circle(c + pt(0, 0.5), 2), fill: RGB.white.cg(0.6)))
        root.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: c.x - 18, y: c.y - 14, width: 34, height: 4), 2), fill: RGB(0x3A404C).cg()))
    
        return root
    }

    static func sprout() -> CALayer {
        let root = Layers.canvas()
        let stem = CGMutablePath()
        stem.move(to: pt(50, 70))
        stem.addQuadCurve(to: pt(51, 82), control: pt(48, 77))
        root.addSublayer(Layers.shape(stem, stroke: RGB(0x3E9B57).cg(), lineWidth: 3))
        for (c, rx, ry, angle) in [(pt(42, 84), 9.0, 4.6, 0.45), (pt(60, 87), 11.0, 5.4, -0.35)] {
            let leaf = Paths.transformed(Paths.ellipse(.zero, rx, ry), CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle))
            root.addSublayer(Layers.gradient(leaf, [RGB(0x6FD07F), RGB(0x3FAE5A)]))
            let rib = Paths.transformed(Paths.polyline([pt(-rx * 0.6, 0), pt(rx * 0.6, 0)]),
                                        CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle))
            root.addSublayer(Layers.shape(rib, stroke: RGB.white.cg(0.35), lineWidth: 1.2))
        }
    
        return root
    }

    static func headphones() -> CALayer {
        let root = Layers.canvas()
        for side in [-1.0, 1.0] {
            let c = FolkCanvas.center + pt(side * 32, 4)
            let cup = Layers.gradient(Paths.roundedRect(CGRect(x: c.x - 6, y: c.y - 10, width: 12, height: 20), 6),
                                      [RGB(0x5B3AA6), RGB(0x2E1B5E)])
            root.addSublayer(cup)
            root.addSublayer(Layers.shape(Paths.ellipse(c + pt(-side * 1.5, 0), 3, 7), fill: RGB(0x9D7BEA).cg()))
        }
    
        return root
    }

    static func note(at c: CGPoint) -> CALayer {
        let root = Layers.canvas()
        let color = RGB(0x8E5BE8).cg()
        root.addSublayer(Layers.shape(Paths.ellipse(c, 3.4, 2.6), fill: color))
        root.addSublayer(Layers.shape(Paths.ellipse(c + pt(8, 2), 3.4, 2.6), fill: color))
        root.addSublayer(Layers.shape(Paths.polyline([c + pt(3, 1), c + pt(3, 12), c + pt(11, 14), c + pt(11, 3)]),
                                      stroke: color, lineWidth: 1.8))
    
        return root
    }

    static func magnifier(hand: RGB?) -> CALayer {
        let root = Layers.canvas()
        let lens = pt(80, 50)
        root.addSublayer(Layers.shape(Paths.polyline([lens + pt(-6, -8), pt(70, 30)]), stroke: RGB(0x2B2F3D).cg(), lineWidth: 4.5))
        root.addSublayer(Layers.shape(Paths.circle(lens, 10), fill: Palette.lightBlue.cg(0.55), stroke: ink, lineWidth: 3))
        root.addSublayer(Layers.shape(Paths.ellipse(lens + pt(-3, 3.5), 2.4, 3.6), fill: RGB.white.cg(0.8)))
        if let hand { root.addSublayer(SoftShape(Paths.ellipse(pt(72, 31), 6, 6.5), shading: .tinted(hand)).layer) }
    
        return root
    }

    static func calendar(at c: CGPoint) -> CALayer {
        let root = Layers.canvas()
        let page = Paths.roundedRect(CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24), 3)
        let card = Layers.shape(page, fill: RGB(0xFFFDF8).cg(), stroke: RGB(0xD5DAE5).cg(), lineWidth: 0.8)
        Layers.dropShadow(card, path: card.path, radius: 1.5, opacity: 0.2)
        root.addSublayer(card)
        let header = CGMutablePath()
        header.addPath(Paths.roundedRect(CGRect(x: c.x - 12, y: c.y + 5, width: 24, height: 7), 3))
        header.addRect(CGRect(x: c.x - 12, y: c.y + 5, width: 24, height: 3))
        root.addSublayer(Layers.shape(header, fill: Palette.coral.cg()))
        for dx in [-6.0, 6.0] {
            root.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: c.x + dx - 1, y: c.y + 9.5, width: 2, height: 5), 1), fill: ink))
        }
        for row in 0..<2 {
            for col in 0..<3 {
                let p = c + pt(CGFloat(col - 1) * 6.5, CGFloat(-row) * 6 - 1)
                root.addSublayer(Layers.shape(Paths.circle(p, 1.5), fill: (row == 1 && col == 1 ? Palette.coral : Palette.lightBlue).cg()))
            }
        }
    
        return root
    }

    static func gamepad() -> CALayer {
        let root = Layers.canvas()
        let pad = Paths.roundedRect(CGRect(x: 33, y: 17, width: 34, height: 15), 7.5)
            .union(Paths.circle(pt(37, 17), 6))
            .union(Paths.circle(pt(63, 17), 6))
        root.addSublayer(Layers.gradient(pad, [RGB(0x3A4052), RGB(0x1C2030)]))
        root.addSublayer(Layers.shape(Paths.polyline([pt(36, 24), pt(44, 24)]), stroke: RGB.white.cg(0.75), lineWidth: 2.4))
        root.addSublayer(Layers.shape(Paths.polyline([pt(40, 20), pt(40, 28)]), stroke: RGB.white.cg(0.75), lineWidth: 2.4))
        for (p, color) in [(pt(60, 27), Palette.aqua), (pt(64.5, 23.5), Palette.coral), (pt(55.5, 23.5), Palette.yellow), (pt(60, 20), Palette.mint)] {
            root.addSublayer(Layers.shape(Paths.circle(p, 2), fill: color.cg()))
        }
    
        return root
    }

    static func cap() -> CALayer {
        let root = Layers.canvas()
        let dome = CGMutablePath()
        dome.move(to: pt(23, 66))
        dome.addCurve(to: pt(77, 66), control1: pt(24, 92), control2: pt(76, 92))
        dome.addQuadCurve(to: pt(23, 66), control: pt(50, 61))
        dome.closeSubpath()
        root.addSublayer(Layers.gradient(dome, [RGB(0x2F8A70), RGB(0x1C5E4C)]))
        let brim = CGMutablePath()
        brim.move(to: pt(22, 66))
        brim.addQuadCurve(to: pt(78, 66), control: pt(50, 60))
        brim.addQuadCurve(to: pt(22, 66), control: pt(50, 55))
        brim.closeSubpath()
        root.addSublayer(Layers.shape(brim, fill: RGB(0x174D3F).cg()))
        root.addSublayer(Layers.shape(Paths.circle(pt(50, 76), 4.5), fill: RGB.white.cg(0.92)))
        for dx in [-1.5, 1.5] {
            root.addSublayer(Layers.shape(Paths.circle(pt(50 + dx, 76.5), 0.9), fill: RGB(0x1C5E4C).cg()))
        }
    
        return root
    }

    static func shield(at c: CGPoint) -> CALayer {
        let root = Layers.canvas()
        func shape(_ s: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.move(to: c + pt(0, 13) * s)
            p.addQuadCurve(to: c + pt(11, 9) * s, control: c + pt(6, 13) * s)
            p.addCurve(to: c + pt(0, -14) * s, control1: c + pt(11, -2) * s, control2: c + pt(6, -10) * s)
            p.addCurve(to: c + pt(-11, 9) * s, control1: c + pt(-6, -10) * s, control2: c + pt(-11, -2) * s)
            p.addQuadCurve(to: c + pt(0, 13) * s, control: c + pt(-6, 13) * s)
            p.closeSubpath()
            return p
        }
        let outer = Layers.gradient(shape(1), [RGB(0x3A4766), RGB(0x1C2438)])
        Layers.dropShadow(outer, path: nil, radius: 2, opacity: 0.25)
        root.addSublayer(outer)
        root.addSublayer(Layers.gradient(Paths.translated(shape(0.55), 0, 1), [RGB(0xE9EDF5), RGB(0xA9B3C7)]))
    
        return root
    }

    static func beret() -> CALayer {
        let root = Layers.canvas()
        let tilt = CGAffineTransform(translationX: 45, y: 72).rotated(by: 0.18)
        root.addSublayer(Layers.gradient(Paths.transformed(Paths.ellipse(.zero, 25, 9), tilt), [RGB(0xEADDFF), RGB(0xC9B2F5)]))
        root.addSublayer(Layers.shape(Paths.transformed(Paths.polyline([pt(-19, -2), pt(19, -2)]), tilt), stroke: RGB(0xB49BE6).cg(), lineWidth: 1.6))
        root.addSublayer(Layers.shape(Paths.circle(pt(47, 83), 2.4), fill: RGB(0xC9B2F5).cg()))
    
        return root
    }

    static func paintbrush(hand: RGB?) -> CALayer {
        let root = Layers.canvas()
        root.addSublayer(Layers.shape(Paths.polyline([pt(76, 26), pt(84, 60)]), stroke: RGB(0xA0673A).cg(), lineWidth: 3.6))
        root.addSublayer(Layers.shape(Paths.polyline([pt(84, 60), pt(85.5, 66)]), stroke: RGB(0xB8C0CF).cg(), lineWidth: 4.4))
        let tip = CGMutablePath()
        tip.move(to: pt(83, 66))
        tip.addQuadCurve(to: pt(88, 78), control: pt(81, 73))
        tip.addQuadCurve(to: pt(88, 66), control: pt(91, 72))
        tip.closeSubpath()
        root.addSublayer(Layers.shape(tip, fill: RGB(0x3B82F6).cg()))
        if let hand { root.addSublayer(SoftShape(Paths.ellipse(pt(77, 30), 6, 6.5), shading: .tinted(hand)).layer) }
    
        return root
    }

    static func bowler() -> CALayer {
        let root = Layers.canvas()
        root.addSublayer(Layers.shape(Paths.ellipse(pt(54, 73), 17, 4), fill: RGB(0x7A4A24).cg()))
        let crown = CGMutablePath()
        crown.move(to: pt(42, 73))
        crown.addCurve(to: pt(66, 73), control1: pt(42, 90), control2: pt(66, 90))
        crown.closeSubpath()
        root.addSublayer(Layers.gradient(crown, [RGB(0xA86B37), RGB(0x7A4A24)]))
        root.addSublayer(Layers.shape(Paths.polyline([pt(43, 76), pt(65, 76)]), stroke: RGB(0x5B3416).cg(), lineWidth: 2.4))
        root.addSublayer(Layers.shape(Paths.polyline([pt(56, 85.5), pt(60, 91)]), stroke: RGB(0x5B3416).cg(), lineWidth: 2.2))
        root.addSublayer(Layers.shape(Paths.circle(pt(61, 92), 2.2), fill: RGB(0x5B3416).cg()))
    
        return root
    }

    static func cup(at c: CGPoint, hand: RGB?) -> CALayer {
        let root = Layers.canvas()
        let mug = CGMutablePath()
        mug.move(to: c + pt(-8, 9))
        mug.addLine(to: c + pt(8, 9))
        mug.addLine(to: c + pt(6.5, -9))
        mug.addQuadCurve(to: c + pt(-6.5, -9), control: c + pt(0, -11))
        mug.closeSubpath()
        let cup = Layers.gradient(mug, [RGB.white, RGB(0xE3E6EE)])
        Layers.dropShadow(cup, path: nil, radius: 1.5, opacity: 0.2)
        root.addSublayer(cup)
        root.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: c.x - 7.6, y: c.y - 3, width: 15.2, height: 7), 1),
                                      fill: RGB(0x8B5A2B).cg()))
        root.addSublayer(Layers.shape(Paths.ellipse(c + pt(0, 9), 8, 2), fill: RGB(0x6B3F1D).cg()))
        if let hand { root.addSublayer(SoftShape(Paths.ellipse(c + pt(9, -1), 6, 6.5), shading: .tinted(hand)).layer) }
    
        return root
    }
}

/// A folk on screen, with a springy entrance and exit. Layer-hosting like CharacterView.
@MainActor
public final class FolkView: NSView {
    public let folk: Folk
    private let rig: FolkRig
    /// Scales the canvas to the view; the rig's own root is left free for popping.
    private let stage = Layers.canvas(FolkCanvas.size, anchor: pt(50, 50))
    /// Folks settle like the companion does (DECISIONS D20): an endless loop keeps the window server drawing.
    private var settleTimer: Timer?

    public init(folk: Folk, frame: NSRect) {
        self.folk = folk
        rig = FolkRig(folk)
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(stage)
        stage.addSublayer(rig.root)
        reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        place()
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("\(folk.displayName), \(folk.role)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FolkView is created in code") }

    public var reducedMotion: Bool = false {
        didSet { breathe() }
    }

    /// Springs up from the floor (or fades in with reduced motion).
    public func popIn() {
        let body = rig.root
        Motion.still { body.opacity = 1; body.transform = CATransform3DIdentity }
        body.add(Motion.keyframes("opacity", [0, 1], duration: 0.18), forKey: "fade")
        if !reducedMotion {
            let pop = CASpringAnimation(perceptualDuration: 0.4, bounce: 0.4)
            pop.keyPath = "transform.scale"
            pop.fromValue = 0.2
            pop.toValue = 1
            pop.duration = pop.settlingDuration
            body.add(pop, forKey: "pop")
        }
        breathe()
    }

    /// Shrinks back into the floor (or fades out), then calls `completion`.
    public func popOut(completion: (() -> Void)?) {
        let body = rig.root
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion?() }
        }
        let fade = Motion.keyframes("opacity", [1, 0], duration: reducedMotion ? 0.18 : 0.22)
        body.add(fade, forKey: "fade")
        if !reducedMotion {
            let shrink = Motion.keyframes("transform.scale", [1, 1.08, 0.2], duration: 0.22, times: [0, 0.3, 1])
            body.add(shrink, forKey: "pop")
        }
        Motion.still { body.opacity = 0 }
        CATransaction.commit()
        settleTimer?.invalidate()
        rig.body.removeAnimation(forKey: "breath")
    }

    /// Breathes again for a while (the pointer came close), then settles.
    public func wake() {
        guard settleTimer == nil, rig.body.animation(forKey: "breath") == nil else { return }
        breathe()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        place()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        place()
    }

    private func breathe() {
        settleTimer?.invalidate()
        settleTimer = nil
        rig.body.removeAnimation(forKey: "breath")
        guard !reducedMotion, rig.root.opacity > 0 else { return }
        rig.body.add(Motion.loop("transform", from: Motion.transform(.identity),
                                 to: Motion.transform(CGAffineTransform(scaleX: 1.02, y: 0.97)), duration: 1.6), forKey: "breath")
        let timer = Timer(timeInterval: Director.settleAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    /// Glides from wherever the breath was back to rest.
    private func settle() {
        settleTimer = nil
        let body = rig.body
        let shown = body.presentation()?.transform
        body.removeAnimation(forKey: "breath")
        guard let shown else { return }
        let glide = CABasicAnimation(keyPath: "transform")
        glide.fromValue = NSValue(caTransform3D: shown)
        glide.toValue = NSValue(caTransform3D: body.transform)
        glide.duration = 0.25
        glide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        body.add(glide, forKey: "settle")
    }

    private func place() {
        let scale = min(bounds.width / FolkCanvas.size.width, bounds.height / FolkCanvas.size.height)
        Motion.still {
            stage.position = CGPoint(x: bounds.midX, y: bounds.midY)
            stage.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            Layers.setContentsScale(max(backing * scale, 1), in: stage)
        }
    }
}
