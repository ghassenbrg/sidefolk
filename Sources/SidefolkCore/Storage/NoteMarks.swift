import Foundation

/// The formatting a note's text can carry (D53). A note stays plain text written in a small Markdown, so search,
/// agents, export and older versions read it as they always did; the editor shows it formatted. Ranges are UTF-16
/// (`NSRange`), for the text view.
public enum NoteMarks {
    public enum Block: Equatable, Sendable {
        case paragraph
        case heading(Int)
        case bullet
        case numbered(Int)
        case check(done: Bool)
        case quote
    }

    /// A line's block and the marker that makes it one ("## ", "- ", "3. ", "- [x] ", "> "), as a length from the
    /// line's start (leading spaces of a nested list included).
    public struct Line: Equatable, Sendable {
        public var block: Block
        public var marker: Int
        /// Spaces before the marker, for nested lists.
        public var indent: Int
        /// Where "[ ]" or "[x]" sits in a checklist line.
        public var box: NSRange?
    }

    public enum Inline: Equatable, Sendable { case bold, italic, strike, code, link }

    /// An inline span: the whole range, and the marker ranges inside it that aren't content.
    public struct Span: Equatable, Sendable {
        public var kind: Inline
        public var range: NSRange
        public var markers: [NSRange]
    }

    // MARK: Blocks

    public static func line(_ text: String) -> Line {
        let ns = text as NSString
        var indent = 0
        while indent < ns.length, ns.character(at: indent) == 0x20 { indent += 1 }
        let rest = ns.substring(from: indent)
        if indent == 0, let m = rest.firstMatch(of: #/^(#{1,3}) /#) {
            return Line(block: .heading(m.1.count), marker: m.0.utf16.count, indent: 0)
        }
        if let m = rest.firstMatch(of: #/^[-*] \[([ xX])\] ?/#) {
            let box = NSRange(location: indent + 2, length: 3)
            return Line(block: .check(done: m.1 != " "), marker: indent + m.0.utf16.count, indent: indent, box: box)
        }
        if let m = rest.firstMatch(of: #/^[-*•] /#) {
            return Line(block: .bullet, marker: indent + m.0.utf16.count, indent: indent)
        }
        if let m = rest.firstMatch(of: #/^(\d{1,3})[.)] /#), let n = Int(m.1) {
            return Line(block: .numbered(n), marker: indent + m.0.utf16.count, indent: indent)
        }
        if indent == 0, let m = rest.firstMatch(of: #/^> ?/#) {
            return Line(block: .quote, marker: m.0.utf16.count, indent: 0)
        }
        return Line(block: .paragraph, marker: 0, indent: 0)
    }

    /// What Return starts the next line with: the same kind of item ("2. " after "1. ", an open box after any box),
    /// or nil when the line isn't a list item. An empty item ends the list instead: `""`.
    public static func continuation(of text: String) -> String? {
        let l = line(text)
        let content = (text as NSString).substring(from: min(l.marker, (text as NSString).length)).trimmingCharacters(in: .whitespaces)
        let pad = String(repeating: " ", count: l.indent)
        switch l.block {
        case .bullet: return content.isEmpty ? "" : pad + "- "
        case .numbered(let n): return content.isEmpty ? "" : pad + "\(n + 1). "
        case .check: return content.isEmpty ? "" : pad + "- [ ] "
        case .quote: return content.isEmpty ? "" : "> "
        case .paragraph, .heading: return nil
        }
    }

    /// `text` with the checklist box of the line starting at `lineStart` ticked or unticked; nil if that line has none.
    public static func toggledCheck(_ text: String, lineStart: Int) -> String? {
        let ns = text as NSString
        guard lineStart <= ns.length else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
        let l = line(ns.substring(with: lineRange).trimmingCharacters(in: .newlines))
        guard case .check(let done) = l.block, let box = l.box else { return nil }
        let at = NSRange(location: lineRange.location + box.location + 1, length: 1)
        return ns.replacingCharacters(in: at, with: done ? " " : "x")
    }

