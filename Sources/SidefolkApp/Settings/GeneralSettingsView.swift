import KeyboardShortcuts
import SidefolkCore
import SwiftUI

/// Settings › General: startup, the Ask shortcut, the name, quiet mode, what times of day mean,
/// notifications and the welcome.
struct GeneralSettingsView: View {
    var model: SettingsModel

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Basics") {
                SettingsRow(title: "Open at login", detail: "Sidefolk starts quietly when you log in.") {
                    Toggle("Open at login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                        .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                }
                if let error = model.loginError {
                    InlineError(error: error).padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                }
                SettingsRow(title: "Ask shortcut", detail: "Opens the Ask panel from any app.") {
                    // The menu bar and the Ask panel show the shortcut, so tell the app when it changes.
                    KeyboardShortcuts.Recorder(for: .ask) { _ in model.services.settingsChanged() }
                        .accessibilityLabel("Ask shortcut")
                }
                SettingsRow(title: "Name", detail: "What your companion is called in bubbles and menus.") {
                    CommitField(label: "Companion name", prompt: "Sidefolk", value: model.settings.companionName, width: 180) { name in
                        let clean = name.isEmpty ? "Sidefolk" : String(name.prefix(30))
                        model.update { $0.companionName = clean }
                    }
                }
            }

            SettingsGroup(title: "Quiet mode", footer: "While quiet, reminders still fire, but only important ones interrupt you.") {
                quietRow
            }

            SettingsGroup(title: "Times of day", footer: "“Tomorrow morning”, “this afternoon” and “tonight” mean these times.") {
                hourRow("Morning", hours: 5...11, key: \.morningHour)
                hourRow("Afternoon", hours: 12...17, key: \.afternoonHour)
                hourRow("Evening", hours: 16...23, key: \.eveningHour)
                SettingsToggle(title: "Morning brief",
                               detail: "At \(TimeText.hour(model.settings.morningHour)), today's reminders, open tasks and watches in one bubble.",
                               isOn: Binding(get: { model.settings.morningBrief }, set: { on in model.update { $0.morningBrief = on } }))
            }

            SettingsGroup(title: "Notifications") {
                SettingsRow(title: "System notifications", detail: notificationDetail) {
                    if model.notificationsAllowed == true {
                        Chip("Allowed", tone: .success, systemImage: "checkmark")
                    } else {
                        Button("Allow notifications") { Task { await model.requestNotifications() } }
                            .buttonStyle(.sf(.primary))
                    }
                }
                SettingsToggle(title: "Use notifications while I'm hidden",
                               detail: "When the companion is tucked away or in the menu bar, reminders arrive as notifications.",
                               isOn: Binding(get: { model.settings.useSystemNotificationsWhenHidden },
                                             set: { on in model.update { $0.useSystemNotificationsWhenHidden = on } }))
            }

            SettingsGroup(title: "Welcome") {
                SettingsRow(title: "Show the welcome again", detail: "Replays the first hello on your desktop. Nothing is reset.") {
                    Button("Show welcome") { model.services.replayOnboarding() }.buttonStyle(.sf(.secondary))
                }
            }
        }
    }

    private var notificationDetail: String {
        switch model.notificationsAllowed {
        case true: "Reminders can reach you when the companion is hidden or you're in another Space."
        case false: "Not allowed yet. Without them, reminders only appear on the desktop."
        case nil: "Checking…"
        }
    }

    @ViewBuilder private var quietRow: some View {
        if let until = model.settings.quietUntil, until > Date() {
            SettingsRow(title: "Quiet until \(TimeText.short(until))", detail: "Bubbles wait; important reminders still come through.") {
                Button("Turn off") { model.setQuiet(until: nil) }.buttonStyle(.sf(.secondary))
            }
        } else {
            SettingsRow(title: "Quiet mode is off", detail: "Turn it on for a meeting or a focus block.") {
                Menu("Be quiet") {
                    Button("For 30 minutes") { model.setQuiet(until: Date().addingTimeInterval(1800)) }
                    Button("For 1 hour") { model.setQuiet(until: Date().addingTimeInterval(3600)) }
                    Button("For 3 hours") { model.setQuiet(until: Date().addingTimeInterval(3 * 3600)) }
                    Button("Until tomorrow morning") { model.setQuiet(until: model.tomorrowMorning()) }
                }
                .menuStyle(.button)
                .buttonStyle(.sf(.secondary))
                .fixedSize()
            }
        }
    }

    private func hourRow(_ title: String, hours: ClosedRange<Int>, key: WritableKeyPath<AppSettings, Int> & Sendable) -> some View {
        let value = model.settings[keyPath: key]
        return SettingsRow(title: title) {
            Picker(title, selection: Binding(get: { model.settings[keyPath: key] }, set: { h in model.update { $0[keyPath: key] = h } })) {
                ForEach(Array(Set(hours).union([value])).sorted(), id: \.self) { Text(TimeText.hour($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// The scrolling body of a Settings tab.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        PageScroll(maxWidth: 600, padding: Theme.Space.xl) { content }
    }
}
