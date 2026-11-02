import AVFoundation
import SidefolkCore

/// A surface's sounds from its pack (D99): read and checked when first played, at one fixed volume and at most four a
/// second. The audio engine runs only while something plays, as for the app's own sounds (D34: an engine left up keeps the
/// output busy, and silenced spoken replies).
@MainActor
final class SurfaceSounds {
    static let shared = SurfaceSounds()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var limiter = CueLimiter()
    private var wired = false
    private var busyUntil = Date.distantPast
    private var idle: Task<Void, Never>?

    func play(_ path: String, from reader: PackAssetReader) {
        guard limiter.sound(at: Date()), GameSounds.interfaceSoundsOn else { return }
        let key = reader.root + "/" + path
        guard let buffer = buffers[key] ?? load(path, reader) else { return }
        buffers[key] = buffer
        if !wired {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = GameSounds.volume
            wired = true
        }
        if !engine.isRunning { guard (try? engine.start()) != nil else { return } }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: [])
        busyUntil = max(busyUntil, Date()).addingTimeInterval(Double(buffer.frameLength) / format.sampleRate)
        idle?.cancel()
        let wait = busyUntil.timeIntervalSinceNow
        idle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait) + GameSounds.linger)
            guard !Task.isCancelled, let self else { return }
            self.player.stop()
            self.engine.stop()
        }
    }

    /// Forgets a pack's sounds when its surface closes.
    func forget(_ reader: PackAssetReader) {
        buffers = buffers.filter { !$0.key.hasPrefix(reader.root + "/") }
    }

    /// In the mixer's format, so one player takes every file; a file that can't be read plays nothing.
    private func load(_ path: String, _ reader: PackAssetReader) -> AVAudioPCMBuffer? {
        guard let url = reader.soundURL(path), let file = try? AVAudioFile(forReading: url),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: source)) != nil, let converter = AVAudioConverter(from: file.processingFormat, to: format) else { return nil }
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024) else { return nil }
        nonisolated(unsafe) var given = false
        nonisolated(unsafe) let input = source
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if given {
                status.pointee = .endOfStream
                return nil
            }
            given = true
            status.pointee = .haveData
            return input
        }
        return error == nil ? out : nil
    }
}
