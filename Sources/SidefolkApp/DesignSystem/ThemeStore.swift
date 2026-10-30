import ImageIO
import Observation
import SidefolkCore
import SwiftUI
import Synchronization

/// The theme every window draws with (D58). `Theme`'s names read it, so call sites never change. It can be read
/// from any thread (tokens are used in layout code and default arguments too), and a SwiftUI view that reads a
/// token is redrawn when the theme changes.
@Observable
final class ThemeStore: Sendable {
    static let shared = ThemeStore()

    @ObservationIgnored private let state = Mutex(ThemeStyle(.harbor))
    @ObservationIgnored private let folderState = Mutex<ThemeReport?>(nil)

    var style: ThemeStyle {
        access(keyPath: \.style)
        return state.withLock { $0 }
    }

    /// The last check of the folder a theme is being made in, while Sidefolk follows it; Settings shows its problems.
    var folderReport: ThemeReport? {
        access(keyPath: \.folderReport)
        return folderState.withLock { $0 }
    }

    /// Switches every window to `theme`.
    func apply(_ theme: InstalledTheme) {
        guard state.withLock({ $0.theme }) != theme else { return }
        let style = ThemeStyle(theme)
        withMutation(keyPath: \.style) {
            state.withLock { $0 = style }
        }
    }

    func setFolderReport(_ report: ThemeReport?) {
        withMutation(keyPath: \.folderReport) {
            folderState.withLock { $0 = report }
        }
    }
}

/// A theme's tokens as SwiftUI values, made once when the theme is applied rather than on every read.
struct ThemeStyle: Sendable {
    let theme: InstalledTheme
    var tokens: ThemeTokens { theme.tokens }
    let ink, inkMuted, inkFaint, surface, surfaceSunken, surfaceRaised, line: Color
    let accent, onAccent, accentSoft, link, danger, dangerSoft, onDanger, success, successSoft: Color
    /// Spacing after the theme's density.
    let space: ThemeTokens.Space
    let fonts: Fonts
    /// The theme's own pictures, decoded once: paper grain, the nook's backdrop, the empty-page art.
    let grain, backdrop, emptyArt: CGImage?

    struct Fonts: Sendable {
        let bubble, bubbleTitle, input, hint, hero, title, heading, body, bodyStrong, caption, captionStrong, eyebrow: Font

        init(_ type: ThemeTokens.Typography) {
            let d: Font.Design = switch type.display {
            case .system: .default
            case .rounded: .rounded
            case .serif: .serif
            }
            let k = type.scale
            bubble = .system(size: 14 * k, weight: .medium, design: d)
            bubbleTitle = .system(size: 15 * k, weight: .semibold, design: d)
            input = .system(size: 16 * k, weight: .regular, design: d)
            hint = .system(size: 11.5 * k, weight: .medium, design: d)
            hero = .system(size: 30 * k, weight: .bold, design: d)
            title = .system(size: 22 * k, weight: .bold, design: d)
            heading = .system(size: 15 * k, weight: .semibold, design: d)
            body = .system(size: 13 * k)
            bodyStrong = .system(size: 13 * k, weight: .semibold)
            caption = .system(size: 11.5 * k)
            captionStrong = .system(size: 11.5 * k, weight: .semibold)
            eyebrow = .system(size: 10.5 * k, weight: .semibold, design: d)
        }
    }

    init(_ theme: InstalledTheme) {
        self.theme = theme
        let tokens = theme.tokens
        let c = tokens.colors
        ink = Color(c.ink)
        inkMuted = Color(c.inkMuted)
        inkFaint = Color(c.inkFaint)
        surface = Color(c.surface)
        surfaceSunken = Color(c.surfaceSunken)
        surfaceRaised = Color(c.surfaceRaised)
        line = Color(c.line)
        accent = Color(c.accent)
        onAccent = Color(c.onAccent)
        accentSoft = Color(c.accentSoft)
        link = Color(c.link)
        danger = Color(c.danger)
        dangerSoft = Color(c.dangerSoft)
        onDanger = Color(c.onDanger)
        success = Color(c.success)
        successSoft = Color(c.successSoft)
        // Whole and half points, so a compact or relaxed theme still lands on the pixel grid.
        let f = tokens.type.density.factor, s = tokens.space
        func scaled(_ v: Double) -> Double { (v * f * 2).rounded() / 2 }
        space = ThemeTokens.Space(xxs: scaled(s.xxs), xs: scaled(s.xs), s: scaled(s.s), m: scaled(s.m), l: scaled(s.l),
                                  xl: scaled(s.xl), xxl: scaled(s.xxl))
        fonts = Fonts(tokens.type)
        grain = Self.image(theme.images["material.grain"])
        backdrop = Self.image(theme.images["companion.backdrop"])
        emptyArt = Self.image(theme.images["art.empty"])
    }

    private static func image(_ url: URL?) -> CGImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

extension Color {
    /// A theme colour: fixed when both appearances agree, otherwise following the window's appearance.
    init(_ pair: ThemeTokens.Pair) {
        if pair.light == pair.dark {
            self.init(hex: pair.light)
        } else {
            self.init(light: pair.light, dark: pair.dark)
        }
    }
}
