import SidefolkCore
import SwiftUI

/// The top of Today (D58): the day, a greeting and what's left in one line, beside your companion and the way to ask
/// it something. One line instead of a large card, so the queue under it is in view when the window opens.
struct TodayHeader: View {
    var greeting: Text
    var status: Text
    var settings: AppSettings
    var ask: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Eyebrow(Text(verbatim: Date().formatted(.dateTime.weekday(.wide).day().month(.wide))))
                greeting.font(Theme.Font.title).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                status.font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            Button(action: ask) {
                Label("Ask \(settings.companionName)…", systemImage: "bubble.left.fill")
            }
            .buttonStyle(.sf(.secondary))
            .fixedSize()
            CompanionPortrait(settings: settings, side: 64)
                .accessibilityHidden(true)
        }
        .padding(.bottom, Theme.Space.xs)
        .accessibilityElement(children: .contain)
    }
}

/// The companion in Home's sidebar (D58): its face, its name and one line about what it's keeping track of; asleep
/// while quiet mode is on, as on the desktop.
struct CompanionNook: View {
    var settings: AppSettings
    var line: String

    /// The theme says how the companion sits (D58): on a soft cushion, as a small badge, or as a tilted sticker.
    private var style: ThemeTokens.Nook.Style { ThemeStore.shared.style.tokens.nook.style }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            portrait
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: settings.companionName).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Text(verbatim: line).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(style == .badge ? Theme.Space.xxs : Theme.Space.s)
        .background { background }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens Today"))
    }

    private var portrait: some View {
        let side: CGFloat = style == .badge ? 30 : 38
        return CompanionPortrait(settings: settings, state: settings.isQuiet(at: Date()) ? .sleeping : .idle, side: side)
            .padding(style == .badge ? 3 : 0)
            .background { if style == .badge { Circle().fill(Theme.accentSoft) } }
            .overlay { if style == .badge { Circle().strokeBorder(Theme.line) } }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        switch style {
        case .cushion:
            ZStack {
                shape.fill(Theme.accentSoft.opacity(0.6))
                if let art = Theme.Art.backdrop {
                    // The theme's backdrop, faded so the name and line above it still read.
                    Image(decorative: art, scale: 2).resizable().scaledToFill().opacity(0.35).clipShape(shape)
                }
            }
        case .badge:
            EmptyView()
        case .sticker:
            ZStack {
                shape.fill(Theme.surfaceRaised)
                if let art = Theme.Art.backdrop {
                    Image(decorative: art, scale: 2).resizable().scaledToFill().opacity(0.35).clipShape(shape)
                }
                shape.strokeBorder(Theme.line, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .rotationEffect(.degrees(-1.5))
        }
    }
}
