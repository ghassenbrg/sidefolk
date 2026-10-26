import AppKit

/// An sRGB color as plain numbers, so palettes can be shared constants under strict concurrency.
struct RGB: Sendable, Equatable {
    var r: CGFloat, g: CGFloat, b: CGFloat

    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = r; self.g = g; self.b = b
    }

    func cg(_ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    /// Linear blend toward `other`; t = 0 keeps self.
    func mix(_ other: RGB, _ t: CGFloat) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    func lighter(_ t: CGFloat) -> RGB { mix(.white, t) }
    func darker(_ t: CGFloat) -> RGB { mix(RGB(0x1B1F3B), t) }

    static let white = RGB(0xFFFFFF)
}

/// Brand palette (docs/PRODUCT.md, logo sheet) plus the few working shades the rig needs.
enum Palette {
    static let navy = RGB(0x0F2D5B)
    static let aqua = RGB(0x2ED4D9)
    static let coral = RGB(0xFF7B6B)
    static let mint = RGB(0x7DD3A7)
    static let lightBlue = RGB(0x93C5FD)
    static let yellow = RGB(0xFFC93C)

    /// Visor glass: navy at the top edge deepening to near-black.
    static let visorTop = RGB(0x1C3C72)
    static let visorMid = RGB(0x0B1D42)
    static let visorBottom = RGB(0x040916)

    /// Eye light: a hot near-white core inside an aqua glow.
    static let eyeCore = RGB(0xC9FDFE)
    static let eyeLight = RGB(0x5EE6EA)

    /// White shell shading, highlight to core shadow. Cool tints keep it reading as soft plastic.
    static let shell = [RGB(0xFFFFFF), RGB(0xFBFCFF), RGB(0xEEF0F7), RGB(0xD9DDEA), RGB(0xC2C8DA)]
    static let shellEdge = RGB(0xB4BBD0)

    /// Mochi's soft white, a touch warmer than the robot's shell; highlight to core shadow.
    static let fur = [RGB(0xFFFFFF), RGB(0xFDFCFC), RGB(0xF1F0F4), RGB(0xDEDDE6), RGB(0xC9C9D6)]
    /// Bead eyes and noses (sampled from the mascot), and Mochi's ear tips.
    static let eyeInk = RGB(0x14254F)
    static let earTip = RGB(0x22365F)

    /// Spark's cream shell (sampled from its render) and its dark navy hands, feet and stalk.
    static let cream = [RGB(0xFFFBF7), RGB(0xFBF3EC), RGB(0xF1E5DC), RGB(0xE1D2C8), RGB(0xCCBBB0)]
    static let creamEdge = RGB(0xC7B6AA)
    static let darkPart = [RGB(0x44506F), RGB(0x323B5A), RGB(0x262D48), RGB(0x1C2238), RGB(0x14192A)]

    /// Dark ink for folk faces and small glyphs.
    static let ink = RGB(0x1A2240)
    static let blush = RGB(0xFF6F91)
}
