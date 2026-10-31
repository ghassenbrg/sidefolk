import SidefolkCore
import SwiftUI

/// The top of Settings › Trust (D37, D84): Guard, the mode in a sentence, and the four modes as cards, each with what
/// it does to one real kind of step. Full access opens its sheet, which asks when it ends.
struct TrustHero: View {
    var model: SettingsModel

    var body: some View {
        let mode = model.policy.mode
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                FolkAvatar(name: "guard", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: mode.headline).font(Theme.Font.title2).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Whatever you pick, Guard checks every step outside the AI, and every step shows in History.",
                         comment: "Settings › Trust: under the mode's headline")
                        .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Grid(horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.m) {
                GridRow {
                    ModeCard(mode: .askEveryTime, current: mode, ends: nil) { choose(.askEveryTime) }
                    ModeCard(mode: .askOncePerKind, current: mode, ends: nil) { choose(.askOncePerKind) }
                }
                GridRow {
                    ModeCard(mode: .auto, current: mode, ends: nil) { choose(.auto) }
                    ModeCard(mode: .fullAccess, current: mode, ends: model.policy.fullAccessEnds) { choose(.fullAccess) }
                }
            }
            Text("For what you ask Sidefolk to do. Other agents and extensions keep their own rules, and everything shows in History.")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.xs)
        }
        .settingAnchor(.approvalMode)
        .sheet(isPresented: Binding(get: { model.confirmingFullAccess }, set: { model.confirmingFullAccess = $0 })) {
            FullAccessSheet(model: model)
        }
    }

    private func choose(_ mode: GuardMode) {
        // Full access is never one click away: the sheet says what it means, and asks when it ends.
        if mode == .fullAccess {
            if model.policy.mode != .fullAccess { model.confirmingFullAccess = true }
        } else {
            Task { await model.setMode(mode) }
        }
    }
}

/// One approval mode: a radio, its name, what it does, and what it does to one example step.
private struct ModeCard: View {
    var mode: GuardMode
    var current: GuardMode
    var ends: Date?
    var action: () -> Void

    var body: some View {
        let selected = mode == current
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    RadioDot(selected: selected)
                    Text(verbatim: mode.title).font(Theme.Font.headline).foregroundStyle(Theme.ink)
                    Spacer(minLength: Theme.Space.xs)
                    if mode == .askOncePerKind {
                        Chip(text: Text("Suggested", comment: "Settings › Trust: the mode Sidefolk suggests"), tone: .accent)
                    }
                    if selected, mode == .fullAccess {
                        Chip(verbatim: ends.map { String(localized: "Ends \(TimeText.clock($0))", comment: "Full access: “Ends 22:00”") }
                                ?? String(localized: "On until you turn it off", comment: "Full access without an end"),
                             tone: .warning)
                    }
                }
                Text(verbatim: mode.explanation).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: mode.exampleSymbol).font(.system(size: 12)).foregroundStyle(Theme.inkMuted).frame(width: 16)
                    Text(mode.example).font(Theme.Font.caption).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Theme.Space.s)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A radio button's look, for cards that are one choice of several.
