import Foundation

/// The playback queue behind every engine (D34). A line is split into sentences; each is made while
/// the one before plays, so the first words start early. `stop()` silences it at once and drops the
/// rest: nothing stale is said afterwards.
@MainActor
public final class SpeechPlayer {
    private let sink: any AudioSink
    private var current: Task<Void, Never>?
    /// How the line being said now reports its end, exactly once.
    private var done: (@MainActor (Error?) -> Void)?
    /// Bumped by every `say` and `stop`, so a line that was cut off never reports twice.
    private var generation = 0
    public private(set) var isSpeaking = false
    /// The mouth follows this: 0...1 while audio plays, nil when it stops.
    public var onLevel: ((Float?) -> Void)?

    public init(sink: any AudioSink) {
        self.sink = sink
        sink.onLevel = { [weak self] level in self?.onLevel?(level) }
    }

    /// Says `text` with `engine`; anything still being said is cut off first. `done` is called once:
    /// nil when it played to the end, `CancellationError` when it was cut off, or the engine's error.
    public func say(_ text: String, with engine: any SpeechOutput, style: VoiceStyle, volume: Float,
                    done: (@MainActor (Error?) -> Void)? = nil) {
        stop()
        let sentences = Sentences.split(text)
        guard !sentences.isEmpty else {
            done?(nil)
            return
        }
        let mine = generation
        isSpeaking = true
        self.done = done
        let sink = self.sink
        current = Task { [weak self] in
            do {
                for sentence in sentences {
                    for try await piece in engine.audio(for: sentence, style: style) {
                        try Task.checkCancellation()
                        sink.schedule(piece, volume: volume)
                    }
                }
                try Task.checkCancellation()
                await sink.drained()
                guard !Task.isCancelled else { return }
                self?.ended(mine, error: nil)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self?.ended(mine, error: error)
            }
        }
    }

    /// Silence, now: the audio stops, the queue is emptied and the engine's work is cancelled.
    public func stop() {
        generation += 1
        current?.cancel()
        current = nil
        sink.stop()
        let cutOff = done
        done = nil
        if isSpeaking {
            isSpeaking = false
            onLevel?(nil)
        }
        cutOff?(CancellationError())
    }

    /// Waits until the line being said now has ended, however it ends.
    public func finished() async {
        await current?.value
    }

    private func ended(_ generation: Int, error: Error?) {
        guard generation == self.generation else { return }
        isSpeaking = false
        current = nil
        if error != nil { sink.stop() }
        onLevel?(nil)
        let report = done
        done = nil
        report?(error)
    }
}
