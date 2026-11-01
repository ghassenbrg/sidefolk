import AppKit
import SidefolkCore
import SwiftUI

/// A rounded content card with an optional accent stripe in the folk's color.
struct SFCard<Content: View>: View {
    var accent: Color?
    @ViewBuilder var content: Content
    @Environment(\.flatCards) private var flat

    var body: some View {
        if flat {
            // Inside a card already (a request in Ask): no second frame around it.
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            framed
        }
    }

    private var framed: some View {
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

// Text in the shared components (D28): each takes catalog keys, so a literal at the call site is
// collected by `make strings` as it is, and `Text` for anything else: `Text(verbatim:)` for names,
// paths and words already localized where they were made, `Text("…")` beside other text.

/// A group's label (Lantern's eyebrow, D84): small, semibold, in sentence case. Never all capitals: they shout, and
/// some scripts have none.
struct Eyebrow: View {
    var text: Text
    var color: Color = Theme.inkMuted

    init(_ text: Text, color: Color = Theme.inkMuted) {
        self.text = text
        self.color = color
    }

    init(text: LocalizedStringKey, color: Color = Theme.inkMuted) {
        self.init(Text(text), color: color)
    }

    var body: some View {
        text.font(Theme.Font.eyebrow).tracking(Self.tracking).foregroundStyle(color)
    }

    /// Arabic and the languages written without spaces between letters get no tracking (03-system › RTL).
    private static var tracking: CGFloat {
        let script = Locale.current.language.script?.identifier
        return ["Arab", "Hans", "Hant", "Jpan", "Kore"].contains(script ?? "") ? 0 : 0.3
    }
}

/// A capsule 22 tall with a word and an optional symbol (Lantern's chip, D84). Plain chips sit on a well; a status
/// chip takes its tone's soft fill and ink ("Changes files", "2 problems"), always with words.
struct Chip: View {
    var text: Text
    var systemImage: String?
    var tint: Color = Theme.accentSoft
    var ink: Color = Theme.ink

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
            text.lineLimit(1)
        }
        .font(.system(size: 11 * ThemeStore.shared.style.tokens.type.scale, weight: .medium))
        .foregroundStyle(ink)
        .padding(.horizontal, 8)
        .frame(minHeight: Theme.Size.chip)
        .background(tint, in: Capsule())
    }
}

/// A friendly empty state with one line of guidance and, when there is one, the one action that fills it
/// (03-system › States: "empty, with the one action that fills it").
struct EmptyState: View {
    var title: Text
    var message: Text
    var systemImage: String
    /// A folk to show instead of the symbol: empty pages are where the family can say hello.
    var folk: String?
    /// Or any picture, such as your companion at work, at its own size.
    var art: NSImage?
    /// The step that fills the page, drawn as its one primary button.
    var actionTitle: Text?
    var action: () -> Void = {}

    init(title: Text, message: Text, systemImage: String, folk: String? = nil, art: NSImage? = nil, actionTitle: Text? = nil,
         action: @escaping () -> Void = {}) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.folk = folk
        self.art = art
        self.actionTitle = actionTitle
        self.action = action
    }

    init(title: LocalizedStringKey, message: LocalizedStringKey, systemImage: String, folk: String? = nil, art: NSImage? = nil) {
        self.init(title: Text(title), message: Text(message), systemImage: systemImage, folk: folk, art: art)
    }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            if let art {
                Image(nsImage: art).resizable().frame(width: art.size.width, height: art.size.height).accessibilityHidden(true)
            } else if let themed = Theme.Art.empty {
                // The theme's own picture for empty pages (D58), in place of the folk.
                Image(decorative: themed, scale: 2).resizable().scaledToFit().frame(maxWidth: 120, maxHeight: 120)
                    .accessibilityHidden(true)
            } else if let folk, let art = FolkArt.image(folk, size: 88) {
                Image(nsImage: art).resizable().scaledToFit().frame(width: 88, height: 88).accessibilityHidden(true)
            } else {
                Image(systemName: systemImage).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.inkFaint)
            }
            title.font(Theme.Font.title2).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            message.font(Theme.Font.body).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(action: action) { actionTitle }.buttonStyle(.sf(.primary, size: .regular)).padding(.top, Theme.Space.xs)
            }
        }
        .frame(maxWidth: 320)
        .padding(Theme.Space.xxl)
    }
}

/// Relative and absolute time labels in the companion's voice ("Tue 09:00", "in 12 min"). Clock times
/// use the same 24-hour words as hints, cards and notifications (`TimeFormat`), so a reminder reads the
/// same everywhere.
enum TimeText {
    /// "17:00" today, else as `short` ("Tomorrow 08:00"): when something ends.
    static func clock(_ date: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? TimeFormat.clock(date, calendar: .autoupdatingCurrent) : short(date, now: now)
    }

