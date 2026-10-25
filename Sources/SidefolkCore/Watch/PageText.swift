import Foundation

/// Turns a fetched page into the lines a person would read, so "did it change?" means "did what
/// I would read change?" and not "did a script, a timestamp or a view counter change?".
public enum PageText {
    /// Normalised text is capped so stored state and diffs stay small.
    public static let maxCharacters = 60_000

    public static func normalise(_ data: Data, contentType: String? = nil) -> String {
        let raw = decode(data, contentType: contentType)
        let type = (contentType ?? "").lowercased()
        var lines: [String]
        if type.contains("json"), let pretty = prettyJSON(data) {
            lines = pretty.components(separatedBy: "\n")
        } else if type.contains("text/plain") || type.contains("text/css") || (!type.contains("html") && !type.contains("xml") && !looksLikeMarkup(raw)) {
            lines = raw.components(separatedBy: .newlines)
        } else {
            lines = htmlLines(raw)
        }
        var out: [String] = []
        var total = 0
        for line in lines {
            let clean = line.displaySafe
            if clean.isEmpty || DynamicText.isNoise(clean) { continue }
            total += clean.count + 1
            if total > maxCharacters { out.append("…"); break }
            out.append(clean)
        }
        return out.joined(separator: "\n")
    }

    // MARK: HTML

