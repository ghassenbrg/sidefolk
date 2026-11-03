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
        // A page draws at its own size, so a few bytes could ask for gigabytes of bitmap.
        guard box.width <= 2048, box.height <= 2048 else { return "is too large: its page must be at most 2048 points on a side." }
        if let why = document.page(at: 1).flatMap(PDFCost.problem) { return why }
        let ratio = box.width / box.height
        guard (0.95...1.05).contains(ratio) else { return "must be square; its page is \(Int(box.width))×\(Int(box.height)) points." }
        return nil
    }
}

/// What a PDF can ask of whoever draws it: its size in bytes says little, as a few kilobytes of nested forms can take minutes. Icons are
/// simple, so this refuses what they don't need: forms inside forms, repeating patterns, drawn fonts, and images larger than a screen.
private enum PDFCost {
    static let deepestForm = 2, mostXObjects = 64, mostPixels = 4_000_000, mostUses = 256, mostContentBytes = 4 * 1024 * 1024

    final class Walk {
        var problem: String?
        var seen = 0
        var depth = 0
    }

    static func problem(_ page: CGPDFPage) -> String? {
        let walk = Walk()
        guard let dictionary = page.dictionary else { return nil }
        check(contentsOf: dictionary, walk)
        var resources: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources { check(resources, walk) }
        return walk.problem
    }

    private static func check(_ resources: CGPDFDictionaryRef, _ walk: Walk) {
        var patterns: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Pattern", &patterns), let patterns {
            each(patterns, walk) { object, walk in
                var stream: CGPDFStreamRef?
                // A shading is a plain gradient; only a tiling pattern draws content, and repeats it.
                if CGPDFObjectGetValue(object, .stream, &stream), stream != nil { walk.problem = "uses a repeating pattern, which an icon doesn't need." }
            }
        }
        var fonts: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts {
            each(fonts, walk) { object, walk in
                var font: CGPDFDictionaryRef?
                var kind: UnsafePointer<CChar>?
                if CGPDFObjectGetValue(object, .dictionary, &font), let font, CGPDFDictionaryGetName(font, "Subtype", &kind), let kind, String(cString: kind) == "Type3" {
                    walk.problem = "uses a drawn font, which an icon doesn't need."
                }
            }
        }
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return }
        each(objects, walk) { object, walk in
            walk.seen += 1
            guard walk.seen <= mostXObjects else { walk.problem = "holds too many parts for an icon."; return }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let info = CGPDFStreamGetDictionary(stream) else { return }
            var kind: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(info, "Subtype", &kind), let kind else { return }
            if String(cString: kind) == "Image" {
                var width: CGPDFInteger = 0, height: CGPDFInteger = 0
                CGPDFDictionaryGetInteger(info, "Width", &width)
                CGPDFDictionaryGetInteger(info, "Height", &height)
                if width <= 0 || height <= 0 || width > 8192 || height > 8192 || width * height > mostPixels { walk.problem = "holds a picture too large for an icon." }
            } else if String(cString: kind) == "Form" {
                guard walk.depth < deepestForm else { walk.problem = "nests its drawing too deeply for an icon."; return }
                checkStream(stream, walk)
                var resources: CGPDFDictionaryRef?
                walk.depth += 1
                if CGPDFDictionaryGetDictionary(info, "Resources", &resources), let resources { check(resources, walk) }
                walk.depth -= 1
            }
        }
    }

    private static func check(contentsOf page: CGPDFDictionaryRef, _ walk: Walk) {
        var stream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(page, "Contents", &stream), let stream { checkStream(stream, walk); return }
        var list: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(page, "Contents", &list), let list else { return }
        guard CGPDFArrayGetCount(list) <= mostXObjects else { walk.problem = "holds too many parts for an icon."; return }
        for index in 0..<CGPDFArrayGetCount(list) {
            var part: CGPDFStreamRef?
            if CGPDFArrayGetStream(list, index, &part), let part { checkStream(part, walk) }
        }
    }

    /// How often it draws its parts: a form used thousands of times is the same cost as thousands of forms.
    private static func checkStream(_ stream: CGPDFStreamRef, _ walk: Walk) {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { return }
        guard data.count <= mostContentBytes else { walk.problem = "holds too much drawing for an icon."; return }
        let uses = String(decoding: data, as: UTF8.self).components(separatedBy: " Do").count - 1
        if uses > mostUses { walk.problem = "draws its parts too many times for an icon." }
    }

    private static func each(_ dictionary: CGPDFDictionaryRef, _ walk: Walk, _ body: @escaping (CGPDFObjectRef, Walk) -> Void) {
        final class Box { let walk: Walk; let body: (CGPDFObjectRef, Walk) -> Void; init(_ w: Walk, _ b: @escaping (CGPDFObjectRef, Walk) -> Void) { walk = w; body = b } }
        let box = Box(walk, body)
        withExtendedLifetime(box) {
            CGPDFDictionaryApplyBlock(dictionary, { _, object, info in
                let box = Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue()
                guard box.walk.problem == nil else { return false }
                box.body(object, box.walk)
                return box.walk.problem == nil
            }, Unmanaged.passUnretained(box).toOpaque())
        }
    }
}
