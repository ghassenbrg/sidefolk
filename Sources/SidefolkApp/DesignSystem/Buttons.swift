import AppKit
import SwiftUI

/// Lantern's buttons (D84, docs/DESIGN.md). One primary per card, sheet or page: the deep aqua fill with its label at
/// 4.5:1, so it never reads as disabled; disabled is faded *and* flat. Secondary is a surface with a hairline; quiet is
/// the link colour alone ("Later", "Dismiss"); destructive is quiet in the danger ink, and `danger` the red fill kept
/// for the button that confirms a destructive sheet or stops something (D74).
struct SFButtonStyle: ButtonStyle {
    /// `plain`: ink without a frame, for icon buttons and toolbars.
    enum Kind { case primary, secondary, destructive, plain, quiet, danger }
    /// Heights: small 24, regular 28 (windows), sidecard 30, large 32 (a page's one main action).
    enum Size { case small, regular, sidecard, large }

    var kind: Kind = .secondary
    var size: Size = .regular
    /// Working: the label stays and a small spinner takes the leading icon's place ("Installing").
    var working = false
    /// One half of a split button (Allow and its menu): square on the side it meets the other half, and tighter.
    enum Join { case leading, trailing }
    var join: Join?

    init(kind: Kind = .secondary, size: Size = .regular, working: Bool = false, join: Join? = nil) {
        self.kind = kind
        self.size = size
        self.working = working
        self.join = join
    }

    /// The names call sites used before Lantern: compact is small, large is large.
    init(kind: Kind, compact: Bool, large: Bool = false) {
        self.init(kind: kind, size: large ? .large : compact ? .small : .regular)
    }

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(style: self, configuration: configuration)
    }

    /// A view, so it can read whether the button is enabled, hovered and in which appearance (a ButtonStyle can't).
    private struct StyledLabel: View {
        var style: SFButtonStyle
        var configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isFocused) private var isFocused
        @Environment(\.showsFocusRing) private var showsRing
        @State private var hovered = false

        var body: some View {
            let r = Theme.Radius.control
            let shape = UnevenRoundedRectangle(topLeadingRadius: style.join == .trailing ? 0 : r, bottomLeadingRadius: style.join == .trailing ? 0 : r,
                                               bottomTrailingRadius: style.join == .leading ? 0 : r, topTrailingRadius: style.join == .leading ? 0 : r,
                                               style: .continuous)
            HStack(spacing: 6) {
                if style.working {
                    ProgressView().controlSize(.mini).tint(style.foreground)
                    // Titles only while working: the spinner is the leading icon then.
                    configuration.label.labelStyle(.titleOnly)
                } else {
                    configuration.label
                }
            }
            .font(style.font)
            .lineLimit(1)
            .padding(.horizontal, style.join == .trailing ? Theme.Space.s : style.padding)
            .frame(minHeight: style.height)
            .foregroundStyle(style.foreground)
            .background(style.fill(dark: scheme == .dark), in: shape)
            // Hover and press darken by a veil of ink, so every kind reacts the same way.
            .overlay(shape.fill(Theme.ink.opacity(veil)))
            .overlay {
                if style.kind == .secondary {
                    shape.strokeBorder(Theme.controlBorder)
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .focusRing((isFocused && buttonsTakeFocus) || showsRing)
            .focusEffectDisabled()
            .onHover { hovered = $0 }
            .animation(Theme.Motion.micro, value: configuration.isPressed)
            .animation(Theme.Motion.micro, value: hovered)
        }

        private var veil: Double {
            guard isEnabled else { return 0 }
            return configuration.isPressed ? 0.08 : hovered ? 0.04 : 0
        }
    }

    private var font: Font {
        switch size {
        case .small: .system(size: 12 * Self.scale, weight: .semibold)
        case .regular, .sidecard: .system(size: 13 * Self.scale, weight: .semibold)
        case .large: .system(size: 14 * Self.scale, weight: .semibold)
        }
    }

    private static var scale: Double { ThemeStore.shared.style.tokens.type.scale }

    private var height: CGFloat {
        switch size {
        case .small: Theme.Size.buttonSmall
        case .regular: Theme.Size.button
        case .sidecard: Theme.Size.buttonSidecard
        case .large: Theme.Size.buttonLarge
        }
    }

    private var padding: CGFloat {
        switch size {
        case .small: Theme.Space.s + 2
        case .regular, .sidecard: Theme.Space.m + 2
        case .large: Theme.Space.l + 2
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.onAccent
        case .secondary, .plain: Theme.ink
        case .destructive: Theme.danger
        case .quiet: Theme.link
        case .danger: Theme.onDanger
        }
    }

    private func fill(dark: Bool) -> Color {
        switch kind {
        case .primary: Theme.accent
        // In dark a card is darker than a raised control; in light the card is white and the hairline does the work.
        case .secondary: dark ? Theme.well : Theme.surfaceRaised
        case .plain, .quiet, .destructive: .clear
        case .danger: Theme.danger
        }
    }
}

