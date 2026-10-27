import Foundation
import PDFKit
import SidefolkExtensionKit

/// PDFs with PDFKit: what one is, its text, several combined into one, and pages taken out into a new file.
/// Originals are never changed; every result is a new file beside them.
enum PDFTools {
    static func open(_ path: String) throws -> PDFDocument {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { throw Problem("\(Paths.show(path)) isn't a PDF I can read.") }
        guard !document.isLocked else { throw Problem("\(Paths.show(path)) is locked with a password.") }
        return document
    }

    static func info(_ raw: String) throws -> String {
        let path = try Paths.full(raw)
        let document = try open(path)
        let attributes = document.documentAttributes ?? [:]
        var parts = ["\((path as NSString).lastPathComponent): \(document.pageCount) page\(document.pageCount == 1 ? "" : "s")"]
        if let page = document.page(at: 0) {
            let box = page.bounds(for: .mediaBox)
            parts.append(String(format: "%.0f × %.0f mm", box.width / 72 * 25.4, box.height / 72 * 25.4) + paper(box.size))
        }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0),
                                               countStyle: .file))
        if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty { parts.append("title “\(title)”") }
        if let author = attributes[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty { parts.append("by \(author)") }
        if document.isEncrypted { parts.append("encrypted") }
        parts.append((document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "no text in it (scanned pages, perhaps)" : "it has text")
        return parts.joined(separator: ", ") + "."
    }

    static func paper(_ size: CGSize) -> String {
        let (w, h) = (min(size.width, size.height), max(size.width, size.height))
        for (name, pw, ph) in [("A4", 595.0, 842.0), ("US Letter", 612.0, 792.0), ("A5", 420.0, 595.0), ("A3", 842.0, 1191.0), ("US Legal", 612.0, 1008.0)]
        where abs(w - pw) < 3 && abs(h - ph) < 3 {
            return " (\(name)\(size.width > size.height ? ", landscape" : ""))"
        }
        return ""
    }

    /// The text of pages `first` to `last`, at most 20,000 characters.
    static func text(_ raw: String, pages: String?) throws -> String {
        let path = try Paths.full(raw)
        let document = try open(path)
        let numbers = try pages.map { try parsePages($0, count: document.pageCount) } ?? Array(1...max(document.pageCount, 1))
        var text = ""
        for n in numbers {
            guard let page = document.page(at: n - 1) else { continue }
            text += "--- Page \(n) ---\n" + (page.string ?? "") + "\n"
            if text.count > 20_000 { break }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Problem("There's no text on those pages (they may be scanned images).") }
        return text.count > 20_000 ? String(text.prefix(20_000)) + "\n[Cut at 20,000 characters: ask for later pages.]" : text
    }

    /// "1-3, 5, 8-" → [1, 2, 3, 5, 8, 9, …].
    static func parsePages(_ text: String, count: Int) throws -> [Int] {
        var pages: [Int] = []
        for part in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
            let ends = part.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard ends.count <= 2, let first = Int(ends[0].isEmpty ? "1" : ends[0]) else { throw Problem("Write pages like 1-3, 5, 8-.") }
            let last = ends.count == 2 ? (ends[1].isEmpty ? count : Int(ends[1]) ?? -1) : first
            guard 1 <= first, first <= last, last <= count else { throw Problem("The PDF has pages 1 to \(count); “\(part)” is outside that.") }
            pages += Array(first...last)
        }
        guard !pages.isEmpty else { throw Problem("Write pages like 1-3, 5, 8-.") }
        return pages
    }

    static func combine(folder raw: String, files: [String], name: String?) throws -> String {
        let folder = try Paths.full(raw)
        guard files.count >= 2 else { throw Problem("Name at least two PDFs in that folder, in the order they go.") }
        let combined = PDFDocument()
        for file in files {
            guard !file.contains("/") else { throw Problem("“\(file)” should be just a file name in \(Paths.show(folder)).") }
            let document = try open(folder + "/" + file)
            for i in 0..<document.pageCount { if let page = document.page(at: i) { combined.insert(page, at: combined.pageCount) } }
        }
        let output = Paths.free(folder + "/" + fileName(name ?? "Combined"))
        guard combined.write(to: URL(fileURLWithPath: output)) else { throw Problem("The combined PDF couldn't be saved.") }
        return "Combined \(files.count) PDFs (\(combined.pageCount) pages) into \(Paths.show(output))."
    }

    static func extract(folder raw: String, file: String, pages: String) throws -> String {
        let folder = try Paths.full(raw)
        guard !file.contains("/") else { throw Problem("“\(file)” should be just a file name in \(Paths.show(folder)).") }
        let document = try open(folder + "/" + file)
        let numbers = try parsePages(pages, count: document.pageCount)
        let result = PDFDocument()
        for n in numbers { if let page = document.page(at: n - 1) { result.insert(page, at: result.pageCount) } }
        let stem = (file as NSString).deletingPathExtension
        let output = Paths.free(folder + "/" + fileName("\(stem) (pages \(pages.replacingOccurrences(of: " ", with: "")))"))
        guard result.write(to: URL(fileURLWithPath: output)) else { throw Problem("The new PDF couldn't be saved.") }
        return "Saved \(numbers.count) page\(numbers.count == 1 ? "" : "s") of \(file) as \(Paths.show(output))."
    }

    /// A safe file name ending in .pdf.
    static func fileName(_ raw: String) -> String {
        let clean = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        let stem = clean.lowercased().hasSuffix(".pdf") ? String(clean.dropLast(4)) : clean
        return (stem.isEmpty ? "Combined" : stem) + ".pdf"
    }
}
