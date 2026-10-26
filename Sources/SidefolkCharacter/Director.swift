import QuartzCore

/// Runs a companion's figure: state changes, the loops each state needs, props, effects, badges
/// and gestures. Shared by the live view and the offscreen renderer (which only wants still frames).
@MainActor
final class Director {
    let rig: any Figure
    let species: CharacterSpecies
    var stage: CALayer { rig.stage }
    var restingFrame: CGRect { rig.restingFrame }

    /// Its colour and what it wears; the marks drawn in its light follow the figure's mark colour.
    var style: CharacterStyle {
        didSet {
            guard style != oldValue else { return }
            rig.dress(style)
            effects.light = rig.markLight
            sharpen()
        }
    }

    private let effects: Effects
    private let badgeChips: Badges
    /// False for offscreen renders: no animation of any kind is added.
    private let live: Bool

    private(set) var state: CharacterState = .idle
    private(set) var look = Look()
    private var badges: Set<CharacterBadge> = []
    private var prop: (kind: CharacterProp, rig: PropRig)?
    private var loops: [Loop] = []
    /// Calm states stop their loops after a while so the window server can rest (blinks continue).
    private var settleTimer: Timer?
    /// Hidden or fully covered: no loops at all.
    private var paused = false
    static let settleAfter: TimeInterval = 20

    var reducedMotion = false {
        didSet { if oldValue != reducedMotion { refreshMotion() } }
    }

    /// Pixels per canvas unit on screen. Layers added later (props, effects, badges) pick it up too.
    var contentsScale: CGFloat = 2 {
        didSet { if oldValue != contentsScale { sharpen() } }
    }

    /// Whether repeating motion runs at all.
    private var moving: Bool { live && !reducedMotion }

    init(_ look: CharacterLook, live: Bool) {
        self.live = live
        species = look.species
        style = look.style
        let rig = Species.figure(for: look.species)
        rig.dress(look.style)
        self.rig = rig
        effects = Effects(stage: rig.stageFX, body: rig.bodyFX, offset: { [unowned rig] in rig.markOffset($0) })
        effects.light = rig.markLight
        badgeChips = Badges(parent: rig.badges)
        show(.idle, animated: false)
    }

    var blinks: Bool { look.blinks }

    func show(_ next: CharacterState, animated: Bool) {
        let previous = state
        state = next
        look = rig.look(for: next)
        let animate = animated && live
        if animate && reducedMotion { crossfade(rig.stage) }
        let transit: Transit = animate && !reducedMotion ? .spring : .instant

        stopLoops(smooth: animate && !reducedMotion)
        setProp(look.prop, animated: animate)
        rig.apply(look.pose, transit)
        effects.show(look.effects, animated: animate, moving: moving)
        startLoops()
        sharpen()
        if animate, previous != next, let flourish = Choreography.entrance(for: next) { play(flourish) }
    }

    func setGaze(_ gaze: CGVector?) {
        rig.setGaze(gaze, live ? .ease(0.32) : .instant)
    }

    func setBadges(_ next: Set<CharacterBadge>, animated: Bool) {
        badges = next
        badgeChips.update(next, moving: moving, animated: animated && live)
        sharpen()
    }

    var silhouette: CGPath { rig.silhouette(extra: prop?.rig.frame) }

    // MARK: Gestures

