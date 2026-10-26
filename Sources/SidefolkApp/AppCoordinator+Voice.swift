import AppKit
import KeyboardShortcuts
import SidefolkCore

/// The talk keys, and the voice controller's view of the app (D34).
extension AppCoordinator: VoiceHost {
    /// Long enough that a quick tap of the Ask shortcut still just opens the panel.
    static let holdToTalk: Duration = .milliseconds(300)

    /// The Ask shortcut: a tap opens or closes the panel; held, with voice input on and the Ask
    /// shortcut as the talk key, it talks. A shortcut of its own talks from the moment it is down.
    func installTalkKeys() {
        KeyboardShortcuts.onKeyDown(for: .ask) { [weak self] in self?.askKeyDown() }
        KeyboardShortcuts.onKeyUp(for: .ask) { [weak self] in self?.askKeyUp() }
        KeyboardShortcuts.onKeyDown(for: .talk) { [weak self] in self?.voice.begin() }
        KeyboardShortcuts.onKeyUp(for: .talk) { [weak self] in self?.voice.end() }
        talkKeysInstalled = true
        applyVoiceKeys()
    }

    /// The talk shortcut only takes its keys from other apps while it is the way to talk.
    func applyVoiceKeys() {
        guard talkKeysInstalled else { return }
        let v = runtime.settings.current.voice
        if v.input && v.talkKey == .ownShortcut { KeyboardShortcuts.enable(.talk) } else { KeyboardShortcuts.disable(.talk) }
    }

    private func askKeyDown() {
        // Carbon repeats nothing, but a second press while one is pending changes nothing either.
        guard askKeyHold == nil, !askKeyTalking else { return }
        askKeySilenced = voice.isSpeaking
        if askKeySilenced { voice.interrupt(cancelRun: true) }
        let v = runtime.settings.current.voice
        guard v.input, v.talkKey == .askShortcut else { return }
        askKeyHold = Task { [weak self] in
            try? await Task.sleep(for: Self.holdToTalk)
            guard let self, !Task.isCancelled else { return }
            askKeyHold = nil
            askKeyTalking = true
            voice.begin()
        }
    }

    private func askKeyUp() {
        askKeyHold?.cancel()
        askKeyHold = nil
        if askKeyTalking {
            askKeyTalking = false
            voice.end()
        } else if !askKeySilenced {
            toggleAsk()
        }
        askKeySilenced = false
    }

    // MARK: VoiceHost

    var voiceServices: any VoiceServices { voice }

    var currentSettings: AppSettings { runtime.settings.current }

    func showAskForVoice() {
        showAsk(focus: true)
    }

    func voiceMood(hearing: Bool, transcribing: Bool) {
        guard mood.hearing != hearing || mood.transcribing != transcribing else { return }
        mood.hearing = hearing
        mood.transcribing = transcribing
        renderMood()
    }

    func voiceMissed() {
        mood.missedSpeech(now: Date())
        renderMood()
    }

    func mouth(_ level: Double?) {
        companion.character.speak(level)
    }

    func cancelRun() {
        let agent = self.agent!
        Task { await agent.cancelAll() }
    }
}
