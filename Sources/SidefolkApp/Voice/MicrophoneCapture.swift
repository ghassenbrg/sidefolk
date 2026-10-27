import Accelerate
import AVFoundation
import AudioToolbox
import Synchronization

/// The microphone, on only while the talk key is held (D34), so the orange dot macOS shows is an
/// honest sign that the companion is listening. Prefers the Mac's own microphone, and rebuilds itself
/// when the audio hardware changes underneath it (a headset plugged in, a format change).
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
    /// The hardware changed and the microphone couldn't be opened again.
    var onLost: (() -> Void)?

    /// Starts sending the microphone's audio to `deliver`, on the audio thread, in its own format.
    func start(_ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        stop()
        self.deliver = deliver
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
        var chosen = AudioDevices.defaultInput()
        if let device = AudioDevices.builtInInput(), let unit = input.audioUnit {
            var id = device
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
            chosen = device
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.noMicrophone }
        meter.opened(device: chosen.flatMap(AudioDevices.name) ?? String(localized: "the microphone"),
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
    }

    private func close() {
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    /// The device or its format changed: a fresh engine on whatever is there now.
    private func reopen() {
        guard engine != nil else { return }
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
        var buffers = 0
        var seconds = 0.0
        /// The loudest sample, 0...1 (full scale).
        var peak: Float = 0
        /// Below about -60 dBFS: a muted, switched-off or wrong microphone, not a quiet voice.
        var silent: Bool { buffers > 0 && peak < 0.001 }
    }

    private let state = Mutex(Reading())

    var reading: Reading { state.withLock { $0 } }

    /// The key went down: nothing heard yet.
    func reset() { state.withLock { $0 = Reading() } }

    func opened(device: String, format: String) {
        state.withLock { $0.device = device; $0.format = format }
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
        state.withLock { $0.buffers += 1; $0.seconds += seconds; $0.peak = max($0.peak, loudest) }
    }
}
