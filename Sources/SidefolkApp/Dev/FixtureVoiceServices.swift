#if DEBUG
import Foundation
import SidefolkCore

/// Settings › Voice with sample answers, for snapshots: no microphone, Keychain, network or speech.
@MainActor
final class FixtureVoiceServices: VoiceServices {
    var microphone = MicrophoneAccess.notAsked
    var status = Recognition.Status.ready(.transcriber)
    var hasElevenLabsKey = false

    func listeningLanguages() async -> [ListeningLanguage] {
        [ListeningLanguage(id: "en-US", name: "English (United States)"), ListeningLanguage(id: "fr-FR", name: "French (France)"),
         ListeningLanguage(id: "ja-JP", name: "Japanese (Japan)")]
    }

    func recognitionStatus(_ language: String?) async -> Recognition.Status { status }

    func installRecognition(_ language: String?, progress: @escaping @MainActor @Sendable (Double) -> Void) async -> UserFacingError? {
        progress(1)
        return nil
    }

    func appleVoices() -> [AppleVoiceChoice] {
        [AppleVoiceChoice(id: "com.apple.voice.premium.en-US.Zoe", name: "Zoe", language: "en-US", quality: .premium),
         AppleVoiceChoice(id: "com.apple.voice.enhanced.en-GB.Serena", name: "Serena", language: "en-GB", quality: .enhanced),
         AppleVoiceChoice(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: .compact)]
    }

    func setElevenLabsKey(_ key: String?) { hasElevenLabsKey = key != nil }

    func elevenLabsVoices() async -> Result<[ElevenLabs.Voice], UserFacingError> {
        .success([ElevenLabs.Voice(id: "v1", name: "Juniper", detail: "female · american · warm"),
                  ElevenLabs.Voice(id: "v2", name: "Rowan", detail: "male · british · calm")])
    }

    func testVoice(_ settings: VoiceSettings) async -> UserFacingError? { nil }
    func openSystemVoices() {}
    func openMicrophoneSettings() {}
}
#endif
