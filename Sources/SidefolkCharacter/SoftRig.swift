import QuartzCore

/// Any soft companion (Mochi, Spark, the folks) built from its `Species`, moved exactly like the
/// robot: the same choreography, props, effects, badges, settling and pausing (see `Figure`).
///
/// Its own layers: the head (or, on one-piece bodies, the face) turns toward the pointer around the
/// neck; ears and antennae hang behind it and droop, trail and sway; worn pieces ride on the head,
/// the face or the body; the scarf wraps between body and head.
@MainActor
final class SoftRig: Figure {
    let stage = Layers.canvas(anchor: pt(100, 100))
    let loop = Layers.canvas()
    let gesture = Layers.canvas()
    /// Rasterized: its looping transform then composites a cached bitmap instead of re-rendering the body.
    let breath: CALayer = {
        let layer = Layers.canvas()
        layer.shouldRasterize = true
        return layer
    }()
    let faceGesture = Layers.canvas()
    let scan = Layers.canvas()
    let blink: CALayer
    let armL: Limb
    let armR: Limb
    let propBack = Layers.canvas()
    let propFront = Layers.canvas()
    let bodyFX = Layers.canvas()
    let stageFX = Layers.canvas()
    let badges = Layers.canvas()

    private let species: Species
    private let body = Layers.canvas()
    private let ground = CAGradientLayer()
    private let feet: [CALayer]
    /// Ears and sprouts behind the head, and the head itself: both turn the same way.
    private let crown: CALayer
    private let head: CALayer
    /// Eyes, brows and mouth; gaze slides this a little further than the head (parallax).
    private let face: CALayer
    private let eyes = Layers.canvas()
    private let appendages: [Appendage]
    private let eyeMarks: [FaceMark]
    private let browMarks: [FaceMark]
    private let mouthMark: FaceMark
    private let backGear = Layers.canvas()
    private let headGear = Layers.canvas()
    private let faceGear = Layers.canvas()
    private let bodyGear = Layers.canvas()
    /// The signature thing in hand: under the arms or over them, as the species draws it.
    private let held = Layers.canvas()
    private let wardrobe = Layers.canvas()
    private lazy var trunk: CGPath = makeTrunk()

    private(set) var pose = Pose()
    private var gaze: CGVector?
    private var style = CharacterAccessory.none
    private var accent = CharacterAccent.aqua

    init(_ species: Species) {
        self.species = species
        let neck = species.neck
        crown = Layers.canvas(anchor: neck)
        head = Layers.canvas(anchor: neck)
        face = Layers.canvas(anchor: neck)
        let (eyeL, eyeR) = species.face.eyes
        blink = Layers.canvas(anchor: pt(100, (eyeL.y + eyeR.y) / 2))
        armL = Limb(shoulder: species.shoulders.0, style: species.arm)
        armR = Limb(shoulder: species.shoulders.1, style: species.arm)
        feet = species.feet.map { Layers.canvas(anchor: $0 + pt(0, species.foot.height * 0.7)) }
        appendages = species.appendages.map(Appendage.init)
        let scale = species.face.scale
        switch species.face.kind {
        case .ink:
            eyeMarks = [eyeL, eyeR].map { FaceMark(center: $0, ink: Palette.eyeInk, shine: true, scale: scale) }
            browMarks = [eyeL, eyeR].map { FaceMark(center: $0, ink: Palette.eyeInk, shine: false, scale: scale) }
            mouthMark = FaceMark(center: species.face.mouth, ink: Palette.eyeInk, shine: false, scale: scale)
        case .screen:
            // Solid glowing ovals, like the render (the robot's eyes have a hot core).
            eyeMarks = [eyeL, eyeR].map { FaceMark(center: $0, core: false) }
            browMarks = [eyeL, eyeR].map { FaceMark(center: $0, core: false) }
            mouthMark = FaceMark(center: species.face.mouth, core: false)
        }
        build()
        dress(CharacterStyle(color: .aqua, accessory: .none))
        apply(pose, .instant)
    }

    // MARK: Building

