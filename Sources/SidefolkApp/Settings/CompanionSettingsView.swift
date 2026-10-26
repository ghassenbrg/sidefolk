import SidefolkCharacter
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
                        Text(String(localized: "size.small", defaultValue: "Small", comment: "Companion size")).tag(CompanionSize.small)
                        Text(String(localized: "size.medium", defaultValue: "Medium", comment: "Companion size, between Small and Large")).tag(CompanionSize.medium)
                        Text(String(localized: "size.large", defaultValue: "Large", comment: "Companion size")).tag(CompanionSize.large)
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

            if !CompanionArt.made.isEmpty {
                SettingsGroup(title: "Made by you",
                              footer: "Companions made from data in Sidefolk's companions folder. They wear the color and scarf chosen above.") {
                    ForEach(CompanionArt.made, id: \.folder) { report in
                        madeRow(report)
                    }
                }
            }

            SettingsGroup(title: "Behavior") {
                SettingsRow(title: "Liveliness", detail: livelinessDetail) {
                    Picker("Liveliness", selection: Binding(get: { model.settings.liveliness },
                                                            set: { level in model.update { $0.liveliness = level } })) {
                        // Their own keys: "Minimal" is also a reasoning effort, which other languages word apart.
                        Text(String(localized: "liveliness.minimal", defaultValue: "Minimal", comment: "How lively the companion is: moves only when something happens")).tag(CompanionLiveliness.minimal)
                        Text(String(localized: "liveliness.balanced", defaultValue: "Balanced", comment: "How lively the companion is: the default")).tag(CompanionLiveliness.balanced)
                        Text(String(localized: "liveliness.lively", defaultValue: "Lively", comment: "How lively the companion is: the most moments")).tag(CompanionLiveliness.lively)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsToggle(title: "Sleep when you're away", detail: "Naps after 10 minutes without input and wakes when you're back.",
                               isOn: setting(\.sleepWhenIdle))
                SettingsToggle(title: "Sounds", detail: "A soft chime for reminders and finished jobs.", isOn: setting(\.sounds))
            }
        }
    }

    private var livelinessDetail: LocalizedStringKey {
        switch model.settings.liveliness {
        case .minimal: "Moves only when something happens, then rests. The lightest on battery."
        case .balanced: "Now and then a stretch, a yawn or a glance at your work; sits down when nothing happens. Still while you type."
        case .lively: "More moments, more often, and eyes that follow the pointer across the screen."
        }
    }

    /// A custom companion: its name and what it is, or why it can't be used.
    private func madeRow(_ report: CompanionReport) -> some View {
        let chosen = report.companion.map { model.settings.customCompanion == $0.id } ?? false
        let detail = report.companion.map { $0.summary ?? "" } ?? report.errors.first ?? ""
        return SettingsRow(title: Text(verbatim: report.companion?.name ?? report.folder.lastPathComponent),
                           detail: Text(verbatim: detail)) {
            if let companion = report.companion {
                if chosen {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                } else {
                    Button("Use") { model.update { $0.choose(custom: companion.id, name: companion.name) } }
                }
            } else {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
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
