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
    /// The species' drawing scale around the floor point; `body` below it holds the pose.
    private let fit = Layers.canvas()
    /// Lifts a floating companion off the floor and bobs it, under the pose.
    private let hover = Layers.canvas()
    private let body = Layers.canvas()
    private let ground = CAGradientLayer()
    private let feet: [CALayer]
    /// Ears and sprouts behind the head, and the head itself: both turn the same way.
    private let crown: CALayer
    private let head: CALayer
    /// Inside each: the pose's droop (asleep), then tilts and nods of antics, around the neck (gaze owns the
    /// outer transform).
    private let crownDroop: CALayer
    private let headDroop: CALayer
    private let crownTilt: CALayer
    private let headTilt: CALayer
    /// Eyes, brows and mouth; gaze slides this a little further than the head (parallax).
    private let face: CALayer
    private let eyes = Layers.canvas()
    private let appendages: [Appendage]
    private let tails: [Appendage]
    private let eyeMarks: [FaceMark]
    private let browMarks: [FaceMark]
    private let mouthMark: FaceMark
    private let backGear = Layers.canvas()
    private let headGear = Layers.canvas()
    private let skinGear = Layers.canvas()
    private let underGear = Layers.canvas()
    private let faceGear = Layers.canvas()
    private let bodyGear = Layers.canvas()
    /// The signature thing in hand: under the arms or over them, as the species draws it.
    private let held = Layers.canvas()
    private let wardrobe = Layers.canvas()
    private lazy var trunk: CGPath = makeTrunk()

    private(set) var pose = Pose()
    private var gaze: CGVector?
    /// How open the mouth is while speaking; nil when silent.
    private var speaking: CGFloat?
    private var style = CharacterAccessory.none
    private var accent = CharacterAccent.aqua

    init(_ species: Species) {
        self.species = species
        let neck = species.neck
        crown = Layers.canvas(anchor: neck)
        head = Layers.canvas(anchor: neck)
        crownDroop = Layers.canvas(anchor: neck)
        headDroop = Layers.canvas(anchor: neck)
        crownTilt = Layers.canvas(anchor: neck)
        headTilt = Layers.canvas(anchor: neck)
        face = Layers.canvas(anchor: neck)
        let (eyeL, eyeR) = species.face.eyes
        blink = Layers.canvas(anchor: pt(100, (eyeL.y + eyeR.y) / 2))
        armL = Limb(shoulder: species.shoulders.0, style: species.arm, side: -1, painted: species.painting?.arms?.0)
        armR = Limb(shoulder: species.shoulders.1, style: species.arm, painted: species.painting?.arms?.1)
        feet = species.feet.map { Layers.canvas(anchor: $0 + pt(0, species.foot.height * 0.7)) }
        appendages = species.appendages.map(Appendage.init)
        tails = species.tails.map(Appendage.init)
        let scale = species.face.scale
        switch species.face.kind {
        case .ink:
            let ink = species.face.ink ?? Palette.eyeInk
            if let iris = species.face.iris {
                // Both catchlights on the side the light comes from (upper left), as in the flat shading.
                eyeMarks = [eyeL, eyeR].map { FaceMark(center: $0, ink: ink, iris: iris, scale: scale, side: -1, size: species.face.eyeSize) }
            } else {
                eyeMarks = [eyeL, eyeR].map { FaceMark(center: $0, ink: ink, shine: true, scale: scale) }
            }
            browMarks = [eyeL, eyeR].map { FaceMark(center: $0, ink: ink, shine: false, scale: scale) }
            mouthMark = FaceMark(center: species.face.mouth, ink: ink, shine: false, scale: scale)
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
        let width = restingFrame.width * (species.hover > 0 ? 0.75 : 0.95)
        ground.frame = CGRect(x: 100 - width / 2, y: Canvas.floor - 7.5, width: width, height: 15)
        ground.colors = [Palette.ink.cg(0.24), Palette.ink.cg(0.11), Palette.ink.cg(0)]
        ground.locations = [0, 0.5, 1]
        // A 2D companion's shadow is one flat soft-edged oval, smaller the higher it floats.
        if species.flat {
            ground.colors = [Palette.ink.cg(0.16), Palette.ink.cg(0.15), Palette.ink.cg(0)]
            ground.locations = [0, 0.82, 1]
        }
        ground.startPoint = CGPoint(x: 0.5, y: 0.5)
        ground.endPoint = CGPoint(x: 1, y: 1)
        stage.addSublayer(ground)

        fit.setAffineTransform(CGAffineTransform(scaleX: species.scale, y: species.scale))
        stage.addSublayer(fit)
        fit.addSublayer(hover)
        hover.setAffineTransform(CGAffineTransform(translationX: 0, y: species.hover))
        hover.addSublayer(body)
        body.addSublayer(loop)
        loop.addSublayer(gesture)
        gesture.addSublayer(breath)

        let footShading = species.footShading ?? species.shading
        let paintedFeet = species.painting?.feet.map { [$0.0, $0.1] }
        for (i, (layer, center)) in zip(feet, species.feet).enumerated() {
            if var painted = paintedFeet?[i] {
                painted.rect = painted.rect.offsetBy(dx: center.x, dy: center.y)
                layer.addSublayer(painted.layer)
            } else {
                let foot = SoftShape(footOutline(center), shading: footShading)
                foot.shadow(radius: 2, opacity: 0.14, offset: CGSize(width: 0, height: -1))
                if let edge = species.edge { foot.outline(edge, alpha: 0.4, width: 0.7) }
                layer.addSublayer(foot.layer)
            }
        }
        // Painted legs reach down to the ankles: painted feet go in front of them, as paws are drawn; flat feet
        // tuck in behind the body.
        if paintedFeet == nil { feet.forEach(breath.addSublayer) }

        crown.addSublayer(crownDroop)
        crownDroop.addSublayer(crownTilt)
        crownTilt.addSublayer(backGear)
        appendages.forEach { crownTilt.addSublayer($0.root) }
        breath.addSublayer(crown)
        tails.forEach { breath.addSublayer($0.root) }
        breath.addSublayer(species.painting?.torso?.layer ?? soft(species.torso, shadow: 5))
        if paintedFeet != nil { feet.forEach(breath.addSublayer) }
        breath.addSublayer(bodyGear)
        breath.addSublayer(wardrobe)

        head.addSublayer(headDroop)
        headDroop.addSublayer(headTilt)
        if let shape = species.head {
            headTilt.addSublayer(species.painting?.head?.layer ?? soft(shape, shadow: 4, shading: species.headShading))
        }
        headTilt.addSublayer(skinGear)
        headTilt.addSublayer(face)
        face.addSublayer(faceGesture)
        // A painted head brings its own screen.
        if case .screen(let rect, let radius) = species.face.kind, species.painting?.head == nil {
            faceGesture.addSublayer(species.flat ? Self.flatScreen(rect, radius) : Self.screen(rect, radius))
        }
        faceGesture.addSublayer(underGear)
        if species.face.cheeks {
            let s = species.face.scale, (eyeL, eyeR) = species.face.eyes
            let under = { (eye: CGPoint) in eye + pt(eye.x < 100 ? -3 * s : 3 * s, -10 * s) }
            let spots = species.face.blushAt.map { [$0.0, $0.1] } ?? (species.face.single ? [under(eyeL)] : [under(eyeL), under(eyeR)])
            let size = species.face.blushSize
            for spot in spots {
                faceGesture.addSublayer(Layers.shape(Paths.ellipse(spot, size.width * s, size.height * s),
                                                     fill: (species.face.blush ?? Palette.blush).cg(species.flat ? 0.6 : 0.42)))
            }
        }
        faceGesture.addSublayer(eyes)
        eyes.addSublayer(scan)
        scan.addSublayer(blink)
        eyeMarks.forEach { blink.addSublayer($0.layer) }
        browMarks.forEach { blink.addSublayer($0.layer) }
        if species.face.single { [eyeMarks[1], browMarks[1]].forEach { $0.layer.isHidden = true } }
        mouthMark.layer.setAffineTransform(CGAffineTransform(scaleX: species.face.mouthSize, y: species.face.mouthSize))
        scan.addSublayer(mouthMark.layer)
        if let nose = species.face.nose {
            scan.addSublayer(Layers.shape(Paths.ellipse(pt(nose.midX, nose.midY), nose.width / 2, nose.height / 2),
                                          fill: (species.face.noseColor ?? species.face.ink ?? Palette.eyeInk).cg()))
        }
        faceGesture.addSublayer(faceGear)
        headTilt.addSublayer(headGear)
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

    func showBody(_ on: Bool) {
        breath.sublayers?.forEach { if $0 !== bodyFX { $0.isHidden = !on } }
        ground.isHidden = !on
    }

    private func footOutline(_ center: CGPoint) -> CGPath {
        species.footShape.map { Paths.translated($0, center.x, center.y) }
            ?? Paths.ellipse(center, species.foot.width / 2, species.foot.height / 2)
    }

    /// A body part in the species' shading, with its soft drop shadow and edge.
    private func soft(_ path: CGPath, shadow: CGFloat, shading: Shading? = nil) -> CALayer {
        let shape = SoftShape(path, shading: shading ?? species.shading)
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

    /// The 2D screen: flat dark glass with one hard band of reflection across its top and an outline.
    private static func flatScreen(_ rect: CGRect, _ radius: CGFloat) -> CALayer {
        let glass = Layers.canvas()
        let path = Paths.roundedRect(rect, radius)
        glass.addSublayer(Layers.shape(path, fill: Palette.visorMid.cg()))
        glass.addSublayer(Layers.shape(path.subtracting(Paths.translated(path, -2.5, 5)), fill: Palette.visorBottom.cg()))
        let band = CGMutablePath()
        band.move(to: pt(rect.minX + 9, rect.maxY - 6))
        band.addQuadCurve(to: pt(rect.minX + 26, rect.maxY - 6), control: pt(rect.minX + 17, rect.maxY - 4))
        glass.addSublayer(Layers.shape(band, stroke: RGB.white.cg(0.55), lineWidth: 3))
        glass.addSublayer(Layers.shape(Paths.circle(pt(rect.minX + 32, rect.maxY - 6.5), 1.6), fill: RGB.white.cg(0.55)))
        glass.addSublayer(Layers.shape(path, stroke: Flat.line(Palette.visorTop).cg(), lineWidth: 2))
        return glass
    }

    // MARK: Figure

    var restingFrame: CGRect { species.restingFrame.applying(fitting) }

    /// Canvas units as the species drew them to canvas units on the stage.
    private var fitting: CGAffineTransform {
        CGAffineTransform(translationX: Canvas.pivot.x, y: Canvas.pivot.y).scaledBy(x: species.scale, y: species.scale)
            .translatedBy(x: -Canvas.pivot.x, y: -Canvas.pivot.y)
    }
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
        (appendages + tails).forEach { $0.draw(material) }
        for (container, mount) in [(backGear, Gear.Mount.back), (headGear, .head), (skinGear, .skin), (underGear, .under), (faceGear, .face),
                                (bodyGear, .body)] {
            container.sublayers?.forEach { $0.removeFromSuperlayer() }
            for gear in species.gear where gear.mount == mount { container.addSublayer(gear.draw(material)) }
        }
        wardrobe.sublayers?.forEach { $0.removeFromSuperlayer() }
        if style.accessory == .scarf { wardrobe.addSublayer(Wardrobe.scarf(species.collar, material, flat: species.flat)) }
        self.style = style.accessory
        if case .screen = species.face.kind {
            (eyeMarks + browMarks + [mouthMark]).forEach { $0.tint(style.color.light) }
        }
    }

    // MARK: Posing

    func apply(_ next: Pose, _ transit: Transit) {
        // Only a new pose jolts the ears; a face changing for a moment (an ease) doesn't.
        let moved = transit.isSpring && next != pose
        pose = next
        Motion.set(body, "transform", Motion.transform(bodyTransform(next)), transit)
        Motion.set(headDroop, "transform", Motion.transform(droop(next)), transit)
        Motion.set(crownDroop, "transform", Motion.transform(droop(next)), transit)
        armL.raise(next.armL - species.armTuck, side: -1, transit)
        armR.raise(next.armR - species.armTuck, side: 1, transit)

        for (i, foot) in feet.enumerated() {
            Motion.set(foot, "transform", Motion.transform(Feet.transform(next, side: i == 0 ? -1 : 1)), transit)
            // Sitting, the feet come forward: in front of the belly instead of under it.
            foot.zPosition = next.feetSplay > 0.5 ? 1 : 0
        }

        let faceTransit: Transit = transit.isInstant ? .instant : .ease(0.22)
        eyeMarks[0].show(next.eyeL, faceTransit, shine: next.shine)
        eyeMarks[1].show(next.eyeR, faceTransit, shine: next.shine)
        browMarks[0].show(next.browL, faceTransit)
        browMarks[1].show(next.browR, faceTransit)
        browMarks.forEach { Motion.set($0.layer, "opacity", Float(next.brows), faceTransit) }
        showMouth(faceTransit)
        Motion.set(held, "opacity", Float(next.holding), faceTransit)

        for (appendage, spec) in zip(appendages, species.appendages) {
            appendage.pose(spec.side < 0 ? next.earL : next.earR, fold: next.earFold, transit)
        }
        // A tail droops with the ears (sad, asleep) and lifts when they perk up.
        let mood = (next.earL + next.earR) / 2
        tails.forEach { $0.pose(mood * 0.6, fold: 0, transit) }
        // A new pose jolts the ears: they lag a moment behind the body.
        if moved { (appendages + tails).forEach { $0.flop(0.16, duration: 0.8) } }

        Motion.set(ground, "transform", Motion.transform(
            CGAffineTransform(scaleX: 0.55 + 0.45 * next.groundShadow, y: 0.7 + 0.3 * next.groundShadow)), transit)
        Motion.set(ground, "opacity", Float(0.3 + 0.7 * next.groundShadow), transit)
        updateGaze(transit.isInstant ? .instant : .ease(0.3))
    }

    /// The body's pose around the floor point. A body without a head of its own droops as a whole: it leans
    /// and sinks by the head's tilt and drop.
    private func bodyTransform(_ pose: Pose) -> CGAffineTransform {
        let whole = species.head == nil
        return CGAffineTransform(translationX: pose.shift, y: pose.lift - (whole ? pose.headDrop * 0.6 : 0))
            .rotated(by: pose.lean - (whole ? pose.headTilt * 0.4 : 0))
            .scaledBy(x: pose.squash.width, y: pose.squash.height)
    }

    /// The head's droop around the neck (none for a body without a head of its own).
    private func droop(_ pose: Pose) -> CGAffineTransform {
        guard species.head != nil else { return .identity }
        return CGAffineTransform(translationX: 0, y: -pose.headDrop).rotated(by: -pose.headTilt)
    }

    func setGaze(_ vector: CGVector?, _ transit: Transit) {
        gaze = vector
        updateGaze(transit)
    }

    func talk(_ openness: CGFloat?, _ transit: Transit) {
        speaking = openness
        showMouth(transit)
    }

    /// The pose's mouth, or the open one while speaking (sized like the face's other marks).
    private func showMouth(_ transit: Transit) {
        if let open = speaking {
            mouthMark.show(Self.talkingMouth(open, width: 4.4 * species.face.scale), transit)
            Motion.set(mouthMark.layer, "opacity", Float(1), transit)
        } else {
            mouthMark.show(pose.mouth, transit)
            Motion.set(mouthMark.layer, "opacity", Float(pose.mouthShown), transit)
        }
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
        var loops: [Loop] = switch state {
        case .sleeping: [sleepNod]
        case .dragging: appendages.enumerated().map { i, a in a.swayLoop(fast: true, phase: Double(i) * 0.2) }
        default: appendages.enumerated().map { i, a in a.swayLoop(fast: false, phase: Double(i) * 1.1) }
        }
        // Tails wag when happy and swish slowly otherwise; asleep they rest.
        let wag = [.success, .celebrating, .dragging].contains(state)
        if state != .sleeping { loops += tails.enumerated().map { i, t in t.swayLoop(fast: wag, phase: 0.6 + Double(i) * 0.4, reach: 3) } }
        if species.hover > 0 {
            // Floating: a slow bob, slower and lower asleep.
            let h = species.hover, sleeping = state == .sleeping
            loops.append(Loop(layer: hover, key: "hover",
                              animation: Motion.loop("transform.translation.y", from: h - (sleeping ? 1 : 2.5), to: h + (sleeping ? 1 : 2.5),
                                                     duration: sleeping ? 3.4 : 2.1)))
        }
        return loops
    }

    /// Asleep, the head nods a little with each slow breath (the whole body, when it has no head of its own).
    private var sleepNod: Loop {
        let nod = Motion.loop("transform.rotation.z", from: 0.015, to: -0.035, duration: 2.8)
        nod.isAdditive = true
        return species.head == nil ? Loop(layer: loop, key: "nod", animation: nod) : Loop(layer: headDroop, key: "nod", animation: nod)
    }

    func follow(_ gesture: CharacterGesture) {
        switch gesture {
        case .hop: (appendages + tails).forEach { $0.flop(0.42, duration: 0.95) }
        case .nod: appendages.forEach { $0.flop(0.2, duration: 0.8) }
        case .shake: (appendages + tails).forEach { $0.swing(0.2, duration: 0.8) }
        case .wave: (appendages + tails).forEach { $0.swing(0.08, duration: 1.2) }
        case .lookAround: appendages.forEach { $0.swing(0.12, duration: 2.2) }
        case .blink: break
        }
    }

    // MARK: Antics

    func movers(_ part: Part) -> [Mover] {
        switch part {
        case .body: [Mover(layer: gesture)]
        case .face: [Mover(layer: faceGesture)]
        case .eyes: [Mover(layer: scan)]
        case .head: [Mover(layer: headTilt), Mover(layer: crownTilt)]
        case .armL: [Mover(layer: armL.loop, turn: -1)]
        case .armR: [Mover(layer: armR.loop, turn: 1)]
        // "Outward" turns a left ear counterclockwise; floppy ears follow more than stiff antennae.
        case .earL: appendages.filter { $0.spec.side < 0 }.map { Mover(layer: $0.trail, turn: $0.spec.floppiness) }
        case .earR: appendages.filter { $0.spec.side > 0 }.map { Mover(layer: $0.trail, turn: -$0.spec.floppiness) }
        }
    }

    func express(_ mood: Mood, on pose: Pose, mirrored: Bool) -> Pose {
        let ink = if case .ink = species.face.kind { true } else { false }
        return Moods.apply(mood, to: pose, ink: ink, scale: species.face.scale, mirrored: mirrored)
    }

    // MARK: Hit testing

    func silhouette(extra: CGRect?) -> CGPath {
        var shape = trunk
        // The head and what grows from it droop with it (asleep).
        let neck = species.neck
        let around = CGAffineTransform(translationX: -neck.x, y: -neck.y).concatenating(droop(pose))
            .concatenating(CGAffineTransform(translationX: neck.x, y: neck.y))
        if let head = species.head { shape = shape.union(Paths.transformed(head, around)) }
        for appendage in appendages { shape = shape.union(Paths.transformed(appendage.outline, around)) }
        for tail in tails { shape = shape.union(tail.outline) }
        for limb in [armL, armR] { shape = shape.union(limb.outline) }
        if style == .scarf { shape = shape.union(Wardrobe.scarfOutline(species.collar)) }
        if let extra { shape = shape.union(CGPath(rect: extra, transform: nil)) }
        let t = CGAffineTransform(translationX: -Canvas.pivot.x, y: -Canvas.pivot.y)
            .concatenating(bodyTransform(pose))
            .concatenating(CGAffineTransform(translationX: Canvas.pivot.x, y: Canvas.pivot.y + species.hover))
        return Paths.transformed(shape, t.concatenating(fitting))
    }

    /// The parts that never move relative to the body, merged once.
    private func makeTrunk() -> CGPath {
        var shape = species.torso
        for center in species.feet { shape = shape.union(footOutline(center)) }
        for gear in species.gear { if let outline = gear.outline { shape = shape.union(outline) } }
        return shape
    }
}