    private func build() {
        ground.type = .radial
        let width = species.restingFrame.width * 0.95
        ground.frame = CGRect(x: 100 - width / 2, y: Canvas.floor - 7.5, width: width, height: 15)
        ground.colors = [Palette.ink.cg(0.24), Palette.ink.cg(0.11), Palette.ink.cg(0)]
        ground.locations = [0, 0.5, 1]
        ground.startPoint = CGPoint(x: 0.5, y: 0.5)
        ground.endPoint = CGPoint(x: 1, y: 1)
        stage.addSublayer(ground)

        stage.addSublayer(body)
        body.addSublayer(loop)
        loop.addSublayer(gesture)
        gesture.addSublayer(breath)

        let footShading = species.footShading ?? species.shading
        for (layer, center) in zip(feet, species.feet) {
            let foot = SoftShape(Paths.ellipse(center, species.foot.width / 2, species.foot.height / 2), shading: footShading)
            foot.shadow(radius: 2, opacity: 0.14, offset: CGSize(width: 0, height: -1))
            if let edge = species.edge { foot.outline(edge, alpha: 0.4, width: 0.7) }
            layer.addSublayer(foot.layer)
            breath.addSublayer(layer)
        }

        crown.addSublayer(backGear)
        appendages.forEach { crown.addSublayer($0.root) }
        breath.addSublayer(crown)
        breath.addSublayer(soft(species.torso, shadow: 5))
        breath.addSublayer(bodyGear)
        breath.addSublayer(wardrobe)

        if let shape = species.head { head.addSublayer(soft(shape, shadow: 4)) }
        head.addSublayer(face)
        face.addSublayer(faceGesture)
        if case .screen(let rect, let radius) = species.face.kind { faceGesture.addSublayer(Self.screen(rect, radius)) }
        if species.face.cheeks {
            for eye in [species.face.eyes.0, species.face.eyes.1] {
                let s = species.face.scale
                faceGesture.addSublayer(Layers.shape(Paths.ellipse(eye + pt(eye.x < 100 ? -3 * s : 3 * s, -10 * s), 5.5 * s, 3.4 * s),
                                                     fill: Palette.blush.cg(0.42)))
            }
        }
        faceGesture.addSublayer(eyes)
        eyes.addSublayer(scan)
        scan.addSublayer(blink)
        eyeMarks.forEach { blink.addSublayer($0.layer) }
        browMarks.forEach { blink.addSublayer($0.layer) }
        scan.addSublayer(mouthMark.layer)
        if let nose = species.face.nose {
            scan.addSublayer(Layers.shape(Paths.ellipse(pt(nose.midX, nose.midY), nose.width / 2, nose.height / 2),
                                          fill: Palette.eyeInk.cg()))
        }
        faceGesture.addSublayer(faceGear)
        head.addSublayer(headGear)
        breath.addSublayer(head)

        if let item = species.held {
            held.addSublayer(item.draw())
            held.opacity = 0
        }
        breath.addSublayer(propBack)
        if species.held?.overArms == false { breath.addSublayer(held) }
        breath.addSublayer(armL.pose)
        breath.addSublayer(armR.pose)
        if species.held?.overArms == true { breath.addSublayer(held) }
        breath.addSublayer(propFront)
        breath.addSublayer(bodyFX)

        stage.addSublayer(stageFX)
        stage.addSublayer(badges)
    }

    /// A body part in the species' shading, with its soft drop shadow and edge.
    private func soft(_ path: CGPath, shadow: CGFloat) -> CALayer {
        let shape = SoftShape(path, shading: species.shading)
        shape.shadow(radius: shadow, opacity: 0.15)
        if let edge = species.edge { shape.outline(edge, alpha: 0.42, width: 0.8) }
        return shape.layer
    }

