import Foundation

/// The looks Sidefolk dresses a game in (D79 amended, "the games look"): a colour of its own, an illustrated scene
/// behind the board and an icon on the menu card, all Sidefolk's art. A game names one in its manifest (`look`) and
/// never sends a picture; a game without one gets the plain look. The order here is the menu's.
///
/// A new look: a case here (and in `solo` if it is played alone), its row in the app's `GameStyle.of` (colours, scene,
/// icon), its pictures in `Sources/SidefolkApp/Play/Art` (`game-bg-<look>.heic`, `game-icon-<look>.webp`) and cases in
/// `GameArt`; then a game names it in its manifest (`"look": "<look>"`).
public enum GameLook: String, Sendable, Hashable, CaseIterable {
    /// Cups on a table: a living room, red.
    case cups
    /// Copying moves: a playroom with fairy lights, green.
    case dance
    /// A reflex: a night-time arcade, neon on navy.
    case arcade
    /// Taking sticks: a lavender reading room, violet.
    case sticks
    /// A quiz: a cosy study, indigo.
    case quiz
    /// Marks on a grid: a garden picnic, teal.
    case grid
    /// Hot and cold numbers: a cabin between snow and fire, orange.
    case numbers
    /// Guessing an animal: a forest clearing, leaf green.
    case animals
    /// Words with balloons: an open sky, sky blue.
    case balloons
    /// Memory cards: a games room, raspberry.
    case cards
    /// Hands thrown: a living room, amber (Sidefolk's own best of three).
    case hands
    /// A word a day: a breakfast nook, sunny yellow.
    case words
    /// Garden Plots, rectangles over numbers: a vegetable garden at morning, soil brown.
    case plots
    /// Seesaw, hearts and stars in balance: a playground at golden hour, plum.
    case seesaw
    /// Sudoku: a quiet reading desk by a window, slate blue.
    case sudoku
    /// Blossoms, one flower per row, column and bed: a flower garden, coral.
    case blossoms

    /// Played alone, a puzzle (the menu's "Puzzles"), rather than against the companion.
    public var solo: Bool { [.words, .plots, .seesaw, .sudoku, .blossoms].contains(self) }
}
