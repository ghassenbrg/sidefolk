import AppKit
import QuartzCore

/// The main character as a tree of layers in canvas units, and the code that moves it between poses.
///
/// Nested transform layers keep concerns apart so their animations never fight over a key path:
/// `body` holds the pose, `loop` the state's repeating motion, `gesture` one-shot moves and
/// `breath` the idle breathing. Faces, arms and props hang below `breath`.
@MainActor
final class Rig {
    /// Root of the canvas. The host scales and centers it.
    let stage = Layers.canvas(anchor: pt(100, 100))

    let body = Layers.canvas()
    let loop = Layers.canvas()
    let gesture = Layers.canvas()
    /// Rasterized: its looping transform then composites a cached bitmap instead of re-rendering the body.
    let breath: CALayer = {
        let layer = Layers.canvas()
        layer.shouldRasterize = true
        return layer
    }()
    /// Visor and eyes; nods and shakes move it, gaze nudges it for parallax.
    let face = Layers.canvas()
    let faceGesture = Layers.canvas()
    /// Eyes, brows and mouth inside the glass; gaze moves this, `scan` sweeps it in loops.
    let eyes = Layers.canvas()
    let scan = Layers.canvas()
    let blink = Layers.canvas(anchor: pt(100, Canvas.eyeL.y))

    let armL: Limb
    let armR: Limb
    let propBack = Layers.canvas()
    let propFront = Layers.canvas()
    /// Effects that ride on the body (sweat, sound waves) and those that float on the stage.
    let bodyFX = Layers.canvas()
    let stageFX = Layers.canvas()
    let badges = Layers.canvas()

    private let ground = CAGradientLayer()
    private let footL = Layers.canvas(anchor: pt(84, 33))
    private let footR = Layers.canvas(anchor: pt(116, 33))
    private let ears: [Ear]
    private let eyeLayers: [FaceMark]   // left, right
    private let browLayers: [FaceMark]
    private let mouthLayer: FaceMark

    private(set) var pose = Pose()
    /// Pointer gaze on top of the pose's own look.
    private var gaze: CGVector?

    /// The light's colour. In a live view Core Animation's implicit animation fades it across.
    var accent: CharacterAccent = .aqua {
        didSet { if accent != oldValue { tint() } }
    }

    init() {
        armL = Limb(shoulder: Canvas.shoulderL)
        armR = Limb(shoulder: Canvas.shoulderR)
        ears = [Ear(center: Canvas.earL, side: -1), Ear(center: Canvas.earR, side: 1)]
        eyeLayers = [FaceMark(center: Canvas.eyeL, core: true), FaceMark(center: Canvas.eyeR, core: true)]
        browLayers = [FaceMark(center: Canvas.eyeL, core: false), FaceMark(center: Canvas.eyeR, core: false)]
        mouthLayer = FaceMark(center: Canvas.mouth, core: false)
        build()
        tint()
        apply(pose, .instant)
    }

    private func tint() {
        let light = accent.light
        ears.forEach { $0.tint(light) }
        (eyeLayers + browLayers + [mouthLayer]).forEach { $0.tint(light) }
    }

    private func build() {
        ground.type = .radial
        ground.frame = CGRect(x: 40, y: Canvas.floor - 8, width: 120, height: 16)
        ground.colors = [Palette.ink.cg(0.26), Palette.ink.cg(0.12), Palette.ink.cg(0)]
        ground.locations = [0, 0.5, 1]
        ground.startPoint = CGPoint(x: 0.5, y: 0.5)
        ground.endPoint = CGPoint(x: 1, y: 1)
        stage.addSublayer(ground)

        stage.addSublayer(body)
        body.addSublayer(loop)
        loop.addSublayer(gesture)
        gesture.addSublayer(breath)

        for (foot, center) in [(footL, Canvas.footL), (footR, Canvas.footR)] {
            let shape = SoftShape(Shapes.foot(center))
            shape.shadow(radius: 2, opacity: 0.12, offset: CGSize(width: 0, height: -1))
            foot.addSublayer(shape.layer)
            breath.addSublayer(foot)
        }

        let fin = SoftShape(Shapes.fin, shading: Shading(colors: Palette.shell, locations: [0, 0.22, 0.5, 0.78, 1],
                                                          center: CGPoint(x: 0.28, y: 0.9),
                                                          reach: CGSize(width: 0.95, height: 1.05)))
        fin.outline(Palette.shellEdge, alpha: 0.55, width: 0.9)
        breath.addSublayer(fin.layer)

        let shell = SoftShape(Shapes.body)
        shell.shadow(radius: 5, opacity: 0.16)
        shell.outline(Palette.shellEdge, alpha: 0.45, width: 0.8)
        breath.addSublayer(shell.layer)
        addShellLights(to: breath)

        ears.forEach { breath.addSublayer($0.layer) }

        breath.addSublayer(face)
        face.addSublayer(faceGesture)
        buildVisor(in: faceGesture)

        breath.addSublayer(propBack)
        breath.addSublayer(armL.pose)
        breath.addSublayer(armR.pose)
        breath.addSublayer(propFront)
        breath.addSublayer(bodyFX)

        stage.addSublayer(stageFX)
        stage.addSublayer(badges)
    }

