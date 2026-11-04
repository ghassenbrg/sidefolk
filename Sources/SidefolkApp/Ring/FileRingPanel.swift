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
    var hover: ((Int?) -> Void)?
    var dropped: (([URL]) -> Bool)?
    var clicked: (() -> Void)?
    var locate: ((NSPoint) -> Int?)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func follow(_ point: NSPoint) -> Int? {
        let index = locate?(convert(point, from: nil))
        hover?(index)
        return index
    }

    override func mouseMoved(with event: NSEvent) { _ = follow(event.locationInWindow) }
    override func mouseUp(with event: NSEvent) { if follow(event.locationInWindow) != nil { clicked?() } }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { follow(sender.draggingLocation) == nil ? [] : .copy }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { follow(sender.draggingLocation) == nil ? [] : .copy }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { hover?(nil) }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard follow(sender.draggingLocation) != nil else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return dropped?(urls) ?? false
    }
}
