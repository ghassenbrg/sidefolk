import AppKit
import SwiftUI

/// Shows and hides Ask beside the companion (the Sidecard's Ask size, D84), its tail toward the head. Opened by a
/// permission slip alone, it stands above the companion as that slip until the person opens Ask.
final class AskPanelController {
    let model: AskModel
    private let hosted: HostedPanel<AskView>
    private var resignObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    /// The two-finger gesture under way: which way it was read, and how far it went sideways.
    private var gesture: (sideways: Bool?, x: CGFloat, y: CGFloat) = (nil, 0, 0)
    var onVisibilityChange: ((Bool) -> Void)?
    /// Esc goes here first (talking, speaking); true when it was handled there.
    var onEscape: (() -> Bool)?

    init(model: AskModel, companionName: String, portrait: NSImage?, hotkey: String) {
        self.model = model
        hosted = HostedPanel(rootView: AskView(model: model, companionName: companionName, portrait: portrait, hotkey: hotkey), allowsKey: true)
        // The glass draws its own shadow; a window shadow would be traced from its faint pixels as a grey outline.
        hosted.panel.hasShadow = false
        hosted.onPlaced = { [weak self] frame, anchor in self?.aimTail(from: frame, at: anchor) }
        model.companionName = companionName
        model.onClose = { [weak self] in self?.hide() }
        hosted.panel.onCancel = { [weak self] in self?.cancel() }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: hosted.panel,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didResignKey() }
        }
        model.onAutoClose = { [weak self] in self?.hide() }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.hosted.panel else { return event }
            return self.swipe(event) ? nil : event
        }
    }

    var isVisible: Bool { hosted.panel.isVisible }
    var frame: NSRect { hosted.panel.frame }

    func update(companionName: String, portrait: NSImage?, hotkey: String) {
        model.companionName = companionName
        hosted.host.rootView = AskView(model: model, companionName: companionName, portrait: portrait, hotkey: hotkey)
    }

    /// `slipsOnly`: a permission slip opened it while it was closed; it shows only that until the person opens Ask.
    func show(beside anchor: NSRect, on screen: NSScreen, focus: Bool = true, slipsOnly: Bool = false) {
        model.freshenIfStale()
        model.compact = slipsOnly && (!isVisible || model.compact)
        fit(on: screen)
        hosted.panel.setContentSize(hosted.fittingSize)
        place(anchor, screen)
        hosted.panel.orderFrontRegardless()
        if focus {
            hosted.panel.makeKey()
            model.focusRequest += 1
        }
        onVisibilityChange?(true)
    }

    /// Keeps the panel attached as the companion moves or the content grows.
    func reposition(beside anchor: NSRect, on screen: NSScreen) {
        guard isVisible else { return }
        fit(on: screen)
        place(anchor, screen)
    }

    /// Ask beside the companion; slips alone above its head. The margins are the glass's shadow room.
    private func place(_ anchor: NSRect, _ screen: NSScreen) {
        if model.showsSlipsOnly {
            hosted.place(beside: anchor, on: screen, gap: 4 - AskView.margin.bottom, preferAbove: true)
        } else {
            hosted.place(beside: anchor, on: screen, gap: 6 - AskView.margin.leading)
        }
    }

    /// Points the tail at the companion's head: from the bottom edge for slips above it, from the side facing it for Ask.
    private func aimTail(from frame: NSRect, at anchor: NSRect) {
        let m = AskView.margin
        let glass = NSRect(x: frame.minX + m.leading, y: frame.minY + m.bottom, width: frame.width - m.leading - m.trailing,
                           height: frame.height - m.top - m.bottom)
        let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft
        var tail: SidecardTail?
        if model.showsSlipsOnly {
            if glass.minY >= anchor.midY {
                let physical = min(max((anchor.midX - glass.minX) / max(glass.width, 1), 0), 1)
                tail = SidecardTail(edge: .bottom, at: rtl ? 1 - physical : physical)
            }
        } else {
            // The head, about a quarter down the companion's body.
            let head = anchor.maxY - anchor.height * 0.25
            let at = (glass.maxY - head) / max(glass.height, 1)
            if (0.05...0.95).contains(at) {
                let right = glass.maxX <= anchor.midX
                tail = SidecardTail(edge: right != rtl ? .trailing : .leading, at: at)
            }
        }
        if model.tail != tail { model.tail = tail }
    }

    /// The results scroll before the panel outgrows the screen (the header and input take about 160 points).
    private func fit(on screen: NSScreen) {
        let room = max(200, screen.visibleFrame.height - 200)
        if model.resultsMaxHeight != room { model.resultsMaxHeight = room }
    }

    /// Two fingers sideways over a result slide it like a notification; far enough, it goes. Up and down
    /// still scroll, and a mouse wheel (no gesture phases) is never a swipe. True when the event was used.
    private func swipe(_ event: NSEvent) -> Bool {
        if !event.momentumPhase.isEmpty { return gesture.sideways == true }
        guard !event.phase.isEmpty else { return false }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { gesture = (nil, 0, 0) }
        // The card follows the fingers whichever way scrolling is set to go.
        let follow: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        gesture.x += event.scrollingDeltaX * follow
        gesture.y += event.scrollingDeltaY
        if gesture.sideways == nil, abs(gesture.x) + abs(gesture.y) > 6 {
            gesture.sideways = abs(gesture.x) > abs(gesture.y) * 1.5 && model.hoveredRequest != nil
        }
        guard gesture.sideways == true, let id = model.swipe?.id ?? model.hoveredRequest else { return false }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if abs(gesture.x) > 90, !event.phase.contains(.cancelled) { model.dismiss(id, toward: gesture.x) } else { model.swipe = nil }
            return true
        }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { model.swipe = (id, gesture.x) }
        return true
    }

    #if DEBUG
    /// Dev (`swift scripts/dev.swift swipe:-140`, then `swipe:end`): two fingers sideways over the newest result,
    /// fed to the gesture code as the trackpad would, so the slide and the dismissal can be seen without one.
    func devSwipe(_ argument: String) {
        func feed(_ phase: CGScrollPhase, _ dx: Int32) {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0) else { return }
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            if let event = NSEvent(cgEvent: cg) { _ = swipe(event) }
        }
        if argument == "end" { return feed(.ended, 0) }
        guard let points = Int32(argument), let newest = model.visibleRequests.first else { return }
        model.hoveredRequest = newest.id
        feed(.began, 0)
        for _ in 0..<10 { feed(.changed, points / 10) }
    }
    #endif

    func hide() {
        guard isVisible else { return }
        hosted.panel.orderOut(nil)
        onVisibilityChange?(false)
    }

    private func cancel() {
        if onEscape?() == true { return }
        if !model.text.isEmpty { model.text = "" } else { hide() }
    }

    private func didResignKey() {
        // Stay up while work, a question or talking is pending; otherwise get out of the way.
        if !model.busy && model.voice == nil && !model.entries.contains(where: \.isPinned) { hide() }
    }
}
