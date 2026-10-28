import Foundation

/// "new conversation", "start fresh", "forget this conversation": the next request starts a new conversation with the
/// AI (D45), at once and without it. Whole sentences only: "start over the report from scratch" or "a new chat app idea"
/// are something else. Deleting history is never done from words; Home › Conversations and Settings › Privacy ask first.
extension IntentParser {
    private static let fresh = IntentPattern(
        #"(?:let'?s\s+|i\s+want\s+to\s+|i'?d\s+like\s+to\s+)?"#
            + #"(?:(?:start|begin|open)\s+(?:a\s+)?(?:new|fresh)\s+(?:conversation|chat|topic|thread)|(?:a\s+)?(?:new|fresh)\s+(?:conversation|chat|topic|thread)"#
            + #"|start\s+(?:fresh|over|again|anew)|(?:change|switch)\s+(?:the\s+)?(?:topic|subject)"#
            + #"|(?:forget|clear|reset|end)\s+(?:this|the|our|that)\s+(?:conversation|chat|thread))"#
            + #"(?:\s+please)?"#)

    func conversation(_ command: String) -> ParsedIntent? {
        let text = command.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: " !."))
        guard Self.fresh.match(text) != nil else { return nil }
        return ParsedIntent(intent: .newConversation, hint: ParsedIntent.hint(String(localized: "Start a new conversation")))
    }
}
