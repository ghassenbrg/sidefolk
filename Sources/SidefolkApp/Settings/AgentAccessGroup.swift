import SidefolkCore
import SwiftUI

/// Settings › Privacy & Permissions › Other agents (D52): what Claude Code, Codex and other MCP apps connected to
/// Sidefolk may do, group by group. Files, commands, the web and Settings are never theirs, whatever is set here.
struct AgentAccessGroup: View {
    var model: SettingsModel

    private var access: AgentAccess { model.settings.agentAccess }

    var body: some View {
        SettingsGroup(title: "Other agents",
                      footer: "For Claude Code, Codex and other apps connected to Sidefolk. Everything they do shows in Activity, and you can undo it there. They never reach your files, commands, the web or Settings.") {
            row("Save notes, reminders and watches",
                detail: "Add to your notebook, remind you, and watch pages or this Mac for you. Their notes are tagged with their name.",
                value: access.save) { p in model.update { $0.agentAccess.save = p } }
            row("Change and delete notes",
                detail: "Edit notes, move them, mark tasks done, or move them to the Trash. Only you can empty the Trash.",
                value: access.change) { p in model.update { $0.agentAccess.change = p } }
            row("Read your notes and reminders",
                detail: "Search and list your notebook, your reminders and today's plan.",
                value: access.read) { p in model.update { $0.agentAccess.read = p } }
        }
    }

    private func row(_ title: LocalizedStringKey, detail: LocalizedStringKey, value: AgentPermission,
                     set: @escaping @Sendable (AgentPermission) -> Void) -> some View {
        SettingsRow(title: Text(title), detail: Text(detail)) {
            Picker(title, selection: Binding(get: { value }, set: set)) {
                Text("Allow").tag(AgentPermission.allow)
                Text("Ask each time").tag(AgentPermission.ask)
                Text("Off").tag(AgentPermission.off)
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
