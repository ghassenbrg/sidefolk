import SidefolkCore
import SwiftUI

/// Primary action: aqua with navy text. Secondary: quiet surface. Destructive: coral tint.
struct SFButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, plain }
    var kind: Kind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(style: self, configuration: configuration)
    }

    /// A view, so it can read whether the button is enabled (a ButtonStyle can't).
    private struct StyledLabel: View {
        var style: SFButtonStyle
        var configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            style.styled(configuration).opacity(isEnabled ? 1 : 0.45)
        }
    }

    private func styled(_ configuration: Configuration) -> some View {
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

/// Relative and absolute time labels in the companion's voice ("Tue 09:00", "in 12 min"). Clock times
/// use the same 24-hour words as hints, cards and notifications (`TimeFormat`), so a reminder reads the
/// same everywhere.
enum TimeText {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(TimeFormat.clock(date, calendar: cal))"
        }
        return TimeFormat.when(date, now: now, calendar: cal)
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

    /// Coarse durations for things that run a while: "under a minute", "14 min", "2 h 5 min", "3 days".
    static func span(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        if m < 1 { return "under a minute" }
        if m < 60 { return "\(m) min" }
        if m < 48 * 60 { return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min" }
        return "\(m / 1440) days"
    }

    /// "09:00" for an hour of the day.
    static func hour(_ hour: Int) -> String { (hour < 10 ? "0" : "") + "\(hour):00" }
}

// MARK: - Window UI (Home, Settings)

extension EnvironmentValues {
    /// When true, pages lay out at their full height instead of scrolling (snapshot rendering).
    @Entry var rendersFullPage = false
}

/// A folk's mark: a circle in its color with its symbol. Stands in until rendered folk images land.
struct FolkBadge: View {
    var name: String
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(Theme.folkColor(name))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: Self.symbol(for: name))
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Theme.navy)
            }
            .accessibilityHidden(true)
    }

    /// The prop each folk holds on the identity sheet.
    static func symbol(for name: String) -> String {
        switch name {
        case "pip": "lightbulb.fill"
        case "tempo": "calendar"
        case "scout": "magnifyingglass"
        case "byte": "chevron.left.forwardslash.chevron.right"
        case "guard": "checkmark.shield.fill"
        case "seed": "leaf.fill"
        case "melody": "music.note"
        case "nova": "paintpalette.fill"
        case "play": "gamecontroller.fill"
        case "brew": "cup.and.saucer.fill"
        default: "puzzlepiece.extension.fill"
        }
    }
}

/// The leading icon of a row: a soft tile in the domain's folk color.
struct IconTile: View {
    var symbol: String
    var folk: String
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Theme.folkColor(folk).opacity(0.24))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityHidden(true)
    }
}

/// Tones for status chips; each maps to a soft background token.
enum ChipTone {
    case neutral, accent, success, warning, danger

    var tint: Color {
        switch self {
        case .neutral: Theme.surfaceSunken
        case .accent: Theme.accentSoft
        case .success: Theme.successSoft
        case .warning: Theme.sun.opacity(0.28)
        case .danger: Theme.dangerSoft
        }
    }
}

extension Chip {
    init(_ text: String, tone: ChipTone, systemImage: String? = nil) {
        self.init(text: text, systemImage: systemImage, tint: tone.tint)
    }
}

/// A section title with its folk, a count, and optional trailing controls.
struct SectionHeader<Trailing: View>: View {
    var title: String
    var folk: String?
    var count: Int?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let folk { FolkBadge(name: folk, size: 20) }
            Text(title).font(Theme.Font.heading).foregroundStyle(Theme.ink)
            if let count, count > 0 {
                Text("\(count)").font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Theme.surfaceRaised, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.line))
            }
            Spacer(minLength: Theme.Space.s)
            trailing
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, folk: String? = nil, count: Int? = nil) {
        self.init(title: title, folk: folk, count: count) { EmptyView() }
    }
}