    /// A dark glass screen with a soft sheen, like the robot's visor.
    private static func screen(_ rect: CGRect, _ radius: CGFloat) -> CALayer {
        let glass = Layers.canvas()
        let path = Paths.roundedRect(rect, radius)
        glass.addSublayer(Layers.gradient(path, [Palette.visorTop, Palette.visorMid, Palette.visorBottom]))
        // Reflections on the glass, above the eyes: a band of sheen and a short glare stroke.
        let band = Paths.roundedRect(CGRect(x: rect.minX + 7, y: rect.maxY - rect.height * 0.4,
                                            width: rect.width - 14, height: rect.height * 0.32), radius * 0.6)
        let sheen = CAGradientLayer()
        sheen.frame = band.boundingBoxOfPath
        sheen.colors = [RGB.white.cg(0.16), RGB.white.cg(0)]
        sheen.startPoint = CGPoint(x: 0.5, y: 1)
        sheen.endPoint = CGPoint(x: 0.5, y: 0)
        let mask = CAShapeLayer()
        mask.path = Paths.translated(band, -sheen.frame.minX, -sheen.frame.minY)
        sheen.mask = mask
        glass.addSublayer(sheen)
        let glare = CGMutablePath()
        glare.move(to: pt(rect.minX + 6, rect.midY - 2))
        glare.addCurve(to: pt(rect.minX + 20, rect.maxY - 5), control1: pt(rect.minX + 6, rect.maxY - 12),
                       control2: pt(rect.minX + 11, rect.maxY - 5))
        glass.addSublayer(Layers.shape(glare, stroke: RGB.white.cg(0.28), lineWidth: 2.6))
        glass.addSublayer(Layers.shape(path, stroke: Palette.visorTop.lighter(0.15).cg(0.6), lineWidth: 1))
        return glass
    }

    // MARK: Figure

    var restingFrame: CGRect { species.restingFrame }
    var listeningLights: [CALayer] { [] }
    var markLight: Light { species.marks ?? accent.light }
    func markOffset(_ effect: Effect) -> CGPoint { species.markOffsets[effect] ?? .zero }

    func look(for state: CharacterState) -> Look {
        var look = Choreography.look(for: state)
        SoftExpressions.adapt(&look, for: state, face: species.face)
        if let item = species.held, state == .idle {
            look.pose.holding = 1
            if let left = item.arms.0 { look.pose.armL = left }
            if let right = item.arms.1 { look.pose.armR = right }
        }
        return look
    }

    func dress(_ style: CharacterStyle) {
        accent = style.color
        let material = style.color.tint
        appendages.forEach { $0.draw(material) }
        for (container, mount) in [(backGear, Gear.Mount.back), (headGear, .head), (faceGear, .face), (bodyGear, .body)] {
            container.sublayers?.forEach { $0.removeFromSuperlayer() }
            for gear in species.gear where gear.mount == mount { container.addSublayer(gear.draw(material)) }
        }
        wardrobe.sublayers?.forEach { $0.removeFromSuperlayer() }
        if style.accessory == .scarf { wardrobe.addSublayer(Wardrobe.scarf(species.collar, material)) }
        self.style = style.accessory
        if case .screen = species.face.kind {
            (eyeMarks + browMarks + [mouthMark]).forEach { $0.tint(style.color.light) }
        }
    }

    // MARK: Posing

    func apply(_ next: Pose, _ transit: Transit) {
        let moved = transit.isInstant ? false : next != pose
        pose = next
        let bodyTransform = CGAffineTransform(translationX: next.shift, y: next.lift)
            .rotated(by: next.lean)
            .scaledBy(x: next.squash.width, y: next.squash.height)
        Motion.set(body, "transform", Motion.transform(bodyTransform), transit)
        armL.raise(next.armL, side: -1, transit)
        armR.raise(next.armR, side: 1, transit)

        let drop = next.feetDangle
        for (i, foot) in feet.enumerated() {
            let side: CGFloat = i == 0 ? -1 : 1
            Motion.set(foot, "transform", Motion.transform(
                CGAffineTransform(translationX: side * drop * 1.5, y: -drop * 4).rotated(by: side * drop * 0.35)), transit)
        }

        let faceTransit: Transit = transit.isInstant ? .instant : .ease(0.22)
        eyeMarks[0].show(next.eyeL, faceTransit, shine: next.shine)
        eyeMarks[1].show(next.eyeR, faceTransit, shine: next.shine)
        browMarks[0].show(next.browL, faceTransit)
        browMarks[1].show(next.browR, faceTransit)
        browMarks.forEach { Motion.set($0.layer, "opacity", Float(next.brows), faceTransit) }
        mouthMark.show(next.mouth, faceTransit)
        Motion.set(mouthMark.layer, "opacity", Float(next.mouthShown), faceTransit)
        Motion.set(held, "opacity", Float(next.holding), faceTransit)

        for (appendage, spec) in zip(appendages, species.appendages) {
            appendage.pose(spec.side < 0 ? next.earL : next.earR, transit)
        }
        // A new pose jolts the ears: they lag a moment behind the body.
        if moved { appendages.forEach { $0.flop(0.16, duration: 0.8) } }

        Motion.set(ground, "transform", Motion.transform(
            CGAffineTransform(scaleX: 0.55 + 0.45 * next.groundShadow, y: 0.7 + 0.3 * next.groundShadow)), transit)
        Motion.set(ground, "opacity", Float(0.3 + 0.7 * next.groundShadow), transit)
        updateGaze(transit.isInstant ? .instant : .ease(0.3))
    }

