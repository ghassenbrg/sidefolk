import AppKit
import SidefolkCharacter
import SidefolkCore

/// The transparent always-on-top window the companion lives in.
final class CompanionPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        canHide = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Allows peeking past the bottom edge of the screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// What the companion window tells the coordinator.
protocol CompanionDelegate: AnyObject {
    func companionClicked()
    func companionDoubleClicked()
    func companionMenu() -> NSMenu
    func companionDragChanged(_ dragging: Bool)
    func companionMoved()
    func companionReceived(_ drop: Attachment)
    func companionFolkClicked(_ folk: DutyFolk)
    func companionReadoutClicked()
    /// Pressing and holding the companion talks (D34), when voice input is on.
    var companionCanTalk: Bool { get }
    func companionHoldBegan()
    func companionHoldEnded()
}

final class CompanionWindowController {
    let panel = CompanionPanel()
    private let container: CompanionContainerView
    let character: CharacterView
    weak var delegate: CompanionDelegate?
    private var monitors: [Any] = []
    private var lastGazeUpdate = Date.distantPast
    private(set) var presence: PresenceMode = .always
    private(set) var peeking = false
    private var size: CGFloat = 76
    private var folkViews: [DutyFolk: FolkView] = [:]
    private var folkOrder: [DutyFolk] = []
    private var raiseTask: Task<Void, Never>?
    private var flightTimer: Timer?
    var eyesFollowPointer = true
    private let readouts = ReadoutPillsModel()
    private let readoutHost: ReadoutHostView

    init() {
        character = CharacterView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        container = CompanionContainerView(character: character)
        readoutHost = ReadoutHostView(rootView: ReadoutPills(model: readouts))
        readoutHost.isHidden = true
        container.addSubview(readoutHost)
        container.owner = self
        panel.contentView = container
    }

    // MARK: Layout

    /// The rig's square view: the body is ~62% of it; the margins hold props, effects and badges.
    /// A 3D companion gets a larger box (round heads and long ears read smaller than the 2D rig's
    /// at the same size); the undrawn 2D rig scales with it, so clicks still land on the body.
    private var characterBox: NSSize {
        let side = (size / 0.62 * (stage3D != nil ? 1.3 : 1)).rounded()
        return NSSize(width: side, height: side)
    }
    /// The feet stand 10% above the view's bottom edge.
    private var feetInset: CGFloat { characterBox.height * 0.1 }
    private var folkSize: CGFloat { (size * 0.62).rounded() }
    /// The live values stand above the folks' heads.
    private var readoutBase: CGFloat { feetInset + folkSize * 0.95 }
    private var readoutSize: NSSize { readouts.items.isEmpty ? .zero : readoutHost.fittingSize }
    /// Room beside the companion for the folks, or for the widest live value; tall enough for every value.
    private var windowSize: NSSize {
        let values = readoutSize
        return NSSize(width: characterBox.width + max(folkSize * 2.6, values.width + 8),
                      height: max(characterBox.height, values.height == 0 ? 0 : readoutBase + values.height + 4))
    }

    func apply(size: CompanionSize, reducedMotion: Bool) {
        self.size = CGFloat(size.points)
        character.reducedMotion = reducedMotion
        folkViews.values.forEach { $0.reducedMotion = reducedMotion }
        let origin = panel.frame.origin
        panel.setFrame(NSRect(origin: origin, size: windowSize), display: true)
        layoutContent()
    }

    /// Who is on the desktop and what it is called. Switching is live: the character crossfades to
    /// the other companion in the same state.
    func apply(look: CharacterLook, name: String) {
        character.look = look
        character.displayName = name
        container.setAccessibilityLabel(name)
        container.setAccessibilityHelp(String(localized: "Press to talk to \(name)."))
        let before = windowSize
        show3D(look.custom == nil && look.threeD ? look.character3D ?? look.species.rawValue : nil)
        if windowSize != before {
            // Grow or shrink about the feet: the companion stays standing where it was.
            let frame = panel.frame
            let x = folksGoLeft ? frame.maxX - windowSize.width : frame.minX
            panel.setFrame(NSRect(x: x, y: frame.minY, width: windowSize.width, height: windowSize.height), display: true)
        }
        layoutContent()
    }

