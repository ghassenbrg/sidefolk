import Foundation

extension String {
    /// The words as people see them: without the isolates the Kit's `L` puts around each value it fills in (invisible,
    /// D76 amended), so a test can compare an extension's words with the sentence it expects.
    var seen: String { filter { $0 != "\u{2068}" && $0 != "\u{2069}" } }
}
