import QuartzCore

/// Little cartoon marks around the character.
enum Effect: Hashable {
    case zzz, dots, exclaim, question, sparkles, sweat, waves, confetti, ticks

    /// Marks that sit on the head move with the body; the rest float on the stage.
    var ridesBody: Bool { self == .sweat || self == .waves }
}

/// A built effect: its layer, where its still frame is, and its repeating motion.
@MainActor
private struct EffectRig {
    let layer: CALayer
    var loops: [Loop] = []
}

/// Shows and hides effects. Each effect's model state is a good still frame (offscreen renders
/// and reduced motion use it); motion is a set of repeating animations added on top.
@MainActor
final class Effects {
    private let stage: CALayer
    private let body: CALayer
    private var rigs: [Effect: EffectRig] = [:]
    private(set) var shown: Set<Effect> = []
    private var moving = false

    /// Marks drawn in the character's own light (zZz, thought dots, waves, "?", alert ticks) follow
    /// the accent; celebration colours and sweat keep theirs.
    var light = CharacterAccent.aqua.light {
        didSet {
            guard light != oldValue else { return }
            let showing = shown
            show([], animated: false, moving: moving)
            rigs.values.forEach { $0.layer.removeFromSuperlayer() }
            rigs = [:]
            show(showing, animated: false, moving: moving)
        }
    }

    init(stage: CALayer, body: CALayer) {
        self.stage = stage
        self.body = body
    }

    func show(_ next: Set<Effect>, animated: Bool, moving: Bool) {
        let leaving = shown.subtracting(next)
        let arriving = next.subtracting(shown)
        for effect in leaving {
            guard let rig = rigs[effect] else { continue }
            stopLoops(rig)
            if animated { fade(rig.layer.superlayer) }
            rig.layer.removeFromSuperlayer()
        }
        for effect in arriving {
            let rig = rigs[effect] ?? Effects.build(effect, light)
            rigs[effect] = rig
            let parent = effect.ridesBody ? body : stage
            parent.addSublayer(rig.layer)
            if animated {
                let pop = CASpringAnimation(perceptualDuration: 0.35, bounce: 0.35)
                pop.keyPath = "transform.scale"
                pop.fromValue = moving ? 0.4 : 1
                pop.toValue = 1
                pop.duration = pop.settlingDuration
                rig.layer.add(pop, forKey: "pop")
                fade(parent)
            }
        }
        shown = next
        if moving != self.moving || !arriving.isEmpty {
            self.moving = moving
            for effect in shown { if let rig = rigs[effect] { moving ? startLoops(rig) : stopLoops(rig) } }
        }
    }

    /// The question mark used by the look-around gesture, built on demand and hidden at rest.
    func question() -> CALayer {
        if let rig = rigs[.question] { return rig.layer }
        let rig = Effects.build(.question, light)
        rig.layer.opacity = 0
        rigs[.question] = rig
        stage.addSublayer(rig.layer)
        return rig.layer
    }

    private func startLoops(_ rig: EffectRig) {
        for loop in rig.loops where loop.layer.animation(forKey: loop.key) == nil {
            loop.layer.add(loop.animation, forKey: loop.key)
        }
    }

    private func stopLoops(_ rig: EffectRig) {
        rig.loops.forEach { $0.layer.removeAnimation(forKey: $0.key) }
    }

