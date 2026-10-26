import AppKit
import SwiftUI

/// The install preview in a window of its own, for when Sidefolk's AI hands a draft over (D39). The
/// request was typed in the Ask panel, which never activates the app, and macOS may not let Sidefolk
/// come forward on its own: a sheet over Settings would then stay hidden (sheets hide while their app
/// is inactive), but a window shows, and asks nothing until clicked.
@MainActor
final class InstallPreviewWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(_ preview: ExtensionInstallPreview, model: SettingsModel) {
        window?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "Review an Extension")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.backgroundColor = NSColor(Theme.surface)
        let host = NSHostingController(rootView: InstallPreviewSheet(preview: preview, model: model) { [weak window] in window?.close() })
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        window.delegate = self
        window.center()
        self.window = window
        WindowActivation.show(window)
    }

    func windowWillClose(_ notification: Notification) {
        if let window { WindowActivation.closed(window) }
        window = nil
    }
}
