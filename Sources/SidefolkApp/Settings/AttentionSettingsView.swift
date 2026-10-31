import SidefolkCore
import SwiftUI

/// Settings › Attention (D84): Open, Focus or Quiet right now and until when, quiet on its own (quiet hours, full-screen
/// apps), and how things reach you (sounds, notifications, the morning brief). Built on Attention's own rules, so each
/// card says exactly what that mode lets through.
struct AttentionSettingsView: View {
    var model: SettingsModel

    var body: some View {
        SettingsPage {
            AttentionHero(model: model)
                .settingAnchor(.attentionMode)

            SettingsGroup(title: Text(verbatim: SettingKey.quietHours.section)) {
                QuietHoursRow(model: model)
                SettingsRow(.fullScreen) {
                    Picker(selection: Binding(get: { model.settings.fullScreen }, set: { r in model.update { $0.fullScreen = r } })) {
                        Text("Quiet while it lasts", comment: "Settings › Attention › When an app is full screen").tag(FullScreenRule.quiet)
                        Text("Focus while it lasts", comment: "Settings › Attention › When an app is full screen").tag(FullScreenRule.focus)
                        Text("Nothing changes", comment: "Settings › Attention › When an app is full screen").tag(FullScreenRule.nothing)
                    } label: { Text(verbatim: SettingKey.fullScreen.title) }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsGroup(title: Text(verbatim: SettingKey.sounds.section),
                          footer: Text("Approvals always come as a card, whatever you choose here: Sidefolk never acts on its own because you looked away.",
                                       comment: "Settings › Attention: under How things reach you")) {
                SettingsToggle(.sounds, isOn: setting(\.sounds))
                SettingsRow(.systemNotifications, detail: notificationDetail) {
                    if model.notificationsAllowed == true {
                        Chip("Allowed", tone: .success, systemImage: "checkmark")
                    } else {
                        Button("Allow notifications") { Task { await model.requestNotifications() } }
                            .buttonStyle(.sf(.primary))
                    }
                }
                SettingsToggle(.hiddenNotifications, isOn: setting(\.useSystemNotificationsWhenHidden))
                SettingsRow(.morningBrief,
                            detail: Text("At \(TimeText.hour(model.settings.morningHour)), today's reminders, open tasks and watches in one bubble.")) {
                    Toggle(isOn: setting(\.morningBrief)) { Text(verbatim: SettingKey.morningBrief.title) }
                        .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                }
            }
        }
        .task { await model.refreshHeld() }
    }

    private var notificationDetail: Text {
        switch model.notificationsAllowed {
        case true: Text("Reminders can reach you when the companion is hidden or you're in another Space.")
        case false: Text("Not allowed yet. Without them, reminders only appear on the desktop.")
        case nil: Text("Checking…")
        }
    }

    private func setting(_ key: WritableKeyPath<AppSettings, Bool> & Sendable) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: key] }, set: { on in model.update { $0[keyPath: key] = on } })
    }
}

/// The top of Attention: the companion with its state, "Focus until 17:00" and how long is left, when it ends, the
/// three modes as cards that say what each lets through, and what is being held.
private struct AttentionHero: View {
    var model: SettingsModel