    func setGaze(_ vector: CGVector?, _ transit: Transit) {
        gaze = vector
        updateGaze(transit)
    }

    /// The eyes look; the head turns a little after them, the features a little further (parallax).
    private func updateGaze(_ transit: Transit) {
        var look = pose.look
        if let gaze {
            look.dx += gaze.dx * pose.gazeFollow
            look.dy += gaze.dy * pose.gazeFollow
        }
        look.dx = max(-1, min(1, look.dx))
        look.dy = max(-1, min(1, look.dy))
        let s = species.face.scale
        let turn = CGAffineTransform(translationX: look.dx * 2.2, y: look.dy * 1.4).rotated(by: -look.dx * 0.045)
        Motion.set(head, "transform", Motion.transform(turn), transit)
        Motion.set(crown, "transform", Motion.transform(turn), transit)
        Motion.set(face, "transform", Motion.transform(CGAffineTransform(translationX: look.dx * 3.5 * s, y: look.dy * 2.4 * s)), transit)
        let inside: CGFloat = if case .screen = species.face.kind { 5 } else { 2 }
        Motion.set(eyes, "transform", Motion.transform(CGAffineTransform(translationX: look.dx * inside * s, y: look.dy * inside * 0.6 * s)),
                   transit)
    }

    // MARK: Motion of its own

    func loops(for state: CharacterState) -> [Loop] {
        switch state {
        case .sleeping: []
        case .dragging: appendages.enumerated().map { i, a in a.swayLoop(fast: true, phase: Double(i) * 0.2) }
        default: appendages.enumerated().map { i, a in a.swayLoop(fast: false, phase: Double(i) * 1.1) }
        }
    }

    func follow(_ gesture: CharacterGesture) {
        switch gesture {
        case .hop: appendages.forEach { $0.flop(0.42, duration: 0.95) }
        case .nod: appendages.forEach { $0.flop(0.2, duration: 0.8) }
        case .shake: appendages.forEach { $0.swing(0.2, duration: 0.8) }
        case .wave: appendages.forEach { $0.swing(0.08, duration: 1.2) }
        case .lookAround: appendages.forEach { $0.swing(0.12, duration: 2.2) }
        case .blink: break
        }
    }

    // MARK: Hit testing

    func silhouette(extra: CGRect?) -> CGPath {
        var shape = trunk
        for appendage in appendages { shape = shape.union(appendage.outline) }
        for limb in [armL, armR] { shape = shape.union(limb.outline) }
        if style == .scarf { shape = shape.union(Wardrobe.scarfOutline(species.collar)) }
        if let extra { shape = shape.union(CGPath(rect: extra, transform: nil)) }
        let t = CGAffineTransform(translationX: Canvas.pivot.x + pose.shift, y: Canvas.pivot.y + pose.lift)
            .rotated(by: pose.lean)
            .scaledBy(x: pose.squash.width, y: pose.squash.height)
            .translatedBy(x: -Canvas.pivot.x, y: -Canvas.pivot.y)
        return Paths.transformed(shape, t)
    }

    /// The parts that never move relative to the body, merged once.
    private func makeTrunk() -> CGPath {
        var shape = species.torso
        if let head = species.head { shape = shape.union(head) }
        for center in species.feet {
            shape = shape.union(Paths.ellipse(center, species.foot.width / 2, species.foot.height / 2))
        }
        for gear in species.gear { if let outline = gear.outline { shape = shape.union(outline) } }
        return shape
    }
}
