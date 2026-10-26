#if DEBUG
import AppKit
import AVFoundation
import Speech
import SidefolkCore

/// Voice without a microphone or speakers, for agents and checks by hand (D34). Nothing is stored
/// and no permission is asked:
///
/// - `SidefolkApp --voice-install fr-FR`: downloads a language's speech model, with progress, as
///   Settings › Voice does.
/// - `SidefolkApp --voice-transcribe <audio file> [--language fr-FR]`: the file goes through the same
///   recognizer and format conversion as the microphone, at the pace it was spoken; prints the words
///   as they firm up, what was heard, and what releasing the talk key would do.
/// - `SidefolkApp --voice-say "<answer>" <out.caf> [--language en-US] [--voice <id>] [--rate 1]`: the
///   line the companion would say for that answer, through the Apple engine and the playback queue,
///   into a file instead of the speakers, with the levels the mouth would follow.
///
/// Try: `say -o /tmp/x.aiff "remind me at 5 to stretch"`, then `--voice-transcribe /tmp/x.aiff`.
enum VoiceDev {
    static func runIfRequested() {
        let args = CommandLine.arguments
        let job: (() async throws -> Void)?
        if let i = args.firstIndex(of: "--voice-install"), i + 1 < args.count {
            job = { try await install(args[i + 1]) }
        } else if let i = args.firstIndex(of: "--voice-transcribe"), i + 1 < args.count {
            job = { try await transcribe(URL(fileURLWithPath: args[i + 1]), language: value("--language", in: args)) }
        } else if let i = args.firstIndex(of: "--voice-say"), i + 2 < args.count {
            job = {
                try await say(args[i + 1], to: URL(fileURLWithPath: args[i + 2]), language: value("--language", in: args),
                              voice: value("--voice", in: args) ?? "", rate: value("--rate", in: args).flatMap(Double.init) ?? 1)
            }
        } else {
            job = nil
        }
        guard let job else { return }
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task {
            do {
                try await job()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("voice dev failed: \(error)\n".utf8))
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    private static func value(_ flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    // MARK: Listening

    /// What Settings › Voice › Download does: macOS fetches the language's model into its own storage.
    private static func install(_ language: String) async throws {
        print("language: \(language) · \(await Recognition.status(language))")
        var shown = -10
        try await Recognition.install(language) { fraction in
            let percent = Int(fraction * 100)
            guard percent / 10 != shown / 10 else { return }
            shown = percent
            print("downloading… \(percent)%")
        }
        print("now: \(await Recognition.status(language))")
    }

    private static func transcribe(_ file: URL, language: String?) async throws {
        print("language: \(Recognition.locale(for: language).identifier(.bcp47)) · \(await Recognition.status(language))")
        let recognizer = try await Recognition.make(language)
        if recognizer is BasicRecognizer, SFSpeechRecognizer.authorizationStatus() != .authorized {
            print("basic recognition needs the speech-recognition permission; it isn't asked from the command line")
            return
        }
        let started = Date()
        var last = ""
        try await recognizer.start { words in
            guard words != last else { return }
            last = words
            print(String(format: "%5.2fs  … %@", Date().timeIntervalSince(started), words))
        }
        try await VoiceController.play(file, into: recognizer)
        let released = Date()
        let heard = await recognizer.finish()
        print(String(format: "heard (%.2fs after release): %@", Date().timeIntervalSince(released), heard))
        guard let words = VoicePolicy.usableTranscript(heard) else {
            print("release: nothing sent (empty or too short); the panel says it didn't catch that")
            return
        }
        let hint = IntentParser().parse(words, now: Date(), knownCollections: [])?.hint ?? "needs AI"
        print("release: sends “\(words)” · \(hint)")
    }

    // MARK: Speaking

    private static func say(_ answer: String, to out: URL, language: String?, voice: String, rate: Double) async throws {
        let line = SpokenLine.answer(answer)
        let sink = FileSink(url: out)
        let player = SpeechPlayer(sink: sink)
        var levels: [Float] = []
        player.onLevel = { level in if let level { levels.append(level) } }
        var failure: Error?
        let style = VoiceStyle(voice: voice, language: language ?? VoiceController.language(of: line), rate: rate)
        let voiceName = AppleVoice.voice(id: voice, language: style.language).map { "\($0.name) (\($0.language), quality \($0.quality.rawValue))" } ?? "none"
        let started = Date()
        player.say(line, with: AppleVoice(), style: style, volume: 1) { failure = $0 }
        await player.finished()
        if let failure { throw failure }
        let seconds = try sink.close()
        print("said: \(line)")
        print("voice: \(voiceName)")
        print(String(format: "wrote %@: %.2fs of audio, made in %.2fs", out.path, seconds, Date().timeIntervalSince(started)))
        let opened = levels.filter { $0 > 0.3 }.count
        print("mouth: \(levels.count) level updates, open (> 0.3) in \(opened), peak \(String(format: "%.2f", levels.max() ?? 0))")
    }
}

/// The playback queue's sink, writing to a file: what the speakers would have played.
private final class FileSink: AudioSink {
    private let url: URL
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var rate = 0.0
    var onLevel: ((Float?) -> Void)?

    init(url: URL) { self.url = url }

    func schedule(_ audio: VoiceAudio, volume: Float) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: audio.sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)) else { return }
        if file == nil {
            file = try? AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            rate = audio.sampleRate
        }
        guard audio.sampleRate == rate else { return }
        audio.samples.withUnsafeBufferPointer { buffer.floatChannelData?[0].update(from: $0.baseAddress!, count: $0.count) }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        try? file?.write(from: buffer)
        frames += AVAudioFramePosition(audio.samples.count)
        // The same loudness scale the player's meter uses, per block of 1024.
        for start in stride(from: 0, to: audio.samples.count, by: 1024) {
            let block = audio.samples[start..<min(start + 1024, audio.samples.count)]
            let rms = (block.reduce(0) { $0 + $1 * $1 } / Float(block.count)).squareRoot()
            onLevel?(min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 40)))
        }
    }

    func drained() async {}

    func stop() {}

    /// Seconds written.
    func close() throws -> Double {
        file = nil
        return rate > 0 ? Double(frames) / rate : 0
    }
}
#endif
