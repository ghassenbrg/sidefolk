import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// A sink that plays nothing: it records what it was given and drains when the test says so.
@MainActor
final class RecordingSink: AudioSink {
    var scheduled: [VoiceAudio] = []
    var stops = 0
    var holdsDrain = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    var onLevel: ((Float?) -> Void)?

    func schedule(_ audio: VoiceAudio, volume: Float) {
        scheduled.append(audio)
        onLevel?(audio.samples.first ?? 0)
    }

    func drained() async {
        guard holdsDrain else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func stop() {
        stops += 1
        release()
    }

    func release() {
        let w = waiting
        waiting = []
        w.forEach { $0.resume() }
    }
}

/// One piece of audio per sentence, its first sample the sentence's length, so order can be checked.
struct CountingEngine: SpeechOutput {
    var failOn: String?

    func audio(for sentence: String, style: VoiceStyle) -> AsyncThrowingStream<VoiceAudio, Error> {
        AsyncThrowingStream { continuation in
            if sentence == failOn {
                continuation.finish(throwing: UserFacingError("The voice broke."))
                return
            }
            continuation.yield(VoiceAudio(samples: [Float(sentence.count) / 100, 0], sampleRate: 24_000))
            continuation.finish()
        }
    }
}

@MainActor @Suite struct SpeechPlayerTests {
    let style = VoiceStyle(voice: "", language: "en", rate: 1)

    /// `done` was called, without an error.
    func endedCleanly(_ outcome: Error??) -> Bool {
        if case .some(.none) = outcome { return true }
        return false
    }

    @Test func aLineIsSaidSentenceBySentenceInOrder() async {
        let sink = RecordingSink()
        let player = SpeechPlayer(sink: sink)
        var levels: [Float?] = []
        player.onLevel = { levels.append($0) }
        var outcome: Error?? = .none
        player.say("Saved to Ideas. I'll remind you at 9.", with: CountingEngine(), style: style, volume: 0.8) { outcome = $0 }
        #expect(player.isSpeaking)
        await player.finished()
        #expect(sink.scheduled.map(\.samples[0]) == [Float("Saved to Ideas.".count) / 100, Float("I'll remind you at 9.".count) / 100])
        #expect(!player.isSpeaking)
        #expect(endedCleanly(outcome))
        // The mouth followed the audio and closed at the end.
        #expect(levels.count == 3 && levels.last == .some(nil))
    }

    @Test func stoppingCutsItOffAtOnceAndSaysSo() async {
        let sink = RecordingSink()
        sink.holdsDrain = true
        let player = SpeechPlayer(sink: sink)
        var outcome: Error?
        player.say("One. Two.", with: CountingEngine(), style: style, volume: 1) { outcome = $0 }
        while sink.scheduled.count < 2 { await Task.yield() }
        player.stop()
        await player.finished()
        #expect(outcome is CancellationError)
        #expect(!player.isSpeaking)
        #expect(sink.stops >= 2)
    }

    @Test func aNewLineReplacesTheOneBeingSaid() async {
        let sink = RecordingSink()
        sink.holdsDrain = true
        let player = SpeechPlayer(sink: sink)
        var first: Error?
        var second: Error?? = .none
        player.say("Old news.", with: CountingEngine(), style: style, volume: 1) { first = $0 }
        while sink.scheduled.isEmpty { await Task.yield() }
        sink.holdsDrain = false
        player.say("New.", with: CountingEngine(), style: style, volume: 1) { second = $0 }
        await player.finished()
        #expect(first is CancellationError)
        #expect(endedCleanly(second))
        #expect(sink.scheduled.last?.samples[0] == Float("New.".count) / 100)
    }

    @Test func aFailingEngineReportsAndSilences() async {
        let sink = RecordingSink()
        let player = SpeechPlayer(sink: sink)
        var outcome: Error?
        player.say("Fine. Broken.", with: CountingEngine(failOn: "Broken."), style: style, volume: 1) { outcome = $0 }
        await player.finished()
        #expect((outcome as? UserFacingError)?.message == "The voice broke.")
        #expect(sink.stops >= 2)
        #expect(!player.isSpeaking)
    }

    @Test func nothingToSayEndsAtOnce() {
        let player = SpeechPlayer(sink: RecordingSink())
        var outcome: Error?? = .none
        player.say("   ", with: CountingEngine(), style: style, volume: 1) { outcome = $0 }
        #expect(endedCleanly(outcome))
        #expect(!player.isSpeaking)
    }
}
