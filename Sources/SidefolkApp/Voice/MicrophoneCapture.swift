import Accelerate
import AVFoundation
import SidefolkCore
import Synchronization

/// The microphone, on only while the talk key is held (D34), so the orange dot macOS shows is an
/// honest sign that the companion is listening. It listens through the input chosen in System
/// Settings › Sound, and rebuilds itself when the audio hardware changes underneath it (a headset
/// plugged in, a format change) or when the microphone sends nothing at all.
final class MicrophoneCapture {
    enum Failure: Error {
        case noMicrophone
        case couldNotStart(Error)
    }

    /// What the microphone delivered since the key went down: for the log, and to tell silence from
    /// words the recognizer missed. Never what was said.
    let meter = MicrophoneMeter()
    private var engine: AVAudioEngine?
    private var deliver: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var observer: NSObjectProtocol?
    private var stallCheck: Task<Void, Never>?
    /// Rebuilds in this press: a device that keeps changing must not keep the microphone cycling.
    private var rebuilds = 0
    /// The hardware changed and the microphone couldn't be opened again.
    var onLost: (() -> Void)?

    /// Starts sending the microphone's audio to `deliver`, on the audio thread, in its own format.
    func start(_ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        stop()
        self.deliver = deliver
        rebuilds = 0
        try open()
    }

    func stop() {
        close()
        deliver = nil
    }

    private func open() throws {
        guard let deliver else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Pointing the engine's audio unit at a microphone by hand left the tap without a single buffer
        // in build 404, even for the default microphone: the engine opens the default input on its own.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.noMicrophone }
        meter.opened(device: AudioDevices.defaultInput().flatMap(AudioDevices.name) ?? String(localized: "the microphone", comment: "Stands in for a microphone's name after “from”: “I only heard silence from the microphone”"),
                     format: "\(Int(format.sampleRate)) Hz, \(format.channelCount) ch\(format.isInterleaved ? ", interleaved" : "")")
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tap(deliver, meter: meter))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.couldNotStart(error)
        }
        self.engine = engine
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reopen() }
        }
        // A buffer comes every tenth of a second or so; none in a second is a microphone that never started.
        let opened = meter.reading.opens
        stallCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.meter.reading.buffers == 0, self.meter.reading.opens == opened else { return }
            Log.shared.info("voice", "microphone silent, reopening", ["opens": "\(opened)"])
            self.reopen()
        }
    }

    private func close() {
        stallCheck?.cancel()
        stallCheck = nil
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    /// The device or its format changed, or nothing came: a fresh engine on whatever is there now.
    private func reopen() {
        guard engine != nil, rebuilds < 3 else { return }
        rebuilds += 1
        close()
        do { try open() } catch { onLost?() }
    }

    /// Built outside the main actor: Core Audio calls it on its own thread.
    nonisolated private static func tap(_ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                                        meter: MicrophoneMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            meter.measure(buffer)
            deliver(buffer)
        }
    }
}

/// How much audio arrived and how loud it got, measured on the audio thread.
nonisolated final class MicrophoneMeter: Sendable {
    struct Reading: Sendable {
        var device = ""
        var format = ""
        /// Times the microphone was opened in this press (0: let go before it opened).
        var opens = 0
        var buffers = 0
        var seconds = 0.0
        /// From the first opening to the first sound, for the log.
        var waited: Duration?
        /// The loudest sample, 0...1 (full scale).
        var peak: Float = 0
        /// Below about -60 dBFS: a muted, switched-off or wrong microphone, not a quiet voice.
        var silent: Bool { buffers > 0 && peak < 0.001 }
    }

    private let state = Mutex(Reading())
    private let started = Mutex<ContinuousClock.Instant?>(nil)

    var reading: Reading { state.withLock { $0 } }

    /// The key went down: nothing heard yet.
    func reset() {
        state.withLock { $0 = Reading() }
        started.withLock { $0 = nil }
    }

    func opened(device: String, format: String) {
        started.withLock { $0 = $0 ?? .now }
        state.withLock { $0.device = device; $0.format = format; $0.opens += 1 }
    }

    func measure(_ buffer: AVAudioPCMBuffer) {
        var loudest: Float = 0
        if let channels = buffer.floatChannelData {
            let interleaved = buffer.format.isInterleaved
            let planes = interleaved ? 1 : Int(buffer.format.channelCount)
            let count = vDSP_Length(Int(buffer.frameLength) * (interleaved ? Int(buffer.format.channelCount) : 1))
            for plane in 0..<planes {
                var peak: Float = 0
                vDSP_maxmgv(channels[plane], 1, &peak, count)
                loudest = max(loudest, peak)
            }
        }
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        let since = started.withLock { $0.map { ContinuousClock.now - $0 } }
        state.withLock {
            if $0.buffers == 0 { $0.waited = since }
            $0.buffers += 1
            $0.seconds += seconds
            $0.peak = max($0.peak, loudest)
        }
    }
}
