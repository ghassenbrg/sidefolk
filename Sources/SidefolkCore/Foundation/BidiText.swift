import Foundation

/// Text an extension sent, made to read the right way round when Sidefolk lays out right to left (D76). Sidefolk strips
/// every direction control from extension text (they can disguise a name or a path, T13), so it adds its own here, at
/// drawing, where it knows the layout: "3024 × 1964" alone, or "~/Desktop/qr.png" and "https://…" inside an Arabic
/// sentence, are isolated left to right instead of being reordered by the sentence around them.
public enum BidiText {
    private static let lri: Character = "\u{2066}", pdi: Character = "\u{2069}"

    /// `text` as drawn in Sidefolk's own layout, which follows its language.
    public static func shown(_ text: String) -> String {
        shown(text, rightToLeft: Locale.Language(identifier: ExtensionStrings.current).characterDirection == .rightToLeft)
    }

    /// `text` as drawn in a layout of that direction: unchanged left to right.
    public static func shown(_ text: String, rightToLeft: Bool) -> String {
        guard rightToLeft, !text.isEmpty else { return text }
        // Nothing that reads either way (numbers, signs, sizes): the numbers' own order is left to right.
        if !text.unicodeScalars.contains(where: isStrong), text.unicodeScalars.contains(where: { $0.properties.numericType != nil }) {
            return String(lri) + text + String(pdi)
        }
        // Paths, addresses and runs of numbers with signs between them, inside a sentence that reads right to left.
        guard text.unicodeScalars.contains(where: isRightToLeft) else { return text }
        return text.replacing(Self.runs) { String(lri) + $0.output + String(pdi) }
    }

    /// `~/…`, `/…/…`, `https://…`, and numbers joined by × : / - (sizes, times, ratios, dates). Text with a space inside
    /// ends the run, so the sentence's own words never move.
    nonisolated(unsafe) private static let runs =
        /(?:~\/|\/[^\s\/]+\/|https?:\/\/)[^\s]*[^\s.,;:!?)»”"']|\d+(?:[.,]\d+)?(?:\s?[×x:\/\-]\s?\d+(?:[.,]\d+)?)+/

    private static func isStrong(_ s: Unicode.Scalar) -> Bool {
        s.properties.isAlphabetic && s.properties.numericType == nil
    }

    private static func isRightToLeft(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF: true
        default: false
        }
    }
}
