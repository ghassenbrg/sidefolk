import Foundation

/// "let's play trivia", "quiz me": a sentence an extension's game says opens it (D75), right away and without AI. The
/// sentences follow the command rules (D50, whole sentences, no slots), and come after Sidefolk's own: "rock paper
/// scissors" is the companion's match. A sentence two extensions' games both claim goes to the AI, as for commands.
extension IntentParser {
    func game(_ command: String) -> ParsedIntent? {
        var found: [GameInfo] = []
        for game in games {
            if game.say.contains(where: { (try? CommandSentence($0))?.match(command) != nil }) { found.append(game) }
        }
        guard let game = found.first, Set(found.map(\.extensionId)).count == 1 else { return nil }
        return ParsedIntent(intent: .game(extensionId: game.extensionId, game: game.game),
                            hint: ParsedIntent.hint(String(localized: "Play \(game.title)", comment: "Opening a game in the Play panel: “Play Trivia”")))
    }
}
