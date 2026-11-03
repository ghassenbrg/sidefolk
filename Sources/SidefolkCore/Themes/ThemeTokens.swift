import Foundation

/// What a theme sets, as plain values (D58): colours as light and dark pairs, spacing and density, type, corner radii,
/// motion, the sidebar's material, the companion's nook and Home's icons (`ThemeLayout`). The app turns
/// them into SwiftUI values; keeping them here lets theme files be read and checked without a window. Sidefolk is the
/// default (D130).
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
        /// The sidebar's plane, and what's written on it (D130). Optional: a theme without them uses its surface and inks.
        public var sidebar = Pair(0)
        public var sidebarInk = Pair(0)
        public var sidebarInkMuted = Pair(0)
        /// The row the person is on, which the theme draws rather than macOS, and its words and icon. It must stand 3:1
        /// from the sidebar (`ThemeCheck.selectionProblems`). Optional: a theme without them uses its accent and label.
        public var sidebarSelected = Pair(0)
        public var onSidebarSelected = Pair(0)
        /// Words over Today's scene. Optional: a theme without them uses its inks.
        public var sceneInk = Pair(0)
        public var sceneInkMuted = Pair(0)

        /// Every role by its name in a theme file, in this order.
        public static var roles: [(name: String, key: WritableKeyPath<Colors, Pair>)] { [
            ("ink", \.ink), ("inkMuted", \.inkMuted), ("inkFaint", \.inkFaint),
            ("surface", \.surface), ("surfaceSunken", \.surfaceSunken), ("surfaceRaised", \.surfaceRaised), ("line", \.line),
            ("accent", \.accent), ("onAccent", \.onAccent), ("accentSoft", \.accentSoft), ("link", \.link),
            ("danger", \.danger), ("dangerSoft", \.dangerSoft), ("onDanger", \.onDanger),
            ("success", \.success), ("successSoft", \.successSoft),
            ("warning", \.warning), ("warningSoft", \.warningSoft), ("onWarning", \.onWarning),
            ("well", \.well), ("glow", \.glow), ("waitGlow", \.waitGlow),
            ("sidebar", \.sidebar), ("sidebarInk", \.sidebarInk), ("sidebarInkMuted", \.sidebarInkMuted),
            ("sidebarSelected", \.sidebarSelected), ("onSidebarSelected", \.onSidebarSelected),
            ("sceneInk", \.sceneInk), ("sceneInkMuted", \.sceneInkMuted),
        ] }

        /// Roles a theme may leave out without a warning: themes made before D84 and D130 didn't have them, and each
        /// has a fitting stand-in (`fillOptional`).
        public static let optionalRoles: Set<String> = ["well", "glow", "waitGlow", "sidebar", "sidebarInk", "sidebarInkMuted", "sidebarSelected",
                                                         "onSidebarSelected", "sceneInk", "sceneInkMuted"]

        /// The stand-ins for optional roles a theme left out: its own sunken surface for wells, its surface, inks and
        /// accent for the sidebar and the scene, the default's lights.
        mutating func fillOptional(missing: Set<String>) {
            if missing.contains("well") { well = surfaceSunken }
            if missing.contains("glow") { glow = ThemeTokens.sidefolk.colors.glow }
            if missing.contains("waitGlow") { waitGlow = ThemeTokens.sidefolk.colors.waitGlow }
            if missing.contains("sidebar") { sidebar = surface }
            if missing.contains("sidebarInk") { sidebarInk = ink }
            if missing.contains("sidebarInkMuted") { sidebarInkMuted = inkMuted }
            if missing.contains("sidebarSelected") { sidebarSelected = accent }
            if missing.contains("onSidebarSelected") { onSidebarSelected = onAccent }
            if missing.contains("sceneInk") { sceneInk = ink }
            if missing.contains("sceneInkMuted") { sceneInkMuted = inkMuted }
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
        /// How a card sits on its page: a hairline and a trace of shadow, or a soft lift with no outline in light (D130).
        public enum Depth: String, Sendable, Equatable, CaseIterable { case line, soft }
        public var sidebar: Sidebar
        /// A faint paper texture over the pages, from the theme's own image.
        public var grain: Bool
        /// A picture washed in at the top of each page, behind the cards.
        public var page: Bool
        public var depth: Depth
        /// A picture at the top of Today, behind the greeting and up under the toolbar (D130). Only Today: other pages
        /// stay plain for work.
        public var scene: Bool

        public init(sidebar: Sidebar, grain: Bool, page: Bool = false, depth: Depth = .line, scene: Bool = false) {
            self.sidebar = sidebar
            self.grain = grain
            self.page = page
            self.depth = depth
            self.scene = scene
        }
    }

    /// How the companion sits in Home's sidebar.
    public struct Nook: Sendable, Equatable {
        public enum Style: String, Sendable, Equatable, CaseIterable { case cushion, badge, sticker }
        public var style: Style
        /// A companion the theme was drawn for; offered, never chosen for the person.
        public var suggests: CompanionChoice?
        /// A picture at the top of the sidebar, with the companion standing in it and the plain list below (D130).
        public var header: Bool
        /// The wordmark in the header's top corner, beside the window's buttons.
        public var logo: Bool

        public init(style: Style, suggests: CompanionChoice?, header: Bool = false, logo: Bool = false) {
            self.style = style
            self.suggests = suggests
            self.header = header
            self.logo = logo
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
    /// The default theme (D130): Sidefolk's own world, calm for all-day use. Colours come from the app icon and logo:
    /// the wordmark's navy for ink and action in light, the scarf's turquoise softened for action in dark, a dim
    /// desaturated midnight for dark's surfaces. The brand aqua and amber stay light, the pool at the companion's feet.
    /// Every text role reads at 4.5:1 or more on every surface; a selected row stands 3:1 from its sidebar. Its art is
    /// in `Resources/Themes/sidefolk`, whose theme.json says these same values.
    public static let sidefolk = ThemeTokens(
        id: "sidefolk",
        name: "Sidefolk",
        colors: Colors(
            ink: Pair(light: 0x1E3457, dark: 0xE2E8F2),
            inkMuted: Pair(light: 0x4C5D7B, dark: 0xA7B3C6),
            inkFaint: Pair(light: 0x55667F, dark: 0x9AA6B9),
            surface: Pair(light: 0xFBFCFE, dark: 0x141D2C),
            // The window's canvas, under the cards.
            surfaceSunken: Pair(light: 0xF1F4FC, dark: 0x101825),
            // Cards.
            surfaceRaised: Pair(light: 0xFFFFFF, dark: 0x182232),
            line: Pair(light: 0xE3E8F2, dark: 0x25303F),
            accent: Pair(light: 0x2A4A7C, dark: 0x7CC9CF),
            onAccent: Pair(light: 0xFFFFFF, dark: 0x0D2529),
            accentSoft: Pair(light: 0xD5E6F3, dark: 0x20344A),
            link: Pair(light: 0x2B66AD, dark: 0x8FC8DA),
            danger: Pair(light: 0xB42318, dark: 0xFF8A80),
            dangerSoft: Pair(light: 0xFDECEA, dark: 0x45201D),
            onDanger: Pair(light: 0xFFFFFF, dark: 0x2A0B08),
            success: Pair(light: 0x13703F, dark: 0x5FD69A),
            successSoft: Pair(light: 0xE3F4EA, dark: 0x173A2A),
            warning: Pair(light: 0x8A4B00, dark: 0xFFC266),
            warningSoft: Pair(light: 0xFFF3DC, dark: 0x3A2E17),
            onWarning: Pair(light: 0xFFFFFF, dark: 0x2A1A00),
            well: Pair(light: 0xEBEFF7, dark: 0x1F2A3B),
            glow: Pair(0x2ED4D9),
            waitGlow: Pair(0xF5A524),
            sidebar: Pair(light: 0xFFFFFF, dark: 0x0A101A),
            sidebarInk: Pair(light: 0x1E3457, dark: 0xD9E0EB),
            sidebarInkMuted: Pair(light: 0x4C5D7B, dark: 0x9AA7BB),
            sidebarSelected: Pair(light: 0x2A4A7C, dark: 0x466189),
            onSidebarSelected: Pair(0xFFFFFF),
            sceneInk: Pair(light: 0x1E3457, dark: 0xE2E8F2),
            sceneInkMuted: Pair(light: 0x3F5070, dark: 0xCBD4E2)
        ),
        space: Space(xxs: 2, xs: 4, s: 8, m: 12, l: 16, xl: 24, xxl: 32),
        radius: Radius(control: 10, card: 16, panel: 18, bubble: 18),
        type: Typography(display: .rounded, scale: 1, density: .regular),
        material: Material(sidebar: .solid, grain: false, depth: .soft, scene: true),
        nook: Nook(style: .cushion, suggests: nil, header: true, logo: true)
    )
}
