// Turns generated companion poses (transparent PNGs, any size) into the app's pose files.
//   swift scripts/companion-art.swift <masters-dir> <out-dir> [size]
// e.g. swift scripts/companion-art.swift ~/art/mochi Resources/Companions/mochi  (masters: generated PNGs)
// <masters-dir>/<pose>.png → <out-dir>/<pose>.png, `size`×`size` (default 512).
//
// Every pose of a character gets the same scale, taken from idle (its opaque height fills
// `fill` of the canvas), so states never change size; each pose's feet sit on one baseline and
// its horizontal position is kept as drawn, so raising an arm doesn't slide the body sideways.
// A pose that was drawn at a different size than idle can be corrected with
// <masters-dir>/scale.json, e.g. {"wave": 0.88} (the ones used are Resources/Companions/<id>-scale.json).
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: swift scripts/companion-art.swift <masters-dir> <out-dir> [size]")
    exit(2)
}
let masters = URL(fileURLWithPath: args[1], isDirectory: true)
let out = URL(fileURLWithPath: args[2], isDirectory: true)
let size = args.count > 3 ? Int(args[3])! : 512
let fill = 0.76          // idle's opaque height as a share of the canvas (room above for raised arms)
let baseline = 0.04      // gap under the feet, as a share of the canvas
let corrections = (try? JSONSerialization.jsonObject(with: Data(contentsOf: masters.appendingPathComponent("scale.json")))) as? [String: Double] ?? [:]

func load(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// RGBA pixels, premultiplied, rows top to bottom.
func pixels(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (data, w, h)
}

/// The opaque part of the picture (alpha above a faint threshold), in top-left pixel coordinates.
func opaqueBounds(_ image: CGImage) -> CGRect {
    let (data, w, h) = pixels(image)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where data[(y * w + x) * 4 + 3] > 10 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return .zero }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func write(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "companion-art", code: 1, userInfo: [NSLocalizedDescriptionKey: "can't write \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "companion-art", code: 2, userInfo: [NSLocalizedDescriptionKey: "can't write \(url.path)"])
    }
}

guard let idle = load(masters.appendingPathComponent("idle.png")) else {
    print("no idle.png in \(masters.path): idle sets the scale for every pose")
    exit(1)
}
let idleBounds = opaqueBounds(idle)
let scale = Double(size) * fill / idleBounds.height
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let poses = try FileManager.default.contentsOfDirectory(atPath: masters.path).filter { $0.hasSuffix(".png") }.sorted()
for file in poses {
    let pose = String(file.dropLast(4))
    guard let image = load(masters.appendingPathComponent(file)) else { print("skip \(file): unreadable"); continue }
    guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst else {
        print("skip \(file): no transparency")
        continue
    }
    let bounds = opaqueBounds(image)
    // Same scale as idle (pictures may come at different sizes, so measure in each picture's own width).
    let k = scale * (corrections[pose] ?? 1) * Double(idle.width) / Double(image.width)
    let drawn = CGSize(width: Double(image.width) * k, height: Double(image.height) * k)
    // Feet on the baseline; horizontally, the picture's own centre on the canvas centre.
    let feet = (bounds.maxY) * k
    let origin = CGPoint(x: (Double(size) - drawn.width) / 2,
                         y: Double(size) * baseline - (drawn.height - feet))   // CoreGraphics y grows upwards
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(origin: origin, size: drawn))
    let result = ctx.makeImage()!
    let fit = opaqueBounds(result)
    if fit.minY <= 0 || fit.minX <= 0 || fit.maxX >= CGFloat(size - 1) {
        print("warning \(pose): touches the edge of the canvas (\(Int(fit.minX)),\(Int(fit.minY)) \(Int(fit.width))x\(Int(fit.height)))")
    }
    try write(result, to: out.appendingPathComponent(file))
    print("\(pose): \(Int(fit.width))x\(Int(fit.height))")
}
