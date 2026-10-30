import SidefolkCore
import SwiftUI

/// Settings › General › Updates (D46): the version that runs, what the last look found, looking by itself,
/// and whether snapshots count.
struct UpdatesSettingsGroup: View {
    var model: SettingsModel
    private var updates: UpdateModel { model.services.updates }

    var body: some View {
        SettingsGroup(title: Text("Updates"), footer: footer) {
            SettingsRow(title: Text("Sidefolk \(updates.running)", comment: "Settings › Updates: the version that runs"), detail: Text(status)) {
                control
            }
            SettingsToggle(title: Text("Check for updates automatically"),
                           detail: updates.published
                               ? Text("A minute after Sidefolk starts and then once a day. It always asks before installing.")
                               : Text("This copy was built on this Mac, so it looks only when you ask."),
                           isOn: Binding(get: { updates.published && model.settings.updates.automatic },
                                         set: { on in model.update { $0.updates.automatic = on } }))
                .disabled(!updates.published)
            SettingsRow(title: "Versions to offer", detail: "Snapshots are test builds that come out before a release.") {
                Picker("Versions to offer", selection: Binding(get: { channel }, set: { c in model.update { $0.updates.channel = c } })) {
                    Text("Releases").tag(UpdateChannel.releases)
                    Text("Releases and snapshots").tag(UpdateChannel.snapshots)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var channel: UpdateChannel {
        model.settings.updates.effectiveChannel
    }

    private var footer: Text {
        Text("Looking means asking GitHub for the list of Sidefolk's releases. The request says which version of Sidefolk asks, and nothing about you.")
    }

    private var status: String {
        switch updates.phase {
        case .checking: return String(localized: "Looking…")
        case .available(let o): return String(localized: "Version \(o.version.shown) is ready.", comment: "Settings › Updates")
        case .downloading, .verifying, .installing: return String(localized: "Updating…")
        case .restarting: return String(localized: "Restarting…")
        case .downloaded: return String(localized: "The new version is in your Downloads folder.")
        case .failed(_, let error): return error.message
        case .idle, .upToDate:
            guard let last = updates.lastCheck else { return String(localized: "Not looked yet.") }
            return String(localized: "Up to date. Looked \(TimeText.relative(last)).", comment: "Settings › Updates: “Up to date. Looked 2 hours ago.”")
        }
    }

    @ViewBuilder private var control: some View {
        switch updates.phase {
        case .available:
            Button("Update…") { updates.actions?.showUpdates() }.buttonStyle(.sf(.primary))
        case .downloading, .verifying, .installing, .restarting:
            Button("Show") { updates.actions?.showUpdates() }.buttonStyle(.sf(.secondary))
        default:
            Button("Check Now") { updates.actions?.checkNow() }.buttonStyle(.sf(.secondary)).disabled(updates.busy)
        }
    }
}
