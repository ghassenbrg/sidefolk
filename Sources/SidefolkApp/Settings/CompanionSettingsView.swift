import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// Settings › Companion: who the companion is, how present it is on the desktop and how it behaves there, on
/// Yours; and the add-on gallery's companions to browse and download, on Gallery (D77), as
/// Settings › Extensions keeps Installed and Gallery side by side.
struct CompanionSettingsView: View {
    var model: SettingsModel
    @FocusState private var focus: CompanionPageFocus?
    private var chooser: CompanionChooserModel { model.chooser }

    var body: some View {
        VStack(spacing: 0) {
            CompanionPageHeader(model: model, focus: $focus)
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.l)
                .frame(maxWidth: .infinity)
            SettingsPage {
                if chooser.page == .gallery {
                    CompanionGalleryView(model: model)
                } else {
                    yours
                }
            }
        }
        .background(Theme.surfaceSunken)
        // ⌘F searches the gallery, as everywhere on the Mac.
        .background {
            Button("Find") {
                chooser.page = .gallery
                focus = .search
            }
            .keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
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
        CompanionPicker(model: model)

        SettingsGroup(title: "Presence") {
            ForEach(PresenceMode.allCases, id: \.self) { mode in
                ChoiceRow(title: title(mode), detail: detail(mode), selected: model.settings.presence == mode) {
                    model.update { $0.presence = mode }
                }
            }
        }

        // Games in the Play panel (D75): how the companion takes a win, and sounds, off until turned on.
        SettingsGroup(title: "Games") {
            SettingsRow(title: "When it wins", detail: toneDetail) {
                Picker("When it wins", selection: Binding(get: { model.settings.games.tone }, set: { tone in model.update { $0.games.tone = tone } })) {
                    Text(String(localized: "tone.gentle", defaultValue: "Gentle", comment: "How the companion takes a win in games: kindly")).tag(GameTone.gentle)
                    Text(String(localized: "tone.cheeky", defaultValue: "Cheeky", comment: "How the companion takes a win in games: a small tease, then kind")).tag(GameTone.cheeky)
                    Text(String(localized: "tone.competitive", defaultValue: "Competitive", comment: "How the companion takes a win in games: a victory dance")).tag(GameTone.competitive)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingsToggle(title: "Game sounds", detail: "Soft sounds in games. Each game's speaker button turns its own on or off.",
                           isOn: Binding(get: { model.settings.games.sounds }, set: { on in model.update { $0.games.sounds = on } }))
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

    private var toneDetail: LocalizedStringKey {
        switch model.settings.games.tone {
        case .gentle: "“Good game!” and nothing more."
        case .cheeky: "A small tease, then kind: “Ha! Mine. Rematch?”"
        case .competitive: "A victory dance, and it wants a rematch when it loses."
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
