import CoreGraphics
import Foundation

/// An extension's icon: a PNG or a one-page PDF inside its folder, checked as an image and nothing more.
/// Sidefolk reads its bytes from the locked, hash-pinned copy and draws them; nothing in it is run, fetched
/// or followed. SVG is refused: it is XML that can point at other files and addresses, and drawing it
/// safely would need a sanitizer. A PDF gives the same crisp vector shapes.
public enum ExtensionIcon {
    public static let maxBytes = 256 * 1024
    public static let fileTypes = ["png", "pdf"]
    /// Pixel sizes a PNG may have on each side; 512 is the recommended size.
    static let pixels = 64...1024

    /// Nil when `data` is a usable icon of the type its name says; otherwise what is wrong, for the author.
    static func problem(_ data: Data, fileName: String) -> String? {
        guard data.count <= maxBytes else { return "is \(data.count / 1024) KiB; icons can be at most 256 KiB." }
        switch (fileName as NSString).pathExtension.lowercased() {
        case "png": return pngProblem(data)
        case "pdf": return pdfProblem(data)
        default: return "must be a .png or .pdf file (SVG isn't accepted; export it as PDF)."
        }
    }

    /// The signature and the IHDR chunk are enough to know the size; the pixels are only decoded when drawn.
    private static func pngProblem(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(24))
        guard bytes.count == 24, bytes[0..<8].elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
              bytes[12..<16].elementsEqual(Array("IHDR".utf8)) else { return "isn't a PNG image." }
        func int(_ at: Int) -> Int { bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        let (width, height) = (int(16), int(20))
        guard width == height else { return "must be square; it is \(width)×\(height) pixels." }
        guard pixels.contains(width) else { return "must be between 64 and 1024 pixels on each side (512 is best); it is \(width)." }
        return nil
    }

    private static func pdfProblem(_ data: Data) -> String? {
        guard data.starts(with: Array("%PDF-".utf8)), let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { return "isn't a PDF document." }
        guard !document.isEncrypted else { return "is an encrypted PDF." }
        guard document.numberOfPages == 1, let box = document.page(at: 1)?.getBoxRect(.mediaBox),
              box.width > 0, box.height > 0 else { return "must be a PDF with exactly one page." }
        let ratio = box.width / box.height
        guard (0.95...1.05).contains(ratio) else { return "must be square; its page is \(Int(box.width))×\(Int(box.height)) points." }
        return nil
    }
}
