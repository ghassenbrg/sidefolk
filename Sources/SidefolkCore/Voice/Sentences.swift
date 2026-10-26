import Foundation
import NaturalLanguage

/// Sentence boundaries in any of the app's languages (NLTokenizer knows "e.g.", "3.5", "。" and "؟").
public enum Sentences {
    public static func split(_ text: String) -> [String] {
        ranges(text).map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func ranges(_ text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
    }
}

/// Text that arrives in pieces comes out as whole sentences, so speech can start before the rest
/// has arrived. The last, possibly unfinished, sentence waits for more text or `flush()`.
public struct SentenceBuffer: Sendable {
    private var pending = ""

    public init() {}

    public mutating func append(_ text: String) -> [String] {
        pending += text
        let ranges = Sentences.ranges(pending)
        guard ranges.count > 1, let last = ranges.last else { return [] }
        let done = String(pending[pending.startIndex..<last.lowerBound])
        pending = String(pending[last.lowerBound...])
        return Sentences.split(done)
    }

    public mutating func flush() -> [String] {
        defer { pending = "" }
        return Sentences.split(pending)
    }
}
