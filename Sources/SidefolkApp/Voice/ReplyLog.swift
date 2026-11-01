import AVFoundation
import SidefolkCore

/// One log line for every spoken-reply decision and one for how its playback ended, counts and settings
/// only, never the words (D34), so a report of "no voice" can be read from the log alone: whether the
/// reply was to be said, why it stayed silent, which engine and voice said it in which language, how much
/// audio reached the speakers and whether it played to the end.
enum ReplyLog {
    /// What `typedSince` saw: words left in the box, or a key pressed after the request.
    struct Typing {
        var typed: Bool
        var boxHasWords: Bool
        /// Seconds since the last key down anywhere on the Mac.
        var keyAgo: TimeInterval
        /// Seconds since the request was sent.
        var askedAgo: TimeInterval
    }

    static func decided(_ decision: VoicePolicy.Decision, line: String, context: ReplyContext, voice: VoiceSettings, typing: Typing,
                        microphone: (recording: [String], listening: [String])) {
        let name: String
        var why: String?
        switch decision {
        case .none: name = "none"
        case .speak: name = "speak"
        case .announce: name = "voiceover"
        case .muted(let silence):
            name = "muted"
            why = silence.rawValue
        }
        var fields = facts(line: line, context: context, voice: voice)
        fields["why"] = why
        fields["box_has_words"] = "\(typing.boxHasWords)"
        fields["key_ago_s"] = seconds(typing.keyAgo)
        fields["asked_ago_s"] = seconds(typing.askedAgo)
        // Programs, never words: who kept it silent, and macOS's own listeners that didn't.
        if !microphone.recording.isEmpty { fields["mic_recording"] = microphone.recording.joined(separator: ",") }
        if !microphone.listening.isEmpty { fields["mic_listening"] = microphone.listening.joined(separator: ",") }
        Log.shared.info("voice", "reply \(name)", fields)
    }

    /// A reply that never reached the policy (`interrupted`: something silenced it after the request).
    static func decided(_ name: String, line: String, context: ReplyContext, voice: VoiceSettings) {
        Log.shared.info("voice", "reply \(name)", facts(line: line, context: context, voice: voice))
    }

    /// The engine, the voice that will really say the line (the chosen one when it speaks the line's
    /// language, else the best installed for it) and the output device.
    static func saying(_ line: String, engine: VoiceEngine, style: VoiceStyle, models: [String], volume: Double) {
        var fields = ["engine": engine.rawValue, "line_language": style.language, "characters": "\(line.count)",
                      "sentences": "\(Sentences.split(line).count)", "volume": String(format: "%.2f", volume),
                      "output": AudioDevices.defaultOutput().flatMap(AudioDevices.name) ?? "none"]
        switch engine {
        case .apple:
            let voice = AppleVoice.voice(id: style.voice, language: style.language)
            fields["chosen_voice"] = style.voice.isEmpty ? "default" : style.voice
            fields["voice"] = voice?.identifier ?? "none"
            fields["voice_language"] = voice?.language ?? "none"
        case .elevenLabs:
            fields["voice"] = style.voice
            fields["models"] = models.joined(separator: ",")
        }
        Log.shared.info("voice", "reply saying", fields)
    }

    /// How the line ended: played to the end, cut off, or failed, and how much audio was made.
    @MainActor
    static func ended(_ error: Error?, player: SpeechPlayer, started: Date) {
        var fields = ["pieces": "\(player.scheduled.pieces)", "audio_s": seconds(player.scheduled.seconds),
                      "after_s": seconds(Date().timeIntervalSince(started))]
        switch error {
        case nil:
            Log.shared.info("voice", player.scheduled.pieces == 0 ? "reply made no audio" : "reply played", fields)
        case is CancellationError:
            Log.shared.info("voice", "reply cut off", fields)
        case let error?:
            fields["error"] = (error as? UserFacingError).map { [$0.message, $0.detail].compactMap { $0 }.joined(separator: " · ") }
                ?? String(describing: error)
            Log.shared.error("voice", "reply failed", fields)
        }
    }

    private static func facts(line: String, context: ReplyContext, voice: VoiceSettings) -> [String: String] {
        ["spoken_request": "\(context.spoken)", "replies": voice.replies.rawValue, "length": voice.length.rawValue,
         "engine": voice.engine.rawValue, "characters": "\(line.count)", "line_language": VoiceController.language(of: line),
         "app_language": AppLanguage.current]
    }

    private static func seconds(_ value: TimeInterval) -> String {
        value > 1e6 ? "never" : String(format: "%.2f", value)
    }
}