    /// Soft secondary lights that sell the "glossy toy" look: a bounce glow along the lower
    /// edge and a broad sheen on the dome.
    private func addShellLights(to parent: CALayer) {
        let sheen = CAGradientLayer()
        sheen.type = .radial
        sheen.frame = CGRect(x: 52, y: 120, width: 60, height: 26)
        sheen.colors = [RGB.white.cg(0.9), RGB.white.cg(0)]
        sheen.startPoint = CGPoint(x: 0.5, y: 0.5)
        sheen.endPoint = CGPoint(x: 1, y: 1)
        parent.addSublayer(sheen)

        // The fin's curl overhangs the dome and shades it a little.
        let tuck = CAGradientLayer()
        tuck.type = .radial
        tuck.frame = CGRect(x: 104, y: 136, width: 34, height: 12)
        tuck.colors = [Palette.shellEdge.cg(0.45), Palette.shellEdge.cg(0)]
        tuck.startPoint = CGPoint(x: 0.5, y: 0.6)
        tuck.endPoint = CGPoint(x: 1, y: 1.1)
        parent.addSublayer(tuck)
    }

    private func buildVisor(in parent: CALayer) {
        let rim = CAGradientLayer()
        rim.frame = Shapes.visorRim.boundingBoxOfPath
        rim.colors = [RGB(0xC5CBDA).cg(), RGB(0xE4E8F0).cg(), RGB(0xF7F8FB).cg()]
        rim.startPoint = CGPoint(x: 0.5, y: 1)
        rim.endPoint = CGPoint(x: 0.5, y: 0)
        let rimMask = CAShapeLayer()
        rimMask.path = Paths.translated(Shapes.visorRim, -rim.frame.minX, -rim.frame.minY)
        rim.mask = rimMask
        parent.addSublayer(rim)

        // The glass clips everything inside it, eye glow included, like light under a screen.
        let glass = Layers.canvas()
        let glassMask = CAShapeLayer()
        glassMask.path = Shapes.visor
        glass.mask = glassMask

        let base = CAGradientLayer()
        base.frame = Canvas.visor
        base.colors = [Palette.visorTop.cg(), Palette.visorMid.cg(), Palette.visorBottom.cg()]
        base.locations = [0, 0.42, 1]
        base.startPoint = CGPoint(x: 0.5, y: 1)
        base.endPoint = CGPoint(x: 0.5, y: 0)
        glass.addSublayer(base)

        // Curved-glass falloff: darker toward the edges.
        let vignette = CAGradientLayer()
        vignette.type = .radial
        vignette.frame = Canvas.visor
        vignette.colors = [RGB(0x000000).cg(0), RGB(0x000000).cg(0), RGB(0x000000).cg(0.35)]
        vignette.locations = [0, 0.6, 1]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.55)
        vignette.endPoint = CGPoint(x: 1.05, y: 1.15)
        glass.addSublayer(vignette)

        glass.addSublayer(eyes)
        eyes.addSublayer(scan)
        scan.addSublayer(blink)
        eyeLayers.forEach { blink.addSublayer($0.layer) }
        browLayers.forEach { blink.addSublayer($0.layer) }
        scan.addSublayer(mouthLayer.layer)

        // Reflections sit above the eyes so they read as on the glass.
        let sheen = CAGradientLayer()
        sheen.frame = CGRect(x: 60, y: 104, width: 80, height: 24)
        sheen.colors = [RGB.white.cg(0.16), RGB.white.cg(0)]
        sheen.startPoint = CGPoint(x: 0.5, y: 1)
        sheen.endPoint = CGPoint(x: 0.5, y: 0)
        let sheenMask = CAShapeLayer()
        sheenMask.path = Paths.ellipse(pt(36, 22), 42, 12)
        sheen.mask = sheenMask
        glass.addSublayer(sheen)

        let glare = CAShapeLayer()
        let streak = CGMutablePath()
        streak.move(to: pt(60, 100))
        streak.addCurve(to: pt(80, 121.5), control1: pt(60, 112), control2: pt(66, 120))
        glare.path = streak
        glare.fillColor = nil
        glare.strokeColor = RGB.white.cg(0.32)
        glare.lineWidth = 3.2
        glare.lineCap = .round
        glass.addSublayer(glare)

