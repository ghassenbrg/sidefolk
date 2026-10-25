import Foundation

/// Readable text from an HTML page: the title and the main text, without scripts, styles, navigation or
/// anything the page hides from human readers (hidden text is a classic place to plant instructions).
/// A forgiving single-pass tokenizer; it never executes or loads anything.
public enum HTMLText {
    public struct Page: Sendable, Equatable {
        public var title: String?
        public var text: String
        public init(title: String?, text: String) {
            self.title = title
            self.text = text
        }
    }

    public static func extract(_ html: String) -> Page {
        let scanner = Markup(Array(html.utf8))
        let title = scanner.innerRange(of: "title", in: 0..<scanner.count).map { cleanLine(scanner.string($0)) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? scanner.innerRange(of: "h1", in: 0..<scanner.count).map { cleanLine(scanner.render($0)) }.flatMap { $0.isEmpty ? nil : $0 }

        // Prefer the page's main content when it holds a meaningful amount of text.
        for tag in ["main", "article"] {
            if let range = scanner.innerRange(of: tag, in: 0..<scanner.count) {
                let text = scanner.render(range)
                if text.count >= 200 { return Page(title: title, text: text) }
            }
        }
        let body = scanner.innerRange(of: "body", in: 0..<scanner.count) ?? 0..<scanner.count
        return Page(title: title, text: scanner.render(body))
    }

    private static func cleanLine(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ").clipped(300)
    }

    // MARK: Tag knowledge

    private static let droppedElements: Set<String> = [
        "script", "style", "noscript", "template", "svg", "iframe", "object", "embed", "canvas", "head", "nav", "select", "audio", "video",
    ]
    private static let voidElements: Set<String> = ["br", "hr", "img", "input", "meta", "link", "area", "base", "col", "embed", "source", "track", "wbr"]
    private static let blockElements: Set<String> = [
        "p", "div", "section", "article", "main", "header", "footer", "aside", "ul", "ol", "li", "tr", "table", "pre", "blockquote",
        "dl", "dt", "dd", "figure", "figcaption", "form", "fieldset", "address", "details", "summary", "caption", "body", "html",
        "h1", "h2", "h3", "h4", "h5", "h6", "hr", "thead", "tbody", "tfoot",
    ]

    // MARK: Markup

    /// Works on UTF-8 bytes: tags are ASCII, so no character decoding is needed to find them.
    private struct Markup {
        let bytes: [UInt8]
        let lower: [UInt8]
        var count: Int { bytes.count }

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
            lower = bytes.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }
        }

        func string(_ range: Range<Int>) -> String {
            HTMLEntities.decode(String(decoding: bytes[range], as: UTF8.self))
        }

        func find(_ needle: [UInt8], from: Int, to: Int) -> Int? {
            guard !needle.isEmpty, to - from >= needle.count else { return nil }
            var i = from
            let last = to - needle.count
            while i <= last {
                if lower[i] == needle[0] {
                    var j = 1
                    while j < needle.count, lower[i + j] == needle[j] { j += 1 }
                    if j == needle.count { return i }
                }
                i += 1
            }
            return nil
        }

        struct Tag {
            var name: String
            var closing: Bool
            var selfClosing: Bool
            var attributes: Range<Int>
            var end: Int   // index just after '>'
        }

        /// Parses a tag starting at `i` (which holds '<'). Nil when it isn't a tag, so '<' is plain text.
        func tag(at i: Int, limit: Int) -> Tag? {
            var j = i + 1
            guard j < limit else { return nil }
            let closing = lower[j] == UInt8(ascii: "/")
            if closing { j += 1 }
            guard j < limit, lower[j] >= 97, lower[j] <= 122 else { return nil }
            let nameStart = j
            while j < limit, (lower[j] >= 97 && lower[j] <= 122) || (lower[j] >= 48 && lower[j] <= 57) || lower[j] == 45 || lower[j] == 58 { j += 1 }
            let name = String(decoding: lower[nameStart..<j], as: UTF8.self)
            let attrStart = j
            var quote: UInt8 = 0
            let cap = min(limit, j + 20_000)
            while j < cap {
                let c = bytes[j]
                if quote != 0 {
                    if c == quote { quote = 0 }
                } else if c == UInt8(ascii: "\"") || c == UInt8(ascii: "'") {
                    quote = c
                } else if c == UInt8(ascii: ">") {
                    return Tag(name: name, closing: closing, selfClosing: j > attrStart && bytes[j - 1] == UInt8(ascii: "/"),
                               attributes: attrStart..<j, end: j + 1)
                }
                j += 1
            }
            return nil
        }

