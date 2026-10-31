import SidefolkCore
import SwiftUI

/// Settings › General › Updates (D46, D70): the version that runs and what the last look found; Sidefolk's own
/// updates (don't check, tell me, or install by itself) and the gallery's add-ons, chosen apart; and whether
/// snapshots count, for both.
struct UpdatesSettingsGroup: View {
    var model: SettingsModel
    private var updates: UpdateModel { model.services.updates }

    var body: some View {
        SettingsGroup(title: Text("Updates"), footer: footer) {
            SettingsRow(title: Text("Sidefolk \(updates.running)", comment: "Settings › Updates: the version that runs"), detail: Text(status)) {
                control
            }
            SettingsRow(title: Text("New versions of Sidefolk", comment: "Settings › Updates: what Sidefolk does about its own updates"),
                        detail: Text(appDetail)) {
                Picker("New versions of Sidefolk", selection: Binding(get: { appMode }, set: { m in model.update { $0.updates.app = m } })) {
                    Text("Don't check", comment: "Settings › Updates › New versions of Sidefolk").tag(AppUpdateMode.off)
                    Text("Tell me", comment: "Settings › Updates › New versions of Sidefolk: ask before installing").tag(AppUpdateMode.notify)
                    Text("Install automatically", comment: "Settings › Updates › New versions of Sidefolk").tag(AppUpdateMode.install)
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!updates.published)
            }
            SettingsToggle(title: Text("Update add-ons automatically"),
                           detail: Text("Companions, themes and extensions from the gallery. An extension whose new version would be allowed to do more always waits for you to look first."),
                           isOn: Binding(get: { model.settings.updates.addons }, set: { on in model.update { $0.updates.addons = on } }))
            AddonUpdateRows(updates: updates)
            SettingsRow(title: "Versions to offer", detail: "Snapshots are test builds that come out before a release. Add-ons follow this too.") {
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

    /// A copy built on this Mac looks only when asked, whatever is chosen.
    private var appMode: AppUpdateMode {
        updates.published ? model.settings.updates.app : .off
    }

    private var appDetail: String {
        guard updates.published else { return String(localized: "This copy was built on this Mac, so it looks only when you ask.") }
        switch model.settings.updates.app {
        case .off: return String(localized: "Sidefolk looks only when you choose Check Now, here or in the menu bar.")
        case .notify: return String(localized: "A minute after Sidefolk starts and then once a day. It always asks before installing.")
        case .install:
            return String(localized: "Looks once a day, downloads and checks a new version, and restarts when you've been away for a few minutes, or when you quit. Never in the middle of something.")
        }
    }

    private var footer: Text {
        Text("Looking means asking GitHub for the list of Sidefolk's releases. The request says which version of Sidefolk asks, and nothing about you.")
    }

    private var status: String {
        switch updates.phase {
        case .checking: return String(localized: "Looking…")
        case .available(let o): return String(localized: "Version \(o.version.shown) is ready.", comment: "Settings › Updates")
        case .ready(let o): return String(localized: "Version \(o.version.shown) installs when you're away or when you quit.", comment: "Settings › Updates")
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
        case .ready:
            Button("Restart Now") { updates.actions?.restartNow() }.buttonStyle(.sf(.secondary))
        case .downloading, .verifying, .installing, .restarting:
            Button("Show") { updates.actions?.showUpdates() }.buttonStyle(.sf(.secondary))
        default:
            Button("Check Now") { updates.actions?.checkNow() }.buttonStyle(.sf(.secondary)).disabled(updates.busy)
        }
    }
}

/// What the add-on updates are waiting for (D70): an extension's update to look at, each with Review; updates the
/// person installs themselves while the switch is off, with Update All; or what the last look updated.
private struct AddonUpdateRows: View {
    var updates: UpdateModel

    var body: some View {
        ForEach(updates.addonReview, id: \.id) { entry in
            SettingsRow(title: Text("\(entry.shownName) \(ReleaseVersion(entry.version)?.shown ?? entry.version) needs a look", comment: "Settings › Updates: an extension update waiting for review"),
                        detail: Text("Its new version would be allowed to do more. Review shows what's new.")) {
                Button("Review…") { updates.addonActions?.review(entry) }.buttonStyle(.sf(.primary))
            }
        }
        if !updates.addonWaiting.isEmpty {
            SettingsRow(title: Text(waitingTitle), detail: Text(verbatim: Wording.list(updates.addonWaiting.map(\.shownName)))) {
                Button("Update All") { updates.addonActions?.updateAddonsNow() }.buttonStyle(.sf(.secondary)).disabled(updates.addonsBusy)
            }
        } else if let at = updates.addonsUpdatedAt, !updates.addonsUpdated.isEmpty {
            SettingsRow(title: Text("Add-ons updated \(TimeText.relative(at))", comment: "Settings › Updates: “Add-ons updated 2 hours ago”"),
                        detail: Text(verbatim: Wording.list(updates.addonsUpdated))) { EmptyView() }
        }
    }

    private var waitingTitle: String {
        String(localized: "\(updates.addonWaiting.count) add-on updates are ready", comment: "Settings › Updates, while add-ons don't update by themselves")
    }
}
