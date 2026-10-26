import Foundation

/// When the companion answers aloud (D34).
public enum SpokenReplies: String, Codable, Sendable, CaseIterable {
    case off
    /// Only to a request the person just spoke; typed requests get text, as before.
    case whenSpoken
    case always
}

/// Which key is held to talk (D34).
public enum TalkKey: String, Codable, Sendable, CaseIterable {
    /// Tap the Ask shortcut to open the panel, hold it to talk.
    case askShortcut
    /// A shortcut of its own, which opens the microphone the moment it goes down.
    case ownShortcut
}

/// Where the spoken replies' voice comes from. Each says plainly what it sends and where.
public enum VoiceEngine: String, Codable, Sendable, CaseIterable {
    /// AVSpeechSynthesizer: on this Mac, nothing sent anywhere.
    case apple
    /// The person's own ElevenLabs key: the words go to api.elevenlabs.io.
    case elevenLabs
}

/// Settings › Voice. Off by default: the microphone is only ever used after the person turns it on.
public struct VoiceSettings: Codable, Sendable, Equatable {
    public var input = false
    public var talkKey: TalkKey = .askShortcut
    /// A BCP 47 locale ("fr-FR") to listen in; nil follows the app's language.
    public var language: String?
    public var replies: SpokenReplies = .whenSpoken
    public var engine: VoiceEngine = .apple
    /// An `AVSpeechSynthesisVoice` identifier; empty picks the best installed voice for the language.
    public var appleVoice = ""
    public var elevenLabsVoice = ""
    /// Shown in Settings without asking ElevenLabs again.
    public var elevenLabsVoiceName = ""
    /// 1 is the engine's normal pace; 0.75...1.5.
    public var rate = 1.0
    /// 0...1, on top of the Mac's own volume.
    public var volume = 0.8

    public init() {}

    public static let rates = 0.75...1.5

    enum CodingKeys: String, CodingKey {
        case input, talkKey, language, replies, engine, appleVoice, elevenLabsVoice, elevenLabsVoiceName, rate, volume
    }

    /// Every field has a default, so settings written by another version still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ into: inout T) { if let v = try? c.decode(T.self, forKey: key) { into = v } }
        read(.input, &input)
        read(.talkKey, &talkKey)
        language = try? c.decodeIfPresent(String.self, forKey: .language)
        read(.replies, &replies)
        read(.engine, &engine)
        read(.appleVoice, &appleVoice)
        read(.elevenLabsVoice, &elevenLabsVoice)
        read(.elevenLabsVoiceName, &elevenLabsVoiceName)
        read(.rate, &rate)
        read(.volume, &volume)
        rate = min(max(rate, Self.rates.lowerBound), Self.rates.upperBound)
        volume = min(max(volume, 0), 1)
    }
}
