import AppKit
import SwiftUI

/// A borderless, non-activating floating panel: typing into it never steals the frontmost app.
final class FloatingPanel: NSPanel {
    var allowsKey = true
    var onCancel: (() -> Void)?

    init(size: NSSize = NSSize(width: 380, height: 120)) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Hosts SwiftUI content in a FloatingPanel that resizes to fit it.
final class HostedPanel<Content: View> {
    let panel: FloatingPanel
    let host: NSHostingController<Content>
    private var lastPlacement: (() -> Void)?
    private var resizeObserver: NSObjectProtocol?
    private var replacing = false

    init(rootView: Content, allowsKey: Bool) {
        panel = FloatingPanel()
        panel.allowsKey = allowsKey
        host = NSHostingController(rootView: rootView)
        host.sizingOptions = [.preferredContentSize]
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        panel.contentViewController = host
        // SwiftUI resizes the window from its top-left corner; re-anchor to the companion instead.
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.replacing else { return }
                self.lastPlacement?()
            }
        }
    }

    var fittingSize: NSSize {
        host.view.layoutSubtreeIfNeeded()
        let ideal = host.sizeThatFits(in: NSSize(width: 600, height: 2000))
        return ideal.width > 1 && ideal.height > 1 ? ideal : host.view.fittingSize
    }

    /// Places the panel next to `anchor` (the companion's frame), on the side with more room,
    /// fully inside the visible frame of `screen`.
    func place(beside anchor: NSRect, on screen: NSScreen, gap: CGFloat = 10, preferAbove: Bool = false) {
        lastPlacement = { [weak self] in self?.place(beside: anchor, on: screen, gap: gap, preferAbove: preferAbove) }
        let size = panel.isVisible && panel.frame.height > 1 ? panel.frame.size : fittingSize
        let visible = screen.visibleFrame
        var origin: NSPoint
        if preferAbove {
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
            if origin.y + size.height > visible.maxY { origin.y = anchor.minY - gap - size.height }
        } else {
            let roomLeft = anchor.minX - visible.minX
            let roomRight = visible.maxX - anchor.maxX
            let x = roomLeft >= roomRight ? anchor.minX - gap - size.width : anchor.maxX + gap
            origin = NSPoint(x: x, y: anchor.minY + anchor.height * 0.35)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        replacing = true
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        replacing = false
    }
}
