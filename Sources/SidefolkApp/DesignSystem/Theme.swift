import AppKit
import SwiftUI

/// Sidefolk design tokens. Every color, size and radius in the UI comes from here.
enum Theme {
    // MARK: Brand palette (approved identity)
    static let navy = Color(hex: 0x0F2D5B)
    static let aqua = Color(hex: 0x2ED4D9)
    static let coral = Color(hex: 0xFF7B6B)
    static let mint = Color(hex: 0x7DD3A7)
    static let lightBlue = Color(hex: 0x93C5FD)
    static let sun = Color(hex: 0xFFC93C)

    // MARK: Semantic, light/dark adaptive
    static let ink = Color(light: 0x0F2D5B, dark: 0xE8EEF8)
    static let inkMuted = Color(light: 0x5B6B85, dark: 0x9AA8BF)
    static let inkFaint = Color(light: 0x8A97AD, dark: 0x6F7F99)
    static let surface = Color(light: 0xFFFFFF, dark: 0x15233B)
    static let surfaceSunken = Color(light: 0xF4F7FB, dark: 0x0E1A2E)
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x1B2C49)
    static let line = Color(light: 0xE2E8F0, dark: 0x26385A)
    static let accent = aqua
    /// Text on aqua: navy keeps 7:1 contrast.
    static let onAccent = Color(hex: 0x0F2D5B)
    static let accentSoft = Color(light: 0xE3F9FA, dark: 0x173F4D)
    static let danger = Color(light: 0xD9473A, dark: 0xFF8A7D)
    static let dangerSoft = Color(light: 0xFFEDEA, dark: 0x4A2622)
    static let success = Color(light: 0x2F9E6D, dark: 0x7DD3A7)
    static let successSoft = Color(light: 0xE6F6EE, dark: 0x1D3D31)
    /// The Now greeting's wash: aqua into light blue, as quiet as the cards around it.
    static let heroStart = Color(light: 0xDDF6F7, dark: 0x153B49)
    static let heroEnd = Color(light: 0xE6EFFD, dark: 0x1B2C49)

    // MARK: Metrics
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let panel: CGFloat = 18
        static let bubble: CGFloat = 20
    }

    enum Font {
        static let bubble = SwiftUI.Font.system(size: 14, weight: .medium, design: .rounded)
        static let bubbleTitle = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded)
        static let input = SwiftUI.Font.system(size: 16, weight: .regular, design: .rounded)
        static let hint = SwiftUI.Font.system(size: 11.5, weight: .medium, design: .rounded)
        static let hero = SwiftUI.Font.system(size: 30, weight: .bold, design: .rounded)
        static let title = SwiftUI.Font.system(size: 22, weight: .bold, design: .rounded)
        static let heading = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 13)
        static let bodyStrong = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let caption = SwiftUI.Font.system(size: 11.5)
        static let captionStrong = SwiftUI.Font.system(size: 11.5, weight: .semibold)
        static let eyebrow = SwiftUI.Font.system(size: 10.5, weight: .semibold, design: .rounded)
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
