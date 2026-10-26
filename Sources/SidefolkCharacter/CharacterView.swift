import AppKit

/// The companion on screen. A layer-hosting view: AppKit never redraws it; all motion is Core
/// Animation running on the render server. The only app-side timer is the blink scheduler.
/// `look` picks who is drawn and how it is dressed; everything else works the same for every companion.
@MainActor
public final class CharacterView: NSView {
    private var director = Director(CharacterLook(.sidefolk), live: true)
    private var blinkTimer: Timer?
    private var gaze: CGVector?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(director.stage)
        reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        director.reducedMotion = reducedMotion
        placeStage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("CharacterView is created in code") }

    // MARK: Public API

    /// Who is drawn. A new style redresses it in place; another companion crossfades in, in the
    /// same state, with the same badges.
    public var look = CharacterLook(.sidefolk) {
        didSet {
            guard look != oldValue else { return }
            if look.identity == director.identity {
                director.style = look.style
            } else {
                replaceDirector()
            }
        }
    }

    /// What VoiceOver calls the companion ("Mochi is listening").
    public var displayName = "Sidefolk"

    /// Setting this animates to the new state.
    public var state: CharacterState {
        get { director.state }
        set { setState(newValue, animated: true) }
    }

    private var occlusionObserver: NSObjectProtocol?

    public func setState(_ state: CharacterState, animated: Bool) {
        guard state != director.state else { return }
        director.show(state, animated: animated && window != nil)
        scheduleBlink()
        life?.noteInteraction()
        life?.refresh()
    }

    public func play(_ gesture: CharacterGesture) {
        director.wake()
        director.play(gesture)
        life?.noteInteraction()
    }

    /// Breathing resumes for a while (e.g. the pointer came close); calm states settle again later.
    public func wake() { director.wake() }

    /// Speaking: the mouth opens with `level`, the voice's loudness (0...1) as it plays; nil closes
    /// it. Driven by the audio, so it moves only while sound comes out.
    public func speak(_ level: Double?) {
        director.speak(level.map { CGFloat($0) })
    }

    /// Look direction, each axis -1...1 (x right, y up); nil looks straight ahead.
    /// Tiny changes are ignored so pointer jitter doesn't keep the eyes busy. A look normally wakes
    /// the breathing (something is near); `wakes: false` for a faint look at something far away.
    public func setGaze(_ vector: CGVector?, wakes: Bool = true) {
        let next = vector.map { CGVector(dx: max(-1, min(1, $0.dx)), dy: max(-1, min(1, $0.dy))) }
        switch (gaze, next) {
        case (nil, nil): return
        case let (old?, new?) where abs(old.dx - new.dx) < 0.06 && abs(old.dy - new.dy) < 0.06: return
        default: break
        }
        gaze = next
        if next != nil, wakes { director.wake() }
        director.setGaze(next)
    }

    /// No bobbing, hopping or sways; state changes crossfade; blinks become a quick fade; moments
    /// show only their faces and nothing starts on its own. Starts from the system's Reduce Motion setting.
    public var reducedMotion: Bool = false {
        didSet {
            director.reducedMotion = reducedMotion
            life?.refresh()
        }
    }

    // MARK: Life (docs/research/lively-companions.md)

    /// How much it does on its own. `.minimal` is the companion of D20; see `Liveliness`.
    public var liveliness: Liveliness = .minimal {
        didSet { if liveliness != oldValue { applyLiveliness() } }
    }

    /// Whether a notification startles it and finished work makes it cheer (the host asks).
    public var reactsToNews: Bool { liveliness.profile.newsReactions && !reducedMotion }

    /// Standing, sitting or lying down (idle only; any other state stands).
    public var posture: CharacterPosture { director.posture }

    public func setPosture(_ posture: CharacterPosture, animated: Bool) {
        director.setPosture(posture, animated: animated && window != nil)
    }

    /// The moment playing now, if any.
    public var performing: CharacterAntic? { director.performing }

    /// Plays a moment now (an answer to the person or the news, or a demo). `toward`, a screen
    /// point, aims a peek or a glance and picks the side it leans to.
    public func perform(_ antic: CharacterAntic, toward target: NSPoint? = nil) {
        perform(antic, toward: target, byItself: false)
    }

    /// Something happened to the companion (the pointer came close, a click, a drag): the quiet
    /// clock restarts and, sitting or lying down, it gets up (stretching after lying down).
    public func noteInteraction() {
        life?.noteInteraction()
        guard director.posture != .stand, state == .idle else { return }
        let wasLying = director.posture == .lie
        director.setPosture(.stand, animated: window != nil)
        if wasLying { perform(.stretch, toward: nil, byItself: true) }
    }

    /// The pointer moved, in screen coordinates: stroking the companion pets it. Hosts call this
    /// from their pointer monitor; away from the companion it costs a rectangle test.
    public func pointerMoved(toScreen point: NSPoint) {
        guard let window else { return }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        let inside = bounds.contains(local) && characterPath.contains(local)
        guard inside || stroking else { return }
        stroking = inside
        guard petting.add(local, inside: inside, at: CACurrentMediaTime()), Self.pettable(state), performing != .pet else { return }
        noteInteraction()
        // It leans into the hand: toward the side being stroked.
        let moment = Antics.pet
        director.perform(local.x > characterFrame.midX ? moment.flipped : moment, name: .pet)
    }

    /// Runs the idle scheduler's clock this many times faster: demos and the render tool only.
    public var lifePace: Double = 1 {
        didSet { life?.pace = lifePace }
    }

    private var life: Life?
    private var petting = PettingDetector()
    private var stroking = false
    /// What it senses of the desk (tests swap it).
    var surroundings: any Surroundings = Desktop()

    var isOnScreen: Bool { window?.occlusionState.contains(.visible) == true }

    static func pettable(_ state: CharacterState) -> Bool { state == .idle || state == .sleeping || state == .listening }

    func perform(_ antic: CharacterAntic, toward target: NSPoint?, byItself: Bool) {
        guard window != nil else { return }
        if !byItself { noteInteraction() }
        var moment = Antics.make(antic)
        if let target, let aim = gaze(toward: target) {
            // Lean and look toward the target; the moment's looks become that exact direction.
            if aim.dx < 0 { moment = moment.flipped }
            moment.looks = moment.looks.map { ($0.at, $0.look == nil ? nil : aim) }
        } else if byItself, Bool.random() {
            moment = moment.flipped
        }
        director.perform(moment, name: antic)
        if byItself, liveliness.profile.wakes { director.wake() }
    }

    /// The look direction (-1...1) from the companion toward a screen point.
    private func gaze(toward point: NSPoint) -> CGVector? {
        guard let window else { return nil }
        let center = window.convertToScreen(convert(characterFrame, to: nil))
        let dx = (point.x - center.midX) / 260, dy = (point.y - center.midY) / 260
        return CGVector(dx: max(-1, min(1, dx)), dy: max(-1, min(1, dy)))
    }

    private func applyLiveliness() {
        let profile = liveliness.profile
        director.settleDelay = profile.settleAfter
        guard profile.every != nil else {
            life?.stop()
            life = nil
            setPosture(.stand, animated: true)
            return
        }
        if let life {
            life.profile = profile
        } else {
            life = Life(profile: profile, view: self, senses: surroundings)
            life?.pace = lifePace
        }
        life?.refresh()
    }

    public var badges: Set<CharacterBadge> = [] {
        didSet { if badges != oldValue { director.setBadges(badges, animated: window != nil) } }
    }

    /// The visible outline in view coordinates (the robot's arms and held prop, a sprite's opaque
    /// pixels), for click-through.
    public var characterPath: CGPath {
        Paths.transformed(director.silhouette, canvasToView)
    }

    /// The body at rest in view coordinates: bubbles and panels attach to it, folks stand beside it.
    public var characterFrame: NSRect {
        director.restingFrame.applying(canvasToView)
    }

    /// What VoiceOver says about the companion, in the app's language (`name` is the companion's).
    public static func accessibilityLabel(for state: CharacterState, name: String = "Sidefolk") -> String {
        switch state {
        case .idle: String(localized: "\(name) is here")
        case .sleeping: String(localized: "\(name) is resting")
        case .listening: String(localized: "\(name) is listening")
        case .hearing: String(localized: "\(name) is listening to you", comment: "VoiceOver, while the microphone is on")
        case .thinking: String(localized: "\(name) is thinking")
        case .working(let prop): prop.activity(name)
        case .waiting: String(localized: "\(name) needs your approval")
        case .success: String(localized: "\(name) finished")
        case .error: String(localized: "\(name) hit a problem")
        case .alert: String(localized: "\(name) needs your attention")
        case .dragging: String(localized: "\(name) is being moved")
        case .celebrating: String(localized: "\(name) is celebrating")
        }
    }

    // MARK: Switching companions

    private func replaceDirector() {
        let old = director
        let next = Director(look, live: true)
        next.reducedMotion = reducedMotion
        next.settleDelay = liveliness.profile.settleAfter
        next.show(old.state, animated: false)
        next.setBadges(badges, animated: false)
        next.setGaze(gaze)
        if let window, !window.occlusionState.contains(.visible) { next.setPaused(true) }
        old.setPaused(true)
        if window != nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.25
            layer?.add(fade, forKey: "companion")
        }
        layer?.replaceSublayer(old.stage, with: next.stage)
        director = next
        placeStage()
        scheduleBlink()
    }

    // MARK: Layout

    public override var isFlipped: Bool { false }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeStage()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        placeStage()
        scheduleBlink()
        life?.refresh()
        occlusionObserver.map(NotificationCenter.default.removeObserver)
        occlusionObserver = nil
        guard let window else { return }
        // Nothing animates while the companion can't be seen (hidden, covered, other Space, screen off).
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                                   object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                self.director.setPaused(!window.occlusionState.contains(.visible))
                self.life?.refresh()
            }
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        placeStage()
    }

    /// Only the character itself takes clicks; the rest of the view is see-through.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return characterPath.contains(local) ? self : nil
    }

    private var fitScale: CGFloat {
        min(bounds.width / Canvas.size.width, bounds.height / Canvas.size.height)
    }

    private var canvasToView: CGAffineTransform {
        CGAffineTransform(translationX: bounds.midX, y: bounds.midY)
            .scaledBy(x: fitScale, y: fitScale)
            .translatedBy(x: -Canvas.size.width / 2, y: -Canvas.size.height / 2)
    }

    private func placeStage() {
        let scale = fitScale
        Motion.still {
            director.stage.position = CGPoint(x: bounds.midX, y: bounds.midY)
            director.stage.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            // Shape layers rasterize at contentsScale; match the pixels they actually cover.
            let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            director.contentsScale = max(backing * scale, 1)
        }
    }

    // MARK: Blinking

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        guard window != nil, director.blinks else { return }
        let timer = Timer(timeInterval: .random(in: 3...7), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.blinkNow() }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func blinkNow() {
        if window?.occlusionState.contains(.visible) == true {
            director.blink(twice: Int.random(in: 0..<5) == 0)
        }
        scheduleBlink()
    }

    // MARK: Accessibility

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .image }
    public override func accessibilityLabel() -> String? { Self.accessibilityLabel(for: state, name: displayName) }
}