        let glint = CAShapeLayer()
        glint.path = Paths.circle(pt(86, 121.5), 1.7)
        glint.fillColor = RGB.white.cg(0.4)
        glass.addSublayer(glint)

        parent.addSublayer(glass)
    }

    var earLights: [CALayer] { ears.map(\.lightLayer) }

    // MARK: Posing

    func apply(_ next: Pose, _ transit: Transit) {
        pose = next
        let body = CGAffineTransform(translationX: next.shift, y: next.lift)
            .rotated(by: next.lean)
            .scaledBy(x: next.squash.width, y: next.squash.height)
        Motion.set(self.body, "transform", Motion.transform(body), transit)

        armL.raise(next.armL, side: -1, transit)
        armR.raise(next.armR, side: 1, transit)

        let drop = next.feetDangle
        Motion.set(footL, "transform", Motion.transform(
            CGAffineTransform(translationX: -drop * 1.5, y: -drop * 4).rotated(by: -drop * 0.35)), transit)
        Motion.set(footR, "transform", Motion.transform(
            CGAffineTransform(translationX: drop * 1.5, y: -drop * 4).rotated(by: drop * 0.35)), transit)

        let faceTransit: Transit = transit.isInstant ? .instant : .ease(0.22)
        eyeLayers[0].show(next.eyeL, faceTransit)
        eyeLayers[1].show(next.eyeR, faceTransit)
        browLayers[0].show(next.browL, faceTransit)
        browLayers[1].show(next.browR, faceTransit)
        browLayers.forEach { Motion.set($0.layer, "opacity", Float(next.brows), faceTransit) }
        mouthLayer.show(next.mouth, faceTransit)
        Motion.set(mouthLayer.layer, "opacity", Float(next.mouthShown), faceTransit)

        ears.forEach { $0.glow(next.earGlow, faceTransit) }

        Motion.set(ground, "transform", Motion.transform(
            CGAffineTransform(scaleX: 0.55 + 0.45 * next.groundShadow, y: 0.7 + 0.3 * next.groundShadow)), transit)
        Motion.set(ground, "opacity", Float(0.3 + 0.7 * next.groundShadow), transit)

        updateGaze(transit.isInstant ? .instant : .ease(0.3))
    }

    /// Pointer gaze; nil looks where the pose looks.
    func setGaze(_ vector: CGVector?, _ transit: Transit) {
        gaze = vector
        updateGaze(transit)
    }

    private func updateGaze(_ transit: Transit) {
        let follow = pose.gazeFollow
        var look = pose.look
        if let gaze {
            look.dx += gaze.dx * follow
            look.dy += gaze.dy * follow
        }
        look.dx = max(-1, min(1, look.dx))
        look.dy = max(-1, min(1, look.dy))
        Motion.set(eyes, "transform", Motion.transform(CGAffineTransform(translationX: look.dx * 9, y: look.dy * 5)), transit)
        Motion.set(face, "transform", Motion.transform(CGAffineTransform(translationX: look.dx * 2.5, y: look.dy * 1.5)), transit)
    }

    // MARK: Hit testing

    /// The outline that should catch clicks for the current pose, in canvas units.
    func silhouette(extra: CGRect?) -> CGPath {
        var shape = Shapes.trunk
        for limb in [armL, armR] { shape = shape.union(limb.outline) }
        if let extra { shape = shape.union(CGPath(rect: extra, transform: nil)) }
        let t = CGAffineTransform(translationX: Canvas.pivot.x + pose.shift, y: Canvas.pivot.y + pose.lift)
            .rotated(by: pose.lean)
            .scaledBy(x: pose.squash.width, y: pose.squash.height)
            .translatedBy(x: -Canvas.pivot.x, y: -Canvas.pivot.y)
        return Paths.transformed(shape, t)
    }
}

extension Transit {
    var isInstant: Bool {
        if case .instant = self { return true }
        return false
    }
}

/// An arm: a mitten that rotates around its shoulder. The pose angle lives on `pose`, repeating
/// motion (typing, waving) on `loop`.
@MainActor
final class Limb {
    let pose: CALayer
    let loop: CALayer
    private let shoulder: CGPoint
    private(set) var angle: CGFloat = 0

