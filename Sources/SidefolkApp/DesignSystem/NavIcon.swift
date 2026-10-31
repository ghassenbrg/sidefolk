import AppKit
import SidefolkCore
import SwiftUI

// Home's navigation icons, simple or colorful (D67): the theme's choice (`layout.icons`) unless the person picked one in
// Settings › General. Simple is the glyph in its colour. Colorful is that glyph in white on a rounded tile of its
// colour, as System Settings draws its sidebar, and an extension's page shows its extension's own icon: the app's
// places stay glyphs either way, since they have no other picture to be honest about.

/// A place's icon in the sidebar or the rail.
struct NavIcon: View {
    var symbol: String
    var color: Color
    /// The tile's side when colorful; the glyph alone keeps the list's own size.
    var size: CGFloat = 20

    var body: some View {
        if ThemeStore.shared.icons == .colorful {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.18), color], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .frame(width: size, height: size)
                .overlay { Image(systemName: Self.drawable(symbol)).font(.system(size: size * 0.52, weight: .semibold)).foregroundStyle(.white) }
                .accessibilityHidden(true)
        } else {
            Image(systemName: Self.drawable(symbol)).foregroundStyle(color)
        }
    }

    /// Callers ask for a place's filled glyph; some have none ("calendar"), and an unknown name draws nothing.
    static func drawable(_ symbol: String) -> String {
        guard symbol.hasSuffix(".fill"), NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil else { return symbol }
        return String(symbol.dropLast(5))
    }
}

/// An extension page's icon in the navigation: its symbol, or its extension's own icon when colorful.
struct PageNavIcon: View {
    var info: ExtensionPageInfo
    var size: CGFloat = 20

    var body: some View {
        if ThemeStore.shared.icons == .colorful {
            ExtensionBadge(look: ExtensionLook(name: info.extensionName, iconPath: info.iconPath, folk: "byte"), size: size,
                           symbol: info.symbol ?? "puzzlepiece.extension")
        } else {
            Image(systemName: info.symbol ?? "puzzlepiece.extension").foregroundStyle(Theme.folkColor("byte"))
        }
    }
}