    /// "Yesterday 18:20", "Today 09:00", "Tue 09:00".
    static func short(_ date: Date, now: Date = Date()) -> String {
        TimeFormat.when(date, now: now, calendar: .autoupdatingCurrent)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }

    /// "42s", "4m 12s", "1h 5m", in the app's language.
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let units: Set<Duration.UnitsFormatStyle.Unit> = s < 3600 ? [.minutes, .seconds] : [.hours, .minutes]
        return Duration.seconds(s).formatted(.units(allowed: units, width: .narrow))
    }

    /// Coarse durations for things that run a while: "under a minute", "14 min", "2 h 5 min", "3 days".
    static func span(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        if m < 1 { return String(localized: "under a minute") }
        if m < 60 { return String(localized: "\(m) min") }
        if m < 48 * 60 { return m % 60 == 0 ? String(localized: "\(m / 60) h") : String(localized: "\(m / 60) h \(m % 60) min") }
        return String(localized: "\(m / 1440) days")
    }

    /// "09:00" for an hour of the day.
    static func hour(_ hour: Int) -> String { (hour < 10 ? "0" : "") + "\(hour):00" }
}

// MARK: - Window UI (Home, Settings)

extension EnvironmentValues {
    /// When true, pages lay out at their full height instead of scrolling (snapshot rendering).
    @Entry var rendersFullPage = false
    /// Cards drawn inside a card (Ask's request cards, D84) lose their own frame.
    @Entry var flatCards = false
}

/// A folk's mark: a circle in its color with its symbol. Stands in until rendered folk images land.
struct FolkBadge: View {
    var name: String
    var size: CGFloat = 22

    var body: some View {
        Group {
            // The folk itself; a coloured disc with its prop for names the family doesn't have (extensions).
            if let art = FolkArt.image(name, size: size * 1.4) {
                Image(nsImage: art).resizable().scaledToFit().frame(width: size * 1.4, height: size * 1.4)
                    .padding(-size * 0.2)
            } else {
                Circle()
                    .fill(Theme.folkColor(name))
                    .overlay {
                        Image(systemName: Self.symbol(for: name))
                            .font(.system(size: size * 0.46, weight: .semibold))
                            .foregroundStyle(Theme.navy)
                    }
            }
        }
        .frame(width: size, height: size)
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
    /// A service's own logo, drawn on a neutral plate instead of the symbol when it loads (D36).
    var logo: ProviderLogo?

    var body: some View {
        if let logo, let image = logo.image {
            LogoTile(logo: logo, image: image, size: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Theme.folkColor(folk).opacity(0.24))
                .frame(width: size, height: size)
                .overlay { Image(systemName: symbol).font(.system(size: size * 0.46, weight: .medium)) }
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
        }
    }
}

/// A service's logo on a neutral plate (D36): colour logos keep their colours, black-or-white ones take the
/// appearance's black or white. The mark is drawn well inside the plate, which is the clear space owners ask for.
struct LogoTile: View {
    var logo: ProviderLogo
    var image: NSImage
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Theme.logoPlate)
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Theme.line))
            .frame(width: size, height: size)
            .overlay {
                Image(nsImage: image)
                    .renderingMode(logo.isMonochrome ? .template : .original)
                    .resizable().scaledToFit()
                    .foregroundStyle(Theme.logoInk)
                    .frame(width: size * 0.66, height: size * 0.66)
            }
            .accessibilityHidden(true)
    }
}

/// Tones for chips; each maps to a soft background token. `accent` marks a thing's kind or origin ("Written for you"),
/// never a status; statuses come from `StatusTone`.
enum ChipTone {
    case neutral, accent, success, warning, danger

    init(_ status: StatusTone) {
        switch status {
        case .success: self = .success
        case .warning: self = .warning
        case .danger: self = .danger
        case .news: self = .accent
        case .neutral: self = .neutral
        }
    }

    var tint: Color {
        switch self {
        case .neutral: Theme.well
        case .accent: Theme.accentSoft
        case .success: Theme.successSoft
        case .warning: Theme.warningSoft
        case .danger: Theme.dangerSoft
        }
    }

    /// The words on the tint: each soft fill with its own ink, so a status reads before it is read.
    var ink: Color {
        switch self {
        case .neutral: Theme.ink
        case .accent: Theme.link
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.danger
        }
    }
}

extension Chip {
    init(_ text: LocalizedStringKey, tone: ChipTone, systemImage: String? = nil) {
        self.init(text: Text(text), systemImage: systemImage, tint: tone.tint, ink: tone.ink)
    }

