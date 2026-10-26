import QuartzCore

/// Runs a sprite companion (DECISIONS D27): one image layer showing the current pose, short
/// crossfades between poses, pose pairs that take turns in busy states, and the vector rig's rules
/// for motion: breathe, settle after `Director.settleAfter` in calm states (an idle sprite sits
/// down, as in the legacy app), loops capped by `Motion`, nothing while hidden.
@MainActor
final class SpriteDirector: Performer {
    let stage = Layers.canvas(anchor: pt(100, 100))
    private let art: SpriteSet
    private let live: Bool

    private let ground = CAGradientLayer()
    /// Lift and the lean toward the pointer, as model values.
    private let body = Layers.canvas()
    /// Swings around the top of the head while dragged.
    private let swing: CALayer
    /// The state's repeating motion, one-shot gestures and breathing never share a key path.
    private let loop = Layers.canvas()
    private let gesture = Layers.canvas()
    private let breath = Layers.canvas()
    private let sprite = CALayer()
    private let badgeLayer = Layers.canvas()
    private let badgeChips: Badges

    private(set) var state: CharacterState = .idle
    private var look = SpriteLook()
    private var badges: Set<CharacterBadge> = []
    private var lean: CGFloat = 0
    /// An idle companion that has settled sits down until something happens.
    private var seated = false
    private var loops: [Loop] = []
    private var settleTimer: Timer?
    private var paused = false

    var reducedMotion = false {
        didSet { if oldValue != reducedMotion { refreshMotion() } }
    }

    var contentsScale: CGFloat = 2 {
        didSet { if oldValue != contentsScale { sharpen() } }
    }

    private var moving: Bool { live && !reducedMotion }

    init(art: SpriteSet, live: Bool) {
        self.art = art
        self.live = live
        swing = Layers.canvas(anchor: pt(100, art.restingFrame.maxY))
        badgeChips = Badges(parent: badgeLayer)
        build()
        show(.idle, animated: false)
    }

    private func build() {
        let width = art.restingFrame.width
        ground.type = .radial
        ground.frame = CGRect(x: 100 - width * 0.55, y: Canvas.floor - 7, width: width * 1.1, height: 14)
        ground.colors = [Palette.ink.cg(0.22), Palette.ink.cg(0.1), Palette.ink.cg(0)]
        ground.locations = [0, 0.5, 1]
        ground.startPoint = CGPoint(x: 0.5, y: 0.5)
        ground.endPoint = CGPoint(x: 1, y: 1)
        stage.addSublayer(ground)

        // Every pose is a whole-canvas bitmap (SpriteSet), so one frame fits them all.
        sprite.frame = CGRect(origin: .zero, size: Canvas.size)
        // Drawn at the largest size shown: mipmaps keep the edges smooth at the small ones.
        sprite.minificationFilter = .trilinear
        stage.addSublayer(body)
        body.addSublayer(swing)
        swing.addSublayer(loop)
        loop.addSublayer(gesture)
        gesture.addSublayer(breath)
        breath.addSublayer(sprite)
        stage.addSublayer(badgeLayer)
    }

    var blinks: Bool { state == .idle }
    var restingFrame: CGRect { art.restingFrame }

    /// The poses on screen (any of a pair), at the current lift and lean.
    var silhouette: CGPath {
        let shape = CGMutablePath()
        // Rectangles all wind the same way, so overlapping poses stay one filled area.
        for pose in shownPoses { shape.addPath(art.silhouette(pose)) }
        return Paths.transformed(shape, placement)
    }

    private var shownPoses: [SpritePose] { seated ? [.sit] : look.poses }

    /// Pose changes crossfade this long: reads as one movement without blurring the two poses.
    private static let fade: CFTimeInterval = 0.22

    private var placement: CGAffineTransform {
        CGAffineTransform(translationX: Canvas.pivot.x, y: Canvas.pivot.y + look.lift)
            .rotated(by: lean)
            .translatedBy(x: -Canvas.pivot.x, y: -Canvas.pivot.y)
    }

