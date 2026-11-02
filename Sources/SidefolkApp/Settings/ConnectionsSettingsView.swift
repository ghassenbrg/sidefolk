import SidefolkCore
import SwiftUI

/// Settings › Connections (D84, was Agents): Claude Code, Codex, the sidefolk command and other MCP apps, each saying
/// exactly what connecting it changes. What they may do once connected is in Trust.
struct ConnectionsSettingsView: View {
    var model: SettingsModel

    var body: some View {
        SettingsPage {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Let your agents reach \(model.settings.companionName)", comment: "Settings › Connections: the page's heading")
                    .font(Theme.Font.title1).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Connected agents can save notes, set reminders, watch pages and tell you when they need you. Sidefolk backs up each file before it changes it.",
                     comment: "Settings › Connections: under the heading")
                    .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AgentsGroup(model: model)
            HStack(spacing: Theme.Space.s) {
                Text("What they may do once connected is in Trust.", comment: "Settings › Connections: a pointer to Trust › What other agents may do")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                Button {
                    model.navigation.jump(to: .agentAccess)
                } label: {
                    Text("Open Trust", comment: "Settings › Connections: opens Trust › What other agents may do").font(Theme.Font.captionStrong)
                }
                .buttonStyle(.sfBare)
                .foregroundStyle(Theme.link)
            }
        }
    }
}