    private static func re(_ pattern: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        // The patterns are constants; a failure here is a programming error caught by the tests.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let comments = re(#"<!--[\s\S]*?-->"#)
    private static let hidden = re(#"<(script|style|noscript|template|svg|iframe|object|canvas)\b[\s\S]*?</\1\s*>"#)
    private static let spaces = re(#"\s+"#)
    private static let lineBreaks = re(#"</?(?:p|div|br|li|tr|h[1-6]|section|article|header|footer|table|ul|ol|form|hr|nav|main|aside|blockquote|pre|dd|dt|dl|figure|figcaption|option|title)\b[^>]*>"#)
    private static let cells = re(#"</?(?:td|th)\b[^>]*>"#)
    private static let tags = re(#"<[^>]*>"#)

    static func looksLikeMarkup(_ text: String) -> Bool {
        let head = text.prefix(2000).lowercased()
        return head.contains("<html") || head.contains("<!doctype html") || head.contains("<body") || head.contains("<div") || head.contains("<?xml") || head.contains("<rss")
    }

    static func htmlLines(_ html: String) -> [String] {
        var s = html
        // Newlines inside HTML text are just spaces; only block-level tags start a new line.
        for (regex, template) in [(comments, ""), (hidden, " "), (spaces, " "), (lineBreaks, "\n"), (cells, " "), (tags, "")] {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return decodeEntities(s).components(separatedBy: .newlines)
    }

    // MARK: Decoding

    static func decode(_ data: Data, contentType: String?) -> String {
        if let name = charset(in: contentType) {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let s = String(data: data, encoding: encoding) { return s }
            }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private static func charset(in contentType: String?) -> String? {
        guard let contentType, let r = contentType.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let rest = contentType[r.upperBound...]
        let name = rest.prefix { !$0.isWhitespace && $0 != ";" && $0 != "\"" && $0 != "'" }
        return name.isEmpty ? nil : String(name)
    }

    private static func prettyJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "copy": "©", "reg": "®", "trade": "™",
        "mdash": "—", "ndash": "–", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bull": "•",
        "middot": "·", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "laquo": "«", "raquo": "»", "times": "×",
        "deg": "°", "plusmn": "±", "frac12": "½", "sect": "§", "para": "¶", "larr": "←", "rarr": "→", "check": "✓",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "&", let semi = text[i...].prefix(12).firstIndex(of: ";") {
                let body = String(text[text.index(after: i)..<semi])
                if let decoded = entity(body) {
                    out += decoded
                    i = text.index(after: semi)
                    continue
                }
            }
            out.append(c)
            i = text.index(after: i)
        }
        return out
    }

    private static func entity(_ body: String) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") { value = UInt32(digits.dropFirst(), radix: 16) } else { value = UInt32(digits) }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return scalar.value == 0xA0 ? " " : String(scalar)
        }
        return named[body.lowercased()] ?? named[body]
    }
}

/// Text that changes by itself: dates, times, "3 minutes ago", view counters, copyright years.
enum DynamicText {
    private static let month = #"(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#

    /// Applied in order; each match becomes "#".
    private static let tokens: [NSRegularExpression] = [
        #"\b\d{4}-\d{2}-\d{2}(?:[T ]\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?\s?(?:Z|[+-]\d{2}:?\d{2}|UTC|GMT)?)?"#,
        #"\b\#(month)\.?\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s+\d{4})?\b"#,
        #"\b\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?\#(month)\.?(?:,?\s+\d{4})?\b"#,
        #"\b\#(month)\.?,?\s+\d{4}\b"#,
        #"\b\d{1,4}[/\-]\d{1,2}[/\-]\d{2,4}\b"#,
        #"\b\d{1,2}\.\d{1,2}\.\d{4}\b"#,
        #"\b\d{1,2}:\d{2}(?::\d{2})?(?:\s?[ap]\.?m\.?)?(?:\s?(?:UTC|GMT|[ECMP][SD]T))?\b"#,
        #"\b(?:\d+|an?|one|a few|several)\s+(?:seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)\s+ago\b"#,
        #"\bjust now\b"#,
        #"\b1[5-9]\d{8}(?:\d{3})?\b"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// "12,345 views" on its own short line is a counter; the same words inside a sentence are content.
    private static let counter = try! NSRegularExpression(
        pattern: #"\b\d[\d,.\s]{0,12}[kKmM]?\+?\s+(?:views?|visitors?|visits?|online|likes?|shares?|comments?|downloads?|subscribers?|followers?|reads?|viewing|watching|installs?)\b"#,
        options: [.caseInsensitive])

    private static let label = try! NSRegularExpression(
        pattern: #"^(?:(?:last\s+)?(?:updated?|modified|published|posted|generated|rendered|refreshed|as of|created|edited|copyright)\b|©|\(c\))"#,
        options: [.caseInsensitive])
    private static let year = try! NSRegularExpression(pattern: #"\b(?:19|20)\d{2}\b"#)

    /// The line with its dynamic parts replaced by "#", lower-cased, whitespace collapsed. Two lines
    /// with the same key differ only in things that change on their own.
    static func key(_ line: String) -> String {
        mask(line).lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func mask(_ line: String) -> String {
        var s = line
        for re in tokens { s = replace(re, in: s) }
        if s.count <= 48 { s = replace(counter, in: s) }
        return s
    }

    private static func replace(_ re: NSRegularExpression, in s: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "#")
    }

    /// Whole lines that carry nothing but a moving value are dropped before comparing.
    static func isNoise(_ line: String) -> Bool {
        let masked = mask(line)
        let range = NSRange(line.startIndex..., in: line)
        let startsWithLabel = label.firstMatch(in: line, range: range) != nil
        if startsWithLabel, masked.contains("#") || year.firstMatch(in: line, range: range) != nil { return true }
        guard masked.contains("#") else { return false }
        return !masked.contains { $0.isLetter }
    }
}

// MARK: Diff

/// What changed between two versions of a page, ignoring what changes by itself.
public struct TextChange: Sendable, Equatable {
    public var removed: [String]
    public var added: [String]
    /// Characters in changed lines as a share of the larger text.
    public var ratio: Double

    public var isEmpty: Bool { removed.isEmpty && added.isEmpty }
    /// Worth telling the user: a line a person would read was added or removed, or at least 1% of the text moved.
    public var isSignificant: Bool { !isEmpty || ratio >= TextDiff.significantRatio }

    /// A short "before → after" for the notice body.
    public var snippet: String {
        var parts: [String] = []
        let pairs = min(removed.count, added.count, 2)
        for i in 0..<pairs { parts.append("“\(removed[i].clipped(70))” → “\(added[i].clipped(70))”") }
        if removed.count > pairs, parts.count < 3 { parts.append("Removed: “\(removed[pairs].clipped(70))”") }
        else if added.count > pairs, parts.count < 3 { parts.append("Added: “\(added[pairs].clipped(70))”") }
        let shown = pairs * 2 + (parts.count > pairs ? 1 : 0)
        let more = removed.count + added.count - shown
        if more > 0 { parts.append("and \(more) more \(more == 1 ? "change" : "changes")") }
        return parts.joined(separator: "\n")
    }
}

public enum TextDiff {
    public static let significantRatio = 0.01

    /// Compares two normalised texts line by line; lines that differ only in dates, times or counters are equal.
    public static func compare(old: String, new: String) -> TextChange {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let ka = a.map(DynamicText.key)
        let kb = b.map(DynamicText.key)
        var gone: [(Int, String)] = []
        var came: [(Int, String)] = []
        for change in kb.difference(from: ka) {
            switch change {
            case .remove(let offset, _, _): gone.append((offset, a[offset]))
            case .insert(let offset, _, _): came.append((offset, b[offset]))
            }
        }
        // Differences are not in reading order; show them top to bottom.
        let removed = gone.sorted { $0.0 < $1.0 }.map(\.1)
        let added = came.sorted { $0.0 < $1.0 }.map(\.1)
        let changed = (removed + added).reduce(0) { $0 + $1.count }
        let basis = max(old.count, new.count, 1)
        return TextChange(removed: removed, added: added, ratio: Double(changed) / Double(basis))
    }

    /// Case-insensitive, whitespace-insensitive "does the page say this?".
    public static func contains(_ text: String, _ needle: String) -> Bool {
        func squash(_ s: String) -> String { s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        let n = squash(needle)
        return !n.isEmpty && squash(text).contains(n)
    }
}
