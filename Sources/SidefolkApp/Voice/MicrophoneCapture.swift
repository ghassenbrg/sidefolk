import AVFoundation
import AudioToolbox

/// The microphone, on only while the talk key is held (D34), so the orange dot macOS shows is an
/// honest sign that the companion is listening. Prefers the Mac's own microphone, and rebuilds itself
/// when the audio hardware changes underneath it (a headset plugged in, a format change).
final class MicrophoneCapture {
    enum Failure: Error {
        case noMicrophone
        case couldNotStart(Error)
    }

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
        if let device = AudioDevices.builtInInput(), let unit = input.audioUnit {
            var id = device
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.noMicrophone }
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tap(deliver))
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
    nonisolated private static func tap(_ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in deliver(buffer) }
    }
}
