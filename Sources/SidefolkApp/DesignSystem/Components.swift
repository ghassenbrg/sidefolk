import SwiftUI

/// Primary action: aqua with navy text. Secondary: quiet surface. Destructive: coral tint.
struct SFButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, plain }
    var kind: Kind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? Theme.Font.captionStrong : Theme.Font.bodyStrong)
            .lineLimit(1)
            .padding(.horizontal, compact ? Theme.Space.s + 2 : Theme.Space.m)
            .padding(.vertical, compact ? 4 : 7)
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.onAccent
        case .secondary, .plain: Theme.ink
        case .destructive: Theme.danger
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: Theme.accent.opacity(pressed ? 0.8 : 1)
        case .secondary: (pressed ? Theme.surfaceSunken : Theme.surfaceRaised)
        case .destructive: Theme.dangerSoft.opacity(pressed ? 0.7 : 1)
        case .plain: pressed ? Theme.surfaceSunken : .clear
        }
    }
}

extension ButtonStyle where Self == SFButtonStyle {
    static var sfPrimary: SFButtonStyle { SFButtonStyle(kind: .primary) }
    static var sfSecondary: SFButtonStyle { SFButtonStyle(kind: .secondary) }
    static var sfDestructive: SFButtonStyle { SFButtonStyle(kind: .destructive) }
    static var sfPlain: SFButtonStyle { SFButtonStyle(kind: .plain) }
    static func sf(_ kind: SFButtonStyle.Kind, compact: Bool = true) -> SFButtonStyle { SFButtonStyle(kind: kind, compact: compact) }
}

/// A rounded content card with an optional accent stripe in the folk's color.
struct SFCard<Content: View>: View {
    var accent: Color?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            if let accent {
                Rectangle().fill(accent).frame(width: 3)
            }
            content
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
    }
}

/// Small uppercase label above a group.
struct Eyebrow: View {
    var text: String
    var color: Color = Theme.inkMuted
    var body: some View {
        Text(text.uppercased()).font(Theme.Font.eyebrow).kerning(0.6).foregroundStyle(color)
    }
}

struct Chip: View {
    var text: String
    var systemImage: String?
    var tint: Color = Theme.accentSoft
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(Theme.Font.captionStrong)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint, in: Capsule())
    }
}

/// A friendly empty state with one line of guidance.
struct EmptyState: View {
    var title: String
    var message: String
    var systemImage: String
    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: systemImage).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.inkFaint)
            Text(title).font(Theme.Font.heading).foregroundStyle(Theme.ink)
            Text(message).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: 320)
        .padding(Theme.Space.xxl)
    }
}

/// Relative and absolute time labels in the companion's voice ("Tue 09:00", "in 12 min").
enum TimeText {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow \(time)" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yesterday) { return "Yesterday \(time)" }
        if abs(date.timeIntervalSince(now)) < 6 * 86400 {
            return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time
        }
        return date.formatted(.dateTime.day().month(.abbreviated)) + " " + time
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}
