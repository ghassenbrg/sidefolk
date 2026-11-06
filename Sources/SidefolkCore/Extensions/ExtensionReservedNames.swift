import Foundation

/// Names that only Sidefolk's own extensions may go by (T40, T41): what people read in the frame, a menu or History can't
/// say it is Sidefolk or the companion unless the signed pack says so. Only at install, where who signed it is known: one
/// already here is never turned off by an app update.
enum ExtensionReservedNames {
    /// The companions' own names as they come (D29, D30). What the person renamed theirs to isn't weighed: it isn't known here.
    private static let companions: Set<String> = ["mochi", "spark", "ember", "kiko", "nimbo", "folio", "iris", "nori", "purl", "rune"]

    /// Looks the same however it is cased, accented or spelled in lookalike letters; spaces and marks between don't hide it.
    static func folded(_ name: String) -> String {
        // Letters drawn the same as Latin ones, which transliterating would turn into something else.
        let lookalikes: [Character: Character] = ["ѕ": "s", "Ѕ": "s", "і": "i", "І": "i", "ı": "i", "Ι": "i", "ԁ": "d", "е": "e", "Е": "e", "ε": "e", "о": "o", "О": "o", "ο": "o", "Ο": "o", "κ": "k", "К": "k", "к": "k"]
        let plainLetters = String(name.map { lookalikes[$0] ?? $0 })
        let latin = plainLetters.applyingTransform(.toLatin, reverse: false) ?? plainLetters
        let plain = latin.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(plain.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// As `folded`, and with the letters that are drawn alike set equal: `i`, `l`, `1` and a bar are one (a capital I for the l of `Sidefolk`), `o` and `0` are one.
    /// Only for comparing with a name kept: the two sides are made the same way.
    static func skeleton(_ name: String) -> String {
        let marked = name.map { $0 == "|" ? "l" : String($0) }.joined()
        return String(folded(marked).map { "il1".contains($0) ? "l" : $0 == "0" ? "o" : $0 })
    }

    static func isReserved(_ name: String) -> Bool {
        let name = skeleton(name)
        return name.hasPrefix(skeleton("sidefolk")) || companions.contains { skeleton($0) == name }
    }

    /// What a pack may not call itself or say it is by, in any language it carries, unless it is Sidefolk's own.
    static func issues(_ manifest: ExtensionManifest, strings: ExtensionStrings?) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if isReserved(manifest.name) { issues.append(ValidationIssue(field: "name", message: "“\(manifest.name)” is kept for Sidefolk's own: choose another name.")) }
        for language in (strings?.tables.keys.sorted() ?? []) {
            if let name = strings?.tables[language]?.name, isReserved(name) {
                issues.append(ValidationIssue(field: "strings/\(language).json", message: "“\(name)” is kept for Sidefolk's own: choose another name."))
            }
        }
        return issues
    }
}
