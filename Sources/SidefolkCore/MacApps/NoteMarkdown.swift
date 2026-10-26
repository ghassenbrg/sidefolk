import Foundation

/// Turns the HTML Notes gives for a note body into Markdown the notebook shows and the model reads:
/// headings, bold, italic, struck text, links, lists (nested and numbered), tables, monospaced text
/// and line breaks. Images and attachments become a named placeholder; their files stay in Notes.
///
/// Notes writes simple HTML (`<div>` per line, `<ul><li>`, `<b>`, `<object><table>`), but a body is
/// still outside content: the tokenizer is forgiving, never recurses, and never loads anything.
public enum NoteMarkdown {
    /// - Parameter attachments: content id (`cid:` in the HTML) → file name, to name embedded images.
    public static func convert(_ html: String, attachments: [String: String] = [:]) -> String {
        var out = Writer()
        var lists: [(ordered: Bool, next: Int)] = []
        var links: [String?] = []
        var skipping: String?
        var cell = 0
        var rowsInTable = 0
        // Notes wraps each table cell's text in <div>s; inside a cell they must not end the row's line.
        var inCell = false
        var index = html.startIndex

        while index < html.endIndex {
            guard let lt = html[index...].firstIndex(of: "<") else {
                if skipping == nil { out.text(String(html[index...])) }
                break
            }
            if lt > index, skipping == nil { out.text(String(html[index..<lt])) }
            guard let gt = html[lt...].firstIndex(of: ">") else {
                if skipping == nil { out.text(String(html[lt...])) }
                break
            }
            index = html.index(after: gt)
            let tag = Tag(String(html[html.index(after: lt)..<gt]))
            if let skipped = skipping {
                if tag.closing, tag.name == skipped { skipping = nil }
                continue
            }
            if inCell, ["br", "div", "p"].contains(tag.name) {
                out.text(" ")
                continue
            }
            switch (tag.name, tag.closing) {
            case ("script", false), ("style", false), ("head", false), ("title", false):
                if !tag.selfClosing { skipping = tag.name }
            case ("br", _):
                out.newline()
            case ("div", _), ("p", _):
                out.endLine()
            case ("h1", false), ("h2", false), ("h3", false), ("h4", false), ("h5", false), ("h6", false):
                out.endLine()
                out.prefix = String(repeating: "#", count: min(Int(tag.name.dropFirst()) ?? 1, 6)) + " "
            case ("h1", true), ("h2", true), ("h3", true), ("h4", true), ("h5", true), ("h6", true):
                out.endBlock()
            case ("b", _), ("strong", _):
                out.emphasis("**")
            case ("i", _), ("em", _):
                out.emphasis("*")
            case ("strike", _), ("s", _), ("del", _):
                out.emphasis("~~")
            case ("tt", _), ("code", _):
                out.emphasis("`")
            case ("pre", false):
                out.endLine()
                out.raw("```")
                out.preformatted = true
            case ("pre", true):
                out.preformatted = false
                out.endLine()
                out.raw("```")
            case ("ul", false), ("ol", false):
                out.endLine()
                lists.append((tag.name == "ol", 1))
            case ("ul", true), ("ol", true):
                out.endLine()
                if !lists.isEmpty { lists.removeLast() }
            case ("li", false):
                out.endLine()
                let depth = max(lists.count - 1, 0)
                var marker = "- "
                if let last = lists.last, last.ordered {
                    marker = "\(last.next). "
                    lists[lists.count - 1].next += 1
                }
                out.prefix = String(repeating: "  ", count: min(depth, 8)) + marker
            case ("li", true):
                out.endBlock()
            case ("blockquote", false):
                out.endLine()
                out.quoteDepth += 1
            case ("blockquote", true):
                out.endLine()
                out.quoteDepth = max(out.quoteDepth - 1, 0)
            case ("a", false):
                let href = tag.attribute("href").flatMap(Self.linkTarget)
                links.append(href)
                if href != nil { out.mark("[") }
            case ("a", true):
                if let href = links.popLast() ?? nil { out.mark("](\(href))") }
            case ("img", _):
                let cid = tag.attribute("src").flatMap { $0.lowercased().hasPrefix("cid:") ? String($0.dropFirst(4)) : nil }
                let name = cid.flatMap { attachments[$0] } ?? ""
                out.text(name.isEmpty ? " [image] " : " [image: \(name)] ")
            case ("table", false):
                out.endLine()
                rowsInTable = 0
            case ("table", true):
                out.endLine()
            case ("tr", false):
                out.endLine()
                cell = 0
            case ("tr", true):
                inCell = false
                if cell > 0 {
                    out.mark(" |")
                    out.endLine()
                    rowsInTable += 1
                    if rowsInTable == 1 { out.raw("|" + String(repeating: " --- |", count: cell)) }
                }
            case ("td", false), ("th", false):
                out.mark(cell == 0 ? "| " : " | ")
                cell += 1
                inCell = true
            case ("td", true), ("th", true):
                inCell = false
            case ("hr", _):
                out.endLine()
                out.raw("---")
            default:
                break
            }
        }
        return out.finish()
    }

