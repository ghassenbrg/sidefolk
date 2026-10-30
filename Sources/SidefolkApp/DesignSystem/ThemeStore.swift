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

    var style: ThemeStyle {
        access(keyPath: \.style)
        return state.withLock { $0 }
    }

    /// Switches every window to `tokens`. Settings' theme picker calls it.
    func apply(_ tokens: ThemeTokens) {
        withMutation(keyPath: \.style) {
            state.withLock { $0 = ThemeStyle(tokens) }
        }
    }
}

/// A theme's tokens as SwiftUI values, made once when the theme is applied rather than on every read.
struct ThemeStyle: Sendable {
    let tokens: ThemeTokens
    let ink, inkMuted, inkFaint, surface, surfaceSunken, surfaceRaised, line: Color
    let accent, onAccent, accentSoft, danger, dangerSoft, onDanger, success, successSoft, heroStart, heroEnd: Color
    let fonts: Fonts

    struct Fonts: Sendable {
        let bubble, bubbleTitle, input, hint, hero, title, heading, body, bodyStrong, caption, captionStrong, eyebrow: Font

        init(display: ThemeTokens.Face) {
            let d: Font.Design = switch display {
            case .system: .default
            case .rounded: .rounded
            case .serif: .serif
            }
            bubble = .system(size: 14, weight: .medium, design: d)
            bubbleTitle = .system(size: 15, weight: .semibold, design: d)
            input = .system(size: 16, weight: .regular, design: d)
            hint = .system(size: 11.5, weight: .medium, design: d)
            hero = .system(size: 30, weight: .bold, design: d)
            title = .system(size: 22, weight: .bold, design: d)
            heading = .system(size: 15, weight: .semibold, design: d)
            body = .system(size: 13)
            bodyStrong = .system(size: 13, weight: .semibold)
            caption = .system(size: 11.5)
            captionStrong = .system(size: 11.5, weight: .semibold)
            eyebrow = .system(size: 10.5, weight: .semibold, design: d)
        }
    }

    init(_ tokens: ThemeTokens) {
        self.tokens = tokens
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
        danger = Color(c.danger)
        dangerSoft = Color(c.dangerSoft)
        onDanger = Color(c.onDanger)
        success = Color(c.success)
        successSoft = Color(c.successSoft)
        heroStart = Color(c.heroStart)
        heroEnd = Color(c.heroEnd)
        fonts = Fonts(display: tokens.display)
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
