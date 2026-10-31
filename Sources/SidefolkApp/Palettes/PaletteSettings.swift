import AppKit
import KeyboardShortcuts
import SidefolkCore
import SwiftUI

/// Where a palette opens (D68), as Maccy offers: near the top of the screen like Spotlight (the first way), at the
/// pointer, or in the middle; from the menu bar icon's menu it opens under the icon. Sidefolk's choice, kept per
/// palette with its shortcut, not the extension's: it decides nothing about the list.
enum PalettePosition: String, CaseIterable, Identifiable {
    case top, pointer, center, menuBar
    var id: String { rawValue }

    static let choices: [PalettePosition] = [.top, .pointer, .center]

    static func key(_ info: ExtensionPaletteInfo) -> String { "palette.\(info.id).position" }

    static func saved(_ info: ExtensionPaletteInfo) -> PalettePosition {
        UserDefaults.standard.string(forKey: key(info)).flatMap(PalettePosition.init(rawValue:)).flatMap { choices.contains($0) ? $0 : nil } ?? .top
    }

    var title: String {
        switch self {
        case .top: String(localized: "Top of the screen", comment: "Where a palette opens")
        case .pointer: String(localized: "At the pointer", comment: "Where a palette opens")
        case .center: String(localized: "Middle of the screen", comment: "Where a palette opens")
        case .menuBar: String(localized: "Under the menu bar icon", comment: "Where a palette opens")
        }
    }

    /// The panel's bottom-left corner on the screen the pointer is on, kept inside it.
    func origin(for size: NSSize, menuIcon: NSRect?, pointer: NSPoint = NSEvent.mouseLocation) -> NSPoint {
        let anchor = menuIcon.map { NSPoint(x: $0.midX, y: $0.minY) } ?? pointer
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .zero }
        var origin: NSPoint
        switch self {
        case .top: origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.22 - size.height)
        case .center: origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        case .pointer: origin = NSPoint(x: pointer.x - 24, y: pointer.y - size.height + 12)
        case .menuBar: origin = NSPoint(x: anchor.x - size.width / 2, y: frame.maxY - size.height - 4)
        }
        origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
        origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - size.height)
        return origin
    }
}

/// A palette's row on its extension's page: its shortcut, changeable, and where it opens. Sidefolk's own part of the
/// page (D63), not the extension's.
struct PaletteSettingsRow: View {
    var info: ExtensionPaletteInfo
    @AppStorage private var position: String

    init(info: ExtensionPaletteInfo) {
        self.info = info
        _position = AppStorage(wrappedValue: PalettePosition.top.rawValue, PalettePosition.key(info))
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "keyboard").foregroundStyle(Theme.inkMuted)
            Text("Open \(info.title) from any app", comment: "An extension's palette and its keyboard shortcut")
                .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            Spacer(minLength: Theme.Space.m)
            Picker(selection: $position) {
                ForEach(PalettePosition.choices) { Text(verbatim: $0.title).tag($0.rawValue) }
            } label: { Text("Opens", comment: "Where an extension's palette opens: a menu's label") }
                .labelsHidden()
                .fixedSize()
                .help(Text("Where it opens", comment: "Help on the menu choosing where a palette opens"))
            KeyboardShortcuts.Recorder(for: PaletteController.shortcutName(info))
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }
}
