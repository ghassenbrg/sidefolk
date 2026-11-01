import Foundation

/// The Play panel's way back to its menu (D79 amended, the games' items). The back arrow is shown on every game and is
/// never refused: at the start, mid-move, during a build-up, while the companion thinks, on the end card or after the
/// game stopped, it puts the game away (to resume from the menu's card for ten minutes) and shows the menu at once.
/// ⌘[ does the same from the keyboard, and ⌫ too unless the board types with it.
public enum PlayBack {
    /// Whether a key goes back to the menu: ⌘[ always; ⌫ (`delete`) unless the board has a part that takes it
    /// (a word being spelled, a number, Sudoku's digits, a text field), locked or not, so a fast ⌫ during a row's flip
    /// never leaves the game.
    public static func goesBack(_ key: String, command: Bool, board: GameBoard?) -> Bool {
        if command { return key == "[" }
        return key == "delete" && !(board?.typesWithDelete ?? false)
    }
}

extension GameBoard {
    /// A part on this board takes ⌫ for itself.
    public var typesWithDelete: Bool {
        keys?.mode == .spell || numberField != nil || entry != nil || puzzle?.input == .digits
    }
}
