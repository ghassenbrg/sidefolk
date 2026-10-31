import Foundation

/// The looks Sidefolk dresses a game in (D79 amended, "the games look"): a colour of its own, an illustrated scene
/// behind the board and an icon on the menu card, all Sidefolk's art. A game names one in its manifest (`look`) and
/// never sends a picture; a game without one gets the plain look.
public enum GameLook: String, Sendable, Hashable, CaseIterable {
    /// A quiz: a cosy study, indigo.
    case quiz
    /// Marks on a grid: a garden picnic, teal.
    case grid
    /// Copying moves: a playroom with fairy lights, green.
    case dance
    /// A reflex: a night-time arcade, neon on navy.
    case arcade
    /// Cups on a table: a living room, red.
    case cups
    /// Hot and cold numbers: a cabin between snow and fire, orange.
    case numbers
    /// Guessing an animal: a forest clearing, leaf green.
    case animals
    /// Words with balloons: an open sky, sky blue.
    case balloons
    /// Taking sticks: a lavender reading room, violet.
    case sticks
    /// Memory cards: a games room, raspberry.
    case cards
    /// A word a day: a breakfast nook, sunny yellow.
    case words
    /// Hands thrown: a living room, amber (Sidefolk's own best of three).
    case hands

    /// Played alone, a puzzle (the menu's "Puzzles"), rather than against the companion.
    public var solo: Bool { self == .words }
}
