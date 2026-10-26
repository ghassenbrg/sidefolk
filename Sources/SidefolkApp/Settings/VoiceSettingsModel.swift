import Foundation
import Observation
import SidefolkCore

/// Whether Sidefolk may use the microphone. Reading it never asks; the person's first press does.
enum MicrophoneAccess {
    case allowed, notAsked, denied
}

/// An installed Apple voice.
struct AppleVoiceChoice: Identifiable, Hashable {
    enum Quality: Int, Comparable {
        case compact, enhanced, premium
        static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
    }

    var id: String
    var name: String
    /// "en-GB".
    var language: String
    var quality: Quality
}

struct ListeningLanguage: Identifiable, Hashable {
    var id: String
    var name: String
}

/// What Settings › Voice reads and does: the app's voice side, or fixtures in snapshots.
@MainActor
protocol VoiceServices: AnyObject {
    var microphone: MicrophoneAccess { get }
    func listeningLanguages() async -> [ListeningLanguage]
    func recognitionStatus(_ language: String?) async -> Recognition.Status
    /// Downloads the language's speech model (macOS keeps it in its own storage).
    func installRecognition(_ language: String?, progress: @escaping @MainActor @Sendable (Double) -> Void) async -> UserFacingError?
    /// The installed voices for the app's language, best first.
    func appleVoices() -> [AppleVoiceChoice]
    var hasElevenLabsKey: Bool { get }
    func setElevenLabsKey(_ key: String?)
    /// Free: lists the voices in the person's ElevenLabs library.
    func elevenLabsVoices() async -> Result<[ElevenLabs.Voice], UserFacingError>
    /// Says one short sentence with these settings (with ElevenLabs it costs a few characters).
    func testVoice(_ settings: VoiceSettings) async -> UserFacingError?
    /// System Settings, where better Apple voices are downloaded.
    func openSystemVoices()
    func openMicrophoneSettings()
}

/// Settings › Voice: talking (input, shortcut, language and its model), when replies are spoken,
/// and the voice that speaks them. Every control changes something real (D34).
@MainActor @Observable
final class VoiceSettingsModel {
    private unowned let parent: SettingsModel
    private var services: any VoiceServices { parent.services.voiceServices }

    private(set) var microphone: MicrophoneAccess = .notAsked
    private(set) var languages: [ListeningLanguage] = []
    private(set) var recognition: Recognition.Status?
    /// 0...1 while the language's model downloads.
    private(set) var downloading: Double?
    private(set) var downloadError: UserFacingError?
    private(set) var appleVoices: [AppleVoiceChoice] = []
    private(set) var hasKey = false
    private(set) var elevenVoices: [ElevenLabs.Voice]?
    private(set) var elevenError: UserFacingError?
    private(set) var loadingVoices = false
    private(set) var testing = false
    private(set) var testFailure: UserFacingError?

    init(parent: SettingsModel) { self.parent = parent }

    var settings: VoiceSettings { parent.settings.voice }
    var companionName: String { parent.settings.companionName }

    func refresh() async {
        microphone = services.microphone
        appleVoices = services.appleVoices()
        hasKey = services.hasElevenLabsKey
        languages = await services.listeningLanguages()
        recognition = await services.recognitionStatus(settings.language)
        if hasKey, settings.engine == .elevenLabs, elevenVoices == nil { await loadVoices() }
    }

    func update(_ change: @escaping @Sendable (inout VoiceSettings) -> Void) {
        parent.update { change(&$0.voice) }
        testFailure = nil
    }

    func setInput(_ on: Bool) {
        update { $0.input = on }
        microphone = services.microphone
    }

    func setLanguage(_ id: String?) {
        update { $0.language = id }
        recognition = nil
        downloadError = nil
        Task { recognition = await services.recognitionStatus(id) }
    }

    func download() async {
        let language = settings.language
        downloadError = nil
        downloading = 0
        downloadError = await services.installRecognition(language) { [weak self] fraction in self?.downloading = fraction }
        downloading = nil
        recognition = await services.recognitionStatus(language)
    }

    func setEngine(_ engine: VoiceEngine) {
        update { $0.engine = engine }
        if engine == .elevenLabs, hasKey, elevenVoices == nil { Task { await loadVoices() } }
    }

    // MARK: ElevenLabs

    func saveKey(_ key: String) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        services.setElevenLabsKey(clean)
        hasKey = services.hasElevenLabsKey
        elevenVoices = nil
        Task { await loadVoices() }
    }

    func removeKey() {
        services.setElevenLabsKey(nil)
        hasKey = services.hasElevenLabsKey
        elevenVoices = nil
        elevenError = nil
        update { $0.elevenLabsVoice = ""; $0.elevenLabsVoiceName = "" }
    }

    func loadVoices() async {
        loadingVoices = true
        switch await services.elevenLabsVoices() {
        case .success(let voices):
            elevenVoices = voices
            elevenError = nil
            // A first voice, so the engine works once the key is in.
            if settings.elevenLabsVoice.isEmpty, let first = voices.first { chooseElevenVoice(first) }
        case .failure(let error):
            elevenVoices = nil
            elevenError = error
        }
        loadingVoices = false
    }

    func chooseElevenVoice(_ voice: ElevenLabs.Voice) {
        let (id, name) = (voice.id, voice.name)
        update { $0.elevenLabsVoice = id; $0.elevenLabsVoiceName = name }
    }

    // MARK: Test

    func test() async {
        testing = true
        testFailure = await services.testVoice(settings)
        testing = false
    }

    func openSystemVoices() { services.openSystemVoices() }
    func openMicrophoneSettings() { services.openMicrophoneSettings() }
}
