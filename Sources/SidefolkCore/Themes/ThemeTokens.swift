import Foundation

/// What a theme sets, as plain values (D58): colours as light and dark pairs, spacing and density, type, corner radii,
/// motion, the sidebar's material, the companion's nook and Home's icons (`ThemeLayout`). The app turns
/// them into SwiftUI values; keeping them here lets theme files be read and checked without a window. Harbor is the
/// default.
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

    /// Colours by role, not by hue, so a theme can't make an error look like a success. What each status role means
    /// is `StatusTone`'s, and the check holds danger to red, warning to amber and success to green.
    public struct Colors: Sendable, Equatable {
        public var ink: Pair
        public var inkMuted: Pair
        public var inkFaint: Pair
        public var surface: Pair
        public var surfaceSunken: Pair
        public var surfaceRaised: Pair
        public var line: Pair
        /// Fills and icons: buttons, selection, the focus ring.
        public var accent: Pair
        /// Text on `accent`.
        public var onAccent: Pair
        public var accentSoft: Pair
        /// The accent as text (links, "Open Today"): readable on every surface, unlike a bright fill colour.
        public var link: Pair
        /// An error, a failure, a destructive action or real risk; readable as text.
        public var danger: Pair
        public var dangerSoft: Pair
        /// Text on a `danger` fill.
        public var onDanger: Pair
        public var success: Pair
        public var successSoft: Pair
        /// Needs a look or is waiting (late, waiting on you): amber, readable as text, never an error.
        public var warning: Pair
        public var warningSoft: Pair
        /// Text on a `warning` fill, like the count of what waits on you.
        public var onWarning: Pair
        /// Wells inside a card: fields, the search, chips, a segmented control's track (Lantern's `sunken`, D84).
        /// Darker than a card in light, lighter in dark. Optional: a theme without it uses its `surfaceSunken`.
        public var well: Pair
        /// The light at the companion's feet while it works or listens (D84). Light, never text. Optional.
        public var glow: Pair
        /// The light when something waits on the person, and the count on its shoulder. Light, never text. Optional.
        public var waitGlow: Pair

        /// Every role by its name in a theme file, in this order.
        public static var roles: [(name: String, key: WritableKeyPath<Colors, Pair>)] { [
            ("ink", \.ink), ("inkMuted", \.inkMuted), ("inkFaint", \.inkFaint),
            ("surface", \.surface), ("surfaceSunken", \.surfaceSunken), ("surfaceRaised", \.surfaceRaised), ("line", \.line),
            ("accent", \.accent), ("onAccent", \.onAccent), ("accentSoft", \.accentSoft), ("link", \.link),
            ("danger", \.danger), ("dangerSoft", \.dangerSoft), ("onDanger", \.onDanger),
            ("success", \.success), ("successSoft", \.successSoft),
            ("warning", \.warning), ("warningSoft", \.warningSoft), ("onWarning", \.onWarning),
            ("well", \.well), ("glow", \.glow), ("waitGlow", \.waitGlow),
        ] }

        /// Roles a theme may leave out without a warning: themes made before Lantern (D84) didn't have them, and each
        /// has a fitting stand-in (`fillOptional`).
        public static let optionalRoles: Set<String> = ["well", "glow", "waitGlow"]

        /// The stand-ins for optional roles a theme left out: its own sunken surface for wells, Harbor's lights.
        mutating func fillOptional(missing: Set<String>) {
            if missing.contains("well") { well = surfaceSunken }
            if missing.contains("glow") { glow = ThemeTokens.harbor.colors.glow }
            if missing.contains("waitGlow") { waitGlow = ThemeTokens.harbor.colors.waitGlow }
        }
    }

    public struct Space: Sendable, Equatable {
        public var xxs, xs, s, m, l, xl, xxl: Double

        public init(xxs: Double, xs: Double, s: Double, m: Double, l: Double, xl: Double, xxl: Double) {
            (self.xxs, self.xs, self.s, self.m, self.l, self.xl, self.xxl) = (xxs, xs, s, m, l, xl, xxl)
        }
    }

    /// Corners (D84): `control` for buttons and fields, `card`, `panel` for the Sidecard, sheets and popovers, `bubble`
    /// for the companion's speech. Chips and pins are capsules; the inner `xs` follows `control`.
    public struct Radius: Sendable, Equatable {
        public var control, card, panel, bubble: Double

        public init(control: Double, card: Double, panel: Double, bubble: Double) {
            (self.control, self.card, self.panel, self.bubble) = (control, card, panel, bubble)
        }
    }

    /// The face headings and the companion's words use; body text is always the system face.
    public enum Face: String, Sendable, Equatable, CaseIterable {
        case system, rounded, serif
    }

    /// How much room things get: spacing is scaled by it.
    public enum Density: String, Codable, Sendable, Equatable, CaseIterable {
        case compact, regular, relaxed

        public var factor: Double {
            switch self {
            case .compact: 0.85
            case .regular: 1
            case .relaxed: 1.15
            }
        }
    }

    public struct Typography: Sendable, Equatable {
        public var display: Face
        /// Every size is multiplied by it, within `scaleRange`.
        public var scale: Double
        public var density: Density

        public static let scaleRange = 0.9...1.15
    }

    /// How things move. Reduce Motion always means none, whatever the theme says.
    public enum Motion: String, Sendable, Equatable, CaseIterable {
        case calm, bouncy, none
    }

    public struct Material: Sendable, Equatable {
        public enum Sidebar: String, Sendable, Equatable, CaseIterable { case solid, translucent }
        public var sidebar: Sidebar
        /// A faint paper texture over the pages, from the theme's own image.
        public var grain: Bool
        /// A picture washed in at the top of each page, behind the cards.
        public var page: Bool

        public init(sidebar: Sidebar, grain: Bool, page: Bool = false) {
            self.sidebar = sidebar
            self.grain = grain
            self.page = page
        }
    }

    /// How the companion sits in Home's sidebar.
    public struct Nook: Sendable, Equatable {
        public enum Style: String, Sendable, Equatable, CaseIterable { case cushion, badge, sticker }
        public var style: Style
        /// A companion the theme was drawn for; offered, never chosen for the person.
        public var suggests: CompanionChoice?

        public init(style: Style, suggests: CompanionChoice?) {
            self.style = style
            self.suggests = suggests
        }
    }

    public var id: String
    public var name: String
    public var colors: Colors
    public var space: Space
    public var radius: Radius
    public var type: Typography
    public var motion: Motion
    public var material: Material
    public var nook: Nook
    /// Home's icons: what D84 left of D64's layouts.
    public var layout: ThemeLayout

    public init(id: String, name: String, colors: Colors, space: Space, radius: Radius, type: Typography,
                motion: Motion = .calm, material: Material = Material(sidebar: .solid, grain: false),
                nook: Nook = Nook(style: .cushion, suggests: nil), layout: ThemeLayout = .desk) {
        self.id = id
        self.name = name
        self.colors = colors
        self.space = space
        self.radius = radius
        self.type = type
        self.motion = motion
        self.material = material
        self.nook = nook
        self.layout = layout
    }
}