extension View {
    /// The raised card surface used across windows: white (navy in dark), hairline, soft lift.
    func cardSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line))
            .shadow(color: Theme.navy.opacity(0.05), radius: 8, y: 2)
    }
}

/// A card whose children are rows separated by hairlines, like a grouped list.
struct RowsCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.pixelLength) private var pixel

    var body: some View {
        Group(subviews: content) { rows in
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Rectangle().fill(Theme.line).frame(height: pixel * 2).padding(.leading, Theme.Space.l)
                    }
                    row.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .cardSurface()
    }
}

/// One line of muted guidance inside a card when a list is empty.
struct InlineEmpty: View {
    var text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(Theme.inkFaint) }
            Text(text).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m + 2)
    }
}

/// A short confirmation at the bottom of a window, with an optional undo.
struct Toast: View {
    var message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text(message).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            if let actionTitle {
                Button(actionTitle, action: action).buttonStyle(.sf(.secondary))
            }
        }
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, actionTitle == nil ? Theme.Space.l : Theme.Space.s)
        .padding(.vertical, Theme.Space.s)
        .cardSurface(radius: 22)
        .shadow(color: Theme.navy.opacity(0.12), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
}

/// A large page title with a one-line subtitle, as on every Home section.
struct PageTitle: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.Font.title).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A scrolling page on the sunken background with a centered column of content.
struct PageScroll<Content: View>: View {
    var maxWidth: CGFloat = 760
    var padding: CGFloat = Theme.Space.xxl
    @ViewBuilder var content: Content
    @Environment(\.rendersFullPage) private var fullPage

    var body: some View {
        if fullPage {
            column.frame(maxWidth: .infinity, alignment: .top).background(Theme.surfaceSunken)
        } else {
            ScrollView { column.frame(maxWidth: .infinity) }
                .scrollContentBackground(.hidden)
                .background(Theme.surfaceSunken)
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) { content }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, padding)
            .padding(.vertical, Theme.Space.xl)
    }
}

// MARK: Settings rows

/// A titled group of settings in one card, with an optional note under it.
struct SettingsGroup<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Eyebrow(text: title).padding(.leading, Theme.Space.xs)
                .accessibilityAddTraits(.isHeader)
            RowsCard { content }
            if let footer {
                Text(footer).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.xs)
            }
        }
    }
}

/// A settings row: what it is (and one line of why) on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.body).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m - 1)
        .frame(minHeight: 44)
    }
}

/// A switch row; the title doubles as the switch's accessibility label.
struct SettingsToggle: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
        }
    }
}

/// One option of a single choice, with a line of explanation. Several of them in a card make a
/// radio group whose options can say what they mean.
struct ChoiceRow: View {
    var title: String
    var detail: String?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ZStack {
                    Circle().strokeBorder(selected ? Theme.accent : Theme.inkFaint, lineWidth: 1.5)
                    if selected {
                        Circle().fill(Theme.accent)
                        Circle().fill(Theme.surfaceRaised).frame(width: 6, height: 6)
                    }
                }
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(selected ? Theme.Font.bodyStrong : Theme.Font.body).foregroundStyle(Theme.ink)
                    if let detail {
                        Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m - 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A text field that saves when editing ends (Return or focus leaves), not on every keystroke,
/// unless `live`: then every change is saved at once, for values a button next to it uses
/// (clicking a button doesn't end editing).
struct CommitField: View {
    var label: String
    var prompt: String = ""
    var value: String
    var width: CGFloat? = 240
    var monospaced = false
    var live = false
    var commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $draft, prompt: Text(prompt))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .font(monospaced ? .system(size: 12, design: .monospaced) : Theme.Font.body)
            .frame(width: width)
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, new in if !focused { draft = new } }
            .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
            .onChange(of: draft) { if live, focused { save() } }
            .onSubmit(save)
            .accessibilityLabel(label)
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != value { commit(trimmed) }
    }
}

/// Plain-language error text under a control: what failed and what to do.
struct InlineError: View {
    var error: UserFacingError

    var body: some View {
        Label {
            Text(error.description).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.danger)
    }
}
