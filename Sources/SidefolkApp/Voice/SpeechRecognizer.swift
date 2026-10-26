import AVFoundation
import Speech
import SidefolkCore

/// Turns what the microphone hears into words, live and on this Mac (D34). Two kinds: Apple's
/// SpeechAnalyzer on macOS 26 and later, and the older recognizer, labelled "basic", before that.
nonisolated protocol SpeechRecognizer: AnyObject, Sendable {
    /// Starts listening; `partial` gets everything heard so far whenever it changes.
    func start(partial: @escaping @MainActor @Sendable (String) -> Void) async throws
    /// One block of audio, in whatever format the microphone gives; called on the audio thread.
    func append(_ buffer: AVAudioPCMBuffer)
    /// No more audio: the final words, "" when nothing was understood.
    func finish() async -> String
    func cancel() async
}

/// Which recognizer serves a language, and whether it is ready to listen.
enum Recognition {
    enum Engine: Equatable {
        /// SpeechTranscriber (macOS 26+): Apple's newest model, the one Notes and Voice Memos use.
        case transcriber
        /// DictationTranscriber (macOS 26+): for languages SpeechTranscriber doesn't cover.
        case dictation
        /// SFSpeechRecognizer forced on device: macOS 15's older recognizer, less accurate.
        case basic
    }

    enum Status: Equatable {
        case ready(Engine)
        /// The language's model has to be downloaded first (by macOS, into its own storage).
        case needsDownload(Engine)
        case unsupported
    }

    enum Failure: Error {
        case unsupported
        case needsDownload
        /// macOS 15: speech recognition wasn't allowed in System Settings.
        case notAllowed
    }

    /// The language to listen in: the one chosen, or the app's (its region is picked with the model).
    static func locale(for chosen: String?) -> Locale {
        Locale(identifier: chosen.flatMap { $0.isEmpty ? nil : $0 } ?? AppLanguage.current)
    }

    static func status(_ chosen: String?) async -> Status {
        let wanted = locale(for: chosen)
        if #available(macOS 26, *), let found = await Analyzer.module(for: wanted) {
            let engine: Engine = found.module is SpeechTranscriber ? .transcriber : .dictation
            return found.installed ? .ready(engine) : .needsDownload(engine)
        }
        return BasicRecognizer.supports(wanted) ? .ready(.basic) : .unsupported
    }

    /// A recognizer ready to start, or why there is none.
    static func make(_ chosen: String?) async throws -> any SpeechRecognizer {
        let wanted = locale(for: chosen)
        if #available(macOS 26, *), let found = await Analyzer.module(for: wanted) {
            guard found.installed else { throw Failure.needsDownload }
            return AnalyzerRecognizer(locale: found.locale, dictation: !(found.module is SpeechTranscriber))
        }
        guard let basic = BasicRecognizer(locale: wanted) else { throw Failure.unsupported }
        return basic
    }

    /// Downloads the language's model (macOS 26+), reporting progress from 0 to 1.
    static func install(_ chosen: String?, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard #available(macOS 26, *) else { return }
        guard let found = await Analyzer.module(for: locale(for: chosen)) else { throw Failure.unsupported }
        try await Analyzer.install(found.module, locale: found.locale, progress: progress)
    }

    /// Every language this Mac can listen in, by name in the app's language.
    static func languages() async -> [(id: String, name: String)] {
        var locales: [Locale]
        if #available(macOS 26, *) {
            locales = await SpeechTranscriber.supportedLocales + DictationTranscriber.supportedLocales
        } else {
            locales = Array(SFSpeechRecognizer.supportedLocales())
        }
        var seen = Set<String>()
        let shown = Locale(identifier: AppLanguage.current)
        return locales.map { $0.identifier(.bcp47) }.filter { seen.insert($0).inserted }
            .map { (id: $0, name: shown.localizedString(forIdentifier: $0) ?? $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
