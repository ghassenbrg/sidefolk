#!/usr/bin/env swift
// Deterministic production exports. Run from the repository root: swift scripts/brand-assets.swift
import AppKit
import ImageIO
import Vision
import CoreImage

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
// Use the actual reference letterforms. No font substitution, generated lettering or text effects.
let reference = read("Resources/Brand/reference/folk-family.png")
let letters = reference.cropping(to: CGRect(x: 43, y: 237, width: 297, height: 80))!
let lc = context(letters.width, letters.height)
lc.draw(letters, in: CGRect(x: 0, y: 0, width: letters.width, height: letters.height))
let lp = lc.data!.assumingMemoryBound(to: UInt8.self)
for y in 0..<letters.height { for x in 0..<letters.width {
    let i = (y * letters.width + x) * 4
    let r = Double(lp[i])/255, g = Double(lp[i+1])/255, b = Double(lp[i+2])/255
    let color = x < 151 ? navy : aqua
    // All letter shapes are below y=16; only the original rays occupy the upper-right strip.
    let allowed = (y >= 16 || x > 258) && b > r * 1.07 && (x < 151 || g > r * 1.12)
    let alpha = allowed ? min(1, max(0, (1-r)/(1-color.0))) : 0
    let a = alpha < 0.08 ? 0 : alpha
    for (j, value) in [color.0, color.1, color.2].enumerated() { lp[i+j] = UInt8((value*a*255).rounded()) }
    lp[i+3] = UInt8((a*255).rounded())
}}
let extractedWordmark = trimmed(lc.makeImage()!, padding: 3)
// Trace only the supplied letter silhouettes, then gently smooth the pixel contours. This
// preserves the reference lettering while providing real scalable vector paths for frameworks.
let mask = context(extractedWordmark.width, extractedWordmark.height)
mask.draw(extractedWordmark, in: CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
let mp = mask.data!.assumingMemoryBound(to: UInt8.self)
for i in 0..<(mask.width * mask.height) {
    let alpha = mp[i*4+3]
    for j in 0..<3 { mp[i*4+j] = 255-alpha }
    mp[i*4+3] = 255
}
let request = VNDetectContoursRequest()
request.detectsDarkOnLight = true
request.contrastAdjustment = 1
request.maximumImageDimension = 2048
let maskImage = CIImage(cgImage: mask.makeImage()!)
let softened = maskImage.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.0])
    .cropped(to: maskImage.extent)
