import Foundation

/// What a theme sets, as plain values (D58): colours as light and dark pairs, spacing and density, type, corner radii,
/// motion, the sidebar's material, the companion's nook and where the app's pieces go (`ThemeLayout`). The app turns
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

        /// Every role by its name in a theme file, in this order.
        public static var roles: [(name: String, key: WritableKeyPath<Colors, Pair>)] { [
            ("ink", \.ink), ("inkMuted", \.inkMuted), ("inkFaint", \.inkFaint),
            ("surface", \.surface), ("surfaceSunken", \.surfaceSunken), ("surfaceRaised", \.surfaceRaised), ("line", \.line),
            ("accent", \.accent), ("onAccent", \.onAccent), ("accentSoft", \.accentSoft), ("link", \.link),
            ("danger", \.danger), ("dangerSoft", \.dangerSoft), ("onDanger", \.onDanger),
            ("success", \.success), ("successSoft", \.successSoft),
            ("warning", \.warning), ("warningSoft", \.warningSoft), ("onWarning", \.onWarning),
        ] }
    }

    public struct Space: Sendable, Equatable {
        public var xxs, xs, s, m, l, xl, xxl: Double

        public init(xxs: Double, xs: Double, s: Double, m: Double, l: Double, xl: Double, xxl: Double) {
            (self.xxs, self.xs, self.s, self.m, self.l, self.xl, self.xxl) = (xxs, xs, s, m, l, xl, xxl)
        }
    }

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
    public enum Density: String, Sendable, Equatable, CaseIterable {
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
    /// Where things go and how they look (D64).
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
    /// The default theme: the approved navy and aqua identity, airy and rounded. Faint ink, link text and the danger
    /// red were deepened in D58 so every text role reads at 4.5:1 or more on every surface, in both appearances.
    public static let harbor = ThemeTokens(
        id: "harbor",
        name: "Harbor",
        colors: Colors(
            ink: Pair(light: 0x0F2D5B, dark: 0xE8EEF8),
            inkMuted: Pair(light: 0x5B6B85, dark: 0x9AA8BF),
            inkFaint: Pair(light: 0x5E718F, dark: 0x8795AC),
            surface: Pair(light: 0xFFFFFF, dark: 0x15233B),
            surfaceSunken: Pair(light: 0xF4F7FB, dark: 0x0E1A2E),
            surfaceRaised: Pair(light: 0xFFFFFF, dark: 0x1B2C49),
            line: Pair(light: 0xE2E8F0, dark: 0x26385A),
            accent: Pair(0x2ED4D9),
            onAccent: Pair(0x0F2D5B),
            accentSoft: Pair(light: 0xE3F9FA, dark: 0x173F4D),
            link: Pair(light: 0x137A7F, dark: 0x2ED4D9),
            danger: Pair(light: 0xC93F33, dark: 0xFF8A7D),
            dangerSoft: Pair(light: 0xFFEDEA, dark: 0x4A2622),
            onDanger: Pair(light: 0xFFFFFF, dark: 0x0F2D5B),
            success: Pair(light: 0x2F9E6D, dark: 0x7DD3A7),
            successSoft: Pair(light: 0xE6F6EE, dark: 0x1D3D31),
            // The brand's sun in the dark; deepened to read at 4.5:1 on light surfaces, Harbor's and any theme's
            // that leaves it out.
            warning: Pair(light: 0x8A5800, dark: 0xFFC93C),
            warningSoft: Pair(light: 0xFFF4D6, dark: 0x3D3317),
            onWarning: Pair(light: 0xFFFFFF, dark: 0x0F2D5B)
        ),
        space: Space(xxs: 2, xs: 4, s: 8, m: 12, l: 16, xl: 24, xxl: 32),
        radius: Radius(control: 8, card: 12, panel: 18, bubble: 20),
        type: Typography(display: .rounded, scale: 1, density: .regular)
    )
}