    init(shoulder: CGPoint) {
        self.shoulder = shoulder
        pose = Layers.canvas(anchor: shoulder)
        loop = Layers.canvas(anchor: shoulder)
        let mitten = SoftShape(Paths.translated(Shapes.arm, shoulder.x, shoulder.y),
                               shading: Shading(colors: Palette.shell, locations: [0, 0.3, 0.6, 0.85, 1],
                                                center: CGPoint(x: 0.35, y: 0.7), reach: CGSize(width: 0.9, height: 0.9)))
        mitten.shadow(radius: 2.5, opacity: 0.18, offset: CGSize(width: 0, height: -1))
        mitten.outline(Palette.shellEdge, alpha: 0.35, width: 0.7)
        pose.addSublayer(loop)
        loop.addSublayer(mitten.layer)
    }

    /// `raise` > 0 swings the hand outward and up; the left arm turns clockwise for that.
    func raise(_ raise: CGFloat, side: CGFloat, _ transit: Transit) {
        angle = raise * side
        Motion.set(pose, "transform", Motion.transform(CGAffineTransform(rotationAngle: angle)), transit)
    }

    /// The mitten's outline at its posed angle, in body coordinates.
    var outline: CGPath {
        Paths.transformed(Shapes.arm, CGAffineTransform(translationX: shoulder.x, y: shoulder.y).rotated(by: angle))
    }
}

/// An ear pod: a white cylinder end with a navy face and a glowing ring in the accent.
@MainActor
final class Ear {
    let layer = Layers.canvas()
    private let ring: CAShapeLayer
    private let light: CAShapeLayer

    init(center: CGPoint, side: CGFloat) {
        let pod = SoftShape(Shapes.earPod(center),
                            shading: Shading(colors: Palette.shell, locations: [0, 0.3, 0.6, 0.85, 1],
                                             center: CGPoint(x: side < 0 ? 0.3 : 0.4, y: 0.72),
                                             reach: CGSize(width: 0.9, height: 0.95)))
        pod.shadow(radius: 3, opacity: 0.16, offset: CGSize(width: -side, height: -1))
        pod.outline(Palette.shellEdge, alpha: 0.4, width: 0.7)
        layer.addSublayer(pod.layer)

        let faceCenter = center + pt(side * 4.5, 0)
        let face = Layers.shape(Paths.ellipse(faceCenter, 7.5, 19), fill: Palette.visorMid.cg())
        layer.addSublayer(face)

        light = Layers.shape(Paths.ellipse(faceCenter, 4.6, 14.5))
        Layers.glow(light, Palette.aqua, radius: 5)
        layer.addSublayer(light)

        ring = Layers.shape(Paths.ellipse(faceCenter, 4.8, 15), lineWidth: 2.6)
        Layers.glow(ring, Palette.aqua, radius: 3)
        layer.addSublayer(ring)
    }

    /// Colours only: the glow's strength belongs to the pose (`glow(_:_:)`).
    func tint(_ accent: Light) {
        light.fillColor = accent.glow.cg(0.55)
        light.shadowColor = accent.glow.cg()
        ring.strokeColor = accent.line.cg()
        ring.shadowColor = accent.glow.cg()
    }

    func glow(_ amount: CGFloat, _ transit: Transit) {
        Motion.set(ring, "opacity", Float(0.45 + 0.55 * amount), transit)
        Motion.set(ring, "shadowRadius", 2 + 4 * amount, transit)
        Motion.set(light, "opacity", Float(max(0, amount - 0.3) * 1.2), transit)
    }

    var lightLayer: CALayer { light }
}

/// One morphing facial stroke (an eye, a brow, the mouth), with optional hot core.
@MainActor
final class FaceMark {
    let layer: CALayer
    private let glow = CAShapeLayer()
    private let core: CAShapeLayer?
    private static let box: CGFloat = 60

    init(center: CGPoint, core hasCore: Bool) {
        let half = FaceMark.box / 2
        layer = CALayer()
        layer.frame = CGRect(x: center.x - half, y: center.y - half, width: FaceMark.box, height: FaceMark.box)
        core = hasCore ? CAShapeLayer() : nil
        for line in [glow, core].compactMap(\.self) {
            line.frame = layer.bounds
            line.fillColor = nil
            line.lineCap = .round
            line.lineJoin = .round
            layer.addSublayer(line)
        }
        Layers.glow(glow, Palette.aqua, radius: 4.5, opacity: 0.95)
    }

    func tint(_ accent: Light) {
        glow.strokeColor = accent.line.cg()
        glow.shadowColor = accent.glow.cg()
        core?.strokeColor = accent.core.cg(0.85)
    }

    func show(_ stroke: Stroke, _ transit: Transit) {
        let local = pt(FaceMark.box / 2, FaceMark.box / 2)
        let path = stroke.path(at: local)
        Motion.set(glow, "path", path, transit)
        Motion.set(glow, "lineWidth", stroke.width, transit)
        if let core {
            Motion.set(core, "path", path, transit)
            Motion.set(core, "lineWidth", stroke.width * 0.4, transit)
        }
    }
}
