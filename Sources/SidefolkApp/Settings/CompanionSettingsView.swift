import SidefolkCore
import SwiftUI

/// Settings › Companion: who the companion is, how present it is on the desktop and how it
/// behaves there.
struct CompanionSettingsView: View {
    var model: SettingsModel

    var body: some View {
        SettingsPage {
            CompanionPicker(model: model)

            SettingsGroup(title: "Presence") {
                ForEach(PresenceMode.allCases, id: \.self) { mode in
                    ChoiceRow(title: title(mode), detail: detail(mode), selected: model.settings.presence == mode) {
                        model.update { $0.presence = mode }
                    }
                }
            }

            SettingsGroup(title: "Look") {
                SettingsRow(title: "Size") {
                    Picker("Size", selection: Binding(get: { model.settings.size }, set: { size in model.update { $0.size = size } })) {
                        Text("Small").tag(CompanionSize.small)
                        Text("Medium").tag(CompanionSize.medium)
                        Text("Large").tag(CompanionSize.large)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsToggle(title: "Eyes follow the pointer", detail: "A glance now and then, never a stare.",
                               isOn: setting(\.eyesFollowPointer))
                SettingsToggle(title: "Show folks on duty",
                               detail: "Tempo, Scout and Byte sit beside the companion while a reminder, watch or agent is live.",
                               isOn: setting(\.showFolks))
            }

            SettingsGroup(title: "Behavior") {
                SettingsToggle(title: "Sleep when you're away", detail: "Naps after 10 minutes without input and wakes when you're back.",
                               isOn: setting(\.sleepWhenIdle))
                SettingsToggle(title: "Sounds", detail: "A soft chime for reminders and finished jobs.", isOn: setting(\.sounds))
            }
        }
    }

    private func setting(_ key: WritableKeyPath<AppSettings, Bool> & Sendable) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: key] }, set: { on in model.update { $0[keyPath: key] = on } })
    }

    private func title(_ mode: PresenceMode) -> LocalizedStringKey {
        switch mode {
        case .always: "Always"
        case .whenNeeded: "Only when needed"
        case .menuBarOnly: "Menu bar only"
        }
    }

    private func detail(_ mode: PresenceMode) -> LocalizedStringKey {
        switch mode {
        case .always: "The companion stays on your desktop, beside your work."
        case .whenNeeded: "A small peek at the edge of the screen until something needs you."
        case .menuBarOnly: "Just the menu bar icon. Reminders arrive as notifications."
        }
    }
}
