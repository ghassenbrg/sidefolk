import SidefolkCore
import SwiftUI

/// The top of Today (D58): a greeting, then the day and what's left in counts on one line, so the queue under it is
/// in view when the window opens. The one bar in the toolbar is where you ask.
struct TodayHeader: View {
    var greeting: Text
    var line: [String]
    /// The Board's: a larger greeting with the counts under it.
    var large = false

    var body: some View {
        let rest = ([Date().formatted(.dateTime.weekday(.wide).month(.wide).day())] + line).joined(separator: " · ")
        if large {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                greeting.font(Theme.Font.hero).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Text(verbatim: line.joined(separator: " · ")).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
            }
            .accessibilityElement(children: .combine)
        } else {
            lineHeader(rest)
        }
    }

    private func lineHeader(_ rest: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                title
                Text(verbatim: rest).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                title
                Text(verbatim: rest).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        greeting.font(Theme.Font.title).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
    }

    static func greeting(at date: Date = Date()) -> Text {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: Text("Good morning")
        case 12..<18: Text("Good afternoon")
        default: Text("Good evening")
        }
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

/// The companion at the foot of the sidebar (D62): its face, and a speech bubble with a hello and what it's on.
struct NookBubble: View {
    var settings: AppSettings
    var greeting: String
    var line: String

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xs) {
            CompanionPortrait(settings: settings, state: settings.isQuiet(at: Date()) ? .sleeping : .idle, side: 44)
                .padding(4)
                .background(Theme.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: greeting).font(Theme.Font.caption).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: line).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.s)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous).strokeBorder(Theme.line))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens Today"))
    }
}
