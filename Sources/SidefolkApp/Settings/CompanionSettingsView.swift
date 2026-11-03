import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// Settings › Companion: who the companion is, where it lives on the desktop and how it behaves there. More companions
/// are in the Gallery, in Home; its sounds moved to Attention (D84).
struct CompanionSettingsView: View {
    var model: SettingsModel
    private var chooser: CompanionChooserModel { model.chooser }

    var body: some View {
        SettingsPage { yours }
        .background(Theme.surfaceSunken)
        .task {
            chooser.reload()
            await model.gallery.load()
        }
        // Back from Finder, where a 2D companion may have been saved in the companions folder.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in chooser.reload() }
        .sheet(item: Binding(get: { chooser.detail }, set: { chooser.detail = $0 })) { entry in
            CompanionGalleryDetail(entry: entry, model: model)
        }
    }

    @ViewBuilder private var yours: some View {
        CompanionPicker(model: model).settingAnchor(.chooseCompanion)

        SettingsGroup(title: Text(verbatim: SettingKey.presence.title), anchor: .presence) {
            ForEach(PresenceMode.allCases, id: \.self) { mode in
                ChoiceRow(title: title(mode), detail: detail(mode), selected: model.settings.presence == mode) {
                    model.update { $0.presence = mode }
                }
            }
        }

        SettingsGroup(title: "Look") {
            SettingsRow(title: Text("Size"), anchor: .size) {
                SegmentedPicker("Size", selection: Binding(get: { model.settings.size }, set: { size in model.update { $0.size = size } }), segments: [
                    .init(CompanionSize.small, Text(String(localized: "size.small", defaultValue: "Small", comment: "Companion size"))),
                    .init(CompanionSize.medium, Text(String(localized: "size.medium", defaultValue: "Medium", comment: "Companion size, between Small and Large"))),
                    .init(CompanionSize.large, Text(String(localized: "size.large", defaultValue: "Large", comment: "Companion size"))),
                ])
            }
            SettingsToggle(.eyesFollow, isOn: setting(\.eyesFollowPointer))
            SettingsToggle(.folks, isOn: setting(\.showFolks))
            SettingsToggle(.companionAppIcon, isOn: setting(\.companionAppIcon))
        }

        SettingsGroup(title: Text(verbatim: SettingKey.liveliness.section)) {
            SettingsRow(title: Text("Liveliness"), detail: Text(livelinessDetail), anchor: .liveliness) {
                // Their own keys: "Minimal" is also a reasoning effort, which other languages word apart.
                SegmentedPicker("Liveliness", selection: Binding(get: { model.settings.liveliness },
                                                                 set: { level in model.update { $0.liveliness = level } }), segments: [
                    .init(CompanionLiveliness.minimal, Text(String(localized: "liveliness.minimal", defaultValue: "Minimal", comment: "How lively the companion is: moves only when something happens"))),
                    .init(CompanionLiveliness.balanced, Text(String(localized: "liveliness.balanced", defaultValue: "Balanced", comment: "How lively the companion is: the default"))),
                    .init(CompanionLiveliness.lively, Text(String(localized: "liveliness.lively", defaultValue: "Lively", comment: "How lively the companion is: the most moments"))),
                ])
            }
            SettingsToggle(.sleep, isOn: setting(\.sleepWhenIdle))
        }
    }

    private var livelinessDetail: LocalizedStringKey {
        switch model.settings.liveliness {
        case .minimal: "Moves only when something happens, then rests. The lightest on battery."
        case .balanced: "Now and then a stretch, a yawn or a glance at your work; sits down when nothing happens. Still while you type."
        case .lively: "More moments, more often, and eyes that follow the pointer across the screen."
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
