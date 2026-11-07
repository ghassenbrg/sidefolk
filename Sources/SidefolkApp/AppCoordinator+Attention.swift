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
                env.interruptions = s.interruptions
            }
        }
        sidecard.model.interruptions = s.interruptions
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

    static let levelChanged = "levelChanged"

    /// "Fewer like this" or "Show these as whispers" on a card (D88): the source's level changes at once, and a whisper
    /// says so with Undo.
    func lowerSource(_ source: InterruptSource, to level: InterruptLevel) {
        let before = runtime.settings.current.interruptions.explicit(source)
        Task {
            await runtime.settings.update { $0.interruptions.set(level, for: source) }
            settingsChanged()
            let name = source.name(companion: runtime.settings.current.companionName,
                                   extensions: ask.extensionLooks.mapValues(\.name))
            let title = level == .whisper
                ? String(localized: "\(name): whispers from now on", comment: "A whisper after “Show these as whispers”: “Claude Code: whispers from now on”")
                : String(localized: "\(name): only in Today from now on", comment: "A whisper after “Fewer like this”: “Claude Code: only in Today from now on”")
            let item = AttentionItem(level: .gentle, source: Self.ownVoice, title: title,
                                     actions: [AttentionAction(id: SidecardItemCard.undo, title: String(localized: "Undo"))],
                                     refKind: Self.levelChanged, refId: source.key)
            levelUndo[item.id] = (source, before)
            sidecard.present(item, .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
        }
    }

    /// Undo on that whisper: the source's level as it was, said back.
    func undoLevel(_ whisperId: String) {
        guard let change = levelUndo.removeValue(forKey: whisperId) else { return }
        Task {
            await runtime.settings.update { $0.interruptions.set(change.before, for: change.source) }
            settingsChanged()
            sidecard.present(AttentionItem(level: .gentle, source: Self.ownVoice,
                                           title: String(localized: "Undone: notices come as before.", comment: "A whisper after undoing “Fewer like this”"),
                                           refKind: "undone"),
                             .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
        }
    }

    /// Full access that ends by itself: say so when it does, so everything showing it reads Guard again.
    func scheduleFullAccessEnd(_ policy: GuardPolicy) {
        fullAccessTimer?.cancel()
        fullAccessTimer = nil
        guard policy.mode == .fullAccess, let ends = policy.fullAccessEnds else { return }
        // Other apps were let in with it (D240): its end is theirs too, and the person hears so, in one line, so that an agent that asks again isn't a surprise.
        let agentsToo = policy.agentsMayActFreely
        fullAccessTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.5, ends.timeIntervalSinceNow + 0.5)))
            guard !Task.isCancelled, let self else { return }
            runtime.events.changed(.permissions)
            if agentsToo {
                sidecard.present(AttentionItem(level: .gentle, source: Self.ownVoice,
                                               title: String(localized: "Full access ended. Other apps ask again.", comment: "A whisper: Full access ended by itself while other apps were let act without asking"),
                                               refKind: "full_access_ended"),
                                 .gentle(autoDismiss: AttentionPolicy.gentleSeconds * 2))
            }
        }
    }
}
