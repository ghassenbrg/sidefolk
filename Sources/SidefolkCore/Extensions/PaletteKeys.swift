/// What a key pressed in an extension's palette does (D63, D68). Maccy's keys work, so muscle memory carries over, beside
/// Sidefolk's first ones: ↩ chooses, ⌥↩ the other way (paste when choosing copies, copy when it pastes), ⇧↩ and ⌥⇧↩ plain
/// text, ⌘1…⌘9 (⌥, ⌥⇧) the row by its number, ⌘P or ⌥P pins, ⌘⌫ or ⌥⌫ deletes, ⌥⌘⌫ clears, ⇧⌥⌘⌫ clears everything.
/// Read by key position (`keyCode`), as shortcuts are, so ⌥P is P and not π.
public enum PaletteKeys {
    public enum Command: Equatable, Sendable {
        /// An item action (`choose`, `alternate`, `plain`, `pin`, `delete`) on the picked row, or on row `index`.
        case item(String, index: Int?)
        /// One of the list's own actions (`clear`, `clear_all`).
        case list(String)
    }

    static let returnKey: UInt16 = 36, enterKey: UInt16 = 76, deleteKey: UInt16 = 51, pKey: UInt16 = 35
    /// The digit keys 1–9 on the main row.
    static let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    public static func command(keyCode: UInt16, command: Bool, option: Bool, shift: Bool, control: Bool) -> Command? {
        guard !control else { return nil }
        switch keyCode {
        case returnKey, enterKey:
            // A plain Return is the search field's own (it also ends typing in an input method), which then chooses.
            if shift { return .item("plain", index: nil) }
            return option || command ? .item(option ? "alternate" : "choose", index: nil) : nil
        case deleteKey:
            if option && command { return .list(shift ? "clear_all" : "clear") }
            return option || command ? .item("delete", index: nil) : nil
        case pKey:
            return (option || command) && !shift ? .item("pin", index: nil) : nil
        default:
            guard let n = digits[keyCode], option || command else { return nil }
            if option { return .item(shift ? "plain" : "alternate", index: n - 1) }
            return shift ? nil : .item("choose", index: n - 1)
        }
    }
}
