import Foundation
import NaturalLanguage

/// Sentence boundaries in any of the app's languages (NLTokenizer knows "e.g.", "3.5", "。" and "؟").
/// The playback queue says a line sentence by sentence, so the first one plays while the next is made.
public enum Sentences {
    public static func split(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
