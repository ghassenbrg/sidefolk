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
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                Text(choice == .none ? String(localized: "No AI yet, and that's fine", comment: "Settings › Brain: no AI chosen")
                     : String(localized: "Questions go to \(choice.title)", comment: "Settings › Brain: “Questions go to Claude Code”"))
                    .font(Theme.Font.title2).foregroundStyle(Theme.ink)
                if let badge = status.badge {
                    Chip(verbatim: badge.text, tone: badge.tone, systemImage: badge.symbol)
                }
                Spacer(minLength: 0)
            }
            if choice != .none {
                HStack(spacing: Theme.Space.s) { steps(choice) }
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label {
                Text("Notes, reminders and watches work without AI. AI is only used for questions and open-ended requests.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle").foregroundStyle(Theme.inkMuted)
            }
            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// You ask the companion → the AI → Guard checks each step: how a question travels, true for every AI.
    @ViewBuilder private func steps(_ choice: AIChoice) -> some View {
        step(image: Image(nsImage: CompanionArt.avatar(for: model.settings, side: 28)),
             title: Text("You ask \(model.settings.companionName)", comment: "Settings › Brain: the first step of a question"),
             detail: Text("Only what needs AI goes on", comment: "Settings › Brain: under “You ask Mochi”"))
        connector
        step(image: Image(systemName: "sparkles"), title: Text(verbatim: choice.title), detail: Text(verbatim: choice.subtitle))
        connector
        step(image: Image(systemName: "checkmark.shield"),
             title: Text("Guard checks every step", comment: "Settings › Brain: the last step of a question"),
             detail: Text("Before anything changes", comment: "Settings › Brain: under “Guard checks every step”"))
    }

    private func step(image: Image, title: Text, detail: Text) -> some View {
        HStack(spacing: Theme.Space.s) {
            image.resizable().scaledToFit().frame(width: 18, height: 18)
                .foregroundStyle(Theme.link)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                title.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var connector: some View {
        Image(systemName: "chevron.forward").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.inkFaint)
            .flipsForRightToLeftLayoutDirection(true)
            .accessibilityHidden(true)
    }
}
