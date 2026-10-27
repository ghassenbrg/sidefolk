import Foundation

/// "dance!", "do a trick", "take a bow", "let's play catch", "breathe with me": playing with the companion (D44),
/// right away and without AI. Whole sentences only, like the rest of the parser: "dance music for the party" and
/// "wave goodbye to Friday's meeting" are not for it.
extension IntentParser {
    private static let tricks: [(IntentPattern, CompanionAct)] = ([
        (#"(?:do\s+(?:a|the|your|some|a\s+little|a\s+happy)\s+)?dance(?:\s+(?:for|with)\s+me)?(?:\s+again)?"#, .dance),
        (#"(?:let'?s\s+)?(?:dance|have\s+a\s+dance)(?:\s+together)?"#, .dance),
        (#"wave(?:\s+(?:at|to)\s+me|\s+hello|\s+hi)?(?:\s+again)?"#, .wave),
        (#"(?:take\s+a\s+|do\s+a\s+)?bow(?:\s+(?:for|to)\s+me)?"#, .bow),
        (#"(?:do\s+a\s+)?(?:back)?(?:flip|somersault|spin)(?:\s+for\s+me)?(?:\s+again)?"#, .flip),
        (#"(?:do\s+a\s+)?(?:hop|jump)(?:\s+for\s+me)?(?:\s+again)?"#, .hop),
        (#"cheer(?:\s+(?:for|with)\s+me)?|celebrate(?:\s+with\s+me)?|(?:let'?s\s+)?celebrate"#, .cheer),
        (#"nod(?:\s+(?:at|to)\s+me)?"#, .nod),
        (#"giggle|laugh(?:\s+with\s+me)?"#, .giggle),
        (#"(?:do|show\s+me)\s+(?:a|your|another)\s+trick|(?:do\s+)?something\s+(?:funny|fun|cute)|make\s+me\s+(?:laugh|smile)|entertain\s+me"#, .trick),
        (#"(?:let'?s\s+|i\s+want\s+to\s+)?play\s+(?:catch(?:\s+me)?|tag|chase)(?:\s+with\s+me)?|catch\s+me\s+if\s+you\s+can"#, .catchMe),
        (#"(?:let'?s\s+)?(?:breathe|do\s+(?:a\s+|some\s+)?breathing(?:\s+exercise)?)(?:\s+(?:with|together|for)\s+me|\s+together)?|"#
            + #"breathe\s+with\s+me|help\s+me\s+(?:relax|breathe|calm\s+down)|i\s+(?:need|want)\s+to\s+(?:relax|calm\s+down|breathe)"#, .breathe),
    ] as [(String, CompanionAct)]).map { (IntentPattern($0.0), $0.1) }

    func play(_ command: String) -> ParsedIntent? {
        let text = command.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: " !."))
        guard let act = Self.tricks.first(where: { $0.0.match(text) != nil })?.1 else { return nil }
        return ParsedIntent(intent: .companion(act), hint: ParsedIntent.hint(act.title))
    }
}
