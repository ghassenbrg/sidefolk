import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SidefolkCore

extension KeyboardShortcuts.Name {
    /// ⌃⌥Space by default (D84): the card beside the companion takes the keyboard.
    static let answerCard = Self("answerCard", default: .init(.space, modifiers: [.control, .option]))
}

/// Answering cards from the keyboard outside Ask (D84). The shortcut is registered only while something on the desktop
/// waits for an answer (a card, a slip, held cards), so the rest of the time the combination stays the other apps'; and
/// never when macOS or Sidefolk's own shortcuts already use it.
extension AppCoordinator {
    func installCardKeys() {
        KeyboardShortcuts.onKeyDown(for: .answerCard) { [weak self] in self?.focusFrontCard() }
        cardKeysInstalled = true
        cardKeysOn = true
        applyCardKeys()
    }

    func applyCardKeys() {
        guard cardKeysInstalled else { return }
        let wanted = CardShortcut.conflict(KeyboardShortcuts.getShortcut(for: .answerCard)) == nil
            && (sidecard.showsSomething || (askPanel.isVisible && ask.compact) || waitingCount > 0)
        guard wanted != cardKeysOn else { return }
        cardKeysOn = wanted
        if wanted { KeyboardShortcuts.enable(.answerCard) } else { KeyboardShortcuts.disable(.answerCard) }
    }

    /// The shortcut, or VoiceOver pressing the card from the companion's group: a slip alone (or Ask) takes the
    /// keyboard; else the card in front; else the held cards fan out; else approvals waiting bring their slip back.
    func focusFrontCard() {
        if askPanel.isVisible { return askPanel.focus() }
        Task {
            if await sidecard.takeKeys() { return }
            if !mood.approvals.isEmpty { showAsk(focus: true, slipsOnly: true) }
        }
    }
}

extension AppCoordinator {
    /// What VoiceOver hears above the companion's head (D84): the slip standing alone, the card or whisper, or the
    /// held cards fanned out.
    func companionSays() -> String? {
        if askPanel.isVisible, ask.compact, let slip = ask.pinnedEntries.first, case .approval(let request) = slip.content {
            return String(localized: "Permission request: \(request.title)")
        }
        guard sidecard.showsSomething else { return nil }
        if sidecard.model.shape == .stack {
            return String(localized: "\(sidecard.model.stack.count) held cards", comment: "VoiceOver: the held cards fanned above the companion")
        }
        return sidecard.model.item.map { String(localized: "Card: \($0.title)", comment: "VoiceOver: the card above the companion, then its title") }
    }

    func companionFocusCard() { focusFrontCard() }
}

/// Whether a shortcut for the card would take keys something else already has.
enum CardShortcut {
    enum Conflict: Equatable { case macOS, ask, talk }

    static func conflict(_ shortcut: KeyboardShortcuts.Shortcut?) -> Conflict? {
        guard let shortcut else { return nil }
        if shortcut == KeyboardShortcuts.getShortcut(for: .ask) { return .ask }
        if shortcut == KeyboardShortcuts.getShortcut(for: .talk) { return .talk }
        return takenByMacOS(shortcut) ? .macOS : nil
    }

    /// macOS's own shortcuts that are switched on (input sources, Spotlight, Mission Control…): ⌃⌥Space is the next
    /// input source on many Macs, and a Carbon hot key never wins against them.
    static func takenByMacOS(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr, let hotKeys = list?.takeRetainedValue() as? [[String: Any]] else { return false }
        return hotKeys.contains { hotKey in
            guard (hotKey[kHISymbolicHotKeyEnabled] as? Bool) == true, let code = hotKey[kHISymbolicHotKeyCode] as? Int,
                  let modifiers = hotKey[kHISymbolicHotKeyModifiers] as? Int else { return false }
            return KeyboardShortcuts.Shortcut(carbonKeyCode: code, carbonModifiers: modifiers) == shortcut
        }
    }

    /// What Settings says when the shortcut can't be used.
    static func explanation(_ conflict: Conflict) -> String {
        switch conflict {
        case .macOS: String(localized: "macOS already uses this shortcut, so it's off. Pick another.",
                            comment: "Settings › General, under the card shortcut")
        case .ask: String(localized: "The Ask shortcut is the same, so this one is off. Pick another.",
                          comment: "Settings › General, under the card shortcut")
        case .talk: String(localized: "The talk shortcut is the same, so this one is off. Pick another.",
                           comment: "Settings › General, under the card shortcut")
        }
    }
}
