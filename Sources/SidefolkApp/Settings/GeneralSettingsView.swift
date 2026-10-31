import KeyboardShortcuts
import SidefolkCore
import SwiftUI

/// Settings › General: startup, the Ask shortcut, language, the theme, quiet mode, what times of day mean,
/// notifications, updates and the welcome. The companion's name lives with the companion (Settings › Companion).
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
                LanguageRow()
                SettingsRow(title: "Appearance", detail: "Light or dark windows, or the same as your Mac.") {
                    Picker("Appearance", selection: Binding(get: { model.settings.appearance }, set: { a in model.update { $0.appearance = a } })) {
                        Text("Same as Mac").tag(AppAppearance.system)
                        Text("Light").tag(AppAppearance.light)
                        Text("Dark").tag(AppAppearance.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                // The theme says simple or colorful; the person may prefer the other (D67).
                SettingsRow(title: "Icons in Home", detail: "Simple glyphs, or colourful tiles with each extension's own icon.") {
                    Picker("Icons in Home", selection: Binding(get: { model.settings.sidebarIcons }, set: { i in model.update { $0.sidebarIcons = i } })) {
                        Text("As the theme", comment: "Settings › General › Icons in Home: follow the theme").tag(ThemeLayout.Icons?.none)
                        Text("Simple", comment: "Settings › General › Icons in Home: glyphs").tag(ThemeLayout.Icons?.some(.simple))
                        Text("Colourful", comment: "Settings › General › Icons in Home: tiles and extensions' own icons").tag(ThemeLayout.Icons?.some(.colorful))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            ThemeSettingsGroup(model: model)

            SettingsGroup(title: "Quiet mode", footer: "While quiet, reminders still fire, but only important ones interrupt you.") {
                quietRow
            }

            SettingsGroup(title: "Times of day", footer: "“Tomorrow morning”, “this afternoon” and “this evening” mean these times; “tonight” is 21:00.") {
                hourRow("Morning", hours: 5...11, key: \.morningHour)
                hourRow("Afternoon", hours: 12...17, key: \.afternoonHour)
                hourRow("Evening", hours: 16...23, key: \.eveningHour)
            }

            SettingsGroup(title: "Morning brief") {
                SettingsToggle(title: "Morning brief",
                               detail: "At \(TimeText.hour(model.settings.morningHour)), today's reminders, open tasks and watches in one bubble.",
                               isOn: Binding(get: { model.settings.morningBrief }, set: { on in model.update { $0.morningBrief = on } }))
            }

            SettingsGroup(title: "Notifications") {
                SettingsRow(title: Text("System notifications"), detail: notificationDetail) {
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

            UpdatesSettingsGroup(model: model)

            SettingsGroup(title: "Welcome") {
                SettingsRow(title: "Show the welcome again", detail: "Replays the first hello on your desktop. Nothing is reset.") {
                    Button("Show welcome") { model.services.replayOnboarding() }.buttonStyle(.sf(.secondary))
                }
            }
        }
    }

    private var notificationDetail: Text {
        switch model.notificationsAllowed {
        case true: Text("Reminders can reach you when the companion is hidden or you're in another Space.")
        case false: Text("Not allowed yet. Without them, reminders only appear on the desktop.")
        case nil: Text("Checking…")
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

    private func hourRow(_ title: LocalizedStringKey, hours: ClosedRange<Int>, key: WritableKeyPath<AppSettings, Int> & Sendable) -> some View {
        let value = model.settings[keyPath: key]
        return SettingsRow(title: title) {
            Picker(title, selection: Binding(get: { model.settings[keyPath: key] }, set: { h in model.update { $0[keyPath: key] = h } })) {
                ForEach(Array(Set(hours).union([value])).sorted(), id: \.self) { Text(verbatim: TimeText.hour($0)).tag($0) }
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

/// The language Sidefolk speaks. It follows the Mac until one is chosen; a change applies on relaunch.
private struct LanguageRow: View {
    @State private var chosen = AppLanguage.chosen
    private let running = AppLanguage.current

    var body: some View {
        SettingsRow(title: Text("Language"), detail: detail) {
            HStack(spacing: Theme.Space.s) {
                if (chosen ?? AppLanguage.system) != running {
                    Button("Restart now") { AppLanguage.relaunch() }.buttonStyle(.sf(.primary))
                }
                Picker("Language", selection: Binding(get: { chosen ?? "" }, set: { code in
                    chosen = code.isEmpty ? nil : code
                    AppLanguage.chosen = chosen
                })) {
                    Text("Same as the Mac (\(AppLanguage.name(of: AppLanguage.system)))").tag("")
                    Divider()
                    ForEach(AppLanguage.supported, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var detail: Text {
        (chosen ?? AppLanguage.system) == running
            ? Text("Typed requests are understood in English without AI; with AI, in any language.")
            : Text("Sidefolk switches language when it restarts.")
    }
}
