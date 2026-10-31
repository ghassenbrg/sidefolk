#!/usr/bin/env swift
// Deterministic production exports. Run from the repository root: swift scripts/brand-assets.swift
import AppKit
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brand = root.appendingPathComponent("Resources/Brand")
let exports = brand.appendingPathComponent("exports")
let icon = root.appendingPathComponent("Resources/Icon")
let fm = FileManager.default
func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func read(_ path: String) -> CGImage {
    let source = CGImageSourceCreateWithURL(root.appendingPathComponent(path) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}
func save(_ image: CGImage, _ url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot write \(url.path)")
}
func scaled(_ image: CGImage, _ width: Int, _ height: Int) -> CGImage {
    let c = context(width, height)
    c.interpolationQuality = .high
    c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return c.makeImage()!
}
func trimmed(_ image: CGImage, padding: Int = 8) -> CGImage {
    let w = image.width, h = image.height, c = context(image.width, image.height)
    c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = c.data!.assumingMemoryBound(to: UInt8.self)
    var left = w, right = 0, top = h, bottom = 0
    for y in 0..<h { for x in 0..<w where p[(y * w + x) * 4 + 3] > 8 {
        left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
    }}
    left = max(0, left - padding); top = max(0, top - padding)
    right = min(w - 1, right + padding); bottom = min(h - 1, bottom + padding)
    return c.makeImage()!.cropping(to: CGRect(x: left, y: top, width: right-left+1, height: bottom-top+1))!
}
// Preserve the generated edge coverage; make nearly opaque interiors truly opaque. The tiny
// generation alpha variation would otherwise tint white shells when displayed on dark surfaces.
func normalized(_ image: CGImage, ink: (Double, Double, Double)? = nil, trimOutput: Bool = true) -> CGImage {
    let w = image.width, h = image.height, c = context(image.width, image.height)
    c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = c.data!.assumingMemoryBound(to: UInt8.self)
    for i in 0..<(w*h) {
        let at = i*4, old = Double(p[at+3]) / 255
        let alpha = old < 0.04 ? 0 : old > 0.94 ? 1 : old
        let channels = ink.map { [$0.0, $0.1, $0.2] }
        for j in 0..<3 {
            let value = channels?[j] ?? (old > 0 ? min(1, Double(p[at+j])/255/old) : 0)
            p[at+j] = UInt8((value * alpha * 255).rounded())
        }
        p[at+3] = UInt8((alpha * 255).rounded())
    }
    return trimOutput ? trimmed(c.makeImage()!) : c.makeImage()!
}
let navy = (15.0/255, 45.0/255, 91.0/255)
let aqua = (46.0/255, 212.0/255, 217.0/255)
// The wordmark is constructed vector geometry (scripts/wordmark.swift), not a contour trace of the
// reference. One SVG master; all platform formats are rendered from exactly these paths.
final class WordmarkSource: NSObject, XMLParserDelegate {
    var paths: [(CGPath, String)] = []
    var size = CGSize.zero
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "svg", let box = attributes["viewBox"]?.split(separator: " ").compactMap({ Double($0) }), box.count == 4 {
            size = CGSize(width: box[2], height: box[3])
        }
        guard elementName == "path", let data = attributes["d"], let fill = attributes["fill"] else { return }
        let expression = try! NSRegularExpression(pattern: #"[MLCZ]|[-+]?[0-9]*\.?[0-9]+"#)
        let tokens = expression.matches(in: data, range: NSRange(data.startIndex..., in: data))
            .map { String(data[Range($0.range, in: data)!]) }
        let path = CGMutablePath()
        var i = 0
        func point() -> CGPoint {
            let p = CGPoint(x: Double(tokens[i])!, y: Double(tokens[i+1])!)
            i += 2; return p
        }
        while i < tokens.count {
            let command = tokens[i]; i += 1
            switch command {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "C": let c1 = point(), c2 = point(), end = point(); path.addCurve(to: end, control1: c1, control2: c2)
            case "Z": path.closeSubpath()
            default: preconditionFailure("Unsupported wordmark command: \(command)")
            }
        }
        paths.append((path, fill))
    }
}
let wordmarkSource = WordmarkSource()
let wordmarkSVG = try String(contentsOf: brand.appendingPathComponent("masters/wordmark.svg"), encoding: .utf8)
let parser = XMLParser(data: Data(wordmarkSVG.utf8))
parser.delegate = wordmarkSource
// scripts/wordmark.swift writes the master: one path per letter and one per ray.
precondition(parser.parse() && wordmarkSource.paths.count == 10 && wordmarkSource.size.width > 0, "Invalid wordmark master")
let wordmarkSize = wordmarkSource.size
typealias Ink = (Double, Double, Double)
let white: Ink = (1, 1, 1)
/// The wordmark with "Side" in one ink and "folk" with its rays in another.
func drawWordmark(_ c: CGContext, width: CGFloat, height: CGFloat, side: Ink, folk: Ink) {
    c.saveGState()
    c.translateBy(x: 0, y: height)
    c.scaleBy(x: width/wordmarkSize.width, y: -height/wordmarkSize.height)
    for (path, fill) in wordmarkSource.paths {
        let color = fill == "#0F2D5B" ? side : folk
        c.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
        c.addPath(path); c.drawPath(using: .eoFill)
    }
    c.restoreGState()
}
func hex(_ ink: Ink) -> String { String(format: "#%02X%02X%02X", Int(ink.0 * 255), Int(ink.1 * 255), Int(ink.2 * 255)) }
try fm.createDirectory(at: exports, withIntermediateDirectories: true)
// Color for light surfaces; reversed (white "Side", aqua "folk") for dark ones; navy and white single-ink.
var wordmarks: [String: CGImage] = [:]
for (name, side, folk) in [("color", navy, aqua), ("reversed", white, aqua), ("navy", navy, navy), ("white", white, white)] {
    let wc = context(4096, Int((4096 * wordmarkSize.height / wordmarkSize.width).rounded()))
    drawWordmark(wc, width: CGFloat(wc.width), height: CGFloat(wc.height), side: side, folk: folk)
    wordmarks[name] = wc.makeImage()!
    let pdf = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: wordmarkSize)
    let pc = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &mediaBox, nil)!
    pc.beginPDFPage(nil); drawWordmark(pc, width: wordmarkSize.width, height: wordmarkSize.height, side: side, folk: folk)
    pc.endPDFPage(); pc.closePDF()
    try (pdf as Data).write(to: exports.appendingPathComponent("wordmark-\(name).pdf"))
    let svg = wordmarkSVG.replacingOccurrences(of: "#0F2D5B", with: hex(side)).replacingOccurrences(of: "#2ED4D9", with: hex(folk))
    try svg.write(to: exports.appendingPathComponent("wordmark-\(name).svg"), atomically: true, encoding: .utf8)
}
let wordmark = wordmarks["color"]!
let mark = normalized(read("Resources/Brand/masters/rabbit-portrait.png"))
let primaryMark = normalized(read("Resources/Brand/masters/rabbit-family.png"))
let familyArt = normalized(read("Resources/Brand/masters/family-current.png"))
let mono = normalized(read("Resources/Brand/exports/mascot-navy.png"))
try save(normalized(read("Resources/Brand/masters/mascot-mochi.png")), exports.appendingPathComponent("mascot-color.png"))
func tint(_ image: CGImage, _ ink: (Double, Double, Double)) -> CGImage {
    normalized(image, ink: ink, trimOutput: false)
}
func lockup(horizontal: Bool, mark: CGImage, word: CGImage) -> CGImage {
    let w = horizontal ? 1600 : 1200
    // Long rabbit ears make this artwork taller than the earlier robot group. Derive the
    // canvas from the actual art instead of cropping the ears or the wordmark at fixed height.
    let stackHeight = 1080.0 * Double(mark.height)/Double(mark.width)
        + 22 + 1060.0 * Double(word.height)/Double(word.width) + 96
    let h = horizontal ? 520 : Int(ceil(stackHeight))
    let c = context(w, h)
    c.interpolationQuality = .high
    if horizontal {
        let mh = 440.0, mw = mh * Double(mark.width)/Double(mark.height)
        c.draw(mark, in: CGRect(x: 24, y: 40, width: mw, height: mh))
        let ww = Double(w)-mw-100, wh = ww*Double(word.height)/Double(word.width)
        c.draw(word, in: CGRect(x: mw+64, y: (Double(h)-wh)/2, width: ww, height: wh))
    } else {
        let mw = 1080.0, mh = mw * Double(mark.height)/Double(mark.width)
        let ww = 1060.0, wh = ww * Double(word.height)/Double(word.width)
        let total = mh + 22 + wh, base = (Double(h)-total)/2
        c.draw(word, in: CGRect(x: 70, y: base, width: ww, height: wh))
        c.draw(mark, in: CGRect(x: 60, y: base+wh+22, width: mw, height: mh))
    }
    return trimmed(c.makeImage()!, padding: 24)
}
for (name, image) in wordmarks { try save(image, exports.appendingPathComponent("wordmark-\(name).png")) }
// The family on its own, for the first hello and the About window.
try save(familyArt, exports.appendingPathComponent("family-color.png"))
try save(mark, exports.appendingPathComponent("mark-color.png"))
try save(mono, exports.appendingPathComponent("mark-navy.png"))
try save(tint(mono, (1,1,1)), exports.appendingPathComponent("mark-white.png"))
for horizontal in [false, true] {
    let name = horizontal ? "logo-horizontal" : "logo-stacked"
    try save(lockup(horizontal: horizontal, mark: primaryMark, word: wordmark), exports.appendingPathComponent("\(name)-color.png"))
    try save(lockup(horizontal: horizontal, mark: mono, word: tint(wordmark, navy)), exports.appendingPathComponent("\(name)-navy.png"))
    try save(lockup(horizontal: horizontal, mark: tint(mono, (1,1,1)), word: tint(wordmark, (1,1,1))), exports.appendingPathComponent("\(name)-white.png"))
}
// The approved 3D Mochi portrait is independent of the transparent logo mark. Keep its
// full-bleed master committed so rebuilding the brand never restores the earlier icon.
// Platform padding and masks belong only in derived exports, never in the source.
try save(mark, icon.appendingPathComponent("icon-artwork.png"))
let iconMaster = read("Resources/Brand/masters/mochi-app-icon.png")
precondition(iconMaster.width == iconMaster.height, "App icon master must be square")
let rawSource = scaled(iconMaster, 2048, 2048)
try save(rawSource, icon.appendingPathComponent("icon-source-2048.png"))
try save(scaled(rawSource, 1024, 1024), icon.appendingPathComponent("icon-1024.png"))

