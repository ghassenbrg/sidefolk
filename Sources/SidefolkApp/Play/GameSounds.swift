import AVFoundation
import SidefolkCore

/// The app's game sounds (D75): short and soft, made here from a few tones and a little noise rather than shipped as
/// files, so they cost nothing to bundle and every one is Sidefolk's own. Extensions only name them; they play at one
/// fixed volume, never in Quiet mode, over a fullscreen app, or when macOS's "Play user interface sound effects" is off.
@MainActor
final class GameSounds {
    static let shared = GameSounds()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var made: [GameSound: AVAudioPCMBuffer] = [:]
    private var started = false
    static let volume: Float = 0.35

    /// Whether the Mac allows interface sounds at all (System Settings › Sound › Play user interface sound effects).
    static var interfaceSoundsOn: Bool {
        UserDefaults(suiteName: "com.apple.systemsound")?.object(forKey: "com.apple.sound.uiaudio.enabled") as? Bool ?? true
    }

    func play(_ sound: GameSound) {
        guard Self.interfaceSoundsOn else { return }
        if !started {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = Self.volume
            guard (try? engine.start()) != nil else { return }
            player.play()
            started = true
        }
        let buffer = made[sound] ?? make(sound)
        made[sound] = buffer
        player.scheduleBuffer(buffer, at: nil, options: [])
    }

    /// A note: its pitch (Hz, gliding to `to`), length, how hard it starts and how fast it fades, with a little noise.
    private struct Note {
        var at: Double
        var hz: Double
        var to: Double? = nil
        var length: Double
        var decay: Double = 12
        var noise: Double = 0
        var level: Double = 1
    }

    private func notes(_ sound: GameSound) -> [Note] {
        switch sound {
        case .tap: [Note(at: 0, hz: 1_400, length: 0.04, decay: 60, noise: 0.3, level: 0.6)]
        case .flip: [Note(at: 0, hz: 2_200, to: 3_400, length: 0.12, decay: 25, level: 0.5)]
        case .rattle: (0..<6).map { Note(at: Double($0) * 0.05, hz: 900 + Double($0 % 3) * 150, length: 0.03, decay: 80, noise: 0.8, level: 0.5) }
        case .pop: [Note(at: 0, hz: 500, to: 1_200, length: 0.07, decay: 40, level: 0.8)]
        case .ding: [Note(at: 0, hz: 1_568, length: 0.5, decay: 7), Note(at: 0, hz: 3_136, length: 0.3, decay: 12, level: 0.3)]
        case .boop: [Note(at: 0, hz: 440, to: 330, length: 0.16, decay: 14, level: 0.8)]
        case .tick: [Note(at: 0, hz: 2_600, length: 0.025, decay: 120, noise: 0.4, level: 0.5)]
        case .whoosh: [Note(at: 0, hz: 300, to: 900, length: 0.3, decay: 8, noise: 1, level: 0.35)]
        case .stamp: [Note(at: 0, hz: 160, to: 90, length: 0.12, decay: 30, noise: 0.5, level: 0.9)]
        case .shuffle: (0..<4).map { Note(at: Double($0) * 0.07, hz: 600, length: 0.06, decay: 50, noise: 1, level: 0.35) }
        case .snap: [Note(at: 0, hz: 2_000, to: 700, length: 0.05, decay: 70, noise: 0.6, level: 0.7)]
        case .cork: [Note(at: 0, hz: 700, to: 300, length: 0.09, decay: 35, level: 0.8)]
        case .fanfare: [Note(at: 0, hz: 523, length: 0.14), Note(at: 0.12, hz: 659, length: 0.14), Note(at: 0.24, hz: 784, length: 0.14),
                        Note(at: 0.36, hz: 1_047, length: 0.5, decay: 5)]
        case .trombone: [Note(at: 0, hz: 392, length: 0.25, decay: 4, level: 0.7), Note(at: 0.25, hz: 370, length: 0.25, decay: 4, level: 0.7),
                         Note(at: 0.5, hz: 349, length: 0.25, decay: 4, level: 0.7), Note(at: 0.75, hz: 330, to: 300, length: 0.7, decay: 3, level: 0.7)]
        }
    }

    private func make(_ sound: GameSound) -> AVAudioPCMBuffer {
        let notes = notes(sound)
        let rate = format.sampleRate
        let total = (notes.map { $0.at + $0.length }.max() ?? 0.1) + 0.02
        let frames = AVAudioFrameCount(total * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        var seed: UInt32 = 0x2545_F491
        for i in 0..<Int(frames) { out[i] = 0 }
        for note in notes {
            var phase = 0.0
            let start = Int(note.at * rate), count = Int(note.length * rate)
            for n in 0..<count where start + n < Int(frames) {
                let t = Double(n) / rate
                let hz = note.to.map { note.hz + ($0 - note.hz) * t / note.length } ?? note.hz
                phase += 2 * .pi * hz / rate
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Double(seed >> 8) / Double(1 << 24) * 2 - 1
                // A soft attack (no click), then the fade.
                let envelope = min(1, t / 0.004) * exp(-t * note.decay)
                let tone = sin(phase) * (1 - note.noise) + noise * note.noise
                out[start + n] += Float(tone * envelope * note.level * 0.5)
            }
        }
        return buffer
    }
}
