import AVFoundation
import SidefolkCore

/// Plays spoken replies: one player node on an engine that runs only while there is something to
/// say, so nothing is open on the audio hardware (and nothing measures levels) once speech ends.
/// Its levels drive the companion's mouth.
final class AudioPlayer: AudioSink {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    /// Buffers scheduled and not played yet.
    private var pending = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Bumped by `stop()`, so callbacks from dropped buffers are ignored.
    private var generation = 0
    private var observer: NSObjectProtocol?
    var onLevel: ((Float?) -> Void)?

    init() {
        engine.attach(node)
        // The output device changed under the engine (headphones in or out): what was playing is lost.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func schedule(_ audio: VoiceAudio, volume: Float) {
        guard !audio.samples.isEmpty, let buffer = prepare(sampleRate: audio.sampleRate, frames: audio.samples.count) else { return }
        audio.samples.withUnsafeBufferPointer { samples in
            buffer.floatChannelData?[0].update(from: samples.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        node.volume = volume
        pending += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack, completionHandler: Self.played(generation, self))
        if !node.isPlaying { node.play() }
    }

    func drained() async {
        guard pending > 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func stop() {
        generation += 1
        if engine.isRunning {
            node.stop()
            node.removeTap(onBus: 0)
            engine.stop()
        }
        pending = 0
        finishWaiting()
        onLevel?(nil)
    }

    /// The engine running in mono float at `sampleRate`, and an empty buffer to fill.
    private func prepare(sampleRate: Double, frames: Int) -> AVAudioPCMBuffer? {
        guard let wanted = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return nil }
        if format != wanted || !engine.isRunning {
            if engine.isRunning {
                node.stop()
                node.removeTap(onBus: 0)
                engine.stop()
            }
            engine.connect(node, to: engine.mainMixerNode, format: wanted)
            node.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.meter(self, generation))
            format = wanted
            do {
                try engine.start()
            } catch {
                Log.shared.error("voice", "audio output didn't start", ["error": String(describing: error)])
                return nil
            }
        }
        return AVAudioPCMBuffer(pcmFormat: wanted, frameCapacity: AVAudioFrameCount(frames))
    }

    private func didPlay(_ generation: Int) {
        guard generation == self.generation else { return }
        pending = max(0, pending - 1)
        guard pending == 0 else { return }
        // Done talking: let the hardware go.
        node.stop()
        node.removeTap(onBus: 0)
        engine.stop()
        onLevel?(nil)
        finishWaiting()
    }

    private func finishWaiting() {
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume() }
    }

    private func heard(_ level: Float, _ generation: Int) {
        guard generation == self.generation, pending > 0 else { return }
        onLevel?(level)
    }

    // Built outside the main actor: Core Audio calls these on its own threads.

    nonisolated private static func played(_ generation: Int, _ player: AudioPlayer) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { [weak player] _ in Task { @MainActor in player?.didPlay(generation) } }
    }

    /// Loudness of each block as it plays, mapped from about -50…-10 dBFS to 0…1.
    nonisolated private static func meter(_ player: AudioPlayer, _ generation: Int) -> AVAudioNodeTapBlock {
        { [weak player] buffer, _ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
            let rms = (sum / Float(buffer.frameLength)).squareRoot()
            let level = min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 40))
            Task { @MainActor in player?.heard(level, generation) }
        }
    }
}
