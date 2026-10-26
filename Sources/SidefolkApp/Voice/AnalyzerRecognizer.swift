import AVFoundation
import Speech
import Synchronization

/// Apple's SpeechAnalyzer (macOS 26+): on device, its model in system storage, nothing added to the
/// app. SpeechTranscriber where it covers the language, DictationTranscriber where it doesn't (D34).
/// It needs no speech-recognition permission, only the microphone's.
@available(macOS 26, *)
nonisolated final class AnalyzerRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let locale: Locale
    private let dictation: Bool
    private let state = Mutex(State())

    private struct State {
        var analyzer: SpeechAnalyzer?
        var inputs: AsyncStream<AnalyzerInput>.Continuation?
        var results: Task<String, Never>?
        var format: AVAudioFormat?
        var converter: AVAudioConverter?
        /// Everything heard so far, for a finish that runs out of time.
        var latest = ""
    }

    init(locale: Locale, dictation: Bool) {
        self.locale = locale
        self.dictation = dictation
    }

    func start(partial: @escaping @MainActor @Sendable (String) -> Void) async throws {
        let module: any SpeechModule
        let results: Task<String, Never>
        let update: @Sendable (String) -> Void = { [weak self] text in
            self?.state.withLock { $0.latest = text }
            Task { @MainActor in partial(text) }
        }
        if dictation {
            let transcriber = DictationTranscriber(locale: locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                                                   reportingOptions: [.volatileResults], attributeOptions: [])
            module = transcriber
            results = Self.collect(transcriber.results, { (String($0.text.characters), $0.isFinal) }, update)
        } else {
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults],
                                                attributeOptions: [])
            module = transcriber
            results = Self.collect(transcriber.results, { (String($0.text.characters), $0.isFinal) }, update)
        }
        // Asks macOS to keep this language's model for Sidefolk (it may hold a few per app).
        _ = try? await AssetInventory.reserve(locale: locale)
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        let (stream, inputs) = AsyncStream<AnalyzerInput>.makeStream()
        // Kept warm a while after use: the next press gets its first words sooner.
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .lingering))
        state.withLock {
            $0.analyzer = analyzer
            $0.inputs = inputs
            $0.results = results
            $0.format = format
        }
        do {
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream)
        } catch {
            inputs.finish()
            results.cancel()
            throw error
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        state.withLock { s in
            guard let inputs = s.inputs, let converted = Self.convert(buffer, to: s.format, using: &s.converter) else { return }
            inputs.yield(AnalyzerInput(buffer: converted))
        }
    }

    func finish() async -> String {
        let (analyzer, inputs, results) = state.withLock { ($0.analyzer, $0.inputs, $0.results) }
        inputs?.finish()
        // The last words settle in a fraction of a second; past four, keep what was heard so far.
        let text = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                try? await analyzer?.finalizeAndFinishThroughEndOfInput()
                return await results?.value ?? ""
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(4))
                return nil
            }
            let first = await group.next() ?? nil
            if first == nil {
                await analyzer?.cancelAndFinishNow()
                results?.cancel()
            }
            group.cancelAll()
            return first
        }
        return (text ?? state.withLock { $0.latest }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        let (analyzer, inputs, results) = state.withLock { ($0.analyzer, $0.inputs, $0.results) }
        inputs?.finish()
        results?.cancel()
        await analyzer?.cancelAndFinishNow()
    }

    // MARK: Helpers

    /// Reads the module's results: settled stretches add up, the volatile tail is shown after them.
    private static func collect<S: AsyncSequence & Sendable>(_ results: S, _ read: @escaping @Sendable (S.Element) -> (String, Bool),
                                                             _ update: @escaping @Sendable (String) -> Void) -> Task<String, Never> {
        Task {
            var settled = ""
            do {
                for try await result in results {
                    let (text, isFinal) = read(result)
                    if isFinal {
                        settled = joined(settled, text)
                        update(settled)
                    } else {
                        update(joined(settled, text))
                    }
                }
            } catch {}
            return settled
        }
    }

    /// Adds a stretch of words, with a space between them unless the script doesn't use spaces.
    static func joined(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else { return head + tail }
        let unspaced = [last, first].contains { $0.unicodeScalars.first?.properties.isIdeographic == true
            || ("\u{3040}"..."\u{30FF}").contains($0) }
        return last.isWhitespace || first.isWhitespace || unspaced ? head + tail : head + " " + tail
    }

    /// The microphone's audio in the analyzer's format (wrong formats are silently ignored by it).
    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat?, using converter: inout AVAudioConverter?) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        if buffer.format == format { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.downmix = true
        }
        guard let converter,
              let out = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 64)
        else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }
}

/// SpeechAnalyzer's modules and their models.
@available(macOS 26, *)
enum Analyzer {
    /// The module and exact locale that serve `wanted`, if any, and whether its model is on this Mac.
    static func module(for wanted: Locale) async -> (module: any SpeechModule, locale: Locale, installed: Bool)? {
        if SpeechTranscriber.isAvailable,
           let (locale, installed) = best(await SpeechTranscriber.supportedLocales, installed: await SpeechTranscriber.installedLocales, for: wanted) {
            return (SpeechTranscriber(locale: locale, preset: .transcription), locale, installed)
        }
        if let (locale, installed) = best(await DictationTranscriber.supportedLocales, installed: await DictationTranscriber.installedLocales,
                                          for: wanted) {
            return (DictationTranscriber(locale: locale, preset: .shortDictation), locale, installed)
        }
        return nil
    }

    /// The locale for `wanted`'s language: the one named exactly; otherwise one already installed
    /// before one to download, the Mac's own region first, then the language's home ("en" → en-US,
    /// "zh-Hans" → zh-CN). Apple's own equivalence picks oddly ("en" → en-ZA), so it isn't used.
    static func best(_ supported: [Locale], installed: [Locale], for wanted: Locale) -> (Locale, installed: Bool)? {
        let language = wanted.language
        let candidates = supported.filter { $0.language.languageCode == language.languageCode }
        let ready = Set(installed.map { $0.identifier(.bcp47) })
        let home = Locale.Language(identifier: language.maximalIdentifier).region
        let script = language.script ?? Locale.Language(identifier: language.maximalIdentifier).script
        func rank(_ locale: Locale) -> Int {
            let region = locale.region
            var score = ready.contains(locale.identifier(.bcp47)) ? 0 : 100
            if let wantedRegion = language.region, region == wantedRegion { score -= 150 }
            if let script, let own = Locale.Language(identifier: locale.language.maximalIdentifier).script, own != script { score += 200 }
            if region == Locale.current.region { score -= 2 } else if region == home { score -= 1 }
            return score
        }
        guard let best = candidates.min(by: { rank($0) < rank($1) }) else { return nil }
        return (best, ready.contains(best.identifier(.bcp47)))
    }

    /// Asks macOS to download the language's model, reporting progress until it is installed.
    static func install(_ module: any SpeechModule, locale: Locale, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        _ = try? await AssetInventory.reserve(locale: locale)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        let observation = observe(request.progress) { fraction in Task { @MainActor in progress(fraction) } }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
        progress(1)
    }

    /// Built outside the main actor: Foundation reports progress on whatever thread does the work.
    nonisolated private static func observe(_ progress: Progress, _ report: @escaping @Sendable (Double) -> Void) -> NSKeyValueObservation {
        progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in report(p.fractionCompleted) }
    }
}