/// A button with no look of its own: a row, a tile, a card, words. SwiftUI's `.plain` takes a click only on what is
/// drawn, the lines of a symbol and the letters of a word, whatever frame it has; this takes it anywhere in its frame.
/// `ButtonHitAreaTests` keeps `.plain` out of the app (DESIGN.md › Buttons).
struct SFBareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Bare(configuration: configuration)
    }

    /// A view, so it can read whether the button is enabled (a ButtonStyle can't).
    private struct Bare: View {
        var configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .focusRing(isFocused && buttonsTakeFocus, radius: Theme.Radius.xs)
                .focusEffectDisabled()
        }
    }
}

/// A button that is only a symbol: at least `side` square, all of it taking the click and showing the hover. The size
/// has to be real layout: a shape or padding reaching past a view's frame takes no clicks, and where two overlap
/// neither does (measured with synthetic clicks, 2026-11-03).
struct SFIconButtonStyle: ButtonStyle {
    var side: CGFloat = Theme.Size.hitTarget

    func makeBody(configuration: Configuration) -> some View {
        Icon(side: side, configuration: configuration)
    }

    private struct Icon: View {
        var side: CGFloat
        var configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            configuration.label
                .frame(minWidth: side, minHeight: side)
                .background(Theme.ink.opacity(isEnabled ? (configuration.isPressed ? 0.12 : hovered ? 0.06 : 0) : 0), in: shape)
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .focusRing(isFocused && buttonsTakeFocus)
                .focusEffectDisabled()
                .onHover { hovered = $0 }
                .animation(Theme.Motion.micro, value: configuration.isPressed)
                .animation(Theme.Motion.micro, value: hovered)
        }
    }
}

extension ButtonStyle where Self == SFBareButtonStyle {
    static var sfBare: SFBareButtonStyle { SFBareButtonStyle() }
}

extension ButtonStyle where Self == SFIconButtonStyle {
    static var sfIcon: SFIconButtonStyle { SFIconButtonStyle() }
    static func sfIcon(side: CGFloat) -> SFIconButtonStyle { SFIconButtonStyle(side: side) }
}

extension ButtonStyle where Self == SFButtonStyle {
    static var sfPrimary: SFButtonStyle { SFButtonStyle(kind: .primary) }
    static var sfSecondary: SFButtonStyle { SFButtonStyle(kind: .secondary) }
    static var sfDestructive: SFButtonStyle { SFButtonStyle(kind: .destructive) }
    static var sfPlain: SFButtonStyle { SFButtonStyle(kind: .plain) }
    /// `compact` (the default) is the small size, for buttons inside rows and cards; `large` a page's one main action.
    static func sf(_ kind: SFButtonStyle.Kind, compact: Bool = true, large: Bool = false) -> SFButtonStyle {
        SFButtonStyle(kind: kind, compact: compact && !large, large: large)
    }

    /// A Lantern button by size, optionally working.
    static func sf(_ kind: SFButtonStyle.Kind, size: SFButtonStyle.Size, working: Bool = false, join: SFButtonStyle.Join? = nil) -> SFButtonStyle {
        SFButtonStyle(kind: kind, size: size, working: working, join: join)
    }
}

/// `\.isFocused` answers for the nearest focusable ancestor, so inside a focused card every button would draw the ring,
/// Allow and Not now together, though Return would press neither. With macOS's keyboard navigation on a button takes focus
/// itself, and is its own nearest ancestor. A row made focusable on purpose draws its own ring (`NextUpRow`).
@MainActor private var buttonsTakeFocus: Bool { NSApp?.isFullKeyboardAccessEnabled ?? false }
