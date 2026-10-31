#if DEBUG
import SidefolkCore
import SwiftUI

/// Lantern's design-system sheet (D84, docs/DESIGN.md), drawn by the app's own tokens and components, for UI snapshots:
/// `design-system-foundations`, `-controls` and `-sidecard`, in the active theme, light and dark, in any language.
/// It is the reference the later phases build from: if something here looks wrong, the component is wrong. Sample
/// words are English content, like the other samples.
struct DesignSystemSheet: View {
    enum Page: String, CaseIterable { case foundations, controls, sidecard }
    var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            header
            switch page {
            case .foundations: DSFoundations()
            case .controls: DSControls()
            case .sidecard: DSSidecard()
            }
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSunken)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.accent)
                .frame(width: 44, height: 44)
                .overlay { Image(systemName: "sparkle").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.onAccent) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Lantern, the design system").font(Theme.Font.display).foregroundStyle(Theme.ink)
                Text(verbatim: "\(page.rawValue.capitalized) · \(ThemeStore.shared.style.tokens.name) · every value from the theme's tokens")
                    .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            SegmentedPicker(Text(verbatim: "Page"), selection: .constant(page),
                            segments: Page.allCases.map { .init($0, verbatim: $0.rawValue.capitalized) })
        }
    }
}

/// A board: a card with a title2 heading and a quiet line beside it.
struct DSBoard<Content: View>: View {
    var title: String
    var detail: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(verbatim: title).font(Theme.Font.title2).foregroundStyle(Theme.ink)
                Text(verbatim: detail).font(Theme.Font.callout).foregroundStyle(Theme.inkFaint)
            }
            content
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardSurface()
    }
}

/// A small label over a sample.
struct DSLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Eyebrow(Text(verbatim: text), color: Theme.inkFaint) }
}

// MARK: Foundations

