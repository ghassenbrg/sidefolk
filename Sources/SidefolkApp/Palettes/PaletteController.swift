import AppKit
import ApplicationServices
import KeyboardShortcuts
import SidefolkCore
import SwiftUI

/// Extensions' palettes (D63): each on its keyboard shortcut, in a panel that doesn't take the app in front away, so
/// choosing an item can paste straight into it.
@MainActor
final class PaletteController {
    private let host: ExtensionHost
    private var registered: Set<String> = []
    private var panel: FloatingPanel?
    private var model: PaletteModel?
    private var resignObserver: NSObjectProtocol?

    init(host: ExtensionHost) {
        self.host = host
    }

    static func shortcutName(_ info: ExtensionPaletteInfo) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("palette.\(info.id)", default: info.hotkey.flatMap(Self.shortcut))
    }

    /// Registers the shortcut of every palette now on, and drops those gone; call it when extensions change.
    func refresh() async {
        let palettes = await host.palettes()
        let ids = Set(palettes.map(\.id))
        for gone in registered.subtracting(ids) {
            KeyboardShortcuts.disable(KeyboardShortcuts.Name("palette.\(gone)"))
            registered.remove(gone)
        }
        for info in palettes where !registered.contains(info.id) {
            let name = Self.shortcutName(info)
            KeyboardShortcuts.enable(name)
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in Task { await self?.toggle(info.id) } }
            registered.insert(info.id)
        }
    }

    func toggle(_ id: String) async {
        if let panel, panel.isVisible, model?.info.id == id { return hide() }
        guard let info = await host.palettes().first(where: { $0.id == id }) else { return }
        show(PaletteModel(info: info, host: host))
    }

    private func show(_ model: PaletteModel) {
        hide()
        self.model = model
        model.onClose = { [weak self] paste in self?.hide(paste: paste) }
        let panel = FloatingPanel(size: NSSize(width: 600, height: 440))
        panel.contentViewController = NSHostingController(rootView: PaletteView(model: model))
        panel.onCancel = { [weak self] in self?.hide() }
        // The upper part of the screen the pointer is on, like Spotlight.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - 300, y: frame.maxY - frame.height * 0.22 - 440))
        }
        panel.makeKeyAndOrderFront(nil)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        self.panel = panel
        Task { await model.reload() }
    }

    private func hide(paste: Bool = false) {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        if paste { Self.paste() }
    }

    /// ⌘V into the app in front, which never lost focus to the panel. Posting keys needs Accessibility; without it the
    /// item is on the clipboard and macOS asks once.
    static func paste() {
        guard AXIsProcessTrusted() else {
            // kAXTrustedCheckOptionPrompt's value, spelled out: the constant is a global var Swift 6 won't read.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    /// A pointer move of nothing where the pointer is: apps watching for activity (chat, meetings) see some, and
    /// nothing moves on screen (D63). Like pasting, it needs Accessibility; without it, nothing happens.
    static func nudge() {
        guard AXIsProcessTrusted(), let here = CGEvent(source: nil)?.location else { return }
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: here, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// `shift+cmd+v` → ⇧⌘V.
    static func shortcut(_ text: String) -> KeyboardShortcuts.Shortcut? {
        var modifiers: NSEvent.ModifierFlags = []
        var key: KeyboardShortcuts.Key?
        for part in text.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "option": modifiers.insert(.option)
            case "ctrl": modifiers.insert(.control)
            default: key = keys[part]
            }
        }
        return key.map { KeyboardShortcuts.Shortcut($0, modifiers: modifiers) }
    }

    private static let keys: [String: KeyboardShortcuts.Key] = [
        "a": .a, "b": .b, "c": .c, "d": .d, "e": .e, "f": .f, "g": .g, "h": .h, "i": .i, "j": .j, "k": .k, "l": .l, "m": .m,
        "n": .n, "o": .o, "p": .p, "q": .q, "r": .r, "s": .s, "t": .t, "u": .u, "v": .v, "w": .w, "x": .x, "y": .y, "z": .z,
        "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four, "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
        "space": .space, "f1": .f1, "f2": .f2, "f3": .f3, "f4": .f4, "f5": .f5, "f6": .f6, "f7": .f7, "f8": .f8, "f9": .f9,
        "f10": .f10, "f11": .f11, "f12": .f12,
    ]
}
