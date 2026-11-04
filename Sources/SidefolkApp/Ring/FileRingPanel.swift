import AppKit
import SidefolkCore
import SwiftUI

/// The ring's window. It takes a drag or clicks and never activates Sidefolk, so the app the person is in stays in front.
final class FileRingPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: RingLayout.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        // On every Space and over full-screen apps, or a drag there would have no ring.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Takes the drag, and the clicks when the shortcut opened it. A slice is found from the pointer alone, so a stray release chooses nothing.
final class FileRingSurface: NSView {
    /// The pointer is here: whether a slice there would take a drop.
    var follow: ((NSPoint) -> Bool)?
    var left: (() -> Void)?
    var dropped: (([URL]) -> Bool)?
    var clicked: (() -> Void)?
    var scrolled: ((NSEvent) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func track(_ point: NSPoint) -> Bool { follow?(convert(point, from: nil)) ?? false }

    /// What the source allows: the person's held key can narrow a drag to link or generic, and asking for copy then gets the drop refused.
    private func operation(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard track(sender.draggingLocation) else { return [] }
        let allowed = sender.draggingSourceOperationMask
        // Never move: a source may delete its copy on that answer, while the extension is about to read it and the card says the original is as it was.
        return [.copy, .generic, .link].first { allowed.contains($0) } ?? []
    }

    override func mouseMoved(with event: NSEvent) { _ = track(event.locationInWindow) }
    override func scrollWheel(with event: NSEvent) { scrolled?(event) }
    override func mouseUp(with event: NSEvent) { if track(event.locationInWindow) { clicked?() } }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { operation(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { operation(sender) }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { left?() }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard track(sender.draggingLocation) else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return dropped?(urls) ?? false
    }
}
