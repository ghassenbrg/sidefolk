import SidefolkCore
import SwiftUI

/// Settings › Privacy & Permissions: how much Sidefolk asks (D37).
struct ApprovalModeGroup: View {
    var model: SettingsModel

    var body: some View {
        SettingsGroup(title: "How much Sidefolk asks",
                      footer: "For what you ask Sidefolk to do. Other agents and extensions keep their own rules, and everything shows in Activity.") {
            ForEach(GuardMode.allCases, id: \.self) { mode in
                ChoiceRow(title: Text(verbatim: mode.title), detail: Text(verbatim: mode.explanation), selected: model.policy.mode == mode) {
                    // Full access is never one click away: the sheet says what it means first.
                    if mode == .fullAccess {
                        if model.policy.mode != .fullAccess { model.confirmingFullAccess = true }
                    } else {
                        Task { await model.setMode(mode) }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { model.confirmingFullAccess }, set: { model.confirmingFullAccess = $0 })) {
            FullAccessSheet(model: model)
        }
    }
}

/// Settings › Privacy & Permissions: what happens when Sidefolk waits on an answer that doesn't come (D37).
struct UnansweredGroup: View {
    var model: SettingsModel

    private var rule: UnansweredRule { model.policy.unanswered }

    var body: some View {
        SettingsGroup(title: "If I don't answer",
                      footer: "When Sidefolk waits for your OK on something you asked for. Other agents' questions count as a no after two minutes.") {
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

/// Says plainly what Full access means before it is on: what Sidefolk will do without asking, what
/// it still asks about, and what holds in every mode.
struct FullAccessSheet: View {
    var model: SettingsModel
    @Environment(\.dismiss) private var dismiss
    /// Inert for a moment, like an approval card, so a stray keypress can't turn it on.
    @State private var armed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "bolt.fill").font(.system(size: 20)).foregroundStyle(Theme.danger)
                    .accessibilityHidden(true)
                Text("Turn on Full access?").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            }
            Text("Sidefolk will do what you ask without checking with you first: moving and trashing files in the folders you shared, opening links and apps, reading pages, running commands and using extensions.")
                .font(Theme.Font.body).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            section("It still asks before", symbol: "exclamationmark.shield", tint: Theme.danger) {
                Text("Anything a web page, file or extension it read could be steering to send your data out: an address you didn't type, a command, a file change, an extension, your clipboard or memory.")
                Text("Working in a folder you haven't shared, or saving a new skill.")
            }
            section("In every mode", symbol: "lock", tint: Theme.inkMuted) {
                Text("What you switched off under “What Sidefolk may do” stays off.")
                Text("Everything it does shows in Activity, with Undo where it can. Files it deletes go to the Trash.")
                Text("Other agents and extensions keep their own rules.")
            }
            Text("You can switch back any time from the menu bar, the Ask panel or here.")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button("Turn On Full Access") {
                    Task {
                        await model.setMode(.fullAccess)
                        dismiss()
                    }
                }
                .buttonStyle(.sfDestructive)
                .disabled(!armed)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 460)
        .background(Theme.surface)
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
        }
    }

    private func section(_ title: LocalizedStringKey, symbol: String, tint: Color, @ViewBuilder lines: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).imageScale(.small).foregroundStyle(tint).accessibilityHidden(true)
                Eyebrow(Text(title))
            }
            VStack(alignment: .leading, spacing: 6) { lines() }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Theme.Space.s + 2)
                .overlay(alignment: .leading) { Rectangle().fill(tint.opacity(0.45)).frame(width: 2) }
        }
        .accessibilityElement(children: .combine)
    }
}
