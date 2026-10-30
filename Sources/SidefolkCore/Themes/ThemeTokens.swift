import Foundation

/// What a theme sets, as plain values: colours as light and dark pairs, spacing, corner radii and the face headings
/// use (D58). The app turns them into SwiftUI colours and fonts; keeping them here lets theme files be read and
/// checked without a window. Harbor is the default, and its values are the app's original design tokens.
public struct ThemeTokens: Sendable, Equatable {
    /// A colour for each appearance, as 0xRRGGBB.
    public struct Pair: Sendable, Equatable {
        public var light: UInt32
        public var dark: UInt32

        public init(light: UInt32, dark: UInt32) {
            self.light = light
            self.dark = dark
        }

        /// The same colour in both appearances.
        public init(_ both: UInt32) {
            self.init(light: both, dark: both)
        }
    }

    /// Colours by role, not by hue, so a theme can't make an error look like a success.
    public struct Colors: Sendable, Equatable {
        public var ink: Pair
        public var inkMuted: Pair
        public var inkFaint: Pair
        public var surface: Pair
        public var surfaceSunken: Pair
        public var surfaceRaised: Pair
        public var line: Pair
        public var accent: Pair
        /// Text on `accent`; the default's navy on aqua keeps 7:1.
        public var onAccent: Pair
        public var accentSoft: Pair
        public var danger: Pair
        public var dangerSoft: Pair
        /// Text on a `danger` fill.
        public var onDanger: Pair
        public var success: Pair
        public var successSoft: Pair
        /// The greeting's wash, from one corner to the other.
        public var heroStart: Pair
        public var heroEnd: Pair
    }

    public struct Space: Sendable, Equatable {
        public var xxs, xs, s, m, l, xl, xxl: Double
    }

    public struct Radius: Sendable, Equatable {
        public var control, card, panel, bubble: Double
    }

    /// The face headings and the companion's words use; body text is always the system face.
    public enum Face: String, Sendable, Equatable, CaseIterable {
        case system, rounded, serif
    }

    public var id: String
    public var name: String
    public var colors: Colors
    public var space: Space
    public var radius: Radius
    public var display: Face

    public init(id: String, name: String, colors: Colors, space: Space, radius: Radius, display: Face) {
        self.id = id
        self.name = name
        self.colors = colors
        self.space = space
        self.radius = radius
        self.display = display
    }
}

extension ThemeTokens {
    /// The default theme: the approved navy and aqua identity, airy and rounded.
    public static let harbor = ThemeTokens(
        id: "harbor",
        name: "Harbor",
        colors: Colors(
            ink: Pair(light: 0x0F2D5B, dark: 0xE8EEF8),
            inkMuted: Pair(light: 0x5B6B85, dark: 0x9AA8BF),
            inkFaint: Pair(light: 0x8A97AD, dark: 0x6F7F99),
            surface: Pair(light: 0xFFFFFF, dark: 0x15233B),
            surfaceSunken: Pair(light: 0xF4F7FB, dark: 0x0E1A2E),
            surfaceRaised: Pair(light: 0xFFFFFF, dark: 0x1B2C49),
            line: Pair(light: 0xE2E8F0, dark: 0x26385A),
            accent: Pair(0x2ED4D9),
            onAccent: Pair(0x0F2D5B),
            accentSoft: Pair(light: 0xE3F9FA, dark: 0x173F4D),
            danger: Pair(light: 0xD9473A, dark: 0xFF8A7D),
            dangerSoft: Pair(light: 0xFFEDEA, dark: 0x4A2622),
            onDanger: Pair(light: 0xFFFFFF, dark: 0x0F2D5B),
            success: Pair(light: 0x2F9E6D, dark: 0x7DD3A7),
            successSoft: Pair(light: 0xE6F6EE, dark: 0x1D3D31),
            heroStart: Pair(light: 0xDDF6F7, dark: 0x153B49),
            heroEnd: Pair(light: 0xE6EFFD, dark: 0x1B2C49)
        ),
        space: Space(xxs: 2, xs: 4, s: 8, m: 12, l: 16, xl: 24, xxl: 32),
        radius: Radius(control: 8, card: 12, panel: 18, bubble: 20),
        display: .rounded
    )
}
