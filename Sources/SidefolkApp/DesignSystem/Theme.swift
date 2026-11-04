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
    /// Waiting or needing a look (late, waiting on you): amber, readable as text. Not an error.
    static var warning: Color { style.warning }
    static var warningSoft: Color { style.warningSoft }
    static var onWarning: Color { style.onWarning }
    /// Wells inside a card: fields, the search, chips, a segmented track (D84).
    static var well: Color { style.well }
    /// The companion's light while it works or listens, and when something waits on the person: light, never text.
    static var glow: Color { style.glow }
    static var waitGlow: Color { style.waitGlow }
    /// The sidebar's plane and what's on it, its selected row (the theme's, not macOS's), and words over Today's scene (D130).
    static var sidebar: Color { style.sidebar }
    static var sidebarInk: Color { style.sidebarInk }
    static var sidebarInkMuted: Color { style.sidebarInkMuted }
    static var sidebarSelected: Color { style.sidebarSelected }
    static var onSidebarSelected: Color { style.onSidebarSelected }
    static var sceneInk: Color { style.sceneInk }
    static var sceneInkMuted: Color { style.sceneInkMuted }
    /// The keyboard's ring (`.focusRing`), 3:1 from a card and the page (D220).
    static var focus: Color { style.focus }
    /// The border of a control that has no fill of its own (a secondary button, an unchecked box): about 3:1 from a card,
    /// so the control can be found without its words (D220).
    static var controlBorder: Color { style.inkFaint.opacity(0.7) }

    /// A status's colour for text and icons, and its soft fill (StatusTone, docs/ARCHITECTURE.md › Colour meaning).
    /// Pair it with a word or an icon: colour is never the only signal.
    static func color(_ tone: StatusTone) -> Color {
        switch tone {
        case .success: success
        case .warning: warning
        case .danger: danger
        case .news: link
        case .neutral: inkMuted
        }
    }

    static func soft(_ tone: StatusTone) -> Color {
        switch tone {
        case .success: successSoft
        case .warning: warningSoft
        case .danger: dangerSoft
        case .news: accentSoft
        case .neutral: surfaceSunken
        }
    }

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
        /// Lantern's 48 and 64, after the theme's density.
        static var xxxl: CGFloat { space.xxl * 1.5 }
        static var xxxxl: CGFloat { space.xxl * 2 }
    }

    enum Radius {
        private static var radius: ThemeTokens.Radius { style.tokens.radius }
        static var control: CGFloat { radius.control }
        static var card: CGFloat { radius.card }
        static var panel: CGFloat { radius.panel }
        static var bubble: CGFloat { radius.bubble }
        /// Inside a chip, a checkbox: three quarters of a control's corner.
        static var xs: CGFloat { (radius.control * 0.75).rounded() }
    }

    /// Lantern's type scale (D84): display (the greeting, empty pages), title1 (a place), title2 (a section, a sheet),
    /// headline (a card or row title), body, callout (a second line), caption, eyebrow (a group, sentence case),
    /// stateWord and number (tiles, pins), bubble (the Sidecard), input (the Say bar), mono (the exact request only).
    enum Font {
        private static var fonts: ThemeStyle.Fonts { style.fonts }
        static var display: SwiftUI.Font { fonts.display }
        static var greeting: SwiftUI.Font { fonts.greeting }
        static var title1: SwiftUI.Font { fonts.title1 }
        static var title2: SwiftUI.Font { fonts.title2 }
        static var headline: SwiftUI.Font { fonts.headline }
        static var callout: SwiftUI.Font { fonts.callout }
        static var stateWord: SwiftUI.Font { fonts.stateWord }
        static var number: SwiftUI.Font { fonts.number }
        static var mono: SwiftUI.Font { fonts.mono }
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

        // Lantern's motion tokens (D84). Views still check Reduce Motion: then nothing scales or travels, and the
        // light pool shows its state as a still colour.
        /// Hover, press, a chip toggling: 120 ms.
        static var micro: Animation? { style.tokens.motion == .none ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.12) }
        /// A list changing, a tab switching: 200 ms.
        static var standard: Animation? { style.tokens.motion == .none ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2) }
        /// The Sidecard growing, a sheet arriving.
        static var enter: Animation? {
            switch style.tokens.motion {
            case .calm: .spring(response: 0.32, dampingFraction: 0.86)
            case .bouncy: .spring(response: 0.36, dampingFraction: 0.7)
            case .none: nil
            }
        }
        /// Something dismissed: 160 ms, easing in.
        static var exit: Animation? { style.tokens.motion == .none ? nil : .timingCurve(0.4, 0, 1, 1, duration: 0.16) }
        /// The working light's breath: 3 s, back and forth.
        static var breath: Animation? { style.tokens.motion == .none ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true) }
    }

    /// The theme's own pictures (D58), when it has them.
    enum Art {
        static var grain: CGImage? { style.grain }
        static func page(dark: Bool) -> CGImage? { dark ? style.pageDark : style.page }
        static var backdrop: CGImage? { style.backdrop }
        /// Today's picture, and the sidebar's header (D130); each appearance falls back to the other's.
        static func scene(dark: Bool) -> CGImage? { dark ? style.sceneDark ?? style.scene : style.scene ?? style.sceneDark }
        static func header(dark: Bool) -> CGImage? { dark ? style.headerDark ?? style.header : style.header ?? style.headerDark }
        static func backdrop(dark: Bool) -> CGImage? { dark ? style.backdropDark ?? style.backdrop : style.backdrop }
        static var empty: CGImage? { style.emptyArt }
        static var tile: CGImage? { style.artTile }
    }

    /// Accent color for each folk, used on cards of its domain: a dot, an avatar's disc, a 2 pt bar (Lantern's folk
    /// accents, D84). Identity, never status: a folk's colour never says that something went well or badly, even when
    /// it happens to be green or red, and it is never body text.
    static func folkColor(_ name: String) -> Color {
        switch name {
        case "pip": coral
        case "tempo": Color(hex: 0x5B8DEF)
        case "scout": Color(hex: 0xF2B33D)
        case "byte": Color(hex: 0x3B6FF5)
        case "guard": Color(hex: 0x1FA88A)
        case "seed": Color(hex: 0x52C08A)
        case "melody": Color(hex: 0x8E6CF0)
        case "nova": Color(hex: 0xA68BFA)
        case "play": Color(hex: 0xF0524F)
        case "brew": Color(hex: 0xC99A5B)
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
