import AppKit
import SidefolkCore
import SwiftUI

/// Sidefolk design tokens. Every color, size and radius in the UI comes from here. The brand palette and logo
/// plates are fixed; everything else is the active theme's (D58, `ThemeStore`), Harbor unless one is chosen.
enum Theme {
    // MARK: Brand palette (approved identity)
    static let navy = Color(hex: 0x0F2D5B)
    static let aqua = Color(hex: 0x2ED4D9)
    static let coral = Color(hex: 0xFF7B6B)
    static let mint = Color(hex: 0x7DD3A7)
    static let lightBlue = Color(hex: 0x93C5FD)
    static let sun = Color(hex: 0xFFC93C)

    private static var style: ThemeStyle { ThemeStore.shared.style }

    // MARK: Semantic, light/dark adaptive, from the theme
    static var ink: Color { style.ink }
    static var inkMuted: Color { style.inkMuted }
    static var inkFaint: Color { style.inkFaint }
    static var surface: Color { style.surface }
    static var surfaceSunken: Color { style.surfaceSunken }
    static var surfaceRaised: Color { style.surfaceRaised }
    static var line: Color { style.line }
    /// What a service's logo sits on, and the ink of one drawn in a single colour (D36). Both are neutral so
    /// brand colours never clash with a folk colour, and the ink is the pure black or white the owners ask for.
    /// The owners' rules don't change with a theme, so neither do these.
    static let logoPlate = Color(light: 0xFFFFFF, dark: 0x0E1A2E)
    static let logoInk = Color(light: 0x000000, dark: 0xFFFFFF)
    static var accent: Color { style.accent }
    static var onAccent: Color { style.onAccent }
    static var accentSoft: Color { style.accentSoft }
    /// The accent as text (links, "Open Today"); `accent` is for fills and icons, and may be too light to read.
    static var link: Color { style.link }
    static var danger: Color { style.danger }
    static var dangerSoft: Color { style.dangerSoft }
    static var onDanger: Color { style.onDanger }
    static var success: Color { style.success }
    static var successSoft: Color { style.successSoft }

    // MARK: Metrics
    enum Space {
        private static var space: ThemeTokens.Space { style.space }
        static var xxs: CGFloat { space.xxs }
        static var xs: CGFloat { space.xs }
        static var s: CGFloat { space.s }
        static var m: CGFloat { space.m }
        static var l: CGFloat { space.l }
        static var xl: CGFloat { space.xl }
        static var xxl: CGFloat { space.xxl }
    }

    enum Radius {
        private static var radius: ThemeTokens.Radius { style.tokens.radius }
        static var control: CGFloat { radius.control }
        static var card: CGFloat { radius.card }
        static var panel: CGFloat { radius.panel }
        static var bubble: CGFloat { radius.bubble }
    }

    enum Font {
        private static var fonts: ThemeStyle.Fonts { style.fonts }
        static var bubble: SwiftUI.Font { fonts.bubble }
        static var bubbleTitle: SwiftUI.Font { fonts.bubbleTitle }
        static var input: SwiftUI.Font { fonts.input }
        static var hint: SwiftUI.Font { fonts.hint }
        static var hero: SwiftUI.Font { fonts.hero }
        static var title: SwiftUI.Font { fonts.title }
        static var heading: SwiftUI.Font { fonts.heading }
        static var body: SwiftUI.Font { fonts.body }
        static var bodyStrong: SwiftUI.Font { fonts.bodyStrong }
        static var caption: SwiftUI.Font { fonts.caption }
        static var captionStrong: SwiftUI.Font { fonts.captionStrong }
        static var eyebrow: SwiftUI.Font { fonts.eyebrow }
    }

    /// How things move, in the theme's way. Each returns nil (no animation) when the theme asks for none; views
    /// still check Reduce Motion themselves, since what to do then depends on what moves.
    enum Motion {
        /// Something arriving, leaving or moving. Bouncy themes overshoot a little more and settle a little slower.
        static func spring(_ duration: Double, bounce: Double = 0) -> Animation? {
            switch style.tokens.motion {
            case .calm: .spring(duration: duration, bounce: bounce)
            case .bouncy: .spring(duration: duration * 1.15, bounce: bounce + 0.25)
            case .none: nil
            }
        }

        /// A quick change in place: a press, a fold opening.
        static func ease(_ duration: Double) -> Animation? {
            style.tokens.motion == .none ? nil : .easeOut(duration: duration)
        }
    }

    /// The theme's own pictures (D58), when it has them.
    enum Art {
        static var grain: CGImage? { style.grain }
        static var backdrop: CGImage? { style.backdrop }
        static var empty: CGImage? { style.emptyArt }
    }

    /// Accent color for each folk, used on cards of its domain.
    static func folkColor(_ name: String) -> Color {
        switch name {
        case "pip": coral
        case "tempo": lightBlue
        case "scout": sun
        case "byte": Color(hex: 0x4F7DF3)
        case "guard": Color(hex: 0x2BB3A3)
        case "seed": mint
        case "melody": Color(hex: 0xA77BF3)
        case "nova": Color(hex: 0xC4A5F5)
        case "play": Color(hex: 0xF25C5C)
        case "brew": Color(hex: 0xE9C79A)
        default: aqua
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// A color that follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