    var body: some View {
        let now = Date()
        let mode = model.settings.attentionMode(at: now)
        let ends = model.settings.attentionEnds(at: now)
        HStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                LightPool(state: mode == .focus ? .focus : .idle, width: 120).offset(y: 6)
                Image(nsImage: CompanionArt.portrait(for: model.settings, side: 128))
                    .resizable().interpolation(.high).frame(width: 128, height: 128)
                    .overlay(alignment: .topTrailing) {
                        ShoulderBadge(state: mode == .focus ? .focus : mode == .quiet ? .quiet : .idle).offset(x: 4, y: -2)
                    }
                    .padding(.bottom, Theme.Space.m)
            }
            .frame(width: 168)
            .frame(maxHeight: .infinity)
            .background(Theme.well)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    Text(verbatim: Self.title(mode, ends: ends)).font(Theme.Font.title2).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let ends, mode != .open {
                        Chip(verbatim: Self.left(until: ends, now: now), tone: .neutral)
                    }
                    Spacer(minLength: Theme.Space.s)
                    if mode != .open { AttentionUntilMenu(model: model, mode: mode) }
                }
                AttentionDial(model: model)
                if mode != .open, model.heldCount > 0 {
                    Label {
                        Text(Self.holding(model.heldCount, name: model.settings.companionName, mode: mode))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "tray").foregroundStyle(Theme.inkMuted)
                    }
                    .font(Theme.Font.body).foregroundStyle(Theme.ink)
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .cardSurface()
    }

    static func title(_ mode: AttentionMode, ends: Date?) -> String {
        switch mode {
        case .open: String(localized: "Open: everything arrives as you set below", comment: "Settings › Attention: the title while Open")
        case .focus: ends.map { String(localized: "Focus until \(TimeText.clock($0))", comment: "Settings › Attention: “Focus until 17:00”") }
            ?? String(localized: "Focus until you turn it off", comment: "Settings › Attention")
        case .quiet: ends.map { String(localized: "Quiet until \(TimeText.clock($0))") }
            ?? String(localized: "Quiet until you turn it off", comment: "Settings › Attention")
        }
    }

    static func left(until: Date, now: Date) -> String {
        String(localized: "\(TimeText.span(max(60, until.timeIntervalSince(now)))) left", comment: "Settings › Attention: “58 min left”")
    }

    static func holding(_ count: Int, name: String, mode: AttentionMode) -> String {
        mode == .focus
            ? String(localized: "\(name) is holding \(count) things. They come as one card when Focus ends.",
                     comment: "Settings › Attention: what waits during Focus")
            : String(localized: "\(name) is holding \(count) things until Quiet ends.", comment: "Settings › Attention: what waits during Quiet")
    }
}

/// Open, Focus and Quiet as three cards (or, `compact`, a segmented control): a click switches, for an hour; the
/// Until menu changes the end.
struct AttentionDial: View {
    var model: SettingsModel
    var compact = false

