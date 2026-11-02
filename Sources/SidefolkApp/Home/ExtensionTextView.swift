import SidefolkCore
import SwiftUI
import Synchronization

extension Text {
    /// An extension's own words, which Sidefolk shows verbatim: sizes, paths and addresses kept left to right when
    /// Sidefolk lays out right to left (`BidiText`, D76).
    init(ext text: String) {
        self.init(verbatim: BidiText.shown(ExtensionCompanionWords.fill(text)))
    }
}

/// `{companion}` in an extension's words, filled in only where Sidefolk shows them (D100): the extension can say the name without
/// ever being told it.
enum ExtensionCompanionWords {
    private static let name = Mutex("")

    /// Told at launch and whenever the settings change.
    static func set(_ companion: String) { name.withLock { $0 = companion } }

    static func fill(_ words: String) -> String {
        guard words.contains("{companion}") else { return words }
        return words.replacingOccurrences(of: "{companion}", with: name.withLock { $0 })
    }
}
