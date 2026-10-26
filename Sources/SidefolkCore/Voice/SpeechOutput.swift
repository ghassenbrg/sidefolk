import Foundation

/// A piece of synthesized speech: mono samples at `sampleRate`.
public struct VoiceAudio: Sendable, Equatable {
    public var samples: [Float]
    public var sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: TimeInterval { Double(samples.count) / sampleRate }
}

/// How a sentence is said.
public struct VoiceStyle: Sendable, Equatable {
    /// The engine's own voice id; empty lets the engine pick its best for `language`.
    public var voice: String
    /// BCP 47 ("en-US", "fr-FR").
    public var language: String
    /// 1 is the engine's normal pace.
    public var rate: Double

    public init(voice: String, language: String, rate: Double) {
        self.voice = voice
        self.language = language
        self.rate = rate
    }
}

/// One voice engine (D34): a sentence in, its audio out, in pieces as they are made. A cloud voice
/// streams many pieces; an on-device one may give one. Cancelling the consuming task stops the work.
public protocol SpeechOutput: Sendable {
    func audio(for sentence: String, style: VoiceStyle) -> AsyncThrowingStream<VoiceAudio, Error>
}

/// Plays what the engines make: the app's audio engine, or a recorder in tests.
@MainActor
public protocol AudioSink: AnyObject {
    /// Queues `audio` after whatever is already playing.
    func schedule(_ audio: VoiceAudio, volume: Float)
    /// Returns once everything scheduled has played, or at once after `stop()`.
    func drained() async
    /// Silence now; everything queued is dropped.
    func stop()
    /// How loud the voice playing now is, 0...1, a dozen or more times a second; nil once it is silent.
    var onLevel: ((Float?) -> Void)? { get set }
}
