import AppKit
import SidefolkCharacter
import SidefolkCore
import SwiftUI

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
    func companionReadoutClicked(_ id: String)
    /// A pin's own menu: pause, resume, stop (D84).
    func companionReadoutMenu(_ id: String) -> NSMenu?
    func companionAgentClicked(_ id: String)
    /// The count on the shoulder: hovered (the stack fans out) or clicked (Ask on top of the stack).
    func companionBadgeHovered(_ hovering: Bool)
    func companionBadgeClicked()
    /// Pressing and holding the companion talks (D34), when voice input is on.
    var companionCanTalk: Bool { get }
    func companionHoldBegan()
    func companionHoldEnded()
    /// What the companion is saying above its head (a card, the held cards, a permission slip), for VoiceOver (D84).
    func companionSays() -> String?
    /// VoiceOver pressed it: the card takes the keyboard, as its shortcut does.
    func companionFocusCard()
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
    /// The light at its feet, the shoulder's mark, the pins and the agents lane (D84).
    let floor = FloorModel()
    private let underlay: FloorHostView<FloorUnderlay>
    private let overlay: FloorHostView<FloorOverlay>
    /// The extras' column (pins and agents) as measured, and where each one stands in the window.
    private var extrasSize = NSSize.zero
    private(set) var extras: [(item: FloorItem, rect: NSRect)] = []
    /// VoiceOver's elements for the corner, by what they stand for (D84).
    var axElements: [String: FloorElement] = [:]
    private var badgeHovered = false
    /// The item the pointer rests on, whose tip shows.
    private var tipFor: FloorItem?
    private lazy var tip: HostedPanel<FloorTip> = {
        let tip = HostedPanel(rootView: FloorTip(content: .words("")), allowsKey: false)
        tip.panel.ignoresMouseEvents = true
        tip.panel.hasShadow = false
        return tip
    }()
    /// Looks every second and a half whether the person works under the companion's corner (only while extras show).
    private var recedeTimer: Timer?
    private var typingUnder = false
    /// The pointer crosses the corner without resting on anything in it.
    private var pointerPassing = false

    init() {
        character = CharacterView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        container = CompanionContainerView(character: character)
        underlay = FloorHostView(rootView: FloorUnderlay(model: floor))
        overlay = FloorHostView(rootView: FloorOverlay(model: floor))
        // The pool under the character (and the 3D stage, which goes right below the character), the rest over it.
        container.addSubview(underlay, positioned: .below, relativeTo: character)
        container.addSubview(overlay)
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
    /// The extras stand above the folks' heads, close to the companion.
    private var readoutBase: CGFloat { feetInset + folkSize * 0.95 }
    /// How far the robot's body frame sits inside its view, where folks always stood.
    private var reach: CGFloat { characterBox.width * 0.17 }
    /// Room beside the companion for its folks (no more than before D84: the extras fit in the same corner, the
    /// founder's rule that it never sprawls over people's work); tall enough for the extras above the folks.
    private var windowSize: NSSize { Self.area(box: characterBox.width, folk: folkSize, extras: extrasSize) }

    /// The corner the companion takes: its box, room for three folks beside it, and the extras above them.
    static func area(box: CGFloat, folk: CGFloat, extras: NSSize) -> NSSize {
        let inset = box * 0.19, reach = box * 0.17, feet = box * 0.1
        let beside = max(folk * 2.6, reach * 0.4 + extras.width + 12 - inset)
        let tall = extras.height == 0 ? 0 : feet + folk * 0.95 + extras.height + 10
        return NSSize(width: box + beside, height: max(box, tall))
    }

    func apply(size: CompanionSize, reducedMotion: Bool) {
        self.size = CGFloat(size.points)
        character.reducedMotion = reducedMotion
        folkViews.values.forEach { $0.reducedMotion = reducedMotion }
        let origin = panel.frame.origin
        panel.setFrame(NSRect(origin: origin, size: windowSize), display: true)
        layoutContent()
    }

    /// Grows or shrinks the window for what stands beside the companion, which stays exactly where it stands.
    private func fitWindow() {
        let before = panel.frame
        let size = windowSize
        if size != before.size {
            // With the folks on the left the companion is at the window's right edge: keep it there.
            let x = folksGoLeft ? before.maxX - size.width : before.minX
            panel.setFrame(NSRect(x: x, y: before.minY, width: size.width, height: size.height), display: true)
        }
        layoutContent()
    }

    /// Who is on the desktop and what it is called. Switching is live: the character crossfades to
    /// the other companion in the same state.
    func apply(look: CharacterLook, name: String) {
        character.look = look
        character.displayName = name
        let before = windowSize
        show3D(look.custom == nil && look.threeD ? look.character3D ?? look.species.rawValue : nil)
        // Grow or shrink about the feet: the companion stays standing where it was.
        if windowSize != before { fitWindow() } else { layoutContent() }
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
        let body = character.characterFrame.offsetBy(dx: charX, dy: 0)
        for (i, folk) in folkOrder.enumerated() {
            guard let v = folkViews[folk] else { continue }
            let step = folkSize * 0.8
            let x = folksOnLeft ? body.minX - reach - CGFloat(i + 1) * step + folkSize * 0.15
                : body.maxX + reach + CGFloat(i) * step - folkSize * 0.15
            // Folk canvases also stand 10% above their bottom; align both feet lines.
            v.frame = NSRect(x: x, y: feetInset - folkSize * 0.1, width: folkSize, height: folkSize)
        }
        layoutFloor(body: body, folksOnLeft: folksOnLeft)
    }

    /// The pool under the feet, the mark on the outer shoulder and the extras above the folks, all in the floor's
    /// top-left coordinates.
    private func layoutFloor(body: NSRect, folksOnLeft: Bool) {
        let bounds = container.bounds
        underlay.frame = bounds
        overlay.frame = bounds
        func flipped(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height) }
        floor.inward = folksOnLeft ? .trailing : .leading
        floor.poolWidth = min(max(body.width * 1.9, 90), 240)
        floor.poolCenter = CGPoint(x: body.midX, y: bounds.height - feetInset - 2)
        // On the shoulder away from the folks, so it never sits behind one.
        let shoulder = folksOnLeft ? body.maxX - body.width * 0.1 : body.minX + body.width * 0.1
        floor.badgeCenter = CGPoint(x: shoulder, y: bounds.height - (body.maxY - body.height * 0.08))
        let inner = folksOnLeft ? body.minX - reach * 0.4 : body.maxX + reach * 0.4
        let column = NSRect(x: folksOnLeft ? inner - extrasSize.width : inner, y: readoutBase, width: extrasSize.width, height: extrasSize.height)
        floor.extrasFrame = flipped(column)
        // Where each extra stands, for clicks and tips: the agents' row at the bottom, the pins above, all aligned
        // toward the companion.
        extras = []
        var y = column.minY
        if !floor.agents.isEmpty {
            for (i, chip) in floor.agents.enumerated() {
                let step = CGFloat(i) * (FloorModel.dot + FloorModel.gap)
                let x = folksOnLeft ? column.maxX - FloorModel.dot - step : column.minX + step
                extras.append((.agent(chip.id), NSRect(x: x, y: y, width: FloorModel.dot, height: FloorModel.dot)))
            }
            y += FloorModel.dot + FloorModel.gap
        }
        for pin in floor.pins.prefix(FloorModel.pinsShown).reversed() {
            extras.append((.pin(pin.id), NSRect(x: column.minX, y: y, width: column.width, height: FloorModel.pinHeight)))
            y += FloorModel.pinHeight + FloorModel.gap
        }
    }

    /// Measures the extras again when they come or go, or a value outgrows its room: a value changing every few
    /// seconds doesn't move the window.
    private func measureExtras(force: Bool) {
        let measured = floor.pins.isEmpty && floor.agents.isEmpty ? .zero
            : NSHostingView(rootView: FloorExtras(pins: floor.pins, agents: floor.agents)).fittingSize
        guard force || measured.width > extrasSize.width || measured.height != extrasSize.height else { return layoutContent() }
        extrasSize = measured
        fitWindow()
        watchForWork(!extras.isEmpty)
    }

    /// Shows these live values beside the companion (none hides them). The window grows to hold them while the
    /// companion stays exactly where it stands.
    func setReadouts(_ items: [Readout]) {
        guard items != floor.pins else { return }
        let ids = floor.pins.map(\.id)
        floor.pins = items
        measureExtras(force: ids != items.map(\.id))
        if case .pin(let id)? = tipFor { showTip(.pin(id)) }
    }

    /// The agents lane: a small face per live Claude Code or Codex session (D84).
    func setAgents(_ chips: [AgentChip]) {
        guard chips != floor.agents else { return }
        floor.agents = chips
        measureExtras(force: true)
    }

    // MARK: Tips and stepping back

    func extra(at point: NSPoint) -> FloorItem? {
        extras.first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }?.item
    }

    /// The pointer rests on an extra or a folk: its short card shows beside it, until the pointer leaves.
    private func showTip(_ item: FloorItem?) {
        tipFor = item
        let content: FloorTip.Content? = switch item {
        case .pin(let id)?: floor.pins.first { $0.id == id }.map { .pin($0) }
        case .agent(let id)?: floor.agents.first { $0.id == id }.map { .agent($0) }
        case .folk(let folk)?: .words(Self.folkLabel(folk))
        case nil: nil
        }
        guard let content, let item, let rect = rect(of: item) else {
            tip.panel.orderOut(nil)
            return
        }
        tip.host.rootView = FloorTip(content: content)
        tip.panel.setContentSize(tip.fittingSize)
        // Beyond the whole column of extras, level with this one: it never covers another pin or face.
        var beside = rect
        if case .folk = item {} else if let first = extras.first {
            let column = extras.dropFirst().reduce(first.rect) { $0.union($1.rect) }
            beside = NSRect(x: column.minX, y: rect.minY, width: column.width, height: rect.height)
        }
        var onScreen = panel.convertToScreen(container.convert(beside, to: nil))
        // Centred on the item: placing beside puts the panel's foot at 35% of the anchor's height.
        onScreen.origin.y = onScreen.midY - tip.panel.frame.height / 2 - onScreen.height * 0.35
        tip.place(beside: onScreen, on: screen, gap: -8)
        if !tip.panel.isVisible { tip.panel.orderFrontRegardless() }
    }

    #if DEBUG
    /// Dev (`tip:<n>`, `tip:off`): the tip of the n-th extra, as if the pointer rested on it; `recede:on|off` too.
    func devFloor(_ command: String) {
        if command.hasPrefix("recede:") {
            pointerPassing = command == "recede:on"
            return recede()
        }
        guard let n = Int(command.dropFirst(4)), extras.indices.contains(n) else { return showTip(nil) }
        showTip(extras[n].item)
    }
    #endif

    private func rect(of item: FloorItem) -> NSRect? {
        if case .folk(let folk) = item { return folkViews[folk]?.frame }
        return extras.first { $0.item == item }?.rect
    }

    /// The extras step back (fade and shrink toward the companion) while the person works under the companion's
    /// corner: typing in a window that reaches under them, or passing the pointer through. Read without any
    /// permission (`Desktop`, the same senses the companion's life uses).
    private func watchForWork(_ on: Bool) {
        guard on != (recedeTimer != nil) else { return }
        recedeTimer?.invalidate()
        recedeTimer = nil
        guard on else {
            typingUnder = false
            return recede()
        }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookForWork() }
        }
        RunLoop.main.add(timer, forMode: .common)
        recedeTimer = timer
    }

    private func lookForWork() {
        guard panel.isVisible, !extras.isEmpty else { return }
        let desk = Desktop()
        let corner = panel.convertToScreen(container.convert(extras.map(\.rect).reduce(extras[0].rect) { $0.union($1) }, to: nil))
        typingUnder = desk.secondsSinceKey < 6 && (desk.activeWindow?.intersects(corner) ?? false)
        recede()
    }

    private func recede() {
        let receded = (typingUnder || pointerPassing) && tipFor == nil
        if floor.receded != receded { floor.receded = receded }
    }

    /// The light and the shoulder's mark, from what is going on.
    func setLight(_ light: DesktopLight) {
        let state: LightPoolState = switch light {
        case .idle: .idle
        case .working: .working
        case .waiting(let n): .waiting(n)
        case .alert: .alert
        case .failed: .failed
        case .focus: .focus
        case .quiet: .quiet
        }
        guard state != floor.light || light.count != floor.count else { return }
        floor.light = state
        floor.count = light.count
        container.setAccessibilityValue(Self.spoken(light))
    }

    /// The light follows the person's voice while the microphone listens (D84).
    func setVoiceLevel(_ level: Double?) {
        if floor.voiceLevel != level { floor.voiceLevel = level }
    }

    /// What VoiceOver hears about the companion's state beside its name.
    private static func spoken(_ light: DesktopLight) -> String {
        switch light {
        case .idle: String(localized: "Resting", comment: "The companion's state, read by VoiceOver: nothing going on")
        case .working: String(localized: "Working", comment: "The companion's state, read by VoiceOver")
        case .waiting(let n), .alert(let n): String(localized: "Waiting for you: \(n)", comment: "The companion's state, read by VoiceOver, with how many things wait")
        case .failed: String(localized: "Something failed", comment: "The companion's state, read by VoiceOver")
        case .focus: String(localized: "Focus", comment: "The companion's state, read by VoiceOver: only what matters gets through")
        case .quiet: String(localized: "Quiet", comment: "The companion's state, read by VoiceOver: only what's critical gets through")
        }
    }

    func readout(at point: NSPoint) -> String? {
        if case .pin(let id)? = extra(at: point) { return id }
        return nil
    }

    func agent(at point: NSPoint) -> String? {
        if case .agent(let id)? = extra(at: point) { return id }
        return nil
    }

    /// A pin, an agent chip, a folk or the count: what a press there means is theirs, not the companion's.
    func onFloor(_ point: NSPoint) -> Bool {
        folk(at: point) != nil || readout(at: point) != nil || agent(at: point) != nil || badge(at: point)
    }

    /// The count on the shoulder, when one shows.
    func badge(at point: NSPoint) -> Bool {
        guard floor.count > 0 else { return false }
        let center = NSPoint(x: floor.badgeCenter.x, y: container.bounds.height - floor.badgeCenter.y)
        return hypot(point.x - center.x, point.y - center.y) <= Theme.Size.stackBadge * 0.7
    }

    /// The count on the shoulder on screen, where held cards fold to (D84); nil while the companion is away.
    var badgeOnScreen: NSPoint? {
        guard panel.isVisible else { return nil }
        let point = NSPoint(x: floor.badgeCenter.x, y: container.bounds.height - floor.badgeCenter.y)
        return panel.convertPoint(toScreen: container.convert(point, to: nil))
    }

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
            hide()
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
        // The pointer stops being tracked with it, so its tip wouldn't go by itself.
        if tipFor != nil { showTip(nil) }
    }

    var isVisible: Bool { panel.isVisible }

    /// Kept off a full-screen app (D138). Still there, so everything placed beside it stays right and it comes straight back;
    /// a window's Space behaviour doesn't do this, measured: it stays on a full-screen space all the same.
    private(set) var hiddenOverFullScreen = false

    func hideOverFullScreen(_ hide: Bool) {
        guard hide != hiddenOverFullScreen else { return }
        hiddenOverFullScreen = hide
        panel.alphaValue = hide ? 0 : 1
        panel.ignoresMouseEvents = hide || panel.ignoresMouseEvents
        if hide, tipFor != nil { showTip(nil) }
    }

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

    /// A folk chosen as the companion carries its own duty as a mark (the count is the floor's shoulder badge, D84).
    func setBadges(watching: Bool, busy: Bool) {
        var b: Set<CharacterBadge> = []
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

    func folkFrame(_ folk: DutyFolk) -> NSRect? { folkViews[folk]?.frame }

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
        // Kept off a full-screen app (D138) there's nothing under the pointer to pet or fan out.
        guard panel.isVisible, !hiddenOverFullScreen else {
            if tipFor != nil { showTip(nil) }
            return
        }
        let frame = panel.frame
        // Click-through everywhere except the character's body and the folks. The silhouette is only
        // tested when the pointer is inside the character's box, and the flag only written on change.
        var ignore = !container.isDraggingFile
        if frame.insetBy(dx: -4, dy: -4).contains(p) {
            let local = container.convert(panel.convertPoint(fromScreen: p), from: nil)
            let onBadge = badge(at: local)
            if onBadge != badgeHovered {
                badgeHovered = onBadge
                delegate?.companionBadgeHovered(onBadge)
            }
            let item = extra(at: local) ?? folk(at: local).map(FloorItem.folk)
            if item != tipFor { showTip(item) }
            if item != nil || onBadge {
                ignore = false
            } else if character.frame.contains(local) {
                ignore = ignore && !character.characterPath.contains(character.convert(local, from: container))
            }
            // Passing through the corner on the way to something under it: the extras step back at once.
            pointerPassing = item == nil && !onBadge && !character.frame.contains(local) && !extras.isEmpty
            recede()
        } else {
            if pointerPassing {
                pointerPassing = false
                recede()
            }
            if badgeHovered {
                badgeHovered = false
                delegate?.companionBadgeHovered(false)
            }
            if tipFor != nil { showTip(nil) }
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
        // One group VoiceOver enters (D84): the companion and everything in its corner, in a sensible order.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Sidefolk companion", comment: "VoiceOver: the group holding the companion, its count, pins, agents and folks"))
    }

    override func accessibilityChildren() -> [Any]? { owner?.accessibleParts(of: self) }

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
        guard event.clickCount == 1, owner?.delegate?.companionCanTalk == true, owner?.onFloor(point) == false else { return }
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
        if let pin = owner?.readout(at: local) {
            owner?.delegate?.companionReadoutClicked(pin)
        } else if let agent = owner?.agent(at: local) {
            owner?.delegate?.companionAgentClicked(agent)
        } else if owner?.badge(at: local) == true {
            owner?.delegate?.companionBadgeClicked()
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
        let local = convert(event.locationInWindow, from: nil)
        let pin = owner?.readout(at: local).flatMap { owner?.delegate?.companionReadoutMenu($0) }
        guard let menu = pin ?? owner?.delegate?.companionMenu() else { return }
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
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let files = Attachment.files(urls) {
            owner?.delegate?.companionReceived(files)
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
