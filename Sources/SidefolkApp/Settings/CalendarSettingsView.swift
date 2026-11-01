import SidefolkCore
import SwiftUI

/// Settings › Trust › Your calendar (D57, D97): whether Today, the morning brief and the AI may read it, and whether
/// Sidefolk may change its events. Both off until the person chooses.
struct CalendarGroup: View {
    var model: SettingsModel
    /// Refreshed after asking macOS, which answers outside SwiftUI.
    @State private var access: CalendarAccess?

    private var on: Bool { model.settings.showCalendar }

    var body: some View {
        SettingsGroup(title: "Your calendar",
                      footer: "Your AI sees your calendar only when it asks and you allow it. It can change events only if you let Sidefolk change them, through Guard, and always asks before deleting one.",
                      anchor: .calendar) {
            ChoiceRow(title: Text("Off"), detail: Text("Today and the morning brief show reminders only."), selected: !on) {
                Task { await model.services.showCalendar(false) }
            }
            ChoiceRow(title: Text("Show my calendar"), detail: Text("Your events on Today and in the morning brief. macOS asks you once."),
                      selected: on) {
                Task {
                    await model.services.showCalendar(true)
                    access = model.services.calendarAccess
                }
            }
            if on {
                switch access ?? model.services.calendarAccess {
                case .allowed:
                    SettingsRow(title: "Calendars", detail: "Allowed") {
                        Chip("Allowed", tone: .success, systemImage: "calendar")
                    }
                    SettingsToggle(title: "Let Sidefolk change events",
                                   detail: "Add, move and delete events from the Calendar page, with Undo. Never events other people are invited to.",
                                   isOn: Binding(get: { model.settings.calendarPage.writes },
                                                 set: { on in Task { await model.services.allowCalendarChanges(on) } }))
                case .notAsked:
                    SettingsRow(title: "Calendars", detail: "macOS hasn't asked you yet.") {
                        Button("Allow…") {
                            Task {
                                await model.services.showCalendar(true)
                                access = model.services.calendarAccess
                            }
                        }
                        .buttonStyle(.sf(.primary))
                    }
                case .denied:
                    SettingsRow(title: "Calendars", detail: "Not allowed for Sidefolk. Allow full access in System Settings.") {
                        Button("Open System Settings") { model.services.openCalendarSettings() }.buttonStyle(.sf(.primary))
                    }
                }
            }
        }
    }
}
