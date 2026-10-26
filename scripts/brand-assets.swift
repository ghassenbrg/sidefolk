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
// The wordmark is authored vector geometry, not a contour trace of the small reference.
// Keep one editable SVG master; all platform formats are rendered from exactly these paths.
final class WordmarkSource: NSObject, XMLParserDelegate {
    var paths: [(CGPath, String)] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
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
precondition(parser.parse() && wordmarkSource.paths.count == 11, "Invalid wordmark master")
func drawWordmark(_ c: CGContext, width: CGFloat, height: CGFloat, ink: (Double, Double, Double)? = nil) {
    c.saveGState()
    c.translateBy(x: 0, y: height)
    c.scaleBy(x: width/300, y: -height/84)
    for (path, fill) in wordmarkSource.paths {
        let color = ink ?? (fill == "#0F2D5B" ? navy : aqua)
        c.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
        c.addPath(path); c.drawPath(using: .eoFill)
    }
    c.restoreGState()
}
let wc = context(4096, 1147)
drawWordmark(wc, width: CGFloat(wc.width), height: CGFloat(wc.height))
let wordmark = wc.makeImage()!
try fm.createDirectory(at: exports, withIntermediateDirectories: true)
for (name, ink) in [("color", Optional<(Double, Double, Double)>.none), ("navy", navy), ("white", (1.0,1.0,1.0))] {
    let pdf = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 84)
    let pc = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &mediaBox, nil)!
    pc.beginPDFPage(nil); drawWordmark(pc, width: 300, height: 84, ink: ink)
    pc.endPDFPage(); pc.closePDF()
    try (pdf as Data).write(to: exports.appendingPathComponent("wordmark-\(name).pdf"))
    let svg = ink == nil ? wordmarkSVG : wordmarkSVG
        .replacingOccurrences(of: "#0F2D5B", with: name == "white" ? "#FFFFFF" : "#0F2D5B")
        .replacingOccurrences(of: "#2ED4D9", with: name == "white" ? "#FFFFFF" : "#0F2D5B")
    try svg.write(to: exports.appendingPathComponent("wordmark-\(name).svg"), atomically: true, encoding: .utf8)
}
let mark = normalized(read("Resources/Brand/masters/rabbit-portrait.png"))
let primaryMark = normalized(read("Resources/Brand/masters/rabbit-family.png"))
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
try save(wordmark, exports.appendingPathComponent("wordmark-color.png"))
try save(tint(wordmark, navy), exports.appendingPathComponent("wordmark-navy.png"))
try save(tint(wordmark, (1,1,1)), exports.appendingPathComponent("wordmark-white.png"))
try save(mark, exports.appendingPathComponent("mark-color.png"))
try save(mono, exports.appendingPathComponent("mark-navy.png"))
try save(tint(mono, (1,1,1)), exports.appendingPathComponent("mark-white.png"))
for horizontal in [false, true] {
    let name = horizontal ? "logo-horizontal" : "logo-stacked"
    try save(lockup(horizontal: horizontal, mark: primaryMark, word: wordmark), exports.appendingPathComponent("\(name)-color.png"))
    try save(lockup(horizontal: horizontal, mark: mono, word: tint(wordmark, navy)), exports.appendingPathComponent("\(name)-navy.png"))
    try save(lockup(horizontal: horizontal, mark: tint(mono, (1,1,1)), word: tint(wordmark, (1,1,1))), exports.appendingPathComponent("\(name)-white.png"))
}
// The reusable source is raw artwork on an edge-to-edge square. Platform padding and
// masks belong only in derived exports, never in the source. No rendered tile, bevel or shadow.
try save(mark, icon.appendingPathComponent("icon-artwork.png"))
let raw = context(2048, 2048)
// A simple blue gradient matches the supplied icon art. It is background color, not tile lighting.
let blueGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
    CGColor(srgbRed: 91/255, green: 164/255, blue: 250/255, alpha: 1),
    CGColor(srgbRed: 144/255, green: 228/255, blue: 242/255, alpha: 1)
] as CFArray, locations: [0, 1])!
raw.drawLinearGradient(blueGradient, start: CGPoint(x: 1024, y: 0),
                       end: CGPoint(x: 1024, y: 2048), options: [])
raw.interpolationQuality = .high
let artworkHeight = 1950.0, artworkWidth = artworkHeight * Double(mark.width)/Double(mark.height)
raw.draw(mark, in: CGRect(x: (2048-artworkWidth)/2, y: -20,
                         width: artworkWidth, height: artworkHeight))
let rawSource = raw.makeImage()!
try save(rawSource, icon.appendingPathComponent("icon-source-2048.png"))
try save(scaled(rawSource, 1024, 1024), icon.appendingPathComponent("icon-1024.png"))

// Legacy ICNS gets only the native macOS outline/inset as a deterministic 2D mask. Its tile
// has no lighting, rim, extruded edge or shadow. The artwork retains its simple blue gradient.
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
