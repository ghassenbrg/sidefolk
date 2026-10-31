import Foundation
import SidefolkCore

/// Open, Focus and Quiet (D84): the settings say which, Attention applies it, and a timer looks again when one ends by
/// itself or quiet hours start or end. Full access's end time gets the same timer, so the menu bar and the Ask panel
/// stop showing it the moment Guard stops applying it.
extension AppCoordinator {
    /// Tells Attention what the settings say now, and when to look again.
    func applyAttention() {
        let s = runtime.settings.current
        let now = Date()
        let quiet = s.isQuiet(at: now), focus = s.isFocused(at: now)
        Task {
            await runtime.attention.update { env in
                env.quiet = quiet
                env.focus = focus
                env.fullScreenRule = s.fullScreen
                env.presence = s.presence
                env.sounds = s.sounds
            }
        }
        refreshMark()
        attentionTimer?.cancel()
        attentionTimer = nil
        guard let next = s.nextAttentionChange(after: now) else { return }
        attentionTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow + 0.5)))
            guard !Task.isCancelled, let self else { return }
            // Each surface reads the new mode from the settings it already follows.
            runtime.events.changed(.settings)
        }
    }

    /// Open, Focus or Quiet until `until` (nil: until turned off), from the Pocket, Settings or the companion's menu.
    func setAttention(_ mode: AttentionMode, until: Date?) {
        Task {
            await runtime.settings.update { $0.setAttention(mode, until: until, now: Date()) }
            settingsChanged()
        }
    }

    /// Full access that ends by itself: say so when it does, so everything showing it reads Guard again.
    func scheduleFullAccessEnd(_ policy: GuardPolicy) {
        fullAccessTimer?.cancel()
        fullAccessTimer = nil
        guard policy.mode == .fullAccess, let ends = policy.fullAccessEnds else { return }
        fullAccessTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.5, ends.timeIntervalSinceNow + 0.5)))
            guard !Task.isCancelled, let self else { return }
            runtime.events.changed(.permissions)
        }
    }
}