    // MARK: States

    func show(_ next: CharacterState, animated: Bool) {
        let previous = state
        state = next
        look = SpriteChoreography.look(for: next)
        seated = false
        let animate = animated && live
        stopLoops(smooth: animate && !reducedMotion)
        sprite.removeAnimation(forKey: "gesture")
        sprite.removeAnimation(forKey: "blink")
        showPose(look.poses[0], animated: animate)
        let transit: Transit = animate && !reducedMotion ? .spring : .instant
        Motion.set(ground, "transform", Motion.transform(
            CGAffineTransform(scaleX: 0.55 + 0.45 * look.shadow, y: 0.7 + 0.3 * look.shadow)), transit)
        Motion.set(ground, "opacity", Float(0.3 + 0.7 * look.shadow), transit)
        if !look.followsPointer { lean = 0 }
        place(transit)
        startLoops()
        if animate, previous != next, let flourish = Choreography.entrance(for: next) { play(flourish) }
    }

    /// Shows `pose` as the model value, crossfading from whatever is on screen.
    private func showPose(_ pose: SpritePose, animated: Bool) {
        let image = art.image(pose)
        let shown = sprite.presentation()?.contents ?? sprite.contents
        Motion.still { sprite.contents = image }
        guard animated, let shown else { return }
        let fade = CABasicAnimation(keyPath: "contents")
        fade.fromValue = shown
        fade.toValue = image
        fade.duration = Self.fade
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sprite.add(fade, forKey: "fade")
    }

    private func place(_ transit: Transit) {
        let lifted = CGAffineTransform(translationX: 0, y: look.lift)
        Motion.set(body, "transform", Motion.transform(lifted.rotated(by: lean)), transit)
    }

    /// No eyes to move: the body leans a couple of degrees toward the pointer instead.
    func setGaze(_ gaze: CGVector?) {
        let next = look.followsPointer ? -(gaze?.dx ?? 0) * 0.035 : 0
        guard next != lean else { return }
        lean = next
        place(live ? .ease(0.4) : .instant)
    }

    func setBadges(_ next: Set<CharacterBadge>, animated: Bool) {
        badges = next
        badgeChips.update(next, moving: moving, animated: animated && live)
        sharpen()
    }

    // MARK: Gestures

