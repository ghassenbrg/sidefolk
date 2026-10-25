import QuartzCore

/// A repeating animation and the layer it runs on.
struct Loop {
    let layer: CALayer
    let key: String
    let animation: CAAnimation
}

/// An object the character holds, built in canvas units in front of the belly. The stubby arms
/// reach its edges, so props are wide and low and never cover the eyes.
@MainActor
struct PropRig {
    let layer: CALayer
    /// Drawn over the arms (the hands are behind it) instead of under them.
    var overArms = false
    /// Canvas area to add to the hit shape.
    var frame: CGRect
    var loops: [Loop] = []
}

@MainActor
enum Props {
    /// Arms and eyes that go with holding `prop`.
    nonisolated static func adjust(_ pose: inout Pose, for prop: CharacterProp) {
        pose.armL = -0.95
        pose.armR = -0.95
        pose.look = CGVector(dx: 0, dy: -0.35)
        pose.gazeFollow = 0.25
        switch prop {
        case .laptop, .none:
            pose.armL = -0.7
            pose.armR = -0.7
            pose.look = CGVector(dx: 0, dy: -0.45)
        case .binoculars:
            pose.look = CGVector(dx: 0.6, dy: 0.25)
            pose.setEyes(Face.oval)
        case .card:
            pose.look = CGVector(dx: 0, dy: 0.2)
            pose.setEyes(Face.oval)
        case .clock, .bell:
            pose.setEyes(Face.oval)
        default:
            break
        }
    }

    static func make(_ prop: CharacterProp) -> PropRig? {
        switch prop {
        case .none: nil
        case .laptop: laptop()
        case .notepad: notepad()
        case .clock: clock()
        case .binoculars: binoculars()
        case .folder: folder()
        case .globe: globe()
        case .card: card()
        case .book: book()
        case .bell: bell()
        }
    }

    // MARK: Builders