let cleanMask = CIContext().createCGImage(softened, from: maskImage.extent)!
try VNImageRequestHandler(cgImage: scaled(cleanMask, mask.width*4, mask.height*4)).perform([request])
let contour = request.results!.first!.normalizedPath
let trace = CGMutablePath()
var points: [CGPoint] = []
func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x+b.x, y: a.y+b.y) }
func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x-b.x, y: a.y-b.y) }
func mul(_ p: CGPoint, _ s: CGFloat) -> CGPoint { CGPoint(x: p.x*s, y: p.y*s) }
func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x*b.x+a.y*b.y }
func unit(_ p: CGPoint) -> CGPoint { mul(p, 1/max(0.000001, sqrt(dot(p,p)))) }
func normalizedPoint(_ p: CGPoint) -> CGPoint {
    CGPoint(x: p.x/CGFloat(mask.width), y: p.y/CGFloat(mask.height))
}
// Least-squares cubic fitting with a subpixel error bound. Simply connecting every contour
// pixel reproduces the screenshot's stair steps even in an SVG; actual fitted curves do not.
func fitCurve(_ p: [CGPoint], _ left: CGPoint, _ right: CGPoint) {
    let first = p[0], last = p.last!, count = p.count
    if count == 2 {
        let d = sqrt(dot(sub(last,first),sub(last,first)))/3
        trace.addCurve(to: normalizedPoint(last), control1: normalizedPoint(add(first,mul(left,d))),
                       control2: normalizedPoint(add(last,mul(right,d))))
        return
    }
    var u = [CGFloat](repeating: 0, count: count)
    for i in 1..<count { let d = sub(p[i],p[i-1]); u[i] = u[i-1]+sqrt(dot(d,d)) }
    let length = max(0.000001,u.last!)
    u = u.map { $0/length }
    var c00: CGFloat = 0, c01: CGFloat = 0, c11: CGFloat = 0, x0: CGFloat = 0, x1: CGFloat = 0
    for i in 0..<count {
        let t = u[i], s = 1-t, b0 = s*s*s, b1 = 3*t*s*s, b2 = 3*t*t*s, b3 = t*t*t
        let a = mul(left,b1), b = mul(right,b2)
        let delta = sub(p[i],add(mul(first,b0+b1),mul(last,b2+b3)))
        c00 += dot(a,a); c01 += dot(a,b); c11 += dot(b,b)
        x0 += dot(a,delta); x1 += dot(b,delta)
    }
    let det = c00*c11-c01*c01
    var al = abs(det) > 0.00000001 ? (x0*c11-x1*c01)/det : 0
    var ar = abs(det) > 0.00000001 ? (c00*x1-c01*x0)/det : 0
    let chord = sub(last,first), distance = sqrt(dot(chord,chord))
    if al < 0.0001 || ar < 0.0001 || al > length || ar > length { al = distance/3; ar = distance/3 }
    let c1 = add(first,mul(left,al)), c2 = add(last,mul(right,ar))
    var error: CGFloat = 0, split = count/2
    for i in 1..<(count-1) {
        let t = u[i], s = 1-t
        let q = add(add(mul(first,s*s*s),mul(c1,3*t*s*s)),add(mul(c2,3*t*t*s),mul(last,t*t*t)))
        let delta = sub(q,p[i]), e = dot(delta,delta)
        if e > error { error = e; split = i }
    }
    if error <= 0.9*0.9 {
        trace.addCurve(to: normalizedPoint(last), control1: normalizedPoint(c1), control2: normalizedPoint(c2))
    } else {
        let center = unit(sub(p[split-1],p[split+1]))
        fitCurve(Array(p[0...split]),left,center)
        fitCurve(Array(p[split...]),mul(center,-1),right)
    }
}
func finishContour() {
    guard points.count > 2 else { points.removeAll(); return }
    let pixels = points.map { CGPoint(x: $0.x*CGFloat(mask.width), y: $0.y*CGFloat(mask.height)) }
    let minX = pixels.map(\.x).min()!, maxX = pixels.map(\.x).max()!
    let minY = pixels.map(\.y).min()!, maxY = pixels.map(\.y).max()!
    let width = maxX-minX, height = maxY-minY
    let area = abs(pixels.indices.reduce(CGFloat.zero) { sum, i in
        let a = pixels[i], b = pixels[(i+1)%pixels.count]
        return sum+a.x*b.y-b.x*a.y
    })/2
    // The i dot and round counters are intentional geometric forms, not wobbly screenshot edges.
    if width < 23, height < 23, width/height > 0.8, width/height < 1.3, area/(width*height) > 0.68 {
        trace.addEllipse(in: CGRect(x: minX/CGFloat(mask.width), y: minY/CGFloat(mask.height),
                                   width: width/CGFloat(mask.width), height: height/CGFloat(mask.height)))
        points.removeAll(); return
    }
    let tangent = unit(sub(pixels[1],pixels.last!))
    trace.move(to: points[0])
    fitCurve(pixels+[pixels[0]],tangent,mul(tangent,-1))
    trace.closeSubpath()
    points.removeAll()
}
contour.applyWithBlock { element in
    switch element.pointee.type {
    case .moveToPoint: finishContour(); points.append(element.pointee.points[0])
    case .addLineToPoint: points.append(element.pointee.points[0])
    case .closeSubpath: finishContour()
    default: preconditionFailure("Unexpected contour segment")
    }
}
finishContour()
func drawWordmark(_ c: CGContext, width: CGFloat, height: CGFloat) {
    c.scaleBy(x: width, y: height)
    for (rect, color) in [(CGRect(x: 0, y: 0, width: 0.507, height: 1), navy),
                           (CGRect(x: 0.507, y: 0, width: 0.493, height: 1), aqua)] {
        c.saveGState(); c.clip(to: rect)
        c.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
        c.addPath(trace); c.drawPath(using: .eoFill); c.restoreGState()
    }
}
let wc = context(4096, Int((4096.0 * Double(extractedWordmark.height) / Double(extractedWordmark.width)).rounded()))
drawWordmark(wc, width: CGFloat(wc.width), height: CGFloat(wc.height))
let wordmark = wc.makeImage()!
try fm.createDirectory(at: exports, withIntermediateDirectories: true)
let pdf = NSMutableData()
var mediaBox = CGRect(x: 0, y: 0, width: extractedWordmark.width, height: extractedWordmark.height)
let pc = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &mediaBox, nil)!
pc.beginPDFPage(nil); drawWordmark(pc, width: mediaBox.width, height: mediaBox.height)
pc.endPDFPage(); pc.closePDF()
try (pdf as Data).write(to: exports.appendingPathComponent("wordmark-color.pdf"))
var commands: [String] = []
func pointString(_ p: CGPoint) -> String { String(format: "%.7f %.7f", Double(p.x), Double(p.y)) }
trace.applyWithBlock { element in
    let e = element.pointee
    switch e.type {
    case .moveToPoint: commands.append("M"+pointString(e.points[0]))
    case .addCurveToPoint: commands.append("C"+pointString(e.points[0])+" "+pointString(e.points[1])+" "+pointString(e.points[2]))
    case .closeSubpath: commands.append("Z")
    default: preconditionFailure("Unexpected trace segment")
    }
}
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(extractedWordmark.width) \(extractedWordmark.height)">
<defs><path id="letters" d="\(commands.joined(separator: " "))"/><clipPath id="side"><rect width=".507" height="1"/></clipPath><clipPath id="folk"><rect x=".507" width=".493" height="1"/></clipPath></defs>
<g transform="translate(0 \(extractedWordmark.height)) scale(\(extractedWordmark.width) -\(extractedWordmark.height))" fill-rule="evenodd"><use href="#letters" fill="#0F2D5B" clip-path="url(#side)"/><use href="#letters" fill="#2ED4D9" clip-path="url(#folk)"/></g>
</svg>
"""
try svg.write(to: exports.appendingPathComponent("wordmark-color.svg"), atomically: true, encoding: .utf8)
let mark = normalized(read("Resources/Brand/masters/mark-clean.png"))
let primaryCrop = read("Resources/Brand/masters/logo-group.png").cropping(to:
    CGRect(x: 200, y: 55, width: 1100, height: 700))!
let primaryContext = context(primaryCrop.width, primaryCrop.height)
primaryContext.draw(primaryCrop, in: CGRect(x: 0, y: 0, width: primaryCrop.width, height: primaryCrop.height))
let pp = primaryContext.data!.assumingMemoryBound(to: UInt8.self)
// The wordmark's upper-right rays cross the crop boundary. They belong to the lettering,
// which is extracted independently from the original board.
for y in 645..<700 { for x in 1030..<1100 {
    let i = (y*1100+x)*4
    let r = Double(pp[i])/255, g = Double(pp[i+1])/255, b = Double(pp[i+2])/255
    if g > 0.5, b/g < 1.15, r < g*0.99 { for j in 0..<4 { pp[i+j] = 0 } }
} }
// Remove detached crop-edge flecks (including the discarded ray's pale antialias rim).
var seen = [Bool](repeating: false, count: 1100*700)
for start in seen.indices where !seen[start] && pp[start*4+3] > 8 {
    var island = [start], cursor = 0
    seen[start] = true
    while cursor < island.count {
        let at = island[cursor], x = at%1100, y = at/1100
        cursor += 1
        for next in [x > 0 ? at-1 : -1, x < 1099 ? at+1 : -1,
                     y > 0 ? at-1100 : -1, y < 699 ? at+1100 : -1] where next >= 0 {
            if !seen[next], pp[next*4+3] > 8 { seen[next] = true; island.append(next) }
        }
    }
    if island.count < 256 { for at in island { for j in 0..<4 { pp[at*4+j] = 0 } } }
}
let primaryMark = normalized(primaryContext.makeImage()!)
let mono = normalized(read("Resources/Brand/masters/mark-monochrome.png"), ink: navy)
func tint(_ image: CGImage, _ ink: (Double, Double, Double)) -> CGImage {
    normalized(image, ink: ink, trimOutput: false)
}
func lockup(horizontal: Bool, mark: CGImage, word: CGImage) -> CGImage {
    let w = horizontal ? 1600 : 1200, h = horizontal ? 520 : 1200
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
// The reusable source is raw artwork on an edge-to-edge flat square. Platform padding and
// masks belong only in derived exports, never in the source. No rendered tile, bevel or shadow.
try save(mark, icon.appendingPathComponent("icon-artwork.png"))
let raw = context(2048, 2048)
raw.setFillColor(CGColor(gray: 1, alpha: 1))
raw.fill(CGRect(x: 0, y: 0, width: 2048, height: 2048))
raw.interpolationQuality = .high
let artworkWidth = 1680.0, artworkHeight = artworkWidth * Double(mark.height)/Double(mark.width)
raw.draw(mark, in: CGRect(x: (2048-artworkWidth)/2, y: (2048-artworkHeight)/2,
                         width: artworkWidth, height: artworkHeight))
let rawSource = raw.makeImage()!
try save(rawSource, icon.appendingPathComponent("icon-source-2048.png"))
try save(scaled(rawSource, 1024, 1024), icon.appendingPathComponent("icon-1024.png"))

// Legacy ICNS gets only the native macOS outline/inset as a deterministic 2D mask. Its tile
// is perfectly flat white, with no lighting, rim, extruded edge, surface gradient or shadow.
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