    private func fade(_ layer: CALayer?) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.2
        layer?.add(transition, forKey: "fade")
    }

    // MARK: Builders

    private static func build(_ effect: Effect, _ light: Light) -> EffectRig {
        switch effect {
        case .zzz: zzz(light)
        case .dots: dots(light)
        case .exclaim: exclaim()
        case .question: question(light)
        case .sparkles: sparkles()
        case .sweat: sweat()
        case .waves: waves(light)
        case .confetti: confetti()
        case .ticks: ticks(light)
        }
    }

    /// A glyph container anchored at `origin`, so pops and bounces grow from that point.
    private static func holder(_ origin: CGPoint) -> CALayer { Layers.canvas(anchor: origin) }

    private static func zzz(_ light: Light) -> EffectRig {
        let root = Layers.canvas()
        var loops: [Loop] = []
        for (i, (origin, size)) in [(pt(127, 124), 9.0), (pt(140, 138), 12.0), (pt(156, 155), 15.0)].enumerated() {
            let z = holder(origin)
            let path = Paths.polyline([origin + pt(-size / 2, size / 2), origin + pt(size / 2, size / 2),
                                       origin + pt(-size / 2, -size / 2), origin + pt(size / 2, -size / 2)])
            let glyph = Layers.shape(path, stroke: light.line.cg(), lineWidth: size * 0.24)
            Layers.glow(glyph, light.glow, radius: 2.5, opacity: 0.7)
            z.addSublayer(glyph)
            root.addSublayer(z)
            let rise = Motion.cycle("transform", [
                Motion.transform(CGAffineTransform(translationX: -3, y: -6).scaledBy(x: 0.6, y: 0.6)),
                Motion.transform(.identity),
                Motion.transform(CGAffineTransform(translationX: 4, y: 7).scaledBy(x: 1.1, y: 1.1)),
            ], duration: 2.7, phase: Double(2 - i) * 0.9)
            let fade = Motion.cycle("opacity", [0, 1, 1, 0], duration: 2.7, times: [0, 0.25, 0.7, 1], phase: Double(2 - i) * 0.9)
            loops += [Loop(layer: z, key: "rise", animation: rise), Loop(layer: z, key: "fade", animation: fade)]
        }
        return EffectRig(layer: root, loops: loops)
    }

    private static func dots(_ light: Light) -> EffectRig {
        let origin = pt(150, 156)
        let root = holder(pt(128, 132))
        let bubble = CGMutablePath()
        bubble.addPath(Paths.roundedRect(CGRect(x: origin.x - 21, y: origin.y - 11, width: 42, height: 22), 11))
        bubble.addPath(Paths.circle(pt(131, 138), 4.2))
        bubble.addPath(Paths.circle(pt(124, 130), 2.6))
        let cloud = Layers.shape(bubble, fill: RGB.white.cg())
        Layers.dropShadow(cloud, path: cloud.path, radius: 3, opacity: 0.22, offset: CGSize(width: 0, height: -1.5))
        root.addSublayer(cloud)
        root.addSublayer(Layers.shape(bubble, stroke: Palette.shellEdge.cg(0.5), lineWidth: 0.8))
        var loops: [Loop] = []
        for i in 0..<3 {
            let center = origin + pt(CGFloat(i - 1) * 11, 0)
            let dot = holder(center)
            dot.addSublayer(Layers.shape(Paths.circle(center, 3.4), fill: light.glow.cg()))
            root.addSublayer(dot)
            let hop = Motion.cycle("transform", [
                Motion.transform(.identity),
                Motion.transform(CGAffineTransform(translationX: 0, y: 3.5).scaledBy(x: 1.15, y: 1.15)),
                Motion.transform(.identity), Motion.transform(.identity),
            ], duration: 1.3, times: [0, 0.18, 0.36, 1], phase: 1.3 - Double(i) * 0.2)
            loops.append(Loop(layer: dot, key: "hop", animation: hop))
        }
        return EffectRig(layer: root, loops: loops)
    }

    private static func exclaim() -> EffectRig {
        let base = pt(158, 140)
        let root = holder(base)
        let glyph = CGMutablePath()
        glyph.addPath(Paths.polyline([base + pt(0, 12), base + pt(1.5, 30)]))
        let bar = Layers.shape(glyph, stroke: Palette.coral.cg(), lineWidth: 8)
        let dot = Layers.shape(Paths.circle(base + pt(-0.5, 2.5), 4.3), fill: Palette.coral.cg())
        for part in [bar, dot] {
            Layers.dropShadow(part, path: nil, radius: 2, opacity: 0.18, offset: CGSize(width: 0, height: -1))
            root.addSublayer(part)
        }
        let bounce = Motion.cycle("transform", [
            Motion.transform(.identity),
            Motion.transform(CGAffineTransform(translationX: 0, y: 5).scaledBy(x: 1.12, y: 1.12)),
            Motion.transform(.identity), Motion.transform(.identity),
        ], duration: 1.2, times: [0, 0.15, 0.32, 1])
        return EffectRig(layer: root, loops: [Loop(layer: root, key: "bounce", animation: bounce)])
    }

    private static func question(_ light: Light) -> EffectRig {
        let base = pt(156, 146)
        let root = holder(base)
        let curl = CGMutablePath()
        curl.move(to: base + pt(-7, 22))
        curl.addCurve(to: base + pt(7, 23), control1: base + pt(-6, 30), control2: base + pt(6, 31))
        curl.addCurve(to: base + pt(0, 11), control1: base + pt(8, 16), control2: base + pt(0, 16))
        let glyph = Layers.shape(curl, stroke: light.line.cg(), lineWidth: 5)
        Layers.glow(glyph, light.glow, radius: 2.5, opacity: 0.6)
        root.addSublayer(glyph)
        let dot = Layers.shape(Paths.circle(base + pt(0, 3), 3.2), fill: light.line.cg())
        Layers.glow(dot, light.glow, radius: 2.5, opacity: 0.6)
        root.addSublayer(dot)
        return EffectRig(layer: root)
    }

    private static func sparkles() -> EffectRig {
        let root = Layers.canvas()
        var loops: [Loop] = []
        let spots: [(CGPoint, CGFloat, RGB)] = [
            (pt(48, 156), 8, Palette.yellow), (pt(154, 168), 10, Palette.aqua),
            (pt(172, 126), 6, Palette.coral), (pt(30, 128), 5.5, Palette.mint),
        ]
        for (i, (center, r, color)) in spots.enumerated() {
            let star = holder(center)
            let shape = Layers.shape(Paths.sparkle(center, r), fill: color.cg())
            Layers.glow(shape, color, radius: 2, opacity: 0.5)
            star.addSublayer(shape)
            root.addSublayer(star)
            let twinkle = Motion.cycle("transform", [
                Motion.transform(CGAffineTransform(scaleX: 0.55, y: 0.55)),
                Motion.transform(CGAffineTransform(rotationAngle: 0.4).scaledBy(x: 1.1, y: 1.1)),
                Motion.transform(CGAffineTransform(scaleX: 0.55, y: 0.55)),
            ], duration: 1.4 + Double(i) * 0.2, phase: Double(i) * 0.35)
            loops.append(Loop(layer: star, key: "twinkle", animation: twinkle))
        }
        return EffectRig(layer: root, loops: loops)
    }

    private static func sweat() -> EffectRig {
        let top = pt(147, 140)
        let root = holder(top)
        let drop = CGMutablePath()
        drop.move(to: top)
        drop.addCurve(to: top + pt(-5.5, -13), control1: top + pt(-1.5, -4), control2: top + pt(-5.5, -8))
        drop.addCurve(to: top + pt(5.5, -13), control1: top + pt(-5.5, -20), control2: top + pt(5.5, -20))
        drop.addCurve(to: top, control1: top + pt(5.5, -8), control2: top + pt(1.5, -4))
        drop.closeSubpath()
        let shape = Layers.gradient(drop, [Palette.lightBlue.lighter(0.5), Palette.lightBlue, RGB(0x6AA8F5)])
        Layers.dropShadow(shape, path: nil, radius: 1.5, opacity: 0.2, offset: CGSize(width: 0, height: -1))
        root.addSublayer(shape)
        root.addSublayer(Layers.shape(Paths.ellipse(top + pt(-2, -12), 1.4, 2.6), fill: RGB.white.cg(0.8)))
        let slide = Motion.cycle("transform.translation.y", [0, 0, -7], duration: 1.8, times: [0, 0.35, 1])
        let fade = Motion.cycle("opacity", [0, 1, 1, 0], duration: 1.8, times: [0, 0.15, 0.7, 1])
        return EffectRig(layer: root, loops: [Loop(layer: root, key: "slide", animation: slide),
                                              Loop(layer: root, key: "fade", animation: fade)])
    }

    private static func waves(_ light: Light) -> EffectRig {
        let root = Layers.canvas()
        var loops: [Loop] = []
        for (i, radius) in [9.0, 16.0].enumerated() {
            let arc = CGMutablePath()
            arc.addArc(center: Canvas.earR + pt(4, 0), radius: radius + 6, startAngle: -0.75, endAngle: 0.75, clockwise: false)
            let wave = Layers.shape(arc, stroke: light.line.cg(), lineWidth: 3.4)
            Layers.glow(wave, light.glow, radius: 2.5, opacity: 0.7)
            root.addSublayer(wave)
            loops.append(Loop(layer: wave, key: "pulse",
                              animation: Motion.loop("opacity", from: 1, to: 0.25, duration: 0.7, phase: Double(i) * 0.35)))
        }
        return EffectRig(layer: root, loops: loops)
    }

    private static func confetti() -> EffectRig {
        let root = Layers.canvas()
        let colors = [Palette.coral, Palette.yellow, Palette.mint, Palette.lightBlue, Palette.aqua]
        let spots: [CGPoint] = [pt(34, 170), pt(58, 186), pt(78, 176), pt(122, 188), pt(146, 178), pt(170, 166),
                                pt(46, 148), pt(160, 150), pt(28, 132), pt(178, 132), pt(96, 192), pt(136, 160)]
        var loops: [Loop] = []
        for (i, p) in spots.enumerated() {
            let bit = holder(p)
            let shape: CAShapeLayer = i % 3 == 0
                ? Layers.shape(Paths.circle(p, 2.8), fill: colors[i % colors.count].cg())
                : Layers.shape(Paths.roundedRect(CGRect(x: p.x - 2.2, y: p.y - 4.5, width: 4.4, height: 9), 1.6),
                               fill: colors[i % colors.count].cg())
            bit.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(i) * 0.7))
            bit.addSublayer(shape)
            root.addSublayer(bit)
            let duration = 1.7 + Double(i % 4) * 0.25
            let fall = Motion.cycle("transform", [
                Motion.transform(CGAffineTransform(translationX: 0, y: 14).rotated(by: CGFloat(i))),
                Motion.transform(CGAffineTransform(translationX: CGFloat(i % 2 == 0 ? 4 : -4), y: -4).rotated(by: CGFloat(i) + 2)),
                Motion.transform(CGAffineTransform(translationX: 0, y: -22).rotated(by: CGFloat(i) + 4)),
            ], duration: duration, phase: Double(i) * 0.31)
            let fade = Motion.cycle("opacity", [0, 1, 1, 0], duration: duration, times: [0, 0.15, 0.75, 1], phase: Double(i) * 0.31)
            loops += [Loop(layer: bit, key: "fall", animation: fall), Loop(layer: bit, key: "fade", animation: fade)]
        }
        return EffectRig(layer: root, loops: loops)
    }

    private static func ticks(_ light: Light) -> EffectRig {
        let center = pt(64, 132)
        let root = holder(center)
        for angle in [2.0, 2.45, 2.9] {
            let dir = pt(cos(angle), sin(angle))
            let tick = Layers.shape(Paths.polyline([center + dir * 26, center + dir * 36]),
                                    stroke: light.line.cg(), lineWidth: 4.6)
            Layers.glow(tick, light.glow, radius: 2, opacity: 0.6)
            root.addSublayer(tick)
        }
        let pulse = Motion.cycle("transform", [
            Motion.transform(.identity),
            Motion.transform(CGAffineTransform(scaleX: 1.12, y: 1.12)),
            Motion.transform(.identity), Motion.transform(.identity),
        ], duration: 1.2, times: [0, 0.15, 0.32, 1])
        return EffectRig(layer: root, loops: [Loop(layer: root, key: "pulse", animation: pulse)])
    }
}