struct RadioDot: View {
    var selected: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(selected ? Theme.accent : Theme.inkFaint, lineWidth: 1.5)
            if selected {
                Circle().fill(Theme.accent)
                Circle().fill(Theme.surfaceRaised).frame(width: 6, height: 6)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

/// Settings › Trust: what happens when Sidefolk waits on an answer that doesn't come (D37).
struct UnansweredGroup: View {
    var model: SettingsModel

    private var rule: UnansweredRule { model.policy.unanswered }

    var body: some View {
        SettingsGroup(title: "If I don't answer",
                      footer: "When Sidefolk waits for your OK on something you asked for. Other agents' questions count as a no after two minutes.",
                      anchor: .unanswered) {
            ChoiceRow(title: "Keep waiting", detail: "The task waits for your answer, a day at most.", selected: rule.action == .keepWaiting) {
                set(.keepWaiting)
            }
            ChoiceRow(title: Text("Skip that step and continue"),
                      detail: Text("After \(rule.waitMinutes) minutes, the task carries on without it. The step waits in Now, where you can still run it."),
                      selected: rule.action == .skip) {
                set(.skip)
            }
            ChoiceRow(title: Text("Stop the task"),
                      detail: Text("After \(rule.waitMinutes) minutes, the task stops. The step waits in Now, where you can still run it."),
                      selected: rule.action == .stop) {
                set(.stop)
            }
            SettingsRow(title: "Wait before skipping or stopping") {
                Picker("Wait before skipping or stopping", selection: Binding(
                    get: { rule.minutes }, set: { minutes in Task { await model.setPolicy { $0.unanswered.minutes = minutes } } }
                )) {
                    ForEach(Array(Set(UnansweredRule.minuteChoices + [rule.minutes])).sorted(), id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(rule.action == .keepWaiting)
            }
        }
    }

    private func set(_ action: UnansweredRule.Action) {
        Task { await model.setPolicy { $0.unanswered.action = action } }
    }
}

/// Says plainly what Full access means before it is on (D37), and when it ends (D84): what Sidefolk will do without
/// asking, what it still asks about, and what holds in every mode. Turning it on is the sheet's one primary step, not a
/// red one: it isn't destructive, and it can always be turned off.
struct FullAccessSheet: View {
    var model: SettingsModel
    @Environment(\.dismiss) private var dismiss
    /// Inert for a moment, like an approval card, so a stray keypress can't turn it on.
    @State private var armed = false
    @State private var end: FullAccessEnd = .inAnHour

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(spacing: Theme.Space.m) {
                    FolkAvatar(name: "guard", size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Turn on Full access?").font(Theme.Font.title2).foregroundStyle(Theme.ink)
                        Text("\(model.settings.companionName) acts without asking until it ends.", comment: "The Full access sheet, under its title")
                            .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    }
                }
                section(Text("What changes", comment: "The Full access sheet: what it does without asking")) {
                    line("terminal", Text("Runs commands without asking"), Text("You still see each one in History, word for word.", comment: "The Full access sheet"))
                    line("folder", Text("Moves, renames and trashes files in the folders you shared", comment: "The Full access sheet"),
                         Text("Anything deleted goes to the Trash.", comment: "The Full access sheet"))
                    line("arrow.up.right", Text("Opens apps and links, reads pages and your Apple Notes, uses extensions", comment: "The Full access sheet"), nil)
                }
                section(Text("What still asks", comment: "The Full access sheet")) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        line("globe", Text("Anything a web page, file or extension it read could be steering to send your data out: an address you didn't type, a command, a file change, an extension, your clipboard or memory."), nil)
                        line("folder.badge.questionmark", Text("Working in a folder you haven't shared, saving a new skill, or removing notes from Apple Notes."), nil)
                        line("person.2", Text("Other agents and extensions keep their own rules."), nil)
                    }
                    .padding(Theme.Space.m)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                section(Text("Ends", comment: "The Full access sheet: when Full access turns itself off")) {
                    SegmentedPicker(Text("Ends", comment: "The Full access sheet: when Full access turns itself off"), selection: $end,
                                    segments: FullAccessEnd.offered().map { .init($0, verbatim: $0.title) })
                    Text("While it's on, the menu bar shows it. Turn it off there with one click. What you switched off under “What Sidefolk may do” stays off.",
                         comment: "The Full access sheet, under Ends")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.xl)
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: Theme.Space.s) {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sf(.secondary, size: .large)).keyboardShortcut(.cancelAction)
                Button("Turn On Full Access") {
                    Task {
                        await model.setMode(.fullAccess, fullAccessEnds: end.date())
                        dismiss()
                    }
                }
                .buttonStyle(.sf(.primary, size: .large))
                .disabled(!armed)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
        }
        .frame(width: Theme.Size.sheet + 40)
        .background(Theme.surface)
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
        }
    }

    private func section(_ title: Text, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            title.font(Theme.Font.headline).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func line(_ symbol: String, _ title: Text, _ detail: Text?) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkMuted)
                .frame(width: 26, height: 26)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if let detail { detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// When Full access ends (D84): in an hour, tonight, or when the person turns it off.
enum FullAccessEnd: Hashable {
    case inAnHour, tonight(Date), never

    /// "Tonight at 22:00" only while that is more than an hour away.
    static func offered(now: Date = Date()) -> [FullAccessEnd] {
        let tonight = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: now)
        return [.inAnHour] + (tonight.map { $0.timeIntervalSince(now) > 3600 ? [.tonight($0)] : [] } ?? []) + [.never]
    }

    var title: String {
        switch self {
        case .inAnHour: String(localized: "In 1 hour", comment: "Full access ends")
        case .tonight(let at): String(localized: "Tonight at \(TimeText.clock(at))", comment: "Full access ends: “Tonight at 22:00”")
        case .never: String(localized: "When I turn it off", comment: "Full access ends")
        }
    }

    func date(now: Date = Date()) -> Date? {
        switch self {
        case .inAnHour: now.addingTimeInterval(3600)
        case .tonight(let at): at
        case .never: nil
        }
    }
}