    init(verbatim text: String, tone: ChipTone, systemImage: String? = nil) {
        self.init(text: Text(verbatim: text), systemImage: systemImage, tint: tone.tint, ink: tone.ink)
    }

    init(text: Text, tone: ChipTone, systemImage: String? = nil) {
        self.init(text: text, systemImage: systemImage, tint: tone.tint, ink: tone.ink)
    }
}

/// A section title with its folk, a count, a quiet line beside it ("2 checks failed"), and optional trailing controls.
struct SectionHeader<Trailing: View>: View {
    var title: Text
    var folk: String?
    var count: Int?
    var detail: Text?
    @ViewBuilder var trailing: Trailing

    init(title: Text, folk: String? = nil, count: Int? = nil, detail: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.folk = folk
        self.count = count
        self.detail = detail
        self.trailing = trailing()
    }

    init(title: LocalizedStringKey, folk: String? = nil, count: Int? = nil, detail: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: Text(title), folk: folk, count: count, detail: detail, trailing: trailing)
    }

    var body: some View {
        // In a narrow column the controls go under the title rather than squeezing it.
        WrapRow(minimum: 140, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                if let folk { FolkBadge(name: folk, size: 26) }
                title.font(Theme.Font.heading).foregroundStyle(Theme.ink).lineLimit(1)
                if let count, count > 0 {
                    Text(count.formatted()).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Theme.well, in: Capsule())
                }
                if let detail {
                    detail.font(Theme.Font.callout).foregroundStyle(Theme.inkFaint).lineLimit(1)
                }
            }
            trailing
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, folk: String? = nil, count: Int? = nil, detail: Text? = nil) {
        self.init(title: Text(title), folk: folk, count: count, detail: detail) { EmptyView() }
    }

    init(title: Text, folk: String? = nil, count: Int? = nil, detail: Text? = nil) {
        self.init(title: title, folk: folk, count: count, detail: detail) { EmptyView() }
    }
}

extension View {
    /// The card surface used across windows (Lantern's card, D84): the theme's card colour, a hairline and e1.
    func cardSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .elevation(.e1, radius: radius)
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

/// One line of muted guidance inside a card when a list is empty, with the step that fills it on
/// the same line (a separate row under it read as a second, unrelated item); in a narrow column the
/// step goes under the words rather than squeezing them (WrapRow).
struct InlineEmpty: View {
    var label: Text
    var systemImage: String?
    var actionTitle: LocalizedStringKey?
    var action: () -> Void = {}

    init(text: LocalizedStringKey, systemImage: String? = nil, actionTitle: LocalizedStringKey? = nil, action: @escaping () -> Void = {}) {
        self.init(label: Text(text), systemImage: systemImage, actionTitle: actionTitle, action: action)
    }

    /// `Text(ext:)` for words that aren't Sidefolk's own: a `LocalizedStringKey` made from them would read their
    /// Markdown, and a `[link](file:…)` in an extension's error would open whatever it names on a click.
    init(label: Text, systemImage: String? = nil, actionTitle: LocalizedStringKey? = nil, action: @escaping () -> Void = {}) {
        self.label = label
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        // The picture stays beside the first line of the words; a button that goes under them lines up with the words.
        WrapRow(minimum: 200, spacing: Theme.Space.s, indent: systemImage == nil ? 0 : 18 + Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                if let systemImage {
                    Image(systemName: systemImage).font(Theme.Font.body).foregroundStyle(Theme.inkFaint).frame(width: 18)
                }
                label.font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let actionTitle {
                Button(actionTitle, action: action).buttonStyle(.sf(.secondary)).fixedSize()
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m + 2)
    }
}

/// A short confirmation at the bottom of a window, with an optional undo. Its words are final:
/// the model that shows it words them (`String(localized:)`), names included.
struct Toast: View {
    var message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text(verbatim: message).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            if let actionTitle {
                Button(action: action) { Text(verbatim: actionTitle) }.buttonStyle(.sf(.secondary))
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
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

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
            column.frame(maxWidth: .infinity, alignment: .top).background { PageBackground() }
        } else {
            ScrollView { column.frame(maxWidth: .infinity) }
                .scrollContentBackground(.hidden)
                .background { PageBackground() }
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
    var title: Text
    var footer: Text?
    /// Where Settings' search lands for the whole group (D84).
    var anchor: SettingKey?
    @ViewBuilder var content: Content

    init(title: Text, footer: Text? = nil, anchor: SettingKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.anchor = anchor
        self.content = content()
    }

    init(title: LocalizedStringKey, footer: LocalizedStringKey? = nil, anchor: SettingKey? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: Text(title), footer: footer.map { Text($0) }, anchor: anchor, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Eyebrow(title).padding(.leading, Theme.Space.xs)
                .accessibilityAddTraits(.isHeader)
            RowsCard { content }
            if let footer {
                footer.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.xs)
            }
        }
        .modifier(OptionalSettingAnchor(key: anchor))
    }
}

/// A settings row: what it is (and one line of why) on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    var title: Text
    var detail: Text?
    /// Where Settings' search lands (D84); set by `SettingsRow(_ key:)`.
    var anchor: SettingKey?
    @ViewBuilder var control: Control

