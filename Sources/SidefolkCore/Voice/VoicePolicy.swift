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
