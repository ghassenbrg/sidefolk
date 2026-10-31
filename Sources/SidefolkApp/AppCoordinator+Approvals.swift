import AppKit
import SidefolkCore

/// How much Sidefolk asks (D37), as the desktop shows it: the Ask panel's chip, the menu bar, and
/// what was done without asking.
extension AppCoordinator {
    func installModeSwitch() {
        refreshMode()
    }

    /// Reads the mode from Guard's policy, where Settings and the menu bar change it.
    func refreshMode() {
        let permissions = runtime.permissions
        Task {
            let policy = (try? await permissions.policy()) ?? GuardPolicy()
            ask.mode = policy.mode
            statusItem.setMode(policy.mode, ends: policy.fullAccessEnds)
            scheduleFullAccessEnd(policy)
        }
    }

    /// Every mode but Full access switches at once; Full access only after its sheet.
    func setMode(_ mode: GuardMode) {
        guard mode != .fullAccess else { return }
        let permissions = runtime.permissions
        let events = runtime.events
        Task {
            try? await permissions.updatePolicy { $0.choose(mode) }
            events.changed(.permissions)
        }
    }

    /// Something Sidefolk's agent did without asking, because of the mode, while the Ask panel is
    /// hidden: say so in a bubble, so nothing it does goes unseen (D37). With the panel open, the
    /// request's own results say it.
    func announceDoneWithoutAsking(_ activity: ToolActivity, ok: Bool) {
        guard ok, activity.actedWithoutAsking, activity.caller.kind == "agent", !askPanel.isVisible else { return }
        let mode: GuardMode = activity.byFullAccess ? .fullAccess : .auto
        let item = AttentionItem(level: .gentle, source: Self.ownVoice,
                                 title: String(localized: "Done without asking: \(activity.summary)",
                                               comment: "A bubble: what Sidefolk did on its own in Auto or Full access"),
                                 body: mode.title, refKind: "unasked")
        bubbles.present(item, .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
    }

    /// Home › Now, where skipped steps wait with "Run it now".
    func openNow() {
        askPanel.hide()
        home.show(section: .now)
    }
}
