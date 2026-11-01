import Foundation

/// A calendar's colour made readable on Lantern's surfaces (D95): a tinted fill, a strong edge, text in the
/// calendar's own colour, and the solid look of a selected event. Only lightness moves (HSL, hue and saturation
/// kept), until text reads at 4.5:1 on its fill and the edge stands out at 3:1 from the surface, in light and in dark.
public enum CalendarPalette {
    public struct Colors: Sendable, Equatable {
        /// The block's background: the colour mixed into the surface.
        public var fill: UInt32
        /// The bar down its leading side, a dot, a checkbox.
        public var edge: UInt32
        /// Its words on `fill`.
        public var text: UInt32
        /// A selected event: solid, with `onSelected` words.
        public var selectedFill: UInt32
        public var onSelected: UInt32
    }

    public static let textContrast = 4.5
    public static let edgeContrast = 3.0

    /// The colours of `color` on `surface` (a card's surface in that appearance).
    public static func colors(_ color: UInt32, surface: UInt32, dark: Bool) -> Colors {
        let fill = mix(surface, color, dark ? 0.30 : 0.17)
        let edge = reaching(edgeContrast, from: color, against: surface, darker: !dark)
        let text = reaching(textContrast, from: color, against: fill, darker: !dark)
        let onSelected: UInt32 = dark ? surface : 0xFFFFFF
        let selected = reaching(textContrast, from: color, against: onSelected, darker: !dark)
        return Colors(fill: fill, edge: edge, text: text, selectedFill: selected, onSelected: onSelected)
    }

    /// The colour, at the least change of lightness (darker or lighter) that reaches `ratio` against `back`.
    static func reaching(_ ratio: Double, from color: UInt32, against back: UInt32, darker: Bool) -> UInt32 {
        if ThemeCheck.contrast(color, back) >= ratio { return color }
        let (h, s, l) = hsl(color)
        let limit = darker ? 0.0 : 1.0
        guard ThemeCheck.contrast(rgb(h, s, limit), back) >= ratio else { return rgb(h, s, limit) }
        // Lightness moves contrast one way between `l` and the limit, so halving the gap finds the nearest that reads.
        var near = l, far = limit
        for _ in 0..<24 {
            let mid = (near + far) / 2
            if ThemeCheck.contrast(rgb(h, s, mid), back) >= ratio { far = mid } else { near = mid }
        }
        return rgb(h, s, far)
    }

    /// `amount` of `top` over `base`.
    static func mix(_ base: UInt32, _ top: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((base >> shift) & 0xFF), b = Double((top >> shift) & 0xFF)
            return UInt32((a + (b - a) * amount).rounded())
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }

    /// Hue (0–360), saturation and lightness (0–1).
    static func hsl(_ hex: UInt32) -> (Double, Double, Double) {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        let hi = max(r, g, b), lo = min(r, g, b), l = (hi + lo) / 2, d = hi - lo
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if hi == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) } else if hi == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h *= 60
        return (h < 0 ? h + 360 : h, min(s, 1), l)
    }

    static func rgb(_ h: Double, _ s: Double, _ l: Double) -> UInt32 {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v + m, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}