    var body: some View {
        let mode = model.settings.attentionMode(at: Date())
        if compact {
            SegmentedPicker(Text(verbatim: SettingKey.attentionMode.title), selection: Binding(get: { mode }, set: choose),
                            segments: AttentionMode.allCases.map { .init($0, $0.word, symbol: $0.symbol) })
        } else {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                ForEach(AttentionMode.allCases, id: \.self) { option in
                    card(option, selected: option == mode)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card(_ option: AttentionMode, selected: Bool) -> some View {
        Button { choose(option) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: 6) {
                    if option == .open {
                        Circle().fill(Theme.success).frame(width: 8, height: 8)
                    } else {
                        Image(systemName: option.symbol).font(.system(size: 12, weight: .semibold))
                    }
                    option.word.font(Theme.Font.bodyStrong)
                }
                .foregroundStyle(selected && option != .open ? Theme.link : Theme.ink)
                option.explanation.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? Theme.accentSoft : Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func choose(_ option: AttentionMode) {
        guard option != model.settings.attentionMode(at: Date()) else { return }
        model.setAttention(option, until: option == .open ? nil : Date().addingTimeInterval(3600))
    }
}

/// When Focus or Quiet ends: in half an hour, an hour, three, at the evening hour, tomorrow morning, or when turned off.
struct AttentionUntilMenu: View {
    var model: SettingsModel
    var mode: AttentionMode

    var body: some View {
        let ends = model.settings.attentionEnds(at: Date())
        Menu {
            ForEach(AttentionSpan.choices(settings: model.settings), id: \.title) { span in
                Button(span.title) { model.setAttention(mode, until: span.until) }
            }
        } label: {
            Text(verbatim: ends.map { String(localized: "Until \(TimeText.clock($0))", comment: "When Focus or Quiet ends: “Until 17:00”") }
                ?? String(localized: "Until I turn it off", comment: "When Focus or Quiet ends"))
        }
        .menuStyle(.button)
        .buttonStyle(.sf(.secondary))
        .fixedSize()
    }
}

/// The ends offered for Focus and Quiet, here and in the Pocket.
struct AttentionSpan {
    var title: String
    var until: Date?

    static func choices(settings: AppSettings, now: Date = Date()) -> [AttentionSpan] {
        let calendar = Calendar.current
        var spans = [
            AttentionSpan(title: String(localized: "For 30 minutes"), until: now.addingTimeInterval(1800)),
            AttentionSpan(title: String(localized: "For 1 hour"), until: now.addingTimeInterval(3600)),
            AttentionSpan(title: String(localized: "For 3 hours"), until: now.addingTimeInterval(3 * 3600)),
        ]
        if let evening = calendar.date(bySettingHour: settings.eveningHour, minute: 0, second: 0, of: now), evening > now.addingTimeInterval(3600) {
            spans.append(AttentionSpan(title: String(localized: "Until \(TimeText.clock(evening))", comment: "When Focus or Quiet ends: “Until 17:00”"),
                                       until: evening))
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let morning = calendar.date(bySettingHour: settings.morningHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        spans.append(AttentionSpan(title: String(localized: "Until tomorrow morning"), until: morning))
        spans.append(AttentionSpan(title: String(localized: "Until I turn it off", comment: "When Focus or Quiet ends"), until: nil))
        return spans
    }
}

extension AttentionMode {
    var word: Text {
        switch self {
        case .open: Text("Open", comment: "Attention: everything arrives as set")
        case .focus: Text("Focus", comment: "Attention: only cards that need an answer; whispers wait")
        case .quiet: Text("Quiet", comment: "Attention: only what can't wait")
        }
    }

    var symbol: String {
        switch self {
        case .open: "circle"
        case .focus: Theme.Symbol.focus
        case .quiet: Theme.Symbol.quiet
        }
    }

    /// What it lets through, as Attention's rules do it.
    var explanation: Text {
        switch self {
        case .open: Text("Everything arrives the way you set below.", comment: "Settings › Attention › Open")
        case .focus: Text("Cards that need an answer still come. Whispers wait and arrive as one card when it ends.",
                          comment: "Settings › Attention › Focus")
        case .quiet: Text("Only what can't wait: reminders come as silent notifications; whispers wait.",
                          comment: "Settings › Attention › Quiet")
        }
    }
}

/// Quiet every night between two times: the switch, and the two times beside it.
private struct QuietHoursRow: View {
    var model: SettingsModel

    var body: some View {
        let hours = model.settings.quietHours
        SettingsRow(.quietHours) {
            HStack(spacing: Theme.Space.s) {
                time(\.start, hours.start)
                Text("to", comment: "Quiet hours: “22:00 to 08:00”").font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                time(\.end, hours.end)
                Toggle(isOn: Binding(get: { hours.on }, set: { on in model.update { $0.quietHours.on = on } })) {
                    Text(verbatim: SettingKey.quietHours.title)
                }
                .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private func time(_ key: WritableKeyPath<QuietHours, Int> & Sendable, _ minutes: Int) -> some View {
        Picker(selection: Binding(get: { minutes }, set: { m in model.update { $0.quietHours[keyPath: key] = m } })) {
            ForEach(Array(Set(stride(from: 0, to: 24 * 60, by: 30)).union([minutes])).sorted(), id: \.self) { m in
                Text(verbatim: String(format: "%02d:%02d", m / 60, m % 60)).tag(m)
            }
        } label: { Text(verbatim: SettingKey.quietHours.title) }
        .labelsHidden()
        .fixedSize()
        .disabled(!model.settings.quietHours.on)
    }
}
