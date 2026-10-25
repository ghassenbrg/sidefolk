import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Turns file bytes into text for the model: plain text in common encodings, and PDFs through PDFKit.
/// Anything else is binary and is refused rather than dumped.
enum FileContent {
    /// Text for `data`, or nil when it looks binary. `data` may end mid-character when the file was cut.
    static func decodeText(_ data: Data) -> String? {
        let head = data.prefix(8_192)
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            let encoding: String.Encoding = data.starts(with: [0xFF, 0xFE]) ? .utf16LittleEndian : .utf16BigEndian
            return String(data: data, encoding: encoding)
        }
        if head.contains(0) { return nil }

        var text: String?
        for cut in 0...3 {   // a cut-off file may end inside a multi-byte character
            if let s = String(data: data.dropLast(cut), encoding: .utf8) { text = s; break }
        }
        if text == nil {
            // Mostly UTF-8 with a few bad bytes is still text; otherwise try the legacy Western encoding.
            let lossy = String(decoding: data, as: UTF8.self)
            let bad = lossy.unicodeScalars.filter { $0.value == 0xFFFD }.count
            if bad * 50 <= max(lossy.unicodeScalars.count, 1) {
                text = lossy
            } else {
                text = String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
            }
        }
        guard let text else { return nil }
        let scalars = text.unicodeScalars
        let control = scalars.filter { $0.value < 0x20 && ![0x09, 0x0A, 0x0D, 0x0C].contains($0.value) }.count
        return control * 20 > max(scalars.count, 1) ? nil : text
    }

    enum PDFResult {
        case text(String, pages: Int)
        case locked
        case unreadable
    }

    static func isPDF(name: String, data: Data) -> Bool {
        (name as NSString).pathExtension.lowercased() == "pdf" || data.starts(with: Array("%PDF".utf8))
    }

    /// Text of the first pages of a PDF, stopping once `maxChars` is reached.
    static func pdfText(_ data: Data, maxChars: Int) -> PDFResult {
        #if canImport(PDFKit)
        guard let document = PDFDocument(data: data) else { return .unreadable }
        if document.isLocked { return .locked }
        var text = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index)?.string, !page.isEmpty { text += page + "\n\n" }
            if text.count > maxChars { break }
        }
        return .text(text, pages: document.pageCount)
        #else
        return .unreadable
        #endif
    }
}