private struct DSFoundations: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                DSBoard(title: "Type scale", detail: "the theme's face for titles and numbers; the system face for reading") { typeScale }
                    .frame(width: 640)
                DSBoard(title: "Colour", detail: "contrast is text on its usual background (WCAG 2)") { colours }
            }
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                DSBoard(title: "Spacing", detail: "8 pt grid") { spacing }
                DSBoard(title: "Corners", detail: "continuous") { corners }
                DSBoard(title: "Depth", detail: "a shadow in light, a hairline in dark") { depth }
            }
        }
    }

    private var typeScale: some View {
        let rows: [(String, Font, String, String)] = [
            ("display", Theme.Font.display, "Good afternoon, Ghassen.", "30 semibold, theme face"),
            ("title1", Theme.Font.title1, "On duty", "22 semibold, theme face"),
            ("title2", Theme.Font.title2, "Install Miraya?", "17 semibold"),
            ("headline", Theme.Font.headline, "Move 12 PDFs to Invoices", "14 semibold"),
            ("body", Theme.Font.body, "Sidefolk starts quietly when you log in.", "13"),
            ("callout", Theme.Font.callout, "2 checks failed · 1 min ago", "12, ink 2 or 3"),
            ("caption", Theme.Font.caption, "15:52 · Pro $12 → $15", "11.5, the floor is 11"),
            ("stateWord", Theme.Font.stateWord, "Changed", "26 semibold, theme face"),
            ("number", Theme.Font.number, "18.4 °C", "26 medium, tabular"),
            ("bubble", Theme.Font.bubble, "Claude Code saved an idea", "14, over wallpapers"),
            ("input", Theme.Font.input, "remind me tomorrow at 9", "17 (15 in Home)"),
            ("mono", Theme.Font.mono, "git push origin main", "12, the exact request only"),
        ]
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    Text(verbatim: row.0).font(Theme.Font.mono).foregroundStyle(Theme.inkFaint).frame(width: 80, alignment: .leading)
                    Text(verbatim: row.2).font(row.1).foregroundStyle(row.0 == "stateWord" ? Theme.link : Theme.ink).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text(verbatim: row.3).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                }
                Divider().overlay(Theme.line)
            }
            HStack {
                DSLabel("Eyebrow, sentence case")
                Spacer()
                Text(verbatim: "Benachrichtigungen während des Fokus zurückhalten").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            }
        }
    }

    private var colours: some View {
        let c = ThemeStore.shared.style.tokens.colors
        let dark = scheme == .dark
        func hex(_ pair: ThemeTokens.Pair) -> UInt32 { dark ? pair.dark : pair.light }
        let card = hex(c.surfaceRaised)
        let swatches: [(String, Color, Color?, UInt32?, UInt32)] = [
            ("ink", Theme.ink, nil, hex(c.ink), card),
            ("inkMuted", Theme.inkMuted, nil, hex(c.inkMuted), card),
            ("inkFaint", Theme.inkFaint, nil, hex(c.inkFaint), card),
            ("link", Theme.link, nil, hex(c.link), card),
            ("accent · onAccent", Theme.accent, Theme.onAccent, hex(c.onAccent), hex(c.accent)),
            ("accentSoft", Theme.accentSoft, Theme.link, hex(c.link), hex(c.accentSoft)),
            ("canvas (surfaceSunken)", Theme.surfaceSunken, nil, nil, 0),
            ("card (surfaceRaised)", Theme.surfaceRaised, nil, nil, 0),
            ("well", Theme.well, Theme.inkFaint, hex(c.inkFaint), hex(c.well)),
            ("warning · soft", Theme.warningSoft, Theme.warning, hex(c.warning), hex(c.warningSoft)),
            ("danger · soft", Theme.dangerSoft, Theme.danger, hex(c.danger), hex(c.dangerSoft)),
            ("success · soft", Theme.successSoft, Theme.success, hex(c.success), hex(c.successSoft)),
        ]
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 4), spacing: Theme.Space.s) {
                ForEach(swatches, id: \.0) { s in
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack(alignment: .topTrailing) {
                            Rectangle().fill(s.1).frame(height: 44)
                                .overlay(alignment: .bottomLeading) {
                                    if let text = s.2 { Text(verbatim: "Aa").font(Theme.Font.bodyStrong).foregroundStyle(text).padding(6) }
                                }
                            if let fore = s.3 {
                                Text(verbatim: String(format: "%.1f", ThemeCheck.contrast(fore, s.4)))
                                    .font(Theme.Font.captionStrong).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 5).background(Theme.surfaceRaised, in: Capsule()).padding(5)
                            }
                        }
                        Text(verbatim: s.0).font(Theme.Font.callout).foregroundStyle(Theme.ink).lineLimit(1).padding(6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
                }
            }
            DSLabel("Light, never text")
            HStack(spacing: Theme.Space.s) {
                ForEach([("glow · working", Theme.glow), ("waitGlow · waiting", Theme.waitGlow), ("danger · failed", Theme.danger)], id: \.0) { light in
                    Text(verbatim: light.0).font(Theme.Font.callout.weight(.semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RadialGradient(colors: [light.1.opacity(0.45), light.1.opacity(0.05)], center: .center, startRadius: 0, endRadius: 110),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
            }
            DSLabel("Folk accents: a dot, an avatar, a 2 pt bar; never body text")
            HStack(spacing: Theme.Space.m) {
                ForEach(["tempo", "scout", "byte", "guard", "pip", "play", "nova", "seed", "melody", "brew"], id: \.self) { folk in
                    VStack(spacing: 4) {
                        FolkAvatar(name: folk, size: Theme.Size.avatar, live: folk == "scout")
                        Text(verbatim: folk.capitalized).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }

    private var spacing: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.s) {
            ForEach([Theme.Space.xs, Theme.Space.s, Theme.Space.m, Theme.Space.l, Theme.Space.xl, Theme.Space.xxl, Theme.Space.xxxl], id: \.self) { v in
                VStack(spacing: 4) {
                    Rectangle().fill(Theme.accentSoft).overlay(Rectangle().strokeBorder(Theme.accent.opacity(0.5))).frame(width: v, height: v)
                    Text(verbatim: "\(Int(v))").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    private var corners: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach([("xs", Theme.Radius.xs), ("control", Theme.Radius.control), ("card", Theme.Radius.card), ("panel", Theme.Radius.panel)], id: \.0) { r in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: r.1, style: .continuous).fill(Theme.accentSoft)
                        .overlay(RoundedRectangle(cornerRadius: r.1, style: .continuous).strokeBorder(Theme.accent.opacity(0.6)))
                        .frame(width: 52, height: 44)
                    Text(verbatim: "\(r.0) \(Int(r.1))").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
            }
            VStack(spacing: 4) {
                Capsule().fill(Theme.accentSoft).overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6))).frame(width: 60, height: 24)
                Text(verbatim: "capsule").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private var depth: some View {
        HStack(spacing: Theme.Space.l) {
            ForEach(Theme.Elevation.allCases, id: \.self) { level in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surfaceRaised)
                        .frame(width: 64, height: 48)
                        .elevation(level)
                    Text(verbatim: "e\(level.rawValue)").font(Theme.Font.captionStrong).foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(.bottom, Theme.Space.l)
    }
}

// MARK: Controls

private struct DSControls: View {
    @State private var segment = 1
    @State private var look = 2
    @State private var on = true
    @State private var off = false
    @State private var say = ""
    @State private var search = ""
    @FocusState private var focus: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            DSBoard(title: "Buttons", detail: "28 tall in windows, 30 in the Sidecard, 32 large, 24 small; one primary per card, sheet or page") {
                buttons
            }
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                DSBoard(title: "Fields", detail: "a well, no border until focus") { fields }
                DSBoard(title: "Chips and states", detail: "22 tall, sentence case; colour always with a word") { chips }
            }
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                DSBoard(title: "Choices", detail: "segmented, switch, radio") { choices }
                DSBoard(title: "Lists and rows", detail: "44 tall, 16 at the sides, a 24 pt icon") { rows }
            }
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                DSBoard(title: "Tiles and pins", detail: "the tone only on the word and a 3 pt bar") { tiles }
                DSBoard(title: "Empty", detail: "with the one action that fills it") {
                    EmptyState(title: Text(verbatim: "Nothing on duty"), message: Text(verbatim: "Watches, live values and agents show up here while they run."),
                               systemImage: "dot.radiowaves.left.and.right", folk: "scout", actionTitle: Text(verbatim: "Watch a page…"))
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 380)
            }
        }
    }

    private var buttons: some View {
        let kinds: [(String, SFButtonStyle.Kind, String)] = [("Primary", .primary, "Allow"), ("Secondary", .secondary, "Not now"),
                                                             ("Quiet", .quiet, "Later"), ("Destructive", .destructive, "Remove"),
                                                             ("Danger, to confirm", .danger, "Delete all"), ("Plain", .plain, "Show more")]
        return Grid(alignment: .leading, horizontalSpacing: Theme.Space.xl, verticalSpacing: Theme.Space.m) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                ForEach(["Default", "Disabled", "Working", "Small", "Sidecard", "Large"], id: \.self) { DSLabel($0) }
            }
            ForEach(kinds, id: \.0) { kind in
                GridRow {
                    Text(verbatim: kind.0).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    Button {} label: { Text(verbatim: kind.2) }.buttonStyle(.sf(kind.1, size: .regular))
                    Button {} label: { Text(verbatim: kind.2) }.buttonStyle(.sf(kind.1, size: .regular)).disabled(true)
                    Button {} label: { Text(verbatim: kind.1 == .primary ? "Installing" : "Looking") }.buttonStyle(.sf(kind.1, size: .regular, working: true))
                    Button {} label: { Text(verbatim: kind.2) }.buttonStyle(.sf(kind.1, size: .small))
                    Button {} label: { Text(verbatim: kind.2) }.buttonStyle(.sf(kind.1, size: .sidecard))
                    Button {} label: { Label { Text(verbatim: kind.2) } icon: { Image(systemName: "play.fill") } }.buttonStyle(.sf(kind.1, size: .large))
                }
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                sample("Empty", Text(verbatim: "Name a place").foregroundStyle(Theme.inkFaint), focused: false)
                sample("Filled", Text(verbatim: "Paris").foregroundStyle(Theme.ink), focused: false)
                sample("Focus", Text(verbatim: "Par|").foregroundStyle(Theme.ink), focused: true)
            }
            HStack(alignment: .top, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 4) {
                    DSLabel("Search")
                    SearchBox(text: $search, prompt: Text(verbatim: "Search settings"), focus: $focus, focusValue: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    DSLabel("Error")
                    fieldText(Text(verbatim: "sk-ant-•••••4f2a").foregroundStyle(Theme.ink), focused: false, problem: true)
                    Label { Text(verbatim: "That key didn't work. Nothing was saved.") } icon: { Image(systemName: "exclamationmark.triangle") }
                        .font(Theme.Font.callout).foregroundStyle(Theme.danger)
                }
            }
            DSLabel("Say bar, Home (40) and desktop (52)")
            SayBarField(text: $say, prompt: Text(verbatim: "Ask Mochi, or type a reminder, note or watch…"), tint: Theme.link)
            SayBarField(text: .constant("remind me tomorrow at 9 to send the deck"), prompt: Text(verbatim: ""), size: .desktop, hint: nil)
            UnderstandingRow(symbol: "bell", sentence: Text(verbatim: "I'll remind you tomorrow at 09:00 to send the deck."),
                             keys: [.init(keys: "↩", title: Text(verbatim: "Set it")), .init(keys: "⌘↩", title: Text(verbatim: "Ask Mochi")),
                                    .init(keys: "⌥↩", title: Text(verbatim: "Save as note"))]) {
                Chip(text: Text(verbatim: "Reminder"), tone: .accent, systemImage: "bell")
                Chip(text: Text(verbatim: "Sun 1 Nov, 09:00"), tone: .neutral, systemImage: "calendar")
                Chip(text: Text(verbatim: "On this Mac, no AI"), tone: .success, systemImage: "checkmark.circle")
            }
        }
    }

    private func sample(_ label: String, _ text: Text, focused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DSLabel(label)
            fieldText(text, focused: focused, problem: false)
        }
    }

    private func fieldText(_ text: Text, focused: Bool, problem: Bool) -> some View {
        text.font(Theme.Font.body)
            .padding(.horizontal, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.field, alignment: .leading)
            .fieldChrome(focused: focused, problem: problem)
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ButtonRow(spacing: Theme.Space.xs) {
                Chip(text: Text(verbatim: "3D"), tone: .neutral)
                Chip(text: Text(verbatim: "Suggested"), tone: .accent)
                Chip(text: Text(verbatim: "Connected"), tone: .success, systemImage: "checkmark")
                Chip(text: Text(verbatim: "2 problems"), tone: .warning)
                Chip(text: Text(verbatim: "Not a time"), tone: .danger)
            }
            DSLabel("What it touches")
            ButtonRow(spacing: Theme.Space.xs) {
                ForEach(Array(Touch.allCases.enumerated()), id: \.offset) { TouchChip($0.element) }
            }
            DSLabel("Counts and states")
            HStack(spacing: Theme.Space.m) {
                CountBadge(count: 3)
                CountBadge(count: 120)
                CountBadge(count: 4, waiting: false)
                StatusBadge(Text(verbatim: "Ready"), state: .tone(.success))
                StatusBadge(Text(verbatim: "Needs you"), state: .tone(.warning))
                StatusBadge(Text(verbatim: "Working"), state: .live)
                StatusBadge(Text(verbatim: "Stopped after crashing"), state: .tone(.danger))
                StatusBadge(Text(verbatim: "Paused"), state: .tone(.neutral))
            }
            DSLabel("Section header")
            SectionHeader(title: Text(verbatim: "Watching"), folk: "scout", count: 3, detail: Text(verbatim: "1 paused")) {
                Button {} label: { Text(verbatim: "Watch a page…") }.buttonStyle(.sf(.secondary))
            }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SegmentedPicker(Text(verbatim: "Channel"), selection: $segment, segments: [.init(0, verbatim: "Releases"), .init(1, verbatim: "Snapshots")])
            SegmentedPicker(Text(verbatim: "Appearance"), selection: $look, segments: [
                .init(0, verbatim: "Light", symbol: "sun.max"), .init(1, verbatim: "Dark", symbol: "moon"),
                .init(2, verbatim: "Same as Mac", symbol: "circle.lefthalf.filled"),
            ])
            SegmentedPicker(Text(verbatim: "Show"), selection: $segment, segments: [.init(0, verbatim: "All 15"), .init(1, verbatim: "On 9"), .init(2, verbatim: "Off 6")],
                            small: true)
            HStack(spacing: Theme.Space.l) {
                Toggle(isOn: $on) { Text(verbatim: "On") }.toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                Toggle(isOn: $off) { Text(verbatim: "Off") }.toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                Toggle(isOn: $on) { Text(verbatim: "Checked") }.toggleStyle(.checkbox).tint(Theme.accent)
            }
            RowsCard {
                ChoiceRow(title: Text(verbatim: "Ask each time"), detail: Text(verbatim: "Guard asks before anything that changes things."), selected: true) {}
                ChoiceRow(title: Text(verbatim: "Auto"), detail: Text(verbatim: "Low-risk steps run without asking."), selected: false) {}
            }
        }
    }

    private var rows: some View {
        RowsCard {
            ListRow(title: Text(verbatim: "Your Mac"), meta: Text(verbatim: "Default · a title and one meta line"),
                    leading: { IconTile(symbol: "desktopcomputer", folk: "byte", size: Theme.Size.rowIcon) }, trailing: { RowChevron() })
            ListRow(title: Text(verbatim: "Clipboard"), meta: Text(verbatim: "Selected · accent soft, link title"), selected: true,
                    leading: { IconTile(symbol: "doc.on.clipboard", folk: "guard", size: Theme.Size.rowIcon) }, trailing: { KeyHint("⇧⌘C") })
            ListRow(title: Text(verbatim: "Keep Awake"), meta: Text(verbatim: "With a switch"),
                    leading: { IconTile(symbol: "bolt", folk: "scout", size: Theme.Size.rowIcon) },
                    trailing: { Toggle(isOn: $on) { Text(verbatim: "Keep Awake") }.toggleStyle(.switch).labelsHidden().tint(Theme.accent) })
            ListRow(title: Text(verbatim: "World Clock"), meta: Text(verbatim: "With a state"),
                    leading: { IconTile(symbol: "clock", folk: "tempo", size: Theme.Size.rowIcon) },
                    trailing: { StatusBadge(Text(verbatim: "Stopped after crashing"), state: .tone(.danger)) })
            ListRow(title: Text(verbatim: "Compact row, 32"), compact: true) { Text(verbatim: "09:00").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted) }
        }
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                StateTile(source: Text(verbatim: "example.com/pricing"), symbol: "globe", value: Text(verbatim: "Changed"), tone: .news,
                          meta: Text(verbatim: "15:52 · Pro $12 → $15"))
                StateTile(source: Text(verbatim: "staging.sidefolk.app"), symbol: "dot.radiowaves.left.and.right", value: Text(verbatim: "Having trouble"),
                          tone: .danger, meta: Text(verbatim: "2 checks failed"))
                StateTile(source: Text(verbatim: "CPU · every 10 s"), symbol: "cpu", value: Text(verbatim: "23%"), tone: nil,
                          meta: Text(verbatim: "stops 17:05"), spark: [12, 18, 15, 22, 19, 25, 21, 23])
            }
            DSLabel("Pins on the desktop: a glass capsule 36 tall")
            HStack(spacing: Theme.Space.s) {
                PinCapsule(symbol: "cpu", label: Text(verbatim: "CPU"), value: Text(verbatim: "23%"), spark: [12, 18, 15, 22, 19, 25, 21, 23])
                PinCapsule(symbol: "cloud", label: Text(verbatim: "Fukuoka"), value: Text(verbatim: "18.4°"))
                PinCapsule(symbol: "cpu", label: Text(verbatim: "CPU"), value: Text(verbatim: "—"), note: Text(verbatim: "paused"))
            }
            .padding(Theme.Space.m)
            .background(LinearGradient(colors: [Theme.glow.opacity(0.18), Theme.lightBlue.opacity(0.18)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }
}

// MARK: Sidecard

private struct DSSidecard: View {
    @State private var ask = "remind me tomorrow at 9 to send the deck to Acme"
    private let portrait = CompanionArt.portrait(for: AppSettings(), side: 84)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            DSBoard(title: "Light pool", detail: "state without reading; colour is never the only signal") {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    ForEach(Array(states.enumerated()), id: \.offset) { _, item in
                        VStack(spacing: Theme.Space.xs) {
                            companion(item.state, held: item.held)
                            item.state.spoken.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                            Text(verbatim: item.note).font(Theme.Font.callout).foregroundStyle(Theme.inkFaint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            DSBoard(title: "The Sidecard, four sizes", detail: "glass, panel corner, a tail to the companion's head") {
                HStack(alignment: .bottom, spacing: Theme.Space.xl) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        DSLabel("Whisper · gentle")
                        Whisper(text: Text(verbatim: "Claude Code saved an idea"), folk: "byte", timeLeft: 0.6) {
                            Button {} label: { Text(verbatim: "Undo") }
                        }
                        .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        DSLabel("Card · attention")
                        SidecardCard(folk: "tempo", source: Text(verbatim: "Tempo · reminder · every 2 h"), title: Text(verbatim: "Stretch and refill water"),
                                     message: Text(verbatim: "You asked yesterday at 18:20. Next one at 19:00."), close: {}) {
                            Button {} label: { Text(verbatim: "Skip today") }.buttonStyle(.sf(.quiet, size: .sidecard))
                            Button {} label: { Text(verbatim: "In 10 min") }.buttonStyle(.sf(.secondary, size: .sidecard))
                            Button {} label: { Text(verbatim: "Done") }.buttonStyle(.sf(.primary, size: .sidecard))
                        }
                        .frame(width: 340)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        DSLabel("Ask · you call it")
                        SidecardSurface(tail: SidecardTail(edge: .bottom, at: 0.85)) {
                            VStack(alignment: .leading, spacing: Theme.Space.m) {
                                SayBarField(text: $ask, prompt: Text(verbatim: "Ask Mochi"), size: .desktop, hint: nil)
                                UnderstandingRow(symbol: "bell", sentence: Text(verbatim: "I'll remind you tomorrow at 09:00 to send the deck to Acme."),
                                                 keys: [.init(keys: "↩", title: Text(verbatim: "Set it")), .init(keys: "⌘↩", title: Text(verbatim: "Ask Mochi"))]) {
                                    Chip(text: Text(verbatim: "Reminder"), tone: .accent, systemImage: "bell")
                                    Chip(text: Text(verbatim: "On this Mac, no AI"), tone: .success, systemImage: "checkmark.circle")
                                }
                            }
                        }
                        .frame(width: Theme.Size.sidecardAsk)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        DSLabel("Stack · held")
                        ZStack(alignment: .topTrailing) {
                            SidecardStack(items: [
                                .init(id: "a", folk: "byte", title: Text(verbatim: "Codex asks")),
                                .init(id: "b", folk: "scout", title: Text(verbatim: "Pricing changed")),
                                .init(id: "c", folk: "tempo", title: Text(verbatim: "Stretch and refill water"), meta: Text(verbatim: "17:00 · Done · In 10 min")),
                            ])
                            ShoulderBadge(state: .waiting(3)).offset(x: 10, y: -12)
                        }
                    }
                }
            }
            DSBoard(title: "Permission slip", detail: "one sentence, what it touches, one clear choice; calm or firm by source, never red unless blocked") {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    slip(strip: SidecardStrip(tone: .calm, text: Text(verbatim: "You asked for this · Guard checks it")), folk: "guard",
                         title: "Mochi wants to move 12 PDFs to Invoices", meta: "From Downloads · waits until 16:27", touches: [.changesFiles], primary: "Allow")
                    slip(strip: SidecardStrip(tone: .firm, text: Text(verbatim: "Another app is asking. Only you can answer it.")), folk: "byte",
                         title: "Codex wants to read what you copied last", meta: "Codex in pockito · waits until 16:12", touches: [.clipboard, .readOnly],
                         primary: "Allow once", hint: "⌘↩")
                }
            }
        }
    }

    private var states: [(state: LightPoolState, held: Int, note: String)] {
        [(.idle, 0, "no light"), (.working, 0, "glow 35%, breathes 3 s"), (.waiting(3), 0, "amber 45%, a count"), (.alert, 0, "amber 60%, one pulse"),
         (.failed, 0, "danger 35%"), (.focus, 0, "grey 15%, half circle"), (.quiet, 0, "off, moon")]
    }

    private func companion(_ state: LightPoolState, held: Int) -> some View {
        ZStack(alignment: .bottom) {
            LightPool(state: state, width: 120).offset(y: 10)
            Image(nsImage: portrait).resizable().scaledToFit().frame(width: 84, height: 84)
                .opacity(state == .quiet ? 0.7 : 1)
                .overlay(alignment: .topTrailing) { ShoulderBadge(state: state, held: held).offset(x: 6, y: -4) }
        }
        .frame(height: 112)
    }

    private func slip(strip: SidecardStrip, folk: String, title: String, meta: String, touches: [Touch], primary: String, hint: String? = nil) -> some View {
        SidecardCard(folk: folk, title: Text(verbatim: title), message: Text(verbatim: meta), strip: strip, tail: nil, extra: {
            HStack(spacing: Theme.Space.xs) {
                ForEach(Array(touches.enumerated()), id: \.offset) { TouchChip($0.element) }
                Button {} label: { Label { Text(verbatim: "Exact request") } icon: { Image(systemName: "chevron.down") } }
                    .buttonStyle(.sf(.quiet, size: .small)).labelStyle(.titleAndIcon)
            }
        }, actions: {
            Button {} label: { Text(verbatim: "Not now") }.buttonStyle(.sf(.secondary, size: .sidecard))
            Button {} label: {
                HStack(spacing: 6) {
                    Text(verbatim: primary)
                    if let hint { Text(verbatim: "\u{2066}\(hint)\u{2069}").opacity(0.75) }
                }
            }.buttonStyle(.sf(.primary, size: .sidecard))
        })
        .frame(width: 400)
    }
}
#endif