    private static func laptop() -> PropRig {
        let root = Layers.canvas()
        let deck = Layers.gradient(Paths.roundedRect(CGRect(x: 56, y: 19, width: 88, height: 8), 3),
                                   [RGB(0xA9B1C2), RGB(0x6D778C)])
        root.addSublayer(deck)
        let lidPath = Paths.roundedRect(CGRect(x: 62, y: 25, width: 76, height: 42), 6)
        let lid = Layers.gradient(lidPath, [RGB(0xF4F6FA), RGB(0xDDE2EB), RGB(0xBCC4D3)])
        Layers.dropShadow(lid, path: nil, radius: 2.5, opacity: 0.2)
        root.addSublayer(lid)
        root.addSublayer(Layers.shape(lidPath, stroke: RGB(0x98A1B4).cg(0.8), lineWidth: 0.8, pad: 1))
        root.addSublayer(Layers.shape(Paths.polyline([pt(66, 65.6), pt(134, 65.6)]), stroke: RGB.white.cg(0.8), lineWidth: 1.2))
        // A tiny visor as the lid's logo.
        root.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: 91, y: 40, width: 18, height: 11), 5),
                                      fill: Palette.navy.cg()))
        for x in [96.0, 104.0] {
            let eye = Layers.shape(Stroke.arc(width: 4, rise: 1.6, thickness: 1.6).path(at: pt(x, 45.5)),
                                   stroke: Palette.eyeLight.cg(), lineWidth: 1.6)
            Layers.glow(eye, Palette.aqua, radius: 1.5)
            root.addSublayer(eye)
        }
        return PropRig(layer: root, overArms: true, frame: CGRect(x: 56, y: 19, width: 88, height: 48))
    }

    private static func notepad() -> PropRig {
        let root = Layers.canvas()
        let page = Layers.canvas(anchor: pt(100, 46))
        page.setAffineTransform(CGAffineTransform(rotationAngle: 0.05))
        let padPath = Paths.roundedRect(CGRect(x: 75, y: 25, width: 50, height: 44), 4)
        let pad = Layers.shape(padPath, fill: RGB(0xFFF8E1).cg(), stroke: RGB(0xE8D6A4).cg(), lineWidth: 0.8)
        Layers.dropShadow(pad, path: pad.path, radius: 2.5, opacity: 0.2)
        page.addSublayer(pad)
        page.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: 75, y: 61, width: 50, height: 8), 4), fill: Palette.coral.cg()))
        for i in 0..<5 {
            page.addSublayer(Layers.shape(Paths.circle(pt(82 + CGFloat(i) * 9, 65), 1.6), fill: RGB.white.cg(0.95)))
        }
        for (i, length) in [36.0, 36, 28, 16].enumerated() {
            let y = 53 - CGFloat(i) * 7
            page.addSublayer(Layers.shape(Paths.polyline([pt(81, y), pt(81 + length, y)]),
                                          stroke: Palette.lightBlue.cg(), lineWidth: 2))
        }
        root.addSublayer(page)

        // The pencil pivots at the right hand and scribbles at the end of the last line.
        let pencil = Layers.canvas(anchor: pt(136, 58))
        let tip = pt(100, 33), end = pt(134, 57)
        let dir = (end - tip) * (1 / hypot(end.x - tip.x, end.y - tip.y))
        let woodEnd = tip + dir * 7
        pencil.addSublayer(Layers.shape(Paths.polyline([woodEnd, end]), stroke: Palette.coral.cg(), lineWidth: 6))
        pencil.addSublayer(Layers.shape(Paths.polyline([end - dir * 3, end]), stroke: RGB(0xFFB3C1).cg(), lineWidth: 6))
        let n = pt(-dir.y, dir.x) * 3
        pencil.addSublayer(Layers.shape(Paths.polyline([woodEnd + n, tip, woodEnd - n], closed: true),
                                        fill: RGB(0xF7D9A8).cg(), stroke: RGB(0xF7D9A8).cg(), lineWidth: 0.8))
        pencil.addSublayer(Layers.shape(Paths.circle(tip + dir * 1.2, 1.3), fill: Palette.navy.cg()))
        root.addSublayer(pencil)

        let scribble = Motion.loop("transform.rotation.z", from: -0.05, to: 0.07, duration: 0.22)
        return PropRig(layer: root, frame: CGRect(x: 75, y: 25, width: 62, height: 44),
                       loops: [Loop(layer: pencil, key: "scribble", animation: scribble)])
    }

    private static func clock() -> PropRig {
        let root = Layers.canvas()
        let c = pt(100, 46)
        for side in [-1.0, 1.0] {
            let bell = Paths.ellipse(c + pt(side * 13, 18), 8, 6.5)
            root.addSublayer(Layers.shape(bell, fill: Palette.coral.darker(0.1).cg()))
            root.addSublayer(Layers.shape(Paths.polyline([c + pt(side * 12, -14), c + pt(side * 16, -22)]),
                                          stroke: Palette.navy.cg(), lineWidth: 3.2))
        }
        let rim = SoftShape(Paths.circle(c, 21), shading: .tinted(Palette.coral))
        rim.shadow(radius: 2.5, opacity: 0.2)
        root.addSublayer(rim.layer)
        root.addSublayer(Layers.shape(Paths.circle(c, 16.5), fill: RGB(0xFFFDF8).cg()))
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6
            let long = i % 3 == 0
            let p0 = c + pt(sin(a), cos(a)) * (long ? 11.5 : 13), p1 = c + pt(sin(a), cos(a)) * 14.5
            root.addSublayer(Layers.shape(Paths.polyline([p0, p1]), stroke: Palette.navy.cg(long ? 1 : 0.45),
                                          lineWidth: long ? 2 : 1.2))
        }
        root.addSublayer(Layers.shape(Paths.polyline([c, c + pt(-6, 5)]), stroke: Palette.navy.cg(), lineWidth: 2.6))
        let minute = Layers.canvas(anchor: c)
        minute.addSublayer(Layers.shape(Paths.polyline([c, c + pt(4, 11)]), stroke: Palette.navy.cg(), lineWidth: 2))
        root.addSublayer(minute)
        root.addSublayer(Layers.shape(Paths.circle(c, 2.2), fill: Palette.coral.cg()))

        let tick = Motion.loop("transform.rotation.z", from: 0, to: -2 * Double.pi, duration: 6, reverses: false,
                               timing: .linear)
        return PropRig(layer: root, frame: CGRect(x: 78, y: 24, width: 44, height: 50),
                       loops: [Loop(layer: minute, key: "tick", animation: tick)])
    }

    private static func binoculars() -> PropRig {
        let root = Layers.canvas()
        for x in [87.0, 113.0] {
            let barrel = Layers.gradient(Paths.roundedRect(CGRect(x: x - 9, y: 42, width: 18, height: 26), 6),
                                         [Palette.navy.lighter(0.15), Palette.navy, Palette.visorBottom],
                                         from: CGPoint(x: 0, y: 0.5), to: CGPoint(x: 1, y: 0.5))
            root.addSublayer(barrel)
        }
        root.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: 95, y: 50, width: 10, height: 12), 3),
                                      fill: Palette.visorMid.cg()))
        for x in [87.0, 113.0] {
            let lens = pt(x, 38)
            let ring = Layers.shape(Paths.circle(lens, 12), fill: Palette.navy.cg())
            Layers.dropShadow(ring, path: ring.path, radius: 2, opacity: 0.25)
            root.addSublayer(ring)
            let glass = Layers.gradient(Paths.circle(lens, 8.5), [Palette.eyeLight, Palette.aqua.darker(0.3)])
            root.addSublayer(glass)
            Layers.glow(glass, Palette.aqua, radius: 3, opacity: 0.7)
            root.addSublayer(Layers.shape(Paths.circle(lens + pt(-3, 3), 2.2), fill: RGB.white.cg(0.85)))
        }
        return PropRig(layer: root, frame: CGRect(x: 74, y: 25, width: 52, height: 44))
    }

    private static func folder() -> PropRig {
        let root = Layers.canvas()
        let back = Paths.roundedRect(CGRect(x: 72, y: 24, width: 56, height: 40), 4)
        root.addSublayer(Layers.shape(back, fill: RGB(0xE9A91F).cg()))
        root.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: 72, y: 58, width: 22, height: 10), 3), fill: RGB(0xE9A91F).cg()))
        let paper = Layers.canvas()
        let sheet = Layers.shape(Paths.roundedRect(CGRect(x: 79, y: 34, width: 42, height: 36), 2),
                                 fill: RGB.white.cg(), stroke: RGB(0xDDE2EC).cg(), lineWidth: 0.8)
        paper.addSublayer(sheet)
        for (i, w) in [30.0, 30, 20].enumerated() {
            let y = 64 - CGFloat(i) * 5
            paper.addSublayer(Layers.shape(Paths.polyline([pt(85, y), pt(85 + w, y)]), stroke: Palette.lightBlue.cg(), lineWidth: 1.8))
        }
        root.addSublayer(paper)
        let frontPath = CGMutablePath()
        frontPath.move(to: pt(76, 24))
        frontPath.addLine(to: pt(124, 24))
        frontPath.addQuadCurve(to: pt(128, 28), control: pt(128, 24))
        frontPath.addLine(to: pt(130, 54))
        frontPath.addQuadCurve(to: pt(126, 57), control: pt(130, 57))
        frontPath.addLine(to: pt(74, 57))
        frontPath.addQuadCurve(to: pt(70, 54), control: pt(70, 57))
        frontPath.addLine(to: pt(72, 28))
        frontPath.addQuadCurve(to: pt(76, 24), control: pt(72, 24))
        frontPath.closeSubpath()
        let front = Layers.gradient(frontPath, [Palette.yellow.lighter(0.25), Palette.yellow, RGB(0xF2B42A)])
        Layers.dropShadow(front, path: nil, radius: 2, opacity: 0.15)
        root.addSublayer(front)
        root.addSublayer(Layers.shape(Paths.polyline([pt(75, 55.5), pt(125, 55.5)]), stroke: RGB.white.cg(0.55), lineWidth: 1.2))

        let shuffle = Motion.loop("transform.translation.y", from: 0, to: 4, duration: 0.9)
        return PropRig(layer: root, frame: CGRect(x: 70, y: 24, width: 60, height: 46),
                       loops: [Loop(layer: paper, key: "shuffle", animation: shuffle)])
    }

    private static func globe() -> PropRig {
        let root = Layers.canvas()
        let c = pt(100, 50), r: CGFloat = 19
        root.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: 86, y: 23, width: 28, height: 6), 3), fill: Palette.navy.cg()))
        root.addSublayer(Layers.shape(Paths.polyline([pt(100, 27), pt(100, 31)]), stroke: Palette.navy.cg(), lineWidth: 4))
        let arc = CGMutablePath()
        arc.addArc(center: c, radius: r + 4, startAngle: -.pi * 0.62, endAngle: .pi * 0.62, clockwise: false)
        root.addSublayer(Layers.shape(arc, stroke: Palette.navy.cg(), lineWidth: 2.6))

        let sphere = Layers.canvas()
        let mask = CAShapeLayer()
        mask.path = Paths.circle(c, r)
        sphere.mask = mask
        let sea = CAGradientLayer()
        sea.type = .radial
        sea.frame = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        sea.colors = [Palette.lightBlue.lighter(0.35).cg(), Palette.lightBlue.cg(), RGB(0x5B9BEA).cg()]
        sea.locations = [0, 0.5, 1]
        sea.startPoint = CGPoint(x: 0.35, y: 0.7)
        sea.endPoint = CGPoint(x: 1.1, y: 1.4)
        sphere.addSublayer(sea)
        // Two copies of the land side by side; sliding them one width reads as a turning globe.
        let land = Layers.canvas()
        for copy in [0.0, 40.0] {
            for blob in [[pt(84, 56), pt(92, 64), pt(99, 58), pt(96, 50), pt(88, 47)],
                         [pt(103, 46), pt(110, 52), pt(116, 46), pt(113, 37), pt(106, 36)],
                         [pt(88, 38), pt(93, 41), pt(95, 35), pt(90, 33)]] {
                land.addSublayer(Layers.shape(Paths.blob(blob.map { $0 + pt(copy - 20, 0) }), fill: Palette.mint.cg()))
            }
        }
        sphere.addSublayer(land)
        let meridian = Layers.shape(Paths.ellipse(c, 8, r), stroke: RGB.white.cg(0.45), lineWidth: 1.2)
        sphere.addSublayer(meridian)
        sphere.addSublayer(Layers.shape(Paths.polyline([c - pt(r, 0), c + pt(r, 0)]), stroke: RGB.white.cg(0.45), lineWidth: 1.2))
        sphere.addSublayer(Layers.shape(Paths.ellipse(c + pt(-7, 8), 5, 3.5), fill: RGB.white.cg(0.45)))
        root.addSublayer(sphere)

        let spin = Motion.loop("transform.translation.x", from: 0, to: 40, duration: 8, reverses: false, timing: .linear)
        return PropRig(layer: root, frame: CGRect(x: 78, y: 23, width: 46, height: 50),
                       loops: [Loop(layer: land, key: "spin", animation: spin)])
    }

    private static func card() -> PropRig {
        let root = Layers.canvas(anchor: pt(100, 26))
        let rect = CGRect(x: 73, y: 27, width: 54, height: 40)
        let cardPath = Paths.roundedRect(rect, 6)
        let card = Layers.shape(cardPath, fill: RGB.white.cg(), stroke: RGB(0xD3D9E6).cg(), lineWidth: 0.8)
        Layers.dropShadow(card, path: card.path, radius: 3, opacity: 0.22)
        root.addSublayer(card)
        let header = CGMutablePath()
        header.addPath(Paths.roundedRect(CGRect(x: rect.minX, y: rect.maxY - 12, width: rect.width, height: 12), 6))
        header.addRect(CGRect(x: rect.minX, y: rect.maxY - 12, width: rect.width, height: 6))
        root.addSublayer(Layers.shape(header, fill: Palette.navy.cg()))
        // A tiny shield: approvals are Guard's job.
        let shield = CGMutablePath()
        let s = pt(81, 61)
        shield.move(to: s + pt(0, 4))
        shield.addLine(to: s + pt(4, 2.6))
        shield.addQuadCurve(to: s + pt(0, -4.2), control: s + pt(4, -2.5))
        shield.addQuadCurve(to: s + pt(-4, 2.6), control: s + pt(-4, -2.5))
        shield.closeSubpath()
        root.addSublayer(Layers.shape(shield, fill: Palette.mint.cg()))
        root.addSublayer(Layers.shape(Paths.polyline([pt(89, 61), pt(118, 61)]), stroke: RGB.white.cg(0.7), lineWidth: 2))
        for (y, w) in [(50.0, 38.0), (44.0, 28.0)] {
            root.addSublayer(Layers.shape(Paths.polyline([pt(80, y), pt(80 + w, y)]), stroke: RGB(0xC9D0DE).cg(), lineWidth: 2.2))
        }
        let yes = Layers.shape(Paths.roundedRect(CGRect(x: 79, y: 31, width: 20, height: 8), 4), fill: Palette.mint.cg())
        let no = Layers.shape(Paths.roundedRect(CGRect(x: 102, y: 31, width: 20, height: 8), 4), fill: Palette.coral.cg())
        root.addSublayer(yes)
        root.addSublayer(no)

        let sway = Motion.loop("transform.rotation.z", from: -0.035, to: 0.035, duration: 1.6)
        return PropRig(layer: root, frame: rect, loops: [Loop(layer: root, key: "sway", animation: sway)])
    }

    private static func book() -> PropRig {
        let root = Layers.canvas()
        let spine: CGFloat = 100
        func page(_ side: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.move(to: pt(spine, 28))
            p.addQuadCurve(to: pt(spine + side * 28, 30), control: pt(spine + side * 12, 24))
            p.addLine(to: pt(spine + side * 28, 64))
            p.addQuadCurve(to: pt(spine, 62), control: pt(spine + side * 12, 58))
            p.closeSubpath()
            return p
        }
        let cover = CGMutablePath()
        cover.move(to: pt(spine, 24))
        cover.addQuadCurve(to: pt(spine - 31, 26), control: pt(spine - 13, 20))
        cover.addLine(to: pt(spine - 31, 62))
        cover.addQuadCurve(to: pt(spine + 31, 62), control: pt(spine, 56))
        cover.addLine(to: pt(spine + 31, 26))
        cover.addQuadCurve(to: pt(spine, 24), control: pt(spine + 13, 20))
        cover.closeSubpath()
        let coverLayer = Layers.shape(cover, fill: RGB(0x4FBF8B).cg())
        Layers.dropShadow(coverLayer, path: coverLayer.path, radius: 2.5, opacity: 0.2)
        root.addSublayer(coverLayer)
        for side in [-1.0, 1.0] {
            root.addSublayer(Layers.shape(page(side), fill: RGB(0xFFFDF7).cg(), stroke: RGB(0xE3E6EE).cg(), lineWidth: 0.8))
            for i in 0..<4 {
                let y = 54 - CGFloat(i) * 6.5
                root.addSublayer(Layers.shape(Paths.polyline([pt(spine + side * 6, y), pt(spine + side * 23, y + 1)]),
                                              stroke: RGB(0xC9D0DE).cg(), lineWidth: 1.6))
            }
        }
        // The turning page folds over the spine and back.
        let turning = Layers.canvas(anchor: pt(spine, 46))
        turning.addSublayer(Layers.shape(page(1), fill: RGB(0xF6F1E6).cg(), stroke: RGB(0xE3E6EE).cg(), lineWidth: 0.8))
        turning.opacity = 0
        root.addSublayer(turning)
        root.addSublayer(Layers.shape(Paths.polyline([pt(spine, 28), pt(spine, 62)]), stroke: RGB(0xD5DAE5).cg(), lineWidth: 1.2))

        let flip = Motion.cycle("transform.scale.x", [1, 1, -1, -1], duration: 3.2, times: [0, 0.55, 0.75, 1])
        let show = Motion.cycle("opacity", [0, 1, 0], duration: 3.2, times: [0, 0.55, 0.76, 1], discrete: true)
        return PropRig(layer: root, frame: CGRect(x: 69, y: 20, width: 62, height: 46),
                       loops: [Loop(layer: turning, key: "flip", animation: flip),
                               Loop(layer: turning, key: "flipShow", animation: show)])
    }

    private static func bell() -> PropRig {
        let top = pt(100, 70)
        let root = Layers.canvas(anchor: top)
        let p = CGMutablePath()
        p.move(to: pt(100, 66))
        p.addCurve(to: pt(115, 44), control1: pt(110, 66), control2: pt(114, 58))
        p.addCurve(to: pt(122, 32), control1: pt(116, 37), control2: pt(122, 36))
        p.addLine(to: pt(78, 32))
        p.addCurve(to: pt(85, 44), control1: pt(78, 36), control2: pt(84, 37))
        p.addCurve(to: pt(100, 66), control1: pt(86, 58), control2: pt(90, 66))
        p.closeSubpath()
        root.addSublayer(Layers.shape(Paths.circle(pt(100, 27.5), 5), fill: Palette.coral.cg()))
        let body = SoftShape(p, shading: .tinted(Palette.yellow))
        body.shadow(radius: 2.5, opacity: 0.2)
        root.addSublayer(body.layer)
        root.addSublayer(Layers.shape(Paths.roundedRect(CGRect(x: 76, y: 29, width: 48, height: 6), 3), fill: RGB(0xF0AE22).cg()))
        root.addSublayer(Layers.shape(Paths.circle(pt(100, 68), 3.4), fill: RGB(0xF0AE22).cg()))
        root.addSublayer(Layers.shape(Paths.ellipse(pt(92, 52), 2.4, 6), fill: RGB.white.cg(0.6)))

        let ring = Motion.cycle("transform.rotation.z", [0, 0.28, -0.24, 0.16, -0.1, 0, 0], duration: 1.8,
                                times: [0, 0.07, 0.16, 0.25, 0.34, 0.42, 1])
        return PropRig(layer: root, frame: CGRect(x: 76, y: 22, width: 48, height: 50),
                       loops: [Loop(layer: root, key: "ring", animation: ring)])
    }
}