    func play(_ gesture: CharacterGesture) {
        guard live else { return }
        if !reducedMotion { rig.follow(gesture) }
        switch gesture {
        case .blink:
            blink(twice: false)
        case .wave:
            let raise: [Double] = reducedMotion ? [0, 2.1, 0] : [0, 2.2, 1.8, 2.3, 1.8, 2.2, 0]
            let wave = reducedMotion
                ? Motion.keyframes("transform.rotation.z", raise, duration: 1.4, times: [0, 0.05, 0.85, 1], discrete: true)
                : Motion.keyframes("transform.rotation.z", raise, duration: 1.5, times: [0, 0.18, 0.34, 0.5, 0.66, 0.82, 1])
            wave.isAdditive = true
            rig.armR.pose.add(wave, forKey: "gesture")
        case .hop:
            guard !reducedMotion else { return }
            rig.gesture.add(Motion.keyframes("transform", [
                Motion.transform(.identity),
                Motion.transform(CGAffineTransform(scaleX: 1.08, y: 0.9)),
                Motion.transform(CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.95, y: 1.06)),
                Motion.transform(CGAffineTransform(scaleX: 1.06, y: 0.93)),
                Motion.transform(.identity),
            ], duration: 0.62, times: [0, 0.16, 0.5, 0.78, 1]), forKey: "gesture")
        case .nod:
            guard !reducedMotion else { return }
            rig.faceGesture.add(Motion.keyframes("transform.translation.y", [0, -4.5, 0, -3.5, 0], duration: 0.75),
                                forKey: "gesture")
            rig.gesture.add(Motion.keyframes("transform.scale.y", [1, 0.975, 1, 0.98, 1], duration: 0.75), forKey: "gesture")
        case .shake:
            guard !reducedMotion else { return }
            rig.faceGesture.add(Motion.keyframes("transform.translation.x", [0, -4.5, 4.5, -3.5, 3.5, 0], duration: 0.6),
                                forKey: "gesture")
            rig.gesture.add(Motion.keyframes("transform.rotation.z", [0, 0.035, -0.035, 0.025, -0.025, 0], duration: 0.6),
                            forKey: "gesture")
        case .lookAround:
            let values: [Double] = [0, -10, -10, 10, 10, 0]
            let scan = reducedMotion
                ? Motion.keyframes("transform.translation.x", [0, -10, 10, 0], duration: 2.2, times: [0, 0.05, 0.45, 0.85, 1],
                                   discrete: true)
                : Motion.keyframes("transform.translation.x", values, duration: 2.2, times: [0, 0.15, 0.4, 0.55, 0.8, 1])
            scan.isAdditive = true
            rig.scan.add(scan, forKey: "gesture")
            let question = effects.question()
            sharpen()
            question.add(Motion.keyframes("opacity", [0, 1, 1, 0], duration: 2.2, times: [0, 0.3, 0.85, 1]), forKey: "gesture")
        }
    }

    func blink(twice: Bool) {
        guard live, look.blinks else { return }
        if reducedMotion {
            rig.blink.add(Motion.keyframes("opacity", [1, 0.25, 1], duration: 0.22), forKey: "blink")
        } else if twice {
            rig.blink.add(Motion.keyframes("transform.scale.y", [1, 0.08, 1, 1, 0.08, 1], duration: 0.46,
                                           times: [0, 0.16, 0.34, 0.56, 0.74, 1]), forKey: "blink")
        } else {
            rig.blink.add(Motion.keyframes("transform.scale.y", [1, 0.08, 1], duration: 0.17, times: [0, 0.45, 1]),
                          forKey: "blink")
        }
    }

    // MARK: Internals

    private func setProp(_ kind: CharacterProp, animated: Bool) {
        guard prop?.kind != kind else { return }
        for container in [rig.propBack, rig.propFront] {
            if animated { crossfade(container) }
            container.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
        prop = nil
        guard let built = Props.make(kind) else { return }
        (built.overArms ? rig.propFront : rig.propBack).addSublayer(built.layer)
        prop = (kind, built)
    }

    private func startLoops() {
        settleTimer?.invalidate()
        settleTimer = nil
        guard moving, !paused else { return }
        loops = [breathing()] + Choreography.loops(for: state, figure: rig) + rig.loops(for: state) + (prop?.rig.loops ?? [])
        loops.forEach { $0.layer.add($0.animation, forKey: $0.key) }
        guard Self.settles(state) else { return }
        let timer = Timer(timeInterval: Self.settleAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    /// States whose motion carries no information after a while (busy states keep moving: that IS the message).
    static func settles(_ state: CharacterState) -> Bool {
        switch state {
        case .idle, .sleeping, .listening: true
        default: false
        }
    }

    private func settle() {
        settleTimer = nil
        stopLoops(smooth: true)
    }

    /// Something happened (a gesture, the pointer came close): breathe again for a while.
    func wake() {
        guard loops.isEmpty, moving, !paused else { return }
        startLoops()
    }

    /// The window is hidden or covered: stop everything; resume when visible again.
    func setPaused(_ hidden: Bool) {
        guard hidden != paused else { return }
        paused = hidden
        if hidden {
            settleTimer?.invalidate()
            settleTimer = nil
            stopLoops(smooth: false)
        } else {
            startLoops()
        }
    }

    /// Removes the running loops. When `smooth`, layers glide from where the loop left them
    /// back to rest instead of snapping (e.g. landing from a mid-air celebration hop).
    private func stopLoops(smooth: Bool) {
        var snapshots: [(CALayer, String, Any)] = []
        if smooth {
            var seen = Set<ObjectIdentifier>()
            for layer in loops.map(\.layer) where seen.insert(ObjectIdentifier(layer)).inserted {
                guard let shown = layer.presentation() else { continue }
                snapshots.append((layer, "transform", NSValue(caTransform3D: shown.transform)))
                snapshots.append((layer, "opacity", shown.opacity))
            }
        }
        loops.forEach { $0.layer.removeAnimation(forKey: $0.key) }
        loops = []
        for (layer, keyPath, from) in snapshots {
            guard let model = layer.value(forKeyPath: keyPath), !(model as AnyObject).isEqual(from) else { continue }
            let settle = CABasicAnimation(keyPath: keyPath)
            settle.fromValue = from
            settle.toValue = model
            settle.duration = 0.25
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(settle, forKey: "settle")
        }
    }

    private func breathing() -> Loop {
        let (sx, sy, duration): (CGFloat, CGFloat, CFTimeInterval) = look.breath == .calm ? (0.992, 1.022, 1.8) : (0.986, 1.045, 2.8)
        let animation = Motion.loop("transform", from: Motion.transform(.identity),
                                    to: Motion.transform(CGAffineTransform(scaleX: sx, y: sy)), duration: duration)
        return Loop(layer: rig.breath, key: "breath", animation: animation)
    }

    private func refreshMotion() {
        stopLoops(smooth: false)
        effects.show([], animated: false, moving: false)
        effects.show(look.effects, animated: false, moving: moving)
        setBadges(badges, animated: false)
        let kind = look.prop
        setProp(.none, animated: false)
        setProp(kind, animated: false)
        startLoops()
        sharpen()
    }

    private func sharpen() {
        if live { Layers.setContentsScale(contentsScale, in: rig.stage) }
    }

    private func crossfade(_ layer: CALayer) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.2
        layer.add(transition, forKey: "crossfade")
    }
}
