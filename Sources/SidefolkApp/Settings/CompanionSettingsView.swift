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

            SettingsGroup(title: "Made by you",
                          footer: "Your own companions: drawn from data in Sidefolk's companions folder, or 3D ones added from a folder. To remove a 3D one, Control-click it.") {
                ForEach(CompanionArt.made, id: \.folder) { report in
                    madeRow(report)
                }
                ForEach(model.gallery.locals, id: \.companion) { local in
                    localRow(local)
                }
                SettingsRow(title: "Add a 3D companion", detail: "A folder with its addon.json, character, model and pictures, made like the gallery's.") {
                    Button("Add from Folder…", systemImage: "folder", action: chooseFolder).buttonStyle(.sf(.secondary))
                }
                if let error = model.gallery.localError { InlineError(error: error) }
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

    /// A 3D companion added from a folder (D59): its picture, name and what it is.
    private func localRow(_ local: InstalledCompanion) -> some View {
        SettingsRow(title: Text(verbatim: local.name), detail: Text(verbatim: local.tagline ?? "")) {
            HStack(spacing: Theme.Space.s) {
                if let avatar = Companion3DStage.avatar(local.companion) {
                    Image(nsImage: avatar).resizable().scaledToFit().frame(width: 28, height: 28).clipShape(Circle())
                        .accessibilityHidden(true)
                }
                if model.settings.localCompanion == local.companion {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                } else {
                    Button("Use") { model.update { $0.choose(local: local.companion, name: local.name) } }
                }
            }
        }
        .contextMenu {
            Button("Remove \(local.name)") { Task { await model.gallery.remove(local: local.companion) } }
        }
    }

    /// The folder of a 3D companion to add: it is checked, and added only once the person agrees.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose Companion")
        panel.message = String(localized: "Choose a 3D companion's folder: its addon.json, character, model and pictures.")
        Task {
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
            guard response == .OK, let url = panel.url else { return }
            await model.gallery.add(companionFolder: url)
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
