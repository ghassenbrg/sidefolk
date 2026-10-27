import AppKit
import SwiftUI

/// Shows and hides the Ask panel beside the companion.
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
        hosted.host.rootView = AskView(model: model, companionName: companionName, portrait: portrait, hotkey: hotkey)
    }

    func show(beside anchor: NSRect, on screen: NSScreen, focus: Bool = true) {
        model.freshenIfStale()
        fit(on: screen)
        hosted.place(beside: anchor, on: screen)
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
        hosted.place(beside: anchor, on: screen)
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