        /// The text between the first `<name …>` and its matching `</name>`.
        func innerRange(of name: String, in range: Range<Int>) -> Range<Int>? {
            let open = Array("<\(name)".utf8)
            var from = range.lowerBound
            while let at = find(open, from: from, to: range.upperBound) {
                let after = at + open.count
                guard after < range.upperBound, !isNameByte(lower[after]) else { from = at + 1; continue }
                guard let t = tag(at: at, limit: range.upperBound), !t.closing else { from = at + 1; continue }
                if t.selfClosing { return nil }
                let close = closingIndex(of: name, from: t.end, limit: range.upperBound)
                return t.end..<(close ?? range.upperBound)
            }
            return nil
        }

        func isNameByte(_ c: UInt8) -> Bool { (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 45 || c == 58 }

        /// Index of the `</name>` that closes an element whose content starts at `from`, counting nesting.
        func closingIndex(of name: String, from: Int, limit: Int) -> Int? {
            if name == "script" || name == "style" {
                return find(Array("</\(name)".utf8), from: from, to: limit)
            }
            var depth = 1
            var i = from
            while i < limit {
                guard let lt = find([UInt8(ascii: "<")], from: i, to: limit) else { return nil }
                if let t = tag(at: lt, limit: limit) {
                    if t.name == name {
                        if t.closing { depth -= 1; if depth == 0 { return lt } }
                        else if !t.selfClosing { depth += 1 }
                    }
                    i = t.end
                } else {
                    i = lt + 1
                }
            }
            return nil
        }

        /// The index just after the end tag of an element whose start tag ended at `from`.
        func skipElement(_ name: String, from: Int, limit: Int) -> Int {
            guard let close = closingIndex(of: name, from: from, limit: limit) else { return limit }
            if let end = find([UInt8(ascii: ">")], from: close, to: limit) { return end + 1 }
            return limit
        }

        func isHidden(_ attributes: Range<Int>) -> Bool {
            let text = String(decoding: lower[attributes], as: UTF8.self)
            let squashed = text.filter { !$0.isWhitespace }
            if squashed.contains("aria-hidden=\"true\"") || squashed.contains("aria-hidden='true'") { return true }
            if squashed.contains("display:none") || squashed.contains("visibility:hidden") { return true }
            // A bare `hidden` attribute, as opposed to a word inside a value.
            var inQuote: Character?
            var token = ""
            for ch in text + " " {
                if let q = inQuote { if ch == q { inQuote = nil }; continue }
                if ch == "\"" || ch == "'" { inQuote = ch; continue }
                if ch.isWhitespace || ch == "=" {
                    if token == "hidden" { return true }
                    token = ""
                } else {
                    token.append(ch)
                }
            }
            return false
        }

        // MARK: Rendering

        func render(_ range: Range<Int>) -> String {
            var out = TextOut()
            var preDepth = 0
            var i = range.lowerBound
            let end = range.upperBound
            while i < end {
                guard let lt = find([UInt8(ascii: "<")], from: i, to: end) else {
                    out.text(string(i..<end), pre: preDepth > 0)
                    break
                }
                if lt > i { out.text(string(i..<lt), pre: preDepth > 0) }
                // Comments, doctype, processing instructions.
                if lt + 3 < end, lower[lt + 1] == UInt8(ascii: "!"), lower[lt + 2] == UInt8(ascii: "-"), lower[lt + 3] == UInt8(ascii: "-") {
                    i = find(Array("-->".utf8), from: lt + 4, to: end).map { $0 + 3 } ?? end
                    continue
                }
                if lt + 1 < end, lower[lt + 1] == UInt8(ascii: "!") || lower[lt + 1] == UInt8(ascii: "?") {
                    i = find([UInt8(ascii: ">")], from: lt, to: end).map { $0 + 1 } ?? end
                    continue
                }
                guard let t = tag(at: lt, limit: end) else {
                    out.text("<", pre: preDepth > 0)
                    i = lt + 1
                    continue
                }
                i = t.end
                if t.closing {
                    if t.name == "pre", preDepth > 0 { preDepth -= 1 }
                    if blockElements.contains(t.name) { out.lineBreak(t.name.hasPrefix("h") || t.name == "p" || t.name == "ul" || t.name == "ol" || t.name == "table" ? 2 : 1) }
                    continue
                }
                if droppedElements.contains(t.name) || (!voidElements.contains(t.name) && !t.selfClosing && isHidden(t.attributes)) {
                    if !t.selfClosing { i = skipElement(t.name, from: t.end, limit: end) }
                    continue
                }
                switch t.name {
                case "br": out.lineBreak(1)
                case "li": out.lineBreak(1); out.marker("- ")
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    out.lineBreak(2)
                    out.marker(String(repeating: "#", count: Int(t.name.dropFirst()) ?? 1) + " ")
                case "td", "th": out.cell()
                case "pre": out.lineBreak(2); preDepth += 1
                case "p", "ul", "ol", "table": out.lineBreak(2)
                default: if blockElements.contains(t.name) { out.lineBreak(1) }
                }
            }
            return out.finish()
        }
    }

