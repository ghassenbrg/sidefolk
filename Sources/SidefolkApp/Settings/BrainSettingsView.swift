import SidefolkCore
import SwiftUI

/// Settings › Brain (D84): who answers questions and how Sidefolk hears and speaks, in one place (AI and Voice were
/// two tabs). The top says where questions go now, where that stands, and the way a question travels.
struct BrainSettingsView: View {
    var model: SettingsModel

    var body: some View {
        SettingsPage {
            BrainHero(model: model)
            AISettingsSections(model: model)
            VoiceSettingsSections(model: model)
        }
    }
}

private struct BrainHero: View {
    var model: SettingsModel
    private var ai: AISettingsModel { model.ai }

    var body: some View {
        let choice = ai.choice
        let status = ai.status(choice)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if choice == .none {
                Text("No AI yet, and that's fine", comment: "Settings › Brain: no AI chosen").font(Theme.Font.headline).foregroundStyle(Theme.ink)
            } else {
                // A line that wraps in a long language: how a question travels, with each step's detail in its help.
                ButtonRow(spacing: Theme.Space.s) {
                    step(Text("You ask \(model.settings.companionName)", comment: "Settings › Brain: the first step of a question"),
                         detail: Text("Only what needs AI goes on", comment: "Settings › Brain: under “You ask Mochi”"))
                    connector
                    step(Text(verbatim: choice.title), detail: Text(verbatim: choice.subtitle))
                    if let badge = status.badge { Chip(verbatim: badge.text, tone: badge.tone, systemImage: badge.symbol) }
                    connector
                    step(Text("Guard checks every step", comment: "Settings › Brain: the last step of a question"),
                         detail: Text("Before anything changes", comment: "Settings › Brain: under “Guard checks every step”"))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Questions go to \(choice.title)", comment: "Settings › Brain: “Questions go to Claude Code”"))
                .accessibilityAddTraits(.isHeader)
            }
            Label {
                Text("Notes, reminders and watches work without AI. AI is only used for questions and open-ended requests.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle").foregroundStyle(Theme.inkMuted)
            }
            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ title: Text, detail: Text) -> some View {
        title.font(Theme.Font.body.weight(.medium)).foregroundStyle(Theme.ink).help(detail)
    }

    private var connector: some View {
        Image(systemName: "chevron.forward").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.inkFaint)
            .flipsForRightToLeftLayoutDirection(true)
            .accessibilityHidden(true)
    }
}
