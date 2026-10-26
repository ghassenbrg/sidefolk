import AppKit

/// The companion on screen. A layer-hosting view: AppKit never redraws it; all motion is Core
/// Animation running on the render server. The only app-side timer is the blink scheduler.
/// `look` picks who is drawn (the vector robot or a sprite companion); everything else works the
/// same for both.
@MainActor
public final class CharacterView: NSView {
    private var performer: any Performer = Director(live: true)
    private var blinkTimer: Timer?
    private var gaze: CGVector?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(performer.stage)
        reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        performer.reducedMotion = reducedMotion
        placeStage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("CharacterView is created in code") }

    // MARK: Public API

    /// Who is drawn. Changing the robot's accent recolours it in place; changing the companion
    /// crossfades to the other one in the same state, with the same badges.
    public var look: CharacterLook = .sidefolk(.aqua) {
        didSet {
            guard look != oldValue else { return }
            switch (oldValue, look, performer) {
            case (.sidefolk, .sidefolk(let accent), let director as Director):
                director.accent = accent
            default:
                replacePerformer()
            }
        }
    }

    /// What VoiceOver calls the companion ("Mochi is listening").
    public var displayName = "Sidefolk"

    /// Setting this animates to the new state.
    public var state: CharacterState {
        get { performer.state }
        set { setState(newValue, animated: true) }
    }

    private var occlusionObserver: NSObjectProtocol?

    public func setState(_ state: CharacterState, animated: Bool) {
        guard state != performer.state else { return }
        performer.show(state, animated: animated && window != nil)
        scheduleBlink()
    }

    public func play(_ gesture: CharacterGesture) {
        performer.wake()
        performer.play(gesture)
    }

    /// Breathing resumes for a while (e.g. the pointer came close); calm states settle again later.
    public func wake() { performer.wake() }

    /// Look direction, each axis -1...1 (x right, y up); nil looks straight ahead.
    /// Tiny changes are ignored so pointer jitter doesn't keep the eyes busy.
    public func setGaze(_ vector: CGVector?) {
        let next = vector.map { CGVector(dx: max(-1, min(1, $0.dx)), dy: max(-1, min(1, $0.dy))) }
        switch (gaze, next) {
        case (nil, nil): return
        case let (old?, new?) where abs(old.dx - new.dx) < 0.06 && abs(old.dy - new.dy) < 0.06: return
        default: break
        }
        gaze = next
        if next != nil { performer.wake() }
        performer.setGaze(next)
    }

    /// No bobbing, hopping or sways; state changes crossfade; blinks become a quick fade.
    /// Starts from the system's Reduce Motion setting.
    public var reducedMotion: Bool = false {
        didSet { performer.reducedMotion = reducedMotion }
    }

    public var badges: Set<CharacterBadge> = [] {
        didSet { if badges != oldValue { performer.setBadges(badges, animated: window != nil) } }
    }

    /// The visible outline in view coordinates (the robot's arms and held prop, a sprite's opaque
    /// pixels), for click-through.
    public var characterPath: CGPath {
        Paths.transformed(performer.silhouette, canvasToView)
    }

    /// The body at rest in view coordinates: bubbles and panels attach to it, folks stand beside it.
    public var characterFrame: NSRect {
        performer.restingFrame.applying(canvasToView)
    }

    public static func accessibilityLabel(for state: CharacterState, name: String = "Sidefolk") -> String {
        switch state {
        case .idle: "\(name) is here"
        case .sleeping: "\(name) is resting"
        case .listening: "\(name) is listening"
        case .thinking: "\(name) is thinking"
        case .working(let prop): "\(name) is \(prop.activity)"
        case .waiting: "\(name) needs your approval"
        case .success: "\(name) finished"
        case .error: "\(name) hit a problem"
        case .alert: "\(name) needs your attention"
        case .dragging: "\(name) is being moved"
        case .celebrating: "\(name) is celebrating"
        }
    }

    // MARK: Switching companions

    private func replacePerformer() {
        let old = performer
        let next = look.performer(live: true)
        next.reducedMotion = reducedMotion
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
        performer = next
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
        occlusionObserver.map(NotificationCenter.default.removeObserver)
        occlusionObserver = nil
        guard let window else { return }
        // Nothing animates while the companion can't be seen (hidden, covered, other Space, screen off).
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                                   object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                self.performer.setPaused(!window.occlusionState.contains(.visible))
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
            performer.stage.position = CGPoint(x: bounds.midX, y: bounds.midY)
            performer.stage.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            // Shape layers rasterize at contentsScale; match the pixels they actually cover.
            let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            performer.contentsScale = max(backing * scale, 1)
        }
    }

    // MARK: Blinking

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        guard window != nil, performer.blinks else { return }
        let timer = Timer(timeInterval: .random(in: 3...7), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.blinkNow() }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func blinkNow() {
        if window?.occlusionState.contains(.visible) == true {
            performer.blink(twice: Int.random(in: 0..<5) == 0)
        }
        scheduleBlink()
    }

    // MARK: Accessibility

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .image }
    public override func accessibilityLabel() -> String? { Self.accessibilityLabel(for: state, name: displayName) }
}