extension ThemeTokens {
    /// The default theme, in the Lantern look (D84): neutral graphite-and-paper surfaces so the companion is the warm
    /// thing on screen, the brand navy as ink, one deep aqua for actions that reads at 4.5:1 with its label in both
    /// appearances (the pale brand aqua read as disabled), and the brand aqua and amber kept as light: the pool at the
    /// companion's feet. Every text role reads at 4.5:1 or more on every surface (03-system's computed ratios).
    public static let harbor = ThemeTokens(
        id: "harbor",
        name: "Harbor",
        colors: Colors(
            ink: Pair(light: 0x0F1E36, dark: 0xEEF2F8),
            inkMuted: Pair(light: 0x465063, dark: 0xB3BDCC),
            inkFaint: Pair(light: 0x5F697C, dark: 0x8C97AA),
            surface: Pair(light: 0xFFFFFF, dark: 0x161D2A),
            // The window's canvas, under the cards.
            surfaceSunken: Pair(light: 0xF4F5F7, dark: 0x0D121C),
            // Cards.
            surfaceRaised: Pair(light: 0xFFFFFF, dark: 0x1A2232),
            line: Pair(light: 0xE3E6EB, dark: 0x273041),
            accent: Pair(light: 0x0B7783, dark: 0x3CD6DB),
            onAccent: Pair(light: 0xFFFFFF, dark: 0x05282C),
            accentSoft: Pair(light: 0xDDF4F5, dark: 0x153A40),
            link: Pair(light: 0x0A6F7A, dark: 0x5FE0E4),
            danger: Pair(light: 0xB42318, dark: 0xFF8A80),
            dangerSoft: Pair(light: 0xFDECEA, dark: 0x45201D),
            onDanger: Pair(light: 0xFFFFFF, dark: 0x2A0B08),
            success: Pair(light: 0x13703F, dark: 0x5FD69A),
            successSoft: Pair(light: 0xE3F4EA, dark: 0x173A2A),
            warning: Pair(light: 0x8A4B00, dark: 0xFFC266),
            warningSoft: Pair(light: 0xFFF3DC, dark: 0x3A2E17),
            onWarning: Pair(light: 0xFFFFFF, dark: 0x2A1A00),
            well: Pair(light: 0xECEFF3, dark: 0x1F2737),
            glow: Pair(0x2ED4D9),
            waitGlow: Pair(0xF5A524)
        ),
        space: Space(xxs: 2, xs: 4, s: 8, m: 12, l: 16, xl: 24, xxl: 32),
        radius: Radius(control: 8, card: 12, panel: 18, bubble: 18),
        type: Typography(display: .rounded, scale: 1, density: .regular)
    )
}