    /// The body without its first line when that line is the note's title (Notes keeps the title in the body).
    public static func droppingTitle(_ title: String, from markdown: String) -> String {
        let lines = markdown.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = lines.first else { return markdown }
        let plain = first.trimmingCharacters(in: CharacterSet(charactersIn: "#*_~` ")).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, plain == title.trimmingCharacters(in: .whitespaces) else { return markdown }
        return lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Web and mail links only; anything else keeps its text and loses the link.
    static func linkTarget(_ href: String) -> String? {
        let decoded = HTMLEntities.decode(href).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = decoded.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:"),
              !decoded.contains(where: { $0.isWhitespace || $0 == ")" || $0 == "(" }) else { return nil }
        return decoded
    }

    // MARK: Pieces

    private struct Tag {
        var name: String
        var closing: Bool
        var selfClosing: Bool
        private var attributes: Substring

        init(_ inner: String) {
            var text = Substring(inner.trimmingCharacters(in: .whitespacesAndNewlines))
            closing = text.hasPrefix("/")
            if closing { text = text.dropFirst() }
            selfClosing = text.hasSuffix("/")
            let nameEnd = text.firstIndex { !($0.isLetter || $0.isNumber) } ?? text.endIndex
            name = text[..<nameEnd].lowercased()
            attributes = text[nameEnd...]
        }

        /// The value of `key="…"` (or single-quoted, or bare).
        func attribute(_ key: String) -> String? {
            var rest = attributes[...]
            while let range = rest.range(of: key, options: .caseInsensitive) {
                let before = range.lowerBound == rest.startIndex ? " " : rest[rest.index(before: range.lowerBound)]
                var after = rest[range.upperBound...].drop { $0 == " " }
                rest = rest[range.upperBound...]
                guard before.isWhitespace, after.first == "=" else { continue }
                after = after.dropFirst().drop { $0 == " " }
                if let quote = after.first, quote == "\"" || quote == "'" {
                    let body = after.dropFirst()
                    return String(body.prefix { $0 != quote })
                }
                return String(after.prefix { !$0.isWhitespace })
            }
            return nil
        }
    }

    /// Builds lines. Text collapses whitespace as HTML does; a line's list or heading marker waits
    /// until the line has text, so empty `<div>`s don't leave stray bullets. Emphasis still open at
    /// the end of a line is closed there, so a mark never runs on into the next line.
    private struct Writer {
        var lines: [String] = []
        var current = ""
        var prefix = ""
        var quoteDepth = 0
        var preformatted = false
        private var pendingSpace = false
        private var open: [String] = []

        mutating func text(_ html: String) {
            let decoded = HTMLEntities.decode(html)
            if preformatted {
                for (i, part) in decoded.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    if i > 0 { newline() }
                    current += part
                }
                return
            }
            for ch in decoded {
                if ch.isWhitespace || ch == "\u{00A0}" {
                    pendingSpace = !current.isEmpty
                    continue
                }
                space(before: ch)
                current.append(ch)
            }
        }

        mutating func mark(_ m: String) {
            if let first = m.first { space(before: first) }
            current += m
        }

        /// Opens a mark, or closes the one that is open: right after the text, with any skipped space after it.
        mutating func emphasis(_ m: String) {
            if let i = open.lastIndex(of: m) {
                open.remove(at: i)
                current += m
            } else {
                open.append(m)
                mark(m)
            }
        }

        /// One space where whitespace was skipped, never two.
        private mutating func space(before next: Character) {
            if pendingSpace, let last = current.last, !last.isWhitespace, !next.isWhitespace { current += " " }
            pendingSpace = false
        }

        mutating func raw(_ line: String) {
            endLine()
            lines.append(String(repeating: "> ", count: quoteDepth) + line)
        }

        /// Ends the line if it has text (block boundaries repeat in Notes' HTML).
        mutating func endLine() {
            guard !current.trimmingCharacters(in: .whitespaces).isEmpty else {
                current = ""
                pendingSpace = false
                return
            }
            flush()
        }

        /// The end of a heading or list item: its marker never carries over to the next line.
        mutating func endBlock() {
            endLine()
            prefix = ""
        }

        /// A `<br>`: ends the line even when it is empty, which is how Notes writes a blank line.
        mutating func newline() {
            if current.trimmingCharacters(in: .whitespaces).isEmpty {
                current = ""
                pendingSpace = false
                lines.append("")
            } else {
                flush()
            }
        }

        private mutating func flush() {
            let body = Self.tidy(current + open.reversed().joined())
            open = []
            lines.append(String(repeating: "> ", count: quoteDepth) + prefix + body)
            current = ""
            prefix = ""
            pendingSpace = false
        }

        /// Drops marks left with nothing between them: Notes often wraps a blank or a line break in <b>.
        static func tidy(_ line: String) -> String {
            var s = line
            for empty in ["****", "~~~~", "``"] { s = s.replacingOccurrences(of: empty, with: "") }
            s = s.replacingOccurrences(of: "** **", with: " ")
            return s.trimmingCharacters(in: .whitespaces)
        }

        mutating func finish() -> String {
            endLine()
            // At most one blank line in a row, none at the ends.
            var out: [String] = []
            for line in lines {
                if line.isEmpty, out.last?.isEmpty ?? true { continue }
                out.append(line)
            }
            while out.last?.isEmpty == true { out.removeLast() }
            return out.joined(separator: "\n")
        }
    }
}
