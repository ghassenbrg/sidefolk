import AppKit
import SwiftUI

/// Shows and hides the Ask panel beside the companion.
final class AskPanelController {
    let model: AskModel
    private let hosted: HostedPanel<AskView>
    private var resignObserver: NSObjectProtocol?
    var onVisibilityChange: ((Bool) -> Void)?

    init(model: AskModel, companionName: String, portrait: NSImage?, hotkey: String) {
        self.model = model
        hosted = HostedPanel(rootView: AskView(model: model, companionName: companionName, portrait: portrait, hotkey: hotkey), allowsKey: true)
        hosted.panel.onCancel = { [weak self] in self?.cancel() }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: hosted.panel,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didResignKey() }
        }
        model.onAutoClose = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { hosted.panel.isVisible }
    var frame: NSRect { hosted.panel.frame }

    func update(companionName: String, portrait: NSImage?, hotkey: String) {
        hosted.host.rootView = AskView(model: model, companionName: companionName, portrait: portrait, hotkey: hotkey)
    }

    func show(beside anchor: NSRect, on screen: NSScreen, focus: Bool = true) {
        model.freshenIfStale()
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
        hosted.place(beside: anchor, on: screen)
    }

    func hide() {
        guard isVisible else { return }
        hosted.panel.orderOut(nil)
        onVisibilityChange?(false)
    }

    private func cancel() {
        if !model.text.isEmpty { model.text = "" } else { hide() }
    }

    private func didResignKey() {
        // Stay up while work or a question is pending; otherwise get out of the way.
        if !model.busy && !model.entries.contains(where: \.isPinned) { hide() }
    }
}
