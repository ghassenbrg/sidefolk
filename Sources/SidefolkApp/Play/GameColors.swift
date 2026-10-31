import SidefolkCore
import SwiftUI

/// The one mapping from what a result means to how it is drawn, in every game and toss (D75, `GameVerdict`): a win
/// for the person is the theme's success green; a loss (the companion winning included) a calm warm sand, never the
/// danger red, which means something went wrong or can't be undone; a draw neutral ink. A symbol or a word always
/// goes with the colour.
enum GameColors {
    /// The games' loss tone: warm and quiet, readable as "not this time" rather than "error".
    static let lost = Color(light: 0xB07A52, dark: 0xD9A982)
    static let lostSoft = Color(light: 0xF3E4D6, dark: 0x4A3A2F)
    /// Chance itself (a card about a coin or dice), the d20's violet: never Play's red, which would read as a result.
    static let chance = Color(hex: 0x7C5CE0)

    static func color(_ verdict: GameVerdict) -> Color {
        switch verdict.role {
        case .success: Theme.success
        case .lost: lost
        case .neutral: Theme.inkMuted
        }
    }

    /// A tile's or a card's fill for a verdict.
    static func fill(_ verdict: GameVerdict) -> Color {
        switch verdict.role {
        case .success: Theme.success
        case .lost: lostSoft
        case .neutral: Theme.surfaceRaised
        }
    }

    /// The text on that fill.
    static func ink(_ verdict: GameVerdict) -> Color {
        verdict == .win ? .white : Theme.ink
    }
}