    // MARK: Output builder

    private struct TextOut {
        var s = ""
        var pendingSpace = false
        var pendingBreaks = 0
        var atLineStart = true

        mutating func lineBreak(_ n: Int) {
            pendingBreaks = max(pendingBreaks, n)
            pendingSpace = false
        }

        mutating func flushBreaks() {
            if pendingBreaks > 0 {
                if !s.isEmpty { s += String(repeating: "\n", count: min(pendingBreaks, 2)) }
                pendingBreaks = 0
                atLineStart = true
                pendingSpace = false
            }
        }

        mutating func marker(_ m: String) {
            flushBreaks()
            s += m
            atLineStart = true   // the text that follows sits right after the marker
            pendingSpace = false
        }

        mutating func cell() {
            guard !atLineStart, pendingBreaks == 0 else { return }
            s += " | "
            atLineStart = true
            pendingSpace = false
        }

        mutating func text(_ str: String, pre: Bool) {
            if pre {
                flushBreaks()
                s += str
                atLineStart = str.hasSuffix("\n")
                return
            }
            for u in str.unicodeScalars {
                if u.properties.isWhitespace || u.value == 0xA0 {
                    pendingSpace = true
                    continue
                }
                flushBreaks()
                if pendingSpace, !atLineStart { s += " " }
                pendingSpace = false
                s.unicodeScalars.append(u)
                atLineStart = false
            }
        }

        func finish() -> String {
            s.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// Decodes the HTML entities that show up in real pages.
enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "copy": "©", "reg": "®", "trade": "™",
        "mdash": "—", "ndash": "–", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "bull": "•", "middot": "·", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "sect": "§", "deg": "°", "plusmn": "±",
        "times": "×", "divide": "÷", "frac12": "½", "frac14": "¼", "frac34": "¾", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓",
        "eacute": "é", "egrave": "è", "agrave": "à", "aacute": "á", "uuml": "ü", "ouml": "ö", "auml": "ä", "szlig": "ß", "ccedil": "ç",
        "ntilde": "ñ", "iexcl": "¡", "iquest": "¿", "check": "✓", "hearts": "♥",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            guard ch == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                out.append(ch)
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<semicolon])
            if let replacement = replacement(for: name) {
                out += replacement
                index = text.index(after: semicolon)
            } else {
                out.append(ch)
                index = text.index(after: index)
            }
        }
        return out
    }

    private static func replacement(for name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            guard let value, value > 0, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return named[name] ?? named[name.lowercased()]
    }
}
