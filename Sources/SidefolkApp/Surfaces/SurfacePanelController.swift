import AppKit
import SidefolkCore
import SwiftUI

/// A surface's window beside the companion (D99): a panel, or an overlay that never takes the keyboard. Its window level
/// is under Sidefolk's own panels and cards, so nothing an extension shows can stand over an approval. It takes the
/// keyboard only when the person opened it (D75); Esc or ✕ puts it away, kept ten minutes.
@MainActor
final class SurfacePanelController {
    let presentation: SurfaceInfo.Presentation
    private let holder = SurfaceHolder()
    private lazy var hosted: HostedPanel<SurfaceRoot> = {
        let hosted = HostedPanel(rootView: SurfaceRoot(holder: holder), allowsKey: presentation == .panel)
        hosted.panel.onCancel = { [weak self] in self?.hide() }
        hosted.panel.firstClickActs = presentation == .panel
        hosted.panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        hosted.panel.hasShadow = presentation == .panel
        hosted.panel.setAccessibilityTitle(String(localized: "Extension panel", comment: "VoiceOver: the window of an extension's panel"))
        return hosted
    }()
    private var keyMonitor: Any?
    private var expiry: Task<Void, Never>?
    private var lastEscape: Date?
    private var placed: (anchor: NSRect, screen: NSScreen, cards: () -> [NSRect])?

    var model: SurfaceModel? { holder.model }
    var isVisible: Bool { hosted.panel.isVisible }
    var frame: NSRect { hosted.panel.frame }
    var onVisibilityChange: ((Bool) -> Void)?
    /// The surface ended here: left past its time, an overlay's life was up, or an overlay was closed.
    var onExpired: ((SurfaceModel, SurfaceCloseReason) -> Void)?
    var onBack: ((SurfaceModel) -> Void)? {
        get { holder.onBack }
        set { holder.onBack = newValue }
    }
    var onSpeaker: ((SurfaceModel) -> Void)? {
        get { holder.onSpeaker }
        set { holder.onSpeaker = newValue }
    }
    var onCloseButton: ((SurfaceModel) -> Void)? {
        get { holder.onClose }
        set { holder.onClose = newValue }
    }

    init(presentation: SurfaceInfo.Presentation) {
        self.presentation = presentation
    }

    func kept(_ info: SurfaceInfo) -> SurfaceModel? {
        guard let model = holder.model, model.info == info, model.failure == nil, Date().timeIntervalSince(model.lastActive) < SurfacePolicy.keptFor else { return nil }
        return model
    }

    func show(_ model: SurfaceModel, beside anchor: NSRect, on screen: NSScreen, cards: @escaping () -> [NSRect], focus: Bool) {
        expiry?.cancel()
        holder.model = model
        placed = (anchor, screen, cards)
        model.onResize = { [weak self] in self?.place() }
        place()
        hosted.panel.orderFrontRegardless()
        if focus, presentation == .panel {
            hosted.panel.makeKey()
            model.view.focusField()
        }
        if keyMonitor == nil, presentation == .panel { watchKeys() }
        onVisibilityChange?(true)
        if presentation == .overlay { startLife(model) }
    }

    /// An overlay goes by itself when its time is up: nothing of an extension's stays on the desktop unattended.
    private func startLife(_ model: SurfaceModel) {
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SurfacePolicy.overlayLifetime))
            guard !Task.isCancelled, let self, self.holder.model === model else { return }
            self.onExpired?(model, .timeout)
        }
    }

    private func place() {
        guard let placed, let model = holder.model else { return }
        let header = presentation == .panel ? SurfacePolicy.headerHeight : SurfacePolicy.chipHeight
        let width = max(model.canvas.width, presentation == .panel ? 260 : 170)
        let size = CGSize(width: width, height: model.canvas.height + header)
        let frame = SurfacePolicy.place(size: size, presentation: presentation, beside: placed.anchor, screen: placed.screen.visibleFrame, avoiding: placed.cards())
        hosted.panel.setFrame(frame, display: true)
    }

    func reposition(beside anchor: NSRect, on screen: NSScreen) {
        guard isVisible, let cards = placed?.cards else { return }
        placed = (anchor, screen, cards)
        place()
    }

    private func watchKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.hosted.panel, let model = self.holder.model else { return event }
            // A text field being typed in (through the input method) keeps its keys.
            if self.hosted.panel.firstResponder is NSTextView { return event }
            guard let key = PlayPanelController.key(event) else { return event }
            let command = event.modifierFlags.contains(.command)
            let now = Date()
            switch SurfacePolicy.route(key, command: command, scene: model.scene, lastEscape: self.lastEscape, now: now) {
            case .system: return event
            case .close:
                self.hide()
                return nil
            case .back:
                model.send(.back)
                return nil
            case .scene:
                if key == "escape" { self.lastEscape = now }
                // Return and Space are the scene's alone: never a press of whichever frame button has the focus.
                return model.press(key, seat: PlayPanelController.seat(event), timestamp: event.timestamp) || key == "return" || key == "space" ? nil : event
            }
        }
    }

    /// Puts it away, keeping it ten minutes (an overlay ends: it was a moment).
    func hide() {
        guard isVisible else { return }
        hosted.panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        onVisibilityChange?(false)
        guard let model = holder.model else { return }
        model.pause()
        if presentation == .overlay {
            expiry?.cancel()
            onExpired?(model, .closed)
            return
        }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SurfacePolicy.keptFor))
            guard !Task.isCancelled, let self, self.holder.model === model, !self.isVisible else { return }
            self.onExpired?(model, .timeout)
        }
    }

    /// Forgets what is kept: another is opening, or it ended.
    func drop() {
        expiry?.cancel()
        holder.model = nil
    }

    #if DEBUG
    /// A click, or a drag along points, on the canvas (points from its top left), through AppKit as the mouse's arrive.
    func devMouse(_ points: [CGPoint], steps: Int = 8) async {
        guard let view = holder.model?.view, let window = view.window, let first = points.first else { return }
        func post(_ type: NSEvent.EventType, _ p: CGPoint) {
            let location = view.convert(p, to: nil)
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            window.sendEvent(event)
        }
        post(.leftMouseDown, first)
        var last = first
        for point in points.dropFirst() {
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps)
                post(.leftMouseDragged, CGPoint(x: last.x + (point.x - last.x) * t, y: last.y + (point.y - last.y) * t))
                try? await Task.sleep(for: .milliseconds(30))
            }
            last = point
        }
        post(.leftMouseUp, last)
    }
    #endif
}

@MainActor @Observable
final class SurfaceHolder {
    var model: SurfaceModel?
    var onBack: ((SurfaceModel) -> Void)?
    var onSpeaker: ((SurfaceModel) -> Void)?
    var onClose: ((SurfaceModel) -> Void)?
}

struct SurfaceRoot: View {
    var holder: SurfaceHolder

    var body: some View {
        if let model = holder.model {
            SurfaceFrame(model: model, onBack: { holder.onBack?(model) }, onSpeaker: { holder.onSpeaker?(model) }, onClose: { holder.onClose?(model) })
                .id(model.info.id)
        } else {
            Color.clear.frame(width: 10, height: 10)
        }
    }
}
