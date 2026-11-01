import Foundation

/// A watched file's text, so a file watch can show what changed (D87). Only plain text files of a modest size are read,
/// by an allow list of kinds: a file watch compares size and time, and reading a photo or a database to keep a copy
/// would cost a lot for nothing a person could read.
enum FileText {
    static let maxBytes = 512 * 1024

    static let textExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "csv", "tsv", "log", "json", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf",
        "html", "htm", "xhtml", "css", "js", "mjs", "ts", "tsx", "jsx", "swift", "py", "rb", "go", "rs", "java", "kt",
        "c", "h", "cpp", "hpp", "m", "sh", "zsh", "sql", "tex", "srt", "vtt", "org", "rst", "adoc",
    ]

    /// The file's lines, made safe to show, or nil when it isn't a small UTF-8 text file.
    static func read(_ path: String, facts: FileFacts) -> String? {
        guard !facts.isDirectory, facts.size <= Double(maxBytes),
              textExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()),
              let data = FileManager.default.contents(atPath: path), !data.contains(0),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return lines(text)
    }

    /// Invisible and bidirectional controls removed from each line (SECURITY T2), trailing spaces trimmed; indentation
    /// stays, since in a file it is part of what changed.
    static func lines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines).map { line in
            var out = String.UnicodeScalarView()
            for u in line.unicodeScalars {
                switch u.value {
                case 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2069, 0xFEFF, 0xE0000...0xE007F: continue
                case 0x00...0x08, 0x0B...0x1F, 0x7F: continue
                case 0x09: out.append(contentsOf: "    ".unicodeScalars)
                default: out.append(u)
                }
            }
            var clean = String(out)
            while clean.last?.isWhitespace == true { clean.removeLast() }
            return clean
        }.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}
