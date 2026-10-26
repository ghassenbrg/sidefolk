import AppKit
import AVFoundation
import SidefolkCore

/// Settings › Voice's side of the voice controller: what it reads never asks for a permission or
/// costs anything; only "Test voice" with ElevenLabs uses characters.
extension VoiceController: VoiceServices {
    var microphone: MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func listeningLanguages() async -> [ListeningLanguage] {
        await Recognition.languages().map { ListeningLanguage(id: $0.id, name: $0.name) }
    }

    func recognitionStatus(_ language: String?) async -> Recognition.Status {
        await Recognition.status(language)
    }

    func installRecognition(_ language: String?, progress: @escaping @MainActor @Sendable (Double) -> Void) async -> UserFacingError? {
        do {
            try await Recognition.install(language, progress: progress)
            return nil
        } catch {
            return UserFacingError("I couldn't download the speech model. Nothing was changed.", recovery: "Check your internet connection and try again.",
                                   detail: String(describing: error))
        }
    }

    /// Best first: the voice used when none is chosen leads the list.
    func appleVoices() -> [AppleVoiceChoice] {
        var voices = AppleVoice.voices(for: AppLanguage.current)
        if let best = AppleVoice.best(for: AppLanguage.current), let i = voices.firstIndex(of: best) { voices.insert(voices.remove(at: i), at: 0) }
        return voices.map { voice in
            let quality: AppleVoiceChoice.Quality = switch voice.quality {
            case .premium: .premium
            case .enhanced: .enhanced
            default: .compact
            }
            return AppleVoiceChoice(id: voice.identifier, name: voice.name, language: voice.language, quality: quality)
        }
    }

    var hasElevenLabsKey: Bool { elevenLabsKey != nil }

    func setElevenLabsKey(_ key: String?) {
        let keys = ProviderKeys(store: secrets)
        let clean = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clean.isEmpty {
            try? keys.remove(account: SecretKey.elevenLabsAPIKey)
        } else {
            try? keys.save(Secret(clean), account: SecretKey.elevenLabsAPIKey, host: ElevenLabs.host)
        }
    }

    func elevenLabsVoices() async -> Result<[ElevenLabs.Voice], UserFacingError> {
        guard let key = elevenLabsKey else { return .failure(UserFacingError("Add your ElevenLabs key first.")) }
        do {
            return .success(try await ElevenLabs(key: key).voices())
        } catch let error as UserFacingError {
            return .failure(error)
        } catch {
            return .failure(UserFacingError("I couldn't list your ElevenLabs voices.", detail: String(describing: error)))
        }
    }

    func testVoice(_ settings: VoiceSettings) async -> UserFacingError? {
        let name = host.currentSettings.companionName
        let line = String(localized: "Hi, I'm \(name). This is how I'll answer you.", comment: "Said aloud by Settings › Voice › Test voice")
        interrupt(cancelRun: false)
        return await withCheckedContinuation { continuation in
            say(line, with: settings) { error in
                switch error {
                case nil, is CancellationError: continuation.resume(returning: nil)
                case let error as UserFacingError: continuation.resume(returning: error)
                case let error?: continuation.resume(returning: UserFacingError("I couldn't play the voice.", detail: String(describing: error)))
                }
            }
        }
    }

    func openSystemVoices() {
        // Accessibility › Spoken Content holds System voice › Manage Voices; older macOS used another pane id.
        for address in ["x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent",
                        "x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems"] {
            if let url = URL(string: address), NSWorkspace.shared.open(url) { return }
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
