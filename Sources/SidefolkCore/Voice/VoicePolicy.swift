import Foundation

/// The rules for when the companion listens and when it speaks (D34). Pure, so they are tested.
public enum VoicePolicy {
    /// Hesitations heard on their own, in the app's languages. A press that caught only one of these
    /// sends nothing (an accidental press must not spend AI quota).
    static let fillers: Set<String> = ["uh", "um", "umm", "hmm", "hm", "mm", "mhm", "er", "erm", "ah", "eh", "oh", "euh", "äh", "ähm",
                                       "eto", "えーと", "えっと", "あの", "음", "어", "嗯", "呃", "اه", "امم"]

    /// What a released talk key sends, or nil when nothing worth sending was heard.
    public static func usableTranscript(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = trimmed.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        let letters = bare.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        guard letters >= 2, !fillers.contains(bare) else { return nil }
        return trimmed
    }

    /// Why a reply that would have been spoken stayed text.
    public enum Silence: String, Sendable, Equatable {
        /// Quiet mode is on.
        case quiet
        /// Another app has the microphone open (a call, a recording).
        case micInUse
        /// The person started typing again after asking.
        case typing
    }

    /// Whether a program with the microphone running is someone recording (a call, a voice memo, a screen recording
    /// with sound), which keeps the companion silent, rather than one of macOS's own background services. Siri's voice
    /// trigger (corespeechd, in /System/Library) runs the microphone whenever anything plays, to hear past it: counting
    /// it muted every reply while a game's sounds, music or a video played. Apps count wherever they live, Apple's
    /// own included (FaceTime, Voice Memos, screencaptureui), and so does /usr/libexec's avconferenced, which carries
    /// FaceTime's calls. An unknown program counts, so a call is never talked over.
    public static func recordsElsewhere(executable path: String?) -> Bool {
        guard let path else { return true }
        return !path.hasPrefix("/System/Library/") || path.contains(".app/")
    }

    /// The person typed after asking: words in the box, or a key pressed anywhere since the request (they went back
    /// to work). The talk key itself (pressed, repeated while held) and Return for a typed request come before the
    /// request; a quarter of a second of slack covers the request being stamped a moment after them.
    /// - Parameters:
    ///   - secondsSinceKey: since the last key went down anywhere on the Mac.
    ///   - secondsSinceRequest: since the request was sent.
    public static func typedSince(boxHasWords: Bool, secondsSinceKey: TimeInterval, secondsSinceRequest: TimeInterval) -> Bool {
        boxHasWords || secondsSinceKey < secondsSinceRequest - 0.25
    }

    public enum Decision: Sendable, Equatable {
        /// No spoken reply was asked for (replies off, or a typed request without "Always").
        case none
        case speak
        /// VoiceOver is running: it reads the line in the person's own voice settings instead.
        case announce
        /// Would have spoken; the words are shown with a muted speaker.
        case muted(Silence)
    }

    public static func reply(spokenRequest: Bool, replies: SpokenReplies, quiet: Bool, micInUseElsewhere: Bool, typedSince: Bool,
                             voiceOver: Bool) -> Decision {
        switch replies {
        case .off: return .none
        case .whenSpoken where !spokenRequest: return .none
        default: break
        }
        if quiet { return .muted(.quiet) }
        if micInUseElsewhere { return .muted(.micInUse) }
        if typedSince { return .muted(.typing) }
        return voiceOver ? .announce : .speak
    }
}
