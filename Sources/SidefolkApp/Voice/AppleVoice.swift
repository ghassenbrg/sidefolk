import AVFoundation
import SidefolkCore

/// Apple's voices, made on this Mac (D34): nothing is sent anywhere. The enhanced and premium voices
/// sound far better than the compact ones that come installed; people download them in System
/// Settings, and the best one installed for the language is the default.
nonisolated struct AppleVoice: SpeechOutput {
    func audio(for sentence: String, style: VoiceStyle) -> AsyncThrowingStream<VoiceAudio, Error> {
        AsyncThrowingStream { continuation in
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = Self.voice(id: style.voice, language: style.language)
            utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(style.rate), AVSpeechUtteranceMinimumSpeechRate),
                                 AVSpeechUtteranceMaximumSpeechRate)
            // The synthesizer lives as long as the stream: it is let go when the stream ends or is cancelled.
            let synthesizer = Synthesizer()
            synthesizer.speaker.write(utterance, toBufferCallback: Self.collect(into: continuation))
            continuation.onTermination = { _ in synthesizer.stop() }
        }
    }

    /// Hands each block on as it is made; an empty block means the sentence is done.
    private static func collect(into continuation: AsyncThrowingStream<VoiceAudio, Error>.Continuation) -> AVSpeechSynthesizer.BufferCallback {
        { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                continuation.finish()
                return
            }
            continuation.yield(VoiceAudio(samples: samples(pcm), sampleRate: pcm.format.sampleRate))
        }
    }

    static func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let count = Int(buffer.frameLength)
        if let floats = buffer.floatChannelData { return Array(UnsafeBufferPointer(start: floats[0], count: count)) }
        if let ints = buffer.int16ChannelData { return (0..<count).map { Float(ints[0][$0]) / 32_768 } }
        if let ints = buffer.int32ChannelData { return (0..<count).map { Float(ints[0][$0]) / 2_147_483_648 } }
        return []
    }

    // MARK: Voices

    /// The installed voices for `language` ("en-US" or "en"), premium first, then enhanced, then
    /// compact; novelty voices and the person's own Personal Voice are left out.
    static func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        let code = Self.code(language)
        // The person's own region first ("en-GB" on a British Mac), then the language's home ("en-US").
        let mine = Locale.current.region?.identifier ?? ""
        let home = Locale.Language(identifier: Locale.Language(identifier: code).maximalIdentifier).region?.identifier ?? ""
        // The Eloquence voices (Eddy, Flo, Grandma…) are characters of their own, so they come last.
        func place(_ voice: AVSpeechSynthesisVoice) -> Int {
            (voice.identifier.contains(".eloquence.") ? 3 : 0) + (voice.language.hasSuffix(mine) ? 0 : (voice.language.hasSuffix(home) ? 1 : 2))
        }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { Self.code($0.language) == code && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                if place(a) != place(b) { return place(a) < place(b) }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    /// The chosen voice when it speaks the line's language, otherwise the best one installed for it.
    static func voice(id: String, language: String) -> AVSpeechSynthesisVoice? {
        if !id.isEmpty, let chosen = AVSpeechSynthesisVoice(identifier: id), code(chosen.language) == code(language) { return chosen }
        return best(for: language)
    }

    /// An enhanced or premium voice when one is installed; otherwise the one macOS itself uses for
    /// the language, rather than whichever compact voice sorts first.
    static func best(for language: String) -> AVSpeechSynthesisVoice? {
        let first = voices(for: language).first
        if let first, first.quality != .default { return first }
        return AVSpeechSynthesisVoice(language: language) ?? first
    }

    static func code(_ language: String) -> String {
        String(language.prefix { $0 != "-" && $0 != "_" }).lowercased()
    }
}

/// Holds the synthesizer for the stream's lifetime; AVSpeechSynthesizer may be stopped from any thread.
nonisolated private final class Synthesizer: @unchecked Sendable {
    let speaker = AVSpeechSynthesizer()

    func stop() {
        speaker.stopSpeaking(at: .immediate)
    }
}