    // MARK: 3D (D51)

    /// The 3D character over the undrawn 2D rig, while a companion is shown in 3D.
    private var stage3D: Companion3DStage?
    private var occlusion3D: NSObjectProtocol?

    /// Shows the 3D character `name`, or the 2D rig itself when nil. The chosen form shows at once: in 3D
    /// the 2D rig is never drawn (only if the page can't load), and switching between 3D companions
    /// swaps the character inside the page already running.
    private func show3D(_ name: String?) {
        guard let name else { removeStage3D(); return }
        character.drawsRig = false
        if let stage = stage3D { stage.show(name); return }
        guard let stage = Companion3DStage(name) else { character.drawsRig = true; return }
        // Like the 2D rig: nothing is drawn while the companion can't be seen.
        occlusion3D = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                             object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stage3D?.setVisible(self.panel.occlusionState.contains(.visible))
            }
        }
        stage.frame = character.frame
        // Under the 2D view: its effects and badges show in front of the 3D character.
        container.addSubview(stage, positioned: .below, relativeTo: character)
        stage3D = stage
        stage.onReady = { [weak self, weak stage] in
            guard let self, let stage else { return }
            stage.handle(.liveliness(self.character.motionLevel))
            stage.handle(.state(self.character.state))
            stage.handle(.posture(self.character.posture))
            stage.setVisible(self.panel.occlusionState.contains(.visible))
        }
        stage.onEffect = { [weak self] effect, seconds in self?.character.flash(effect, for: seconds) }
        stage.onFailed = { [weak self] in
            guard let self else { return }
            self.removeStage3D()
            self.layoutContent()
        }
        character.onCue = { [weak stage] in stage?.handle($0) }
    }

    /// The files of these 3D characters changed on disk (a newer version from the gallery): if one is on the
    /// desktop, a fresh page loads it (the running one keeps what it imported) and takes over once it has drawn,
    /// so the window is never empty.
    func reload3D(_ names: [String]) {
        guard let old = stage3D, names.contains(old.character) else { return }
        occlusion3D.map(NotificationCenter.default.removeObserver)
        occlusion3D = nil
        stage3D = nil
        show3D(old.character)
        guard let fresh = stage3D else { old.removeFromSuperview(); return }
        let ready = fresh.onReady, failed = fresh.onFailed
        fresh.onReady = { [weak old] in ready?(); old?.removeFromSuperview() }
        fresh.onFailed = { [weak old] in old?.removeFromSuperview(); failed?() }
    }

    private func removeStage3D() {
        stage3D?.removeFromSuperview()
        stage3D = nil
        occlusion3D.map(NotificationCenter.default.removeObserver)
        occlusion3D = nil
        character.onCue = nil
        character.drawsRig = true
    }

    private func layoutContent() {
        let box = characterBox
        let folksOnLeft = folksGoLeft
        let charX = folksOnLeft ? windowSize.width - box.width : 0
        character.frame = NSRect(x: charX, y: 0, width: box.width, height: box.height)
        stage3D?.frame = character.frame
        // Folks stand beside the body, not the square view: a slim companion keeps them close.
        // `reach` is how far the robot's body frame sits inside its view, where folks always stood.
        let body = character.characterFrame.offsetBy(dx: charX, dy: 0)
        let reach = box.width * 0.17
        for (i, folk) in folkOrder.enumerated() {
            guard let v = folkViews[folk] else { continue }
            let step = folkSize * 0.8
            let x = folksOnLeft ? body.minX - reach - CGFloat(i + 1) * step + folkSize * 0.15
                : body.maxX + reach + CGFloat(i) * step - folkSize * 0.15
            // Folk canvases also stand 10% above their bottom; align both feet lines.
            v.frame = NSRect(x: x, y: feetInset - folkSize * 0.1, width: folkSize, height: folkSize)
        }
        let values = readoutSize
        readouts.alignment = folksOnLeft ? .trailing : .leading
        let inner = folksOnLeft ? body.minX - reach * 0.4 : body.maxX + reach * 0.4
        readoutHost.frame = NSRect(x: max(0, folksOnLeft ? inner - values.width : inner), y: readoutBase,
                                   width: values.width, height: values.height)
    }

    /// Shows these live values beside the companion (none hides them). The window grows to hold them while the
    /// companion stays exactly where it stands.
    func setReadouts(_ items: [Readout]) {
        guard items != readouts.items else { return }
        let before = panel.frame
        let left = folksGoLeft
        readouts.items = items
        readoutHost.isHidden = items.isEmpty
        readoutHost.invalidateIntrinsicContentSize()
        let size = windowSize
        if size != before.size {
            // With the folks on the left the companion is at the window's right edge: keep it there.
            let x = left ? before.maxX - size.width : before.minX
            panel.setFrame(NSRect(x: x, y: before.minY, width: size.width, height: size.height), display: true)
        }
        layoutContent()
    }

    func readout(at point: NSPoint) -> Bool { !readoutHost.isHidden && readoutHost.frame.contains(point) }

    /// Folks sit on whichever side of the companion has more room on screen.
    private var folksGoLeft: Bool {
        guard let screen = panel.screen ?? NSScreen.main else { return true }
        return panel.frame.midX > screen.visibleFrame.midX
    }

    /// The character's body at rest in screen coordinates (panels and bubbles attach to it).
    var characterFrameOnScreen: NSRect {
        panel.convertToScreen(character.convert(character.characterFrame, to: nil))
    }

    var screen: NSScreen { panel.screen ?? NSScreen.main ?? NSScreen.screens[0] }

    // MARK: Showing

    func show(presence: PresenceMode) {
        self.presence = presence
        if presence == .menuBarOnly {
            panel.orderOut(nil)
            return
        }
        if !panel.isVisible {
            restorePosition()
            panel.orderFrontRegardless()
            startMonitors()
        }
        setPeeking(presence == .whenNeeded, animated: true)
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    /// "Only when needed": only the top of the head shows until something needs the user.
    func setPeeking(_ peek: Bool, animated: Bool) {
        guard peek != peeking || !animated else { return }
        peeking = peek
        var frame = panel.frame
        let floor = screen.visibleFrame.minY - feetInset
        frame.origin.y = peek ? floor - characterBox.height * 0.58 : savedFloorOffset() + floor
        if animated && !character.reducedMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Steps forward for something that needs the user, then tucks back (when-needed mode).
    func stepForward(for seconds: TimeInterval = 20) {
        if presence == .whenNeeded { setPeeking(false, animated: true) }
        // Something arrived: lively companions jump at it, the minimal one hops as before.
        if character.reactsToNews { character.perform(.startle) } else { character.play(.hop) }
        raiseTask?.cancel()
        guard presence == .whenNeeded else { return }
        raiseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.setPeeking(true, animated: true)
        }
    }

    func keepRaised(_ raised: Bool) {
        guard presence == .whenNeeded else { return }
        raiseTask?.cancel()
        setPeeking(!raised, animated: true)
    }

    // MARK: State

    func render(_ pose: CompanionPose) {
        let state = Self.state(for: pose)
        let changed = state != character.state
        character.setState(state, animated: true)
        // Something got done: glad about it, with two hops (the success pose alone hops once).
        if changed, state == .success, character.reactsToNews { character.perform(.cheer) }
    }

    func setBadges(watching: Bool, busy: Bool, waiting: Int) {
        var b: Set<CharacterBadge> = []
        if waiting > 0 { b.insert(.count(waiting)) }
        if watching, folkViews[.scout] == nil { b.insert(.watching) }
        if busy, folkViews[.byte] == nil { b.insert(.busy) }
        character.badges = b
    }

    /// Folks stand beside the companion while their duty is live (D9). A folk that is the companion
    /// itself doesn't stand beside itself: its duty shows as the companion's badge instead (D30).
    func setFolks(_ folks: [DutyFolk], visible: Bool) {
        let me = character.look.species.folk
        let wanted = visible ? folks.filter { Self.folk(for: $0) != me } : []
        for (folk, view) in folkViews where !wanted.contains(folk) {
            folkViews[folk] = nil
            view.popOut { view.removeFromSuperview() }
        }
        folkOrder = wanted
        for folk in wanted where folkViews[folk] == nil {
            let v = FolkView(folk: Self.folk(for: folk), frame: .zero)
            v.reducedMotion = character.reducedMotion
            v.setAccessibilityLabel(Self.folkLabel(folk))
            container.addSubview(v)
            folkViews[folk] = v
            layoutContent()
            v.popIn()
        }
        layoutContent()
    }

    /// The folks standing beside the companion now.
    var folksShown: [DutyFolk] { folkOrder }

    func folk(at point: NSPoint) -> DutyFolk? {
        folkViews.first { $0.value.frame.contains(point) }?.key
    }

    static func state(for pose: CompanionPose) -> CharacterState {
        switch pose {
        case .idle: .idle
        case .sleeping: .sleeping
        case .listening: .listening
        case .hearing: .hearing
        case .thinking: .thinking
        case .waiting: .waiting
        case .success: .success
        case .error: .error
        case .alert: .alert
        case .dragging: .dragging
        case .celebrating: .celebrating
        case .working(let category):
            switch category {
            case .notes, .memory: .working(.notepad)
            case .time: .working(.clock)
            case .watch: .working(.binoculars)
            case .files: .working(.folder)
            case .web: .working(.globe)
            case .system, .agents, .extensions: .working(.laptop)
            }
        }
    }

    static func folk(for duty: DutyFolk) -> Folk {
        switch duty {
        case .tempo: .tempo
        case .scout: .scout
        case .byte: .byte
        }
    }

    static func folkLabel(_ duty: DutyFolk) -> String {
        switch duty {
        case .tempo: String(localized: "Tempo: a reminder is coming up")
        case .scout: String(localized: "Scout: watching things for you")
        case .byte: String(localized: "Byte: an agent or command is running")
        }
    }

    // MARK: Position

    private func displayKey(_ screen: NSScreen) -> String {
        if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            return "companion.position." + (CFUUIDCreateString(nil, uuid) as String)
        }
        return "companion.position.main"
    }

    private func savedFloorOffset() -> CGFloat {
        let stored = UserDefaults.standard.array(forKey: displayKey(screen)) as? [Double]
        return CGFloat(stored?[1] ?? 0)
    }

    func restorePosition() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        let size = windowSize
        let floor = v.minY - feetInset
        var origin = NSPoint(x: v.maxX - size.width - 8, y: floor)
        if let stored = UserDefaults.standard.array(forKey: displayKey(screen)) as? [Double], stored.count == 2 {
            origin.x = v.minX + CGFloat(stored[0]) * max(1, v.width - size.width)
            origin.y = floor + CGFloat(stored[1])
        }
        origin.x = min(max(origin.x, v.minX), v.maxX - size.width)
        origin.y = min(max(origin.y, floor), v.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        layoutContent()
    }

    func savePosition() {
        let v = screen.visibleFrame
        let rx = Double((panel.frame.minX - v.minX) / max(1, v.width - panel.frame.width))
        let dy = Double(max(0, panel.frame.minY - (v.minY - feetInset)))
        UserDefaults.standard.set([min(max(rx, 0), 1), dy], forKey: displayKey(screen))
    }

    /// Lands on the floor when released near it.
    func settleAfterDrag() {
        let v = screen.visibleFrame
        var frame = panel.frame
        let floor = v.minY - feetInset
        frame.origin.x = min(max(frame.origin.x, v.minX - characterBox.width * 0.15), v.maxX - frame.width + characterBox.width * 0.15)
        frame.origin.y = min(max(frame.origin.y, floor), v.maxY - frame.height)
        if frame.minY - floor < 60 { frame.origin.y = floor }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = character.reducedMotion ? 0 : 0.25
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.savePosition()
                self?.layoutContent()
                self?.delegate?.companionMoved()
                self?.character.perform(.land)
            }
        }
    }

    /// Thrown: it tumbles through the air, lands on the bottom of the screen and is dizzy after a
    /// hard landing. The window moves along the arc for under a second, then everything stops.
    func fling(_ velocity: CGVector) {
        guard !character.reducedMotion else { return settleAfterDrag() }
        let v = screen.visibleFrame
        let flight = Fling(from: panel.frame.origin, velocity: velocity, floor: v.minY - feetInset,
                           span: (v.minX - characterBox.width * 0.15)...(v.maxX - panel.frame.width + characterBox.width * 0.15))
        character.perform(.spin)
        let start = CACurrentMediaTime()
        flightTimer?.invalidate()
        flightTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = CACurrentMediaTime() - start
                self.panel.setFrameOrigin(flight.position(at: t))
                guard t >= flight.duration else { return }
                self.flightTimer?.invalidate()
                self.flightTimer = nil
                self.savePosition()
                self.layoutContent()
                self.delegate?.companionMoved()
                self.character.perform(.land)
                guard flight.impact > 0.35 else { return }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(0.55))
                    self?.character.perform(.dizzy)
                }
            }
        }
    }

    var isFlying: Bool { flightTimer != nil }

    /// Hops to `origin` for a game (D44): the window glides there while the companion hops. The person's own spot
    /// isn't saved; the game brings it back there at the end.
    func hop(to origin: NSPoint, done: (@MainActor @Sendable () -> Void)? = nil) {
        character.perform(.hop)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = character.reducedMotion ? 0 : 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(origin: origin, size: panel.frame.size), display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.layoutContent()
                self?.delegate?.companionMoved()
                done?()
            }
        }
    }

    func moveToScreen(of point: NSPoint) {
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(point) }), target != screen else { return }
        let v = target.visibleFrame
        panel.setFrameOrigin(NSPoint(x: v.maxX - windowSize.width - 8, y: v.minY - feetInset))
        savePosition()
    }

    // MARK: Pointer (click-through + gaze)

    private func startMonitors() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved(NSEvent.mouseLocation) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] e in
            MainActor.assumeIsolated { self?.pointerMoved(NSEvent.mouseLocation) }
            return e
        }) { monitors.append(local) }
    }

    private func pointerMoved(_ p: NSPoint) {
        guard panel.isVisible else { return }
        let frame = panel.frame
        // Click-through everywhere except the character's body and the folks. The silhouette is only
        // tested when the pointer is inside the character's box, and the flag only written on change.
        var ignore = !container.isDraggingFile
        if frame.insetBy(dx: -4, dy: -4).contains(p) {
            let local = container.convert(panel.convertPoint(fromScreen: p), from: nil)
            if folk(at: local) != nil || readout(at: local) {
                ignore = false
            } else if character.frame.contains(local) {
                ignore = ignore && !character.characterPath.contains(character.convert(local, from: container))
            }
        }
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
        // Stroking it with the pointer pets it.
        if !isFlying { character.pointerMoved(toScreen: p) }
        // Eyes follow the pointer when it is near (max 20 updates a second).
        guard eyesFollowPointer, !character.reducedMotion else { return }
        let now = Date()
        guard now.timeIntervalSince(lastGazeUpdate) > 0.05 else { return }
        lastGazeUpdate = now
        let c = characterFrameOnScreen
        let dx = p.x - c.midX, dy = p.y - c.midY
        let distance = hypot(dx, dy)
        if distance < 260, distance > 6 {
            character.setGaze(CGVector(dx: max(-1, min(1, dx / 160)), dy: max(-1, min(1, dy / 160))))
            character.noteInteraction()
            folkViews.values.forEach { $0.wake() }
        } else if character.liveliness == .lively, distance > 6 {
            // Lively: it keeps an eye on the pointer across the screen, more faintly far away.
            let reach = min(1, distance / 500) / distance
            character.setGaze(CGVector(dx: dx * reach, dy: dy * reach), wakes: false)
        } else {
            character.setGaze(nil)
        }
    }
}