    init(title: Text, detail: Text? = nil, anchor: SettingKey? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.anchor = anchor
        self.control = control()
    }

    init(title: LocalizedStringKey, detail: LocalizedStringKey? = nil, @ViewBuilder control: () -> Control) {
        self.init(title: Text(title), detail: detail.map { Text($0) }, control: control)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                title.font(Theme.Font.body).foregroundStyle(Theme.ink)
                if let detail {
                    detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m - 1)
        .frame(minHeight: 44)
        .modifier(OptionalSettingAnchor(key: anchor))
    }
}

/// A switch row; the title doubles as the switch's accessibility label.
struct SettingsToggle: View {
    var title: Text
    var detail: Text?
    var anchor: SettingKey?
    @Binding var isOn: Bool

    init(title: Text, detail: Text? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    init(title: LocalizedStringKey, detail: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.init(title: Text(title), detail: detail.map { Text($0) }, isOn: isOn)
    }

    var body: some View {
        SettingsRow(title: title, detail: detail, anchor: anchor) {
            Toggle(isOn: $isOn) { title }.toggleStyle(.switch).labelsHidden().tint(Theme.accent)
        }
    }
}

/// One option of a single choice, with a line of explanation. Several of them in a card make a
/// radio group whose options can say what they mean.
struct ChoiceRow: View {
    var title: Text
    var detail: Text?
    var selected: Bool
    var action: () -> Void

    init(title: Text, detail: Text? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.selected = selected
        self.action = action
    }

    init(title: LocalizedStringKey, detail: LocalizedStringKey? = nil, selected: Bool, action: @escaping () -> Void) {
        self.init(title: Text(title), detail: detail.map { Text($0) }, selected: selected, action: action)
    }

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
                    title.font(selected ? Theme.Font.bodyStrong : Theme.Font.body).foregroundStyle(Theme.ink)
                    if let detail {
                        detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
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
    var label: Text
    /// Grey text while empty: words (`Text("Optional")`) or an example (`Text(verbatim: "sk-ant-…")`).
    var prompt: Text?
    var value: String
    var width: CGFloat?
    var monospaced: Bool
    var live: Bool
    var commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(label: Text, prompt: Text? = nil, value: String, width: CGFloat? = 240, monospaced: Bool = false, live: Bool = false,
         commit: @escaping (String) -> Void) {
        self.label = label
        self.prompt = prompt
        self.value = value
        self.width = width
        self.monospaced = monospaced
        self.live = live
        self.commit = commit
    }

    init(label: LocalizedStringKey, prompt: Text? = nil, value: String, width: CGFloat? = 240, monospaced: Bool = false,
         live: Bool = false, commit: @escaping (String) -> Void) {
        self.init(label: Text(label), prompt: prompt, value: value, width: width, monospaced: monospaced, live: live, commit: commit)
    }

    var body: some View {
        TextField(text: $draft, prompt: prompt) { label }
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(monospaced ? Theme.Font.mono : Theme.Font.body)
            .focused($focused)
            .padding(.horizontal, Theme.Space.s)
            .frame(minHeight: Theme.Size.field)
            .fieldChrome(focused: focused)
            .frame(width: width)
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
            Text(verbatim: error.description).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.danger)
    }
}

/// The theme's paper grain (D58), tiled faintly over a page. It never takes a click and VoiceOver never sees it.
struct ThemeGrain: View {
    var body: some View {
        if let grain = Theme.Art.grain {
            Image(decorative: grain, scale: 2)
                .resizable(resizingMode: .tile)
                .opacity(0.06)
                .blendMode(.multiply)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}

/// A page's colour, with the theme's wash at the top when it has one (D64): a sky or a dusk fading into the page,
/// behind the cards.
struct PageBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Theme.surfaceSunken
            if let wash = Theme.Art.page(dark: scheme == .dark) {
                Image(decorative: wash, scale: 2).resizable().scaledToFill()
                    .frame(height: 420, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .clipped()
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                    .opacity(0.55)
            }
        }
        .ignoresSafeArea()
        // The wash is scaled to fill: unclipped it spread over the Settings sidebar beside the page and took its
        // clicks (Daylight, Paper Garden).
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
