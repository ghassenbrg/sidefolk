import SidefolkCore
import SwiftUI

/// Settings › Privacy › Your calendar (D57): whether Today, the morning brief and the AI may read it. Off until the
/// person chooses; read-only always.
struct CalendarGroup: View {
    var model: SettingsModel
    /// Refreshed after asking macOS, which answers outside SwiftUI.
    @State private var access: CalendarAccess?

    private var on: Bool { model.settings.showCalendar }

    var body: some View {
        SettingsGroup(title: "Your calendar",
                      footer: "Sidefolk only reads your calendar, never changes it. Your AI sees it only when it asks and you allow it.") {
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