/// Handles clicks, drags, the context menu and drops for the companion.
final class CompanionContainerView: NSView {
    weak var owner: CompanionWindowController?
    let character: CharacterView
    private var mouseDownAt: NSPoint?
    private var windowOriginAtDown: NSPoint?
    private var dragging = false
    /// The last tenth of a second of a drag, for the speed it is let go at.
    private var trail: [(time: TimeInterval, point: NSPoint)] = []
    private(set) var isDraggingFile = false
    /// Pressed and not moved yet: held long enough, it talks instead of clicking or dragging.
    private var holdTimer: Timer?
    private var holding = false
    static let holdToTalk: TimeInterval = 0.35

    init(character: CharacterView) {
        self.character = character
        super.init(frame: .zero)
        addSubview(character)
        registerForDraggedTypes([.fileURL, .URL, .string])
        setAccessibilityRole(.button)
        setAccessibilityLabel("Sidefolk")
        setAccessibilityHelp(String(localized: "Press to talk to \("Sidefolk")."))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        owner?.delegate?.companionClicked()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownAt = NSEvent.mouseLocation
        windowOriginAtDown = window?.frame.origin
        dragging = false
        holding = false
        holdTimer?.invalidate()
        holdTimer = nil
        trail = [(event.timestamp, NSEvent.mouseLocation)]
        let point = convert(event.locationInWindow, from: nil)
        guard event.clickCount == 1, owner?.delegate?.companionCanTalk == true,
              owner?.folk(at: point) == nil, owner?.readout(at: point) != true else { return }
        let timer = Timer(timeInterval: Self.holdToTalk, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mouseDownAt != nil, !self.dragging else { return }
                self.holding = true
                self.owner?.delegate?.companionHoldBegan()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    override func mouseDragged(with event: NSEvent) {
        guard !holding, let start = mouseDownAt, let origin = windowOriginAtDown, let window else { return }
        let p = NSEvent.mouseLocation
        trail.append((event.timestamp, p))
        trail.removeAll { event.timestamp - $0.time > 0.1 }
        if !dragging, hypot(p.x - start.x, p.y - start.y) > 4 {
            dragging = true
            holdTimer?.invalidate()
            holdTimer = nil
            owner?.delegate?.companionDragChanged(true)
        }
        guard dragging else { return }
        window.setFrameOrigin(NSPoint(x: origin.x + p.x - start.x, y: origin.y + p.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownAt = nil }
        holdTimer?.invalidate()
        holdTimer = nil
        if holding {
            holding = false
            owner?.delegate?.companionHoldEnded()
            return
        }
        if dragging {
            dragging = false
            owner?.delegate?.companionDragChanged(false)
            let velocity = Self.velocity(trail)
            if Fling.isToss(velocity) { owner?.fling(velocity) } else { owner?.settleAfterDrag() }
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        if owner?.readout(at: local) == true {
            owner?.delegate?.companionReadoutClicked()
        } else if let folk = owner?.folk(at: local) {
            owner?.delegate?.companionFolkClicked(folk)
        } else if event.clickCount == 2 {
            owner?.delegate?.companionDoubleClicked()
        } else if event.clickCount == 1 {
            character.perform(.boop)
            owner?.delegate?.companionClicked()
        }
    }

    /// Points per second over the drag's last tenth of a second.
    static func velocity(_ trail: [(time: TimeInterval, point: NSPoint)]) -> CGVector {
        guard let first = trail.first, let last = trail.last, last.time - first.time > 0.01 else { return .zero }
        let dt = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = owner?.delegate?.companionMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: Drops

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isDraggingFile = true
        window?.ignoresMouseEvents = false
        character.play(.hop)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { isDraggingFile = false }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDraggingFile = false
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let file = urls.first {
            owner?.delegate?.companionReceived(Attachment(kind: .file(file), label: file.lastPathComponent, text: nil))
            return true
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            owner?.delegate?.companionReceived(Attachment(kind: .url(url), label: url.host ?? url.absoluteString, text: url.absoluteString))
            return true
        }
        if let text = pb.string(forType: .string), !text.isEmpty {
            let label = text.trimmingCharacters(in: .whitespacesAndNewlines).clipped(40)
            owner?.delegate?.companionReceived(Attachment(kind: .text, label: "“\(label)”", text: text.clipped(20_000)))
            return true
        }
        return false
    }
}