    /// The line's text with its block marker set to `block` (or removed, for a paragraph). Toggling the same kind
    /// again removes it, as a formatting button does.
    public static func setting(_ block: Block, on text: String) -> String {
        let current = line(text)
        let body = (text as NSString).substring(from: min(current.marker, (text as NSString).length))
        let same: Bool = switch (current.block, block) {
        case (.heading(let a), .heading(let b)): a == b
        case (.bullet, .bullet), (.numbered, .numbered), (.check, .check), (.quote, .quote): true
        default: false
        }
        if same { return String(repeating: " ", count: current.indent) + body }
        let pad = String(repeating: " ", count: current.indent)
        switch block {
        case .paragraph: return pad + body
        case .heading(let n): return String(repeating: "#", count: min(max(n, 1), 3)) + " " + body
        case .bullet: return pad + "- " + body
        case .numbered(let n): return pad + "\(n). " + body
        case .check(let done): return pad + (done ? "- [x] " : "- [ ] ") + body
        case .quote: return "> " + body
        }
    }

    // MARK: Inline

    /// Bold (`**`), italic (`*` or `_`), strikethrough (`~~`), code (`` ` ``) and links (`[label](url)`) in one line.
    /// Code wins over everything inside it; spans don't nest across each other.
    public static func spans(in text: String) -> [Span] {
        let ns = text as NSString
        var spans: [Span] = []
        var taken = IndexSet()
        func add(_ kind: Inline, _ pattern: String, open: Int, close: Int) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let r = m.range
                guard r.length > open + close, !taken.intersects(integersIn: r.location..<(r.location + r.length)) else { continue }
                taken.insert(integersIn: r.location..<(r.location + r.length))
                spans.append(Span(kind: kind, range: r, markers: [NSRange(location: r.location, length: open),
                                                                  NSRange(location: r.location + r.length - close, length: close)]))
            }
        }
        add(.code, "`[^`\\n]+`", open: 1, close: 1)
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\((https?://[^)\\s]+)\\)") {
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let r = m.range, label = m.range(at: 1)
                guard !taken.intersects(integersIn: r.location..<(r.location + r.length)) else { continue }
                taken.insert(integersIn: r.location..<(r.location + r.length))
                let after = label.location + label.length
                spans.append(Span(kind: .link, range: r, markers: [NSRange(location: r.location, length: 1),
                                                                    NSRange(location: after, length: r.location + r.length - after)]))
            }
        }
        add(.bold, "\\*\\*(?=\\S)[^\\n]*?\\S\\*\\*", open: 2, close: 2)
        add(.strike, "~~(?=\\S)[^\\n]*?\\S~~", open: 2, close: 2)
        add(.italic, "(?<![\\w*])\\*(?=[^\\s*])[^*\\n]*?[^\\s*]\\*(?![\\w*])|(?<![\\w*])\\*[^\\s*]\\*(?![\\w*])", open: 1, close: 1)
        add(.italic, "(?<![\\w_])_(?=\\S)[^_\\n]*?\\S_(?![\\w_])", open: 1, close: 1)
        return spans.sorted { $0.range.location < $1.range.location }
    }

    /// The link's address in a `[label](url)` span.
    public static func url(of span: Span, in text: String) -> URL? {
        guard span.kind == .link, let close = span.markers.last else { return nil }
        let inner = (text as NSString).substring(with: NSRange(location: close.location + 2, length: close.length - 3))
        return URL(string: inner)
    }

    /// One line as words, without its marks: "- [ ] **Oat** milk" reads "Oat milk".
    public static func plain(_ text: String) -> String {
        let l = line(text)
        let ns = text as NSString
        var body = ns.substring(from: min(l.marker, ns.length)) as NSString
        for span in spans(in: body as String).reversed() {
            for marker in span.markers.reversed() { body = body.replacingCharacters(in: marker, with: "") as NSString }
        }
        return (body as String).trimmingCharacters(in: .whitespaces)
    }
}
