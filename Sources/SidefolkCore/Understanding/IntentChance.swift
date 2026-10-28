import Foundation

/// "flip a coin", "heads or tails?", "roll 2 dice", "roll a d20", "rock paper scissors", and then just "rock": chance
/// played by the companion on the desktop (D44, amended), right away and without AI. Whole sentences only:
/// "flip a coin to decide where we eat tonight" and "rock music" are not for it.
extension IntentParser {
    private static let count = #"(?<n>\d{1,2}|two|three|four|five|six|seven|eight|nine|ten)"#
    private static let forMe = #"(?:\s+for\s+me)?(?:\s+again)?"#
    private static let hand = #"(?<hand>rock|paper|scissors)"#
    private static let rps = #"(?:rock[\s,]+paper[\s,]+(?:and\s+|or\s+)?scissors|rps)"#
    /// "I choose rock", "I'll go with paper", "my hand is scissors".
    private static let playing = #"(?:(?:i\s+(?:choose|pick|play|throw|go\s+with)|i'?ll\s+(?:play|pick|throw|go\s+with)|my\s+hand\s+is)\s+)?"#

    private static let coins = IntentPattern(
        #"(?:let'?s\s+)?(?:flip|toss)\s+(?:(?:a|one|the)\s+)?coin"# + forMe + #"|heads\s+or\s+tails|(?:do\s+a\s+)?coin\s+(?:flip|toss)"# + forMe
            + #"|(?:flip|toss)\s+"# + count + #"\s+coins"# + forMe)
    /// "roll a die", "roll a dice", "roll the die"; "roll dice" and "roll the dice" are two, as in most board games.
    private static let oneDie = IntentPattern(#"(?:let'?s\s+)?(?:roll|throw)\s+(?:(?:a|one)\s+(?:die|dice|d6)|the\s+(?:die|d6))"# + forMe)
    private static let twoDice = IntentPattern(#"(?:let'?s\s+)?(?:roll|throw)\s+(?:the\s+)?dice"# + forMe)
    /// "roll 3 dice", "roll two d20s".
    private static let someDice = IntentPattern(#"(?:roll|throw)\s+"# + count + #"\s+(?:dice|d(?<s>\d{1,3})s?)"# + forMe)
    /// "roll a d20", "roll 2d6+1", "roll a 20-sided die".
    private static let notation = IntentPattern(
        #"(?:roll|throw)\s+(?:(?:a|an|one)\s+)?(?<n>\d{1,2})?d(?<s>\d{1,3})(?:\s*(?<m>[+-]\s*\d{1,3}))?"# + forMe
            + #"|(?:roll|throw)\s+(?:a|an|one)\s+(?<sides>\d{1,3})[\s-]sided\s+(?:die|dice)"# + forMe)
    private static let handsAsked = IntentPattern(#"(?:(?:let'?s|i\s+want\s+to)\s+)?(?:play\s+)?"# + rps + #"(?:\s+with\s+me)?"#)
    private static let handPlayed = IntentPattern(
        #"(?:(?:let'?s\s+)?(?:play\s+)?"# + rps + #"\s*[,:!\-–—]?\s*)?"# + playing + hand)

    func chance(_ command: String) -> ParsedIntent? {
        let text = command.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: " !.?"))
        let found: ChanceIntent
        if let c = Self.coins.match(text) {
            found = ChanceIntent(.coin, count: c["n"].flatMap(Self.number) ?? 1)
        } else if Self.oneDie.match(text) != nil {
            found = ChanceIntent(.dice)
        } else if Self.twoDice.match(text) != nil {
            found = ChanceIntent(.dice, count: 2)
        } else if let c = Self.someDice.match(text) ?? Self.notation.match(text) {
            let modifier = c["m"].map { Int($0.replacingOccurrences(of: " ", with: "")) ?? 0 } ?? 0
            found = ChanceIntent(.dice, count: c["n"].flatMap(Self.number) ?? 1, sides: (c["s"] ?? c["sides"]).flatMap { Int($0) } ?? 6,
                                 modifier: modifier)
        } else if let c = Self.handPlayed.match(text) {
            found = ChanceIntent(.rockPaperScissors, hand: c["hand"].flatMap { Hand(rawValue: $0.lowercased()) })
        } else if Self.handsAsked.match(text) != nil {
            found = ChanceIntent(.rockPaperScissors)
        } else {
            return nil
        }
        // What the tool would refuse is the AI's to explain (a hundred coins, a 1-sided die).
        let limit = found.kind == .coin ? Toss.maxCoins : Toss.maxDice
        guard (1...limit).contains(found.count), Toss.sidesRange.contains(found.sides), Toss.modifierRange.contains(found.modifier) else {
            return nil
        }
        return ParsedIntent(intent: .chance(found), hint: ParsedIntent.hint(Self.title(found)))
    }

    private static func number(_ word: String) -> Int? { Int(word) ?? WhenLexicon.numberWords[word.lowercased()].map { Int($0) } }

    /// "Flip a coin", "Roll 2d6", "Rock, paper, scissors: rock", in the app's language.
    static func title(_ c: ChanceIntent) -> String {
        switch c.kind {
        case .coin: c.count > 1 ? String(localized: "Flip \(c.count) coins") : String(localized: "Flip a coin")
        case .dice:
            c.count == 1 && c.sides == 6 && c.modifier == 0 ? String(localized: "Roll a die")
                : String(localized: "Roll \(Toss.notation(count: c.count, sides: c.sides, modifier: c.modifier))", comment: "Rolling dice written as players do: “Roll 2d6”")
        case .rockPaperScissors:
            c.hand.map { String(localized: "Rock, paper, scissors: \($0.title)", comment: "Playing a round with the person's hand: “Rock, paper, scissors: Paper”") }
                ?? String(localized: "Rock, paper, scissors")
        }
    }
}
