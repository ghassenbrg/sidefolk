import AppKit
import SwiftUI

/// Lantern's sizes, depth, glass and symbols (D84, docs/DESIGN.md). Sizes are the same in every theme: themes dress
/// the app (colours, faces, density, corners, materials), they don't move its parts.
extension Theme {
    enum Size {
        /// Rows: a list row, a compact row, a row in Home's sidebar.
        static let row: CGFloat = 44
        static let compactRow: CGFloat = 32
        static let sidebarRow: CGFloat = 30
        /// The least a click target may be, and an icon-only button.
        static let hitTarget: CGFloat = 28
        /// Buttons: small, in a window, in the Sidecard, large (a page's one main action).
        static let buttonSmall: CGFloat = 24
        static let button: CGFloat = 28
        static let buttonSidecard: CGFloat = 30
        static let buttonLarge: CGFloat = 32
        /// A text field and the search, in a window.
        static let field: CGFloat = 28
        /// The Say bar: in Home's toolbar, and on the desktop.
        static let sayBarHome: CGFloat = 40
        static let sayBarDesktop: CGFloat = 52
        static let sayBarHomeMaxWidth: CGFloat = 560
        static let chip: CGFloat = 22
        /// A row's leading icon, and a folk's avatar in its three sizes.
        static let rowIcon: CGFloat = 24
        static let avatarSmall: CGFloat = 24
        static let avatar: CGFloat = 32
        static let avatarLarge: CGFloat = 48
        /// Home: the sidebar, the content's widest and its padding (24 under 900 points).
        static let sidebar: CGFloat = 232
        static let sidebarMin: CGFloat = 200
        static let contentMaxWidth: CGFloat = 1080
        static let contentPadding: CGFloat = 32
        static let contentPaddingNarrow: CGFloat = 24
        static let columnGap: CGFloat = 24
        /// Sheets, and the install sheet (D71).
        static let sheet: CGFloat = 520
        static let installSheet: CGFloat = 600
        /// The Sidecard: a card's width range, and Ask's. German needs up to 400 (package B's notes).
        static let sidecardMin: CGFloat = 320
        static let sidecardMax: CGFloat = 400
        static let sidecardAsk: CGFloat = 420
        /// The count on the companion's shoulder when cards wait.
        static let stackBadge: CGFloat = 28
        /// A tile on Today or a page, and a pin on the desktop.
        static let tileMin: CGFloat = 160
        static let tileMax: CGFloat = 240
        static let pin: CGFloat = 36
    }

    /// How far something sits above the page: e0 flat in a list, e1 a card on the canvas, e2 a popover or a tile
    /// under the pointer, e3 the Sidecard, a sheet, the Pocket.
    enum Elevation: Int, CaseIterable {
        case e0, e1, e2, e3
    }

    /// Focus and Quiet look the same everywhere (D84): a half circle for Focus, a moon for Quiet.
    enum Symbol {
        static let focus = "circle.lefthalf.filled"
        static let quiet = "moon.fill"
        /// The Say bar and Ask: words to the companion.
        static let say = "sparkle"
    }
}

extension View {
    /// Lantern's depth (Theme.Elevation): a shadow in light, a hairline in dark where shadows don't read, and with
    /// Increase Contrast the hairline becomes a control's border.
    func elevation(_ level: Theme.Elevation, radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(ElevationModifier(level: level, radius: radius))
    }

    /// The Sidecard's and the Pocket's glass: the wallpaper's colour through a blur, a hairline and e3. With Reduce
    /// Transparency it is the card surface, opaque.
    /// `elevation`: e3 for the Sidecard and the Pocket; e2 for small glass on the desktop (pins), whose shadow
    /// would otherwise reach further than the pin.
    func lanternGlass(radius: CGFloat = Theme.Radius.panel, elevation: Theme.Elevation = .e3) -> some View {
        modifier(GlassModifier(radius: radius, elevation: elevation))
    }
}

private struct ElevationModifier: ViewModifier {
    var level: Theme.Elevation
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .overlay {
                if level != .e0 {
                    shape.strokeBorder(contrast == .increased ? Theme.controlBorder : dark ? Color.white.opacity(0.06) : Theme.line)
                }
            }
            .shadow(color: shadow(dark: dark).color, radius: shadow(dark: dark).radius, y: shadow(dark: dark).y)
    }

    /// 03-system's elevation table, as SwiftUI radii (half the CSS blur).
    private func shadow(dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        let ink = Color(hex: 0x0F1E36)
        switch level {
        case .e0: return (.clear, 0, 0)
        case .e1: return dark ? (.clear, 0, 0) : (ink.opacity(0.05), 1, 1)
        case .e2: return (dark ? .black.opacity(0.4) : ink.opacity(0.10), 9, 6)
        case .e3: return (dark ? .black.opacity(0.55) : ink.opacity(0.18), 24, 18)
        }
    }
}

extension EnvironmentValues {
    /// Glass drawn as solid surfaces, as Reduce Transparency has it; for snapshots of that setting, which a view can't
    /// set. The system's own setting is read beside it.
    @Entry var solidSurfaces = false
}

private struct GlassModifier: ViewModifier {
    var radius: CGFloat
    var elevation: Theme.Elevation
    @Environment(\.accessibilityReduceTransparency) private var systemSolid
    @Environment(\.solidSurfaces) private var solid
    private var reduceTransparency: Bool { systemSolid || solid }
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Theme.surfaceRaised)
                } else {
                    // 03-system: rgba(250,251,253,.72) in light, rgba(24,30,43,.70) in dark, over a 30 pt blur.
                    shape.fill(.regularMaterial)
                        .overlay(shape.fill(scheme == .dark ? Color(hex: 0x181E2B, opacity: 0.7) : Color(hex: 0xFAFBFD, opacity: 0.72)))
                }
            }
            .elevation(elevation, radius: radius)
    }
}