// Legacy ICNS gets only the native macOS outline/inset as a deterministic 2D mask. Its tile
// has no lighting, rim, extruded edge or shadow. The portrait retains its own studio lighting.
let ac = context(1024, 1024)
ac.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                 cornerWidth: 185, cornerHeight: 185, transform: nil))
ac.clip()
ac.interpolationQuality = .high
ac.draw(rawSource, in: CGRect(x: 100, y: 100, width: 824, height: 824))
let app = ac.makeImage()!
try save(app, icon.appendingPathComponent("icon-macos-1024.png"))
let set = icon.appendingPathComponent("Sidefolk.iconset")
let catalog = icon.appendingPathComponent("Sidefolk.xcassets")
let appSet = catalog.appendingPathComponent("AppIcon.appiconset")
var catalogImages: [[String: Any]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(points)x\(points)\(suffix).png"
        try save(scaled(app, points*scale, points*scale), set.appendingPathComponent(name))
        try save(scaled(app, points*scale, points*scale), appSet.appendingPathComponent(name))
        catalogImages.append(["filename": name, "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x"])
    }
}
try JSONSerialization.data(withJSONObject: ["info": ["author": "Sidefolk", "version": 1]], options: [.prettyPrinted, .sortedKeys])
    .write(to: catalog.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["images": catalogImages, "info": ["author": "Sidefolk", "version": 1]], options: [.prettyPrinted, .sortedKeys])
    .write(to: appSet.appendingPathComponent("Contents.json"))
for (name, filename, image) in [("AppIconSource", "icon-source-2048.png", rawSource),
                                 ("IconArtwork", "icon-artwork.png", mark)] {
    let imageSet = catalog.appendingPathComponent("\(name).imageset")
    try save(image, imageSet.appendingPathComponent(filename))
    try JSONSerialization.data(withJSONObject: ["images": [["filename": filename, "idiom": "universal", "scale": "1x"]],
                                               "info": ["author": "Sidefolk", "version": 1]], options: [.prettyPrinted, .sortedKeys])
        .write(to: imageSet.appendingPathComponent("Contents.json"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", set.path, "-o", icon.appendingPathComponent("Sidefolk.icns").path]
try process.run(); process.waitUntilExit()
precondition(process.terminationStatus == 0, "iconutil failed")
print("Exported standalone transparent logos, wordmarks, marks and macOS iconset / icns.")
