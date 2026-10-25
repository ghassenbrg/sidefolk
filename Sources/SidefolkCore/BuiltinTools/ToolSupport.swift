import Foundation

// Small helpers shared by the built-in tools: reading model-supplied input defensively,
// recording where content came from, and cleaning text that came from outside.

extension Caller {
    /// Provenance stored on notes and facts: `user | agent | routine | external:<client> | extension:<id>`.
    var sourceTag: String {
        switch self {
        case .user: "user"
        case .agent: "agent"
        case .routine: "routine"
        case .external(let client): "external:\(client)"
        case .extension(let id): "extension:\(id)"
        }
    }
}

enum ItemProvenance {
    /// Content written by an external agent, an extension or an unattended routine is not the
    /// user's own words, so reading it back taints the turn (docs/SECURITY.md T3).
    static func isForeign(_ source: String) -> Bool {
        source.hasPrefix("external") || source.hasPrefix("extension") || source.hasPrefix("routine")
    }

    /// "from codex" for foreign sources, nil for the user's own and Sidefolk's.
    static func note(for source: String) -> String? {
        guard isForeign(source) else { return nil }
        let name = source.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
        return "from \(name ?? source)"
    }
}

extension JSONValue {
    /// A trimmed, non-empty string no longer than `limit` characters.
    func requiredText(_ key: String, limit: Int = 2_000) throws -> String {
        guard let s = string(key) else { throw ToolError.invalidInput("“\(key)” is required.") }
        guard s.count <= limit else {
            throw UserFacingError("“\(key)” is too long (the limit is \(limit.formatted()) characters).")
        }
        return s
    }

    func optionalText(_ key: String, limit: Int = 2_000) throws -> String? {
        guard string(key) != nil else { return nil }
        return try requiredText(key, limit: limit)
    }

    /// A list given as an array of strings, a comma or newline separated string, or one value.
    /// Nil when the key is absent; entries are trimmed and blanks dropped.
    func textList(_ key: String) -> [String]? {
        guard let value = self[key], !value.isNull else { return nil }
        switch value {
        case .array(let items):
            return items.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        case .string(let s):
            return s.components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        default:
            return nil
        }
    }

    /// An integer input clamped into `range`; the default when absent or not a number.
    func clampedInt(_ key: String, default fallback: Int, in range: ClosedRange<Int>) -> Int {
        guard let n = self[key]?.intValue else { return fallback }
        return min(max(n, range.lowerBound), range.upperBound)
    }
}

/// Plain, deterministic formatting for text the model reads.
enum ToolFormat {
    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func minute(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return day(date) + String(format: " %02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func bytes(_ count: Int64) -> String {
        count.formatted(ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: false, includesActualByteCount: false, locale: Locale(identifier: "en_US")))
    }

    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// Collapses all whitespace (newlines included) so a value fits on one line.
    static func oneLine(_ text: String, _ limit: Int) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").clipped(limit)
    }

    /// "a, b and 2 more" for short summaries.
    static func names(_ names: [String], max: Int = 3) -> String {
        guard names.count > max else { return names.joined(separator: ", ") }
        return names.prefix(max).joined(separator: ", ") + " and \(names.count - max) more"
    }
}

/// Hygiene for text that came from outside the user's own notes (docs/SECURITY.md T2): invisible and
/// bidi characters can hide instructions, and a closing wrapper tag could end the untrusted block early.
enum ExternalText {
    static func clean(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in text.unicodeScalars where !isStripped(u) { scalars.append(u) }
        return String(scalars).replacingOccurrences(of: "</untrusted", with: "< /untrusted", options: .caseInsensitive)
    }

    static func isStripped(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2069, 0xFEFF, 0xE0000...0xE007F: true
        case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F: true
        default: false
        }
    }

    /// Cleans, then caps to `limit` characters. `truncated` says whether anything was cut.
    static func prepare(_ text: String, limit: Int) -> (text: String, truncated: Bool) {
        let cleaned = clean(text)
        guard cleaned.count > limit else { return (cleaned, false) }
        return (String(cleaned.prefix(limit)), true)
    }
}