    func play(_ gesture: CharacterGesture) {
        guard live else { return }
        switch gesture {
        case .blink:
            blink(twice: false)
        case .wave:
            flash(.wave, for: 1.5)
        case .lookAround:
            // The head tilt reads as "hm?".
            flash(.listen, for: 2.0)
        case .hop:
            guard !reducedMotion else { return }
            self.gesture.add(Motion.keyframes("transform", [
                Motion.transform(.identity),
                Motion.transform(CGAffineTransform(scaleX: 1.08, y: 0.9)),
                Motion.transform(CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.95, y: 1.06)),
                Motion.transform(CGAffineTransform(scaleX: 1.06, y: 0.93)),
                Motion.transform(.identity),
            ], duration: 0.62, times: [0, 0.16, 0.5, 0.78, 1]), forKey: "gesture")
        case .nod:
            guard !reducedMotion else { return }
            self.gesture.add(Motion.keyframes("transform.scale.y", [1, 0.96, 1, 0.97, 1], duration: 0.75), forKey: "gesture")
        case .shake:
            guard !reducedMotion else { return }
            self.gesture.add(Motion.keyframes("transform.rotation.z", [0, 0.045, -0.045, 0.03, -0.03, 0], duration: 0.6),
                             forKey: "gesture")
        }
    }

    func blink(twice: Bool) {
        guard live, state == .idle, !seated else { return }
        let closed = art.image(.blink), open = art.image(.idle)
        let blink = twice
            ? Motion.keyframes("contents", [closed, open, closed], duration: 0.5, times: [0, 0.32, 0.62, 1], discrete: true)
            : Motion.keyframes("contents", [closed], duration: 0.16, times: [0, 1], discrete: true)
        sprite.add(blink, forKey: "blink")
    }

    /// Shows another pose for a moment over the state's own (a discrete swap, also under reduced motion).
    private func flash(_ other: SpritePose, for duration: CFTimeInterval) {
        sprite.add(Motion.keyframes("contents", [art.image(other)], duration: duration, times: [0, 1], discrete: true),
                   forKey: "gesture")
    }

    // MARK: Loops and settling (D20)

    private func startLoops() {
        settleTimer?.invalidate()
        settleTimer = nil
        guard moving, !paused else { return }
        loops = [breathing()] + SpriteChoreography.loops(for: state, loop: loop, swing: swing)
        if look.poses.count > 1 {
            let count = Double(look.poses.count)
            let turns = Motion.cycle("contents", look.poses.map { art.image($0) }, duration: look.beat * count,
                                     times: (0...look.poses.count).map { Double($0) / count }, discrete: true)
            // Added later, it would hide the crossfade into the state; start when that ends.
            if sprite.animation(forKey: "fade") != nil {
                turns.beginTime = sprite.convertTime(CACurrentMediaTime(), from: nil) + Self.fade
            }
            loops.append(Loop(layer: sprite, key: "turns", animation: turns))
        }
        loops.forEach { $0.layer.add($0.animation, forKey: $0.key) }
        guard Director.settles(state) else { return }
        let timer = Timer(timeInterval: Director.settleAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private func settle() {
        settleTimer = nil
        stopLoops(smooth: true)
        guard state == .idle else { return }
        seated = true
        showPose(.sit, animated: true)
    }

    func wake() {
        guard loops.isEmpty, moving, !paused else { return }
        standUp()
        startLoops()
    }

    func setPaused(_ hidden: Bool) {
        guard hidden != paused else { return }
        paused = hidden
        if hidden {
            settleTimer?.invalidate()
            settleTimer = nil
            stopLoops(smooth: false)
        } else {
            standUp()
            startLoops()
        }
    }

    private func standUp() {
        guard seated else { return }
        seated = false
        showPose(look.poses[0], animated: live)
    }

    /// Removes the running loops; when `smooth`, transforms glide back to rest instead of snapping.
    private func stopLoops(smooth: Bool) {
        var snapshots: [(CALayer, Any)] = []
        if smooth {
            var seen = Set<ObjectIdentifier>()
            // The sprite's own loop swaps images; there is no transform to glide back.
            for layer in loops.map(\.layer) where layer !== sprite && seen.insert(ObjectIdentifier(layer)).inserted {
                guard let shown = layer.presentation() else { continue }
                snapshots.append((layer, NSValue(caTransform3D: shown.transform)))
            }
        }
        loops.forEach { $0.layer.removeAnimation(forKey: $0.key) }
        loops = []
        for (layer, from) in snapshots {
            let settle = CABasicAnimation(keyPath: "transform")
            settle.fromValue = from
            settle.toValue = NSValue(caTransform3D: layer.transform)
            settle.duration = 0.25
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(settle, forKey: "settle")
        }
    }

    private func breathing() -> Loop {
        // Gentler than the vector shell's: a stretched photo-like render looks rubbery sooner.
        let (sx, sy, duration): (CGFloat, CGFloat, CFTimeInterval) = look.breath == .calm ? (0.995, 1.014, 1.8) : (0.99, 1.028, 2.8)
        let animation = Motion.loop("transform", from: Motion.transform(.identity),
                                    to: Motion.transform(CGAffineTransform(scaleX: sx, y: sy)), duration: duration)
        return Loop(layer: breath, key: "breath", animation: animation)
    }

    private func refreshMotion() {
        stopLoops(smooth: false)
        if seated {
            seated = false
            showPose(look.poses[0], animated: false)
        }
        setBadges(badges, animated: false)
        startLoops()
    }

    private func sharpen() {
        if live { Layers.setContentsScale(contentsScale, in: stage) }
    }
}
