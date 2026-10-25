import Foundation

/// Hygiene for text that did not come from the user's own typing (docs/SECURITY.md T2): invisible
/// and bidi characters removed, size capped, wrapped in a tag whose closing form cannot be forged.
/// This makes injected instructions easier for the model to recognise; it is not a boundary. Guard's
/// taint rules are what keep a steered model from acting.
public enum UntrustedText {
    public static let maxBytes = 20_000
    static let tag = "untrusted_content"

    /// `<untrusted_content source="…">…</untrusted_content>`.
    public static func wrap(_ text: String, source: String) -> String {
        "<\(tag) source=\"\(attribute(source))\">\n\(escapeTags(clean(text)))\n</\(tag)>"
    }

    /// Removes zero-width, bidi-override and tag characters and caps the text at `limit` bytes.
    public static func clean(_ text: String, limit: Int = maxBytes) -> String {
        var scalars = String.UnicodeScalarView()
        var bytes = 0
        for s in text.unicodeScalars where !isInvisible(s) {
            let size = String(s).utf8.count
            if bytes + size > limit {
                return String(scalars) + "\n[cut at \(limit / 1000) KB]"
            }
            scalars.append(s)
            bytes += size
        }
        return String(scalars)
    }

    static func isInvisible(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2069, 0xFEFF, 0xE0000...0xE007F: true
        default: false
        }
    }

    /// Content can't open or close the wrapper: `</untrusted_content` becomes `&lt;/untrusted_content`.
    static func escapeTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?i)<(\s*/?\s*untrusted_content)"#, with: "&lt;$1", options: .regularExpression)
    }

    /// A label safe inside a double-quoted attribute.
    static func attribute(_ source: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-:/@()"))
        let kept = String(String.UnicodeScalarView(clean(source, limit: 400).unicodeScalars.filter { allowed.contains($0) }))
        return kept.clipped(80)
    }
}

public extension ToolOutcome {
    /// What the model reads for this call: `modelText`, with untrusted results passed through
    /// `UntrustedText` (source label, stripped invisibles, size cap, unforgeable closing tag).
    var promptText: String {
        if case .ok(let result) = status, result.untrusted {
            return UntrustedText.wrap(result.text, source: activity.tool)
        }
        return modelText
    }
}
