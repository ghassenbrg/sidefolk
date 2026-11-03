import Foundation

/// Text a card asks the person to read in full, in the parts it's laid out by: only its look changes, and every line of it is in a part (T44).
public enum ApprovalText {
    public struct Part: Sendable, Equatable {
        /// A paragraph's first line, when the rest of it is "•" lines.
        public var heading: String?
        /// Its "•" lines without the mark, or the whole paragraph when it isn't laid out as a list.
        public var rows: [String]
    }

    public static func parts(_ text: String) -> [Part] {
        text.components(separatedBy: "\n\n").map { paragraph in
            let lines = paragraph.components(separatedBy: "\n")
            let rows = lines.dropFirst().filter { $0.hasPrefix("• ") }.map { String($0.dropFirst(2)) }
            guard !rows.isEmpty, rows.count == lines.count - 1, !lines[0].hasPrefix("• ") else { return Part(heading: nil, rows: [paragraph]) }
            return Part(heading: lines[0], rows: rows)
        }
    }

    /// The parts as the text they came from.
    public static func joined(_ parts: [Part]) -> String {
        parts.map { part in
            guard let heading = part.heading else { return part.rows.joined(separator: "\n") }
            return ([heading] + part.rows.map { "• \($0)" }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
