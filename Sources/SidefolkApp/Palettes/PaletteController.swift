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
    /// The palettes now on, for the menu bar icon's menu.
    private(set) var current: [ExtensionPaletteInfo] = []
    private var panel: FloatingPanel?
    private var model: PaletteModel?
    private var resignObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    init(host: ExtensionHost) {
        self.host = host
    }

    static func shortcutName(_ info: ExtensionPaletteInfo) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("palette.\(info.id)", default: info.hotkey.flatMap(Self.shortcut))
    }

    /// Registers the shortcut of every palette now on, and drops those gone; call it when extensions change.
    func refresh() async {
        let palettes = await host.palettes()
        current = palettes
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

    /// Opens or closes the palette; `under` is the menu bar icon's frame when it was opened from its menu.
    func toggle(_ id: String, under: NSRect? = nil) async {
        if let panel, panel.isVisible, model?.info.id == id { return hide() }
        guard let info = await host.palettes().first(where: { $0.id == id }) else { return }
        // The list first, so the panel opens at its size (with the preview beside it or not) and nothing jumps.
        let model = PaletteModel(info: info, host: host)
        await model.reload()
        show(model, under: under)
    }

    private func show(_ model: PaletteModel, under: NSRect?) {
        hide()
        self.model = model
        model.onClose = { [weak self] paste in self?.hide(paste: paste) }
        let size = NSSize(width: PaletteView.width(preview: model.hasPreview), height: PaletteView.height)
        let panel = FloatingPanel(size: size)
        panel.contentViewController = NSHostingController(rootView: PaletteView(model: model))
        panel.onCancel = { [weak self] in self?.hide() }
        let position = under == nil ? PalettePosition.saved(model.info) : .menuBar
        panel.setFrameOrigin(position.origin(for: size, menuIcon: under))
        panel.makeKeyAndOrderFront(nil)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        // Maccy's keys and the row numbers, read before the search field so ⌥P pins instead of typing π (PaletteKeys).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel, let model = self.model else { return event }
            let flags = event.modifierFlags
            guard let command = PaletteKeys.command(keyCode: event.keyCode, command: flags.contains(.command), option: flags.contains(.option),
                                                    shift: flags.contains(.shift), control: flags.contains(.control)) else { return event }
            model.handle(command)
            return nil
        }
        // A list that starts or stops offering a preview changes the panel's width, about its middle.
        model.onPreviewChange = { [weak panel] wide in
            guard let panel else { return }
            var frame = panel.frame
            let width = PaletteView.width(preview: wide)
            frame.origin.x += (frame.width - width) / 2
            frame.size.width = width
            panel.setFrame(frame, display: true)
        }
        self.panel = panel
    }

    private func hide(paste: Bool = false) {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        if paste { Self.paste() }
    }

    #if DEBUG
    /// A key in the open palette, for scripts/dev.swift: `down`, `up`, or a key code with `cmd`, `opt`, `shift`.
    func press(_ spec: String) {
        guard let model else { return }
        let parts = spec.split(separator: ":").map(String.init)
        switch parts.first {
        case "down": model.move(1)
        case "up": model.move(-1)
        default:
            guard let code = parts.first.flatMap(UInt16.init),
                  let command = PaletteKeys.command(keyCode: code, command: parts.contains("cmd"), option: parts.contains("opt"),
                                                    shift: parts.contains("shift"), control: false) else { return }
            model.handle(command)
        }
    }
    #endif

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
