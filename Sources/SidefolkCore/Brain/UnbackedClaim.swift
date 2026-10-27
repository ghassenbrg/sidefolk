import Foundation

/// A reply that says something was done, or is about to be, from a run that called no tool. Nothing
/// happened, and the person would wait for it: gemma on Ollama answered "I'll show you the temperature
/// in Fukuoka every minute" and never called watch.report. The loop then asks the model once more.
/// English only, the words models slip into; a reply in another language passes as it is.
enum UnbackedClaim {
    /// "I'll show…", "I've set…", "I'm watching…", "Reminder set", "Done."
    private static let patterns = [
        #"\b(?:i'll|i will|i'm going to|i am going to|i've|i have|i'm|i am)\s+(?:also\s+|now\s+|just\s+|go ahead and\s+)?"#
            + #"(?:show(?:ing|n)?|display(?:ing|ed)?|remind(?:ing|ed)?|watch(?:ing|ed)?|track(?:ing|ed)?|monitor(?:ing|ed)?|"#
            + #"notify(?:ing)?|notified|alert(?:ing|ed)?|ping(?:ing|ed)?|let you know|keep(?:ing)? (?:an eye|you posted|you updated)|"#
            + #"sav(?:e|ed|ing)|add(?:ed|ing)?|creat(?:e|ed|ing)|set(?:ting)? (?:up |a |an |the |it|you|that|this|your)|"#
            + #"schedul(?:e|ed|ing)|start(?:ed|ing)? (?:a |an |the |watching|showing|tracking|reporting)|not(?:e|ed|ing)|"#
            + #"remember(?:ed|ing)?|report(?:ed|ing)?|turn(?:ed|ing)? (?:on|off)|stopp?(?:ed|ing)? (?:the|it|that|this|your|watching|showing)|"#
            + #"cancel(?:l?ed|l?ing)? (?:the|it|that|this|your)|delet(?:e|ed|ing)|remov(?:e|ed|ing)|sen(?:d|t|ding) (?:you|it|the|a))\b"#,
        #"\b(?:reminder|watch|watcher|note|timer|alarm|report)\s+(?:is\s+|has been\s+)?(?:set|saved|created|added|scheduled|started)\b"#,
        #"^\s*(?:done|all set)\b"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive, .anchorsMatchLines]) }

    static func found(in reply: String) -> Bool {
        let text = reply.replacingOccurrences(of: "\u{2019}", with: "'")
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    /// Sent as the user's turn, never shown: the model either acts now or says plainly what it can't do.
    static let nudge = """
        Your last reply says something was done or will be done, but you called no tool, so nothing happened. \
        If one of your tools does what the user asked, call it now. Otherwise reply again without saying anything \
        was or will be done: say plainly what you can't do, or ask for what you need.
        """
}
