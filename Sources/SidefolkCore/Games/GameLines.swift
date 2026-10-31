import Foundation

/// How the companion takes a win (D75), a setting: gentle ("Good game!"), cheeky (a small tease, then kind; the
/// default) or competitive (a victory dance).
public enum GameTone: String, Codable, Sendable, CaseIterable {
    case gentle, cheeky, competitive
}

/// The companion's own lines for a game's `line` keys (D75), in the person's language and the chosen tone. A game
/// names the key; Sidefolk picks the words, so the companion never says an extension's text.
public enum GameLines {
    /// One of the key's lines; `pick` chooses among them (a random number, or a fixed one in tests).
    public static func line(_ key: GameCue.Line, tone: GameTone, pick: Int = Int.random(in: 0..<1000)) -> String {
        let pool = lines(key, tone)
        return pool[abs(pick) % pool.count]
    }

    // Explicit keys: several lines share their English words with other strings, and each language words them apart.
    static func lines(_ key: GameCue.Line, _ tone: GameTone) -> [String] {
        switch key {
        case .hello: [String(localized: "game.line.hello.1", defaultValue: "Ooh, a game!", comment: "The companion, as a game starts"),
                      String(localized: "game.line.hello.2", defaultValue: "I'm ready!", comment: "The companion, as a game starts")]
        case .yourTurn: [String(localized: "game.line.yourTurn.1", defaultValue: "Your turn.", comment: "The companion, in a game"),
                         String(localized: "game.line.yourTurn.2", defaultValue: "Over to you.", comment: "The companion, in a game: your turn")]
        case .myTurn: [String(localized: "game.line.myTurn.1", defaultValue: "My turn!", comment: "The companion, in a game"),
                       String(localized: "game.line.myTurn.2", defaultValue: "Here I go.", comment: "The companion, in a game: its turn")]
        case .thinking: [String(localized: "game.line.thinking.1", defaultValue: "Hmm…", comment: "The companion thinks, in a game"),
                         String(localized: "game.line.thinking.2", defaultValue: "Let me think…", comment: "The companion thinks, in a game")]
        case .closeOne: [String(localized: "game.line.closeOne.1", defaultValue: "Ooh, so close!", comment: "The companion, after a near miss in a game"),
                         String(localized: "game.line.closeOne.2", defaultValue: "Nearly!", comment: "The companion, after a near miss in a game")]
        case .record: [String(localized: "game.line.record.1", defaultValue: "A new best!", comment: "The companion: the person beat their record"),
                       String(localized: "game.line.record.2", defaultValue: "That's a record!", comment: "The companion: the person beat their record")]
        case .streak: [String(localized: "game.line.streak.1", defaultValue: "You're on a roll!", comment: "The companion: several right in a row"),
                       String(localized: "game.line.streak.2", defaultValue: "Another one!", comment: "The companion: several right in a row")]
        case .encourage: [String(localized: "game.line.encourage.1", defaultValue: "Next one's yours.", comment: "The companion encourages the person"),
                          String(localized: "game.line.encourage.2", defaultValue: "Keep going!", comment: "The companion encourages the person")]
        case .caughtCheating: [String(localized: "game.line.caught.1", defaultValue: "…fine, it was in my paw.", comment: "The companion, caught cheating in a game, for fun"),
                               String(localized: "game.line.caught.2", defaultValue: "You caught me!", comment: "The companion, caught cheating in a game, for fun")]
        case .hintIntro: [String(localized: "game.line.hint.1", defaultValue: "Psst… here's a clue.", comment: "The companion gives a hint in a game"),
                          String(localized: "game.line.hint.2", defaultValue: "I'll help a little.", comment: "The companion gives a hint in a game")]
        case .bye: [String(localized: "game.line.bye.1", defaultValue: "That was fun.", comment: "The companion, as a game closes"),
                    String(localized: "game.line.bye.2", defaultValue: "Let's play again soon.", comment: "The companion, as a game closes")]
        case .draw: [String(localized: "game.line.draw.1", defaultValue: "A draw!", comment: "The companion: nobody won"),
                     String(localized: "game.line.draw.2", defaultValue: "Nobody wins that one.", comment: "The companion: nobody won")]
        case .youWin: youWin(tone)
        case .iWin: iWin(tone)
        case .tease: tease(tone)
        }
    }

    private static func youWin(_ tone: GameTone) -> [String] {
        switch tone {
        case .gentle: [String(localized: "game.line.youWin.gentle.1", defaultValue: "Well played!", comment: "The companion lost a game; gentle tone"),
                       String(localized: "game.line.youWin.gentle.2", defaultValue: "You win. Nicely done!", comment: "The companion lost a game; gentle tone")]
        case .cheeky: [String(localized: "game.line.youWin.cheeky.1", defaultValue: "You got me.", comment: "The companion lost a game; cheeky tone"),
                       String(localized: "game.line.youWin.cheeky.2", defaultValue: "Okay, you win… this time.", comment: "The companion lost a game; cheeky tone")]
        case .competitive: [String(localized: "game.line.youWin.competitive.1", defaultValue: "Lucky! Again!", comment: "The companion lost a game; competitive tone"),
                            String(localized: "game.line.youWin.competitive.2", defaultValue: "I demand a rematch!", comment: "The companion lost a game; competitive tone")]
        }
    }

    private static func iWin(_ tone: GameTone) -> [String] {
        switch tone {
        case .gentle: [String(localized: "game.line.iWin.gentle.1", defaultValue: "I won! Good game.", comment: "The companion won a game; gentle tone"),
                       String(localized: "game.line.iWin.gentle.2", defaultValue: "That one's mine. Good game!", comment: "The companion won a game; gentle tone")]
        case .cheeky: [String(localized: "game.line.iWin.cheeky.1", defaultValue: "Ha! Mine. Rematch?", comment: "The companion won a game; cheeky tone: a small tease, then kind"),
                       String(localized: "game.line.iWin.cheeky.2", defaultValue: "Too easy… kidding. Good game!", comment: "The companion won a game; cheeky tone: a small tease, then kind")]
        case .competitive: [String(localized: "game.line.iWin.competitive.1", defaultValue: "Victory!", comment: "The companion won a game; competitive tone"),
                            String(localized: "game.line.iWin.competitive.2", defaultValue: "Still undefeated!", comment: "The companion won a game; competitive tone")]
        }
    }

    private static func tease(_ tone: GameTone) -> [String] {
        switch tone {
        case .gentle: [String(localized: "game.line.tease.gentle.1", defaultValue: "Oh? Interesting.", comment: "The companion, playfully, about the person's move; gentle tone"),
                       String(localized: "game.line.tease.gentle.2", defaultValue: "Hmm, are you sure?", comment: "The companion, playfully, about the person's move; gentle tone")]
        case .cheeky: [String(localized: "game.line.tease.cheeky.1", defaultValue: "Ooh, bold.", comment: "The companion teases the person's move; cheeky tone"),
                       String(localized: "game.line.tease.cheeky.2", defaultValue: "Hehe. Sure about that?", comment: "The companion teases the person's move; cheeky tone")]
        case .competitive: [String(localized: "game.line.tease.competitive.1", defaultValue: "Not this time!", comment: "The companion taunts, playfully; competitive tone"),
                            String(localized: "game.line.tease.competitive.2", defaultValue: "I see what you're doing.", comment: "The companion taunts, playfully; competitive tone")]
        }
    }
}
