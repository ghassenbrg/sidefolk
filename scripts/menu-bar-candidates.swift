#!/usr/bin/env swift
// Design exploration for the 18 pt menu bar template: every candidate drawn at real size on light and
// dark bars beside system menu bar symbols, as 1x pixels, and magnified. The shipped glyph comes from
// Resources/MenuBar/SidefolkMenuBar.pdf and the previous one from the large monochrome mark it was
// shrunk from. Run from the repository root: swift scripts/menu-bar-candidates.swift <out.png>
import AppKit
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/menu-bar-candidates.png", relativeTo: root)

// MARK: Shared Mochi geometry (18 × 18 pt, y down)

func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, angle: Double = 0) -> CGPath {
    var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle * .pi / 180)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &t)
}
let head = ellipse(9, 11.3, 6.9, 5.5)
let leftEar = ellipse(5.8, 4.9, 2.05, 4.3, angle: -16)
let rightEar = ellipse(12.2, 4.9, 2.05, 4.3, angle: 16)
let ears = leftEar.union(rightEar)
let silhouette = head.union(ears)
let eyes = ellipse(6.5, 11.7, 0.95, 1.15).union(ellipse(11.5, 11.7, 0.95, 1.15))
let nose = ellipse(9, 12.85, 0.75, 0.48)
/// The upper part of each ear, as the brand's navy ear tips.
let tips: CGPath = {
    func tip(_ ear: CGPath, _ cx: Double, _ angle: Double) -> CGPath {
        var t = CGAffineTransform(translationX: cx, y: 4.9).rotated(by: angle * .pi / 180)
        return ear.intersection(CGPath(rect: CGRect(x: -4, y: -6, width: 8, height: 5.4), transform: &t))
    }
    return tip(leftEar, 5.8, -16).union(tip(rightEar, 12.2, 16))
}()
let scarf: CGPath = {
    let band = CGPath(roundedRect: CGRect(x: 3.2, y: 14.6, width: 11.6, height: 2.6), cornerWidth: 1.3, cornerHeight: 1.3, transform: nil)
    let tail = CGPath(roundedRect: CGRect(x: 10.6, y: 15.2, width: 2.6, height: 2.8), cornerWidth: 1.1, cornerHeight: 1.1, transform: nil)
    return band.union(tail)
}()
func outlined(_ p: CGPath, _ width: Double) -> CGPath { p.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10) }
/// A ring of clear space around a shape, so the shapes beside it read as separate pieces.
func gap(_ p: CGPath, _ width: Double) -> CGPath { outlined(p, width * 2) }

struct Candidate {
    var name: String
    var note: String
    var draw: (CGContext) -> Void
}

func fill(_ c: CGContext, _ p: CGPath) { c.addPath(p); c.fillPath() }
func clear(_ c: CGContext, _ p: CGPath) { c.saveGState(); c.setBlendMode(.clear); c.addPath(p); c.fillPath(); c.restoreGState() }

/// A vector or image file drawn into the 18 pt box.
func file(_ path: String) -> (CGContext) -> Void {
    let image = NSImage(contentsOf: root.appendingPathComponent(path))
    return { c in
        guard let image else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
        image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}

let candidates: [Candidate] = [
    Candidate(name: "Before", note: "the large monochrome mark shrunk: rays, paw, scarf and outline compete at 18 pt",
              draw: file("Resources/Brand/exports/mascot-navy.pdf")),
    Candidate(name: "A · solid", note: "filled head and ears, eyes cut out: bold, but the ears merge into one blob") { c in
        fill(c, silhouette); clear(c, eyes)
    },
    Candidate(name: "B · outline", note: "1.5 pt outline and two eyes: calm and Apple-like, a generic bunny") { c in
        fill(c, outlined(silhouette, 1.5)); fill(c, eyes)
    },
    Candidate(name: "C · ear tips", note: "outline with solid ear tips, eyes: the brand's navy tips read even at 1x") { c in
        fill(c, outlined(silhouette, 1.5)); fill(c, tips); fill(c, eyes)
    },
    Candidate(name: "C2 · ear tips + nose", note: "C with Mochi's nose: the face reads as Mochi rather than any bunny") { c in
        fill(c, outlined(silhouette, 1.5)); fill(c, tips); fill(c, eyes); fill(c, nose)
    },
    Candidate(name: "D · solid + scarf", note: "filled head with a separate scarf: Mochi, but heavy beside system glyphs") { c in
        fill(c, silhouette.subtracting(gap(scarf, 0.8))); fill(c, scarf); clear(c, eyes)
    },
    Candidate(name: "E · tips + scarf", note: "C with the scarf as one shape: most Mochi, crowded at 1x") { c in
        fill(c, outlined(silhouette, 1.5).subtracting(gap(scarf, 0.8))); fill(c, tips); fill(c, scarf); fill(c, eyes)
    },
    Candidate(name: "Shipped · C2", note: "eyes and nose on whole 2x pixels, all inside the 18 pt box (Resources/MenuBar)",
              draw: file("Resources/MenuBar/SidefolkMenuBar.pdf")),
]

// MARK: Rendering

let scale: CGFloat = 2
func bitmap(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
/// The glyph as an alpha mask at `pixels` per point, like the template macOS tints.
func mask(_ draw: (CGContext) -> Void, pixels: CGFloat) -> CGImage {
    let c = bitmap(Int(18 * pixels), Int(18 * pixels))
    c.translateBy(x: 0, y: 18 * pixels); c.scaleBy(x: pixels, y: -pixels)
    c.setFillColor(CGColor(gray: 0, alpha: 1))
    draw(c)
    return c.makeImage()!
}
func symbol(_ name: String) -> (CGContext) -> Void {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))!
    return { c in
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
        let s = image.size
        image.draw(in: NSRect(x: (18 - s.width) / 2, y: (18 - s.height) / 2, width: s.width, height: s.height))
        NSGraphicsContext.restoreGraphicsState()
    }
}
let system = ["wifi", "battery.75percent", "magnifyingglass", "switch.2"].map(symbol)

let rowHeight: CGFloat = 100, width: CGFloat = 1330
let height = 70 + CGFloat(candidates.count) * rowHeight
let c = bitmap(Int(width * scale), Int(height * scale))
c.scaleBy(x: scale, y: scale)
NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
c.setFillColor(CGColor(gray: 0.96, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = .init(white: 0.2, alpha: 1)) {
    (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
func tinted(_ m: CGImage, _ rect: CGRect, _ color: NSColor, pixelated: Bool = false) {
    c.saveGState()
    c.interpolationQuality = pixelated ? .none : .high
    c.clip(to: rect, mask: m)
    c.setFillColor(color.cgColor); c.fill(rect)
    c.restoreGState()
}
text("Menu bar template candidates · real size on light and dark bars beside system symbols, then 1x pixels, then 2x pixels magnified ×5",
     16, height - 32, size: 13, weight: .semibold)
for (i, candidate) in candidates.enumerated() {
    let top = height - 60 - CGFloat(i) * rowHeight
    text(candidate.name, 16, top - 22, size: 13, weight: .semibold)
    text(candidate.note, 16, top - 40, size: 11, color: .init(white: 0.4, alpha: 1))
    let retina = mask(candidate.draw, pixels: 2), plain = mask(candidate.draw, pixels: 1)
    for (j, dark) in [false, true].enumerated() {
        let background = dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.985, alpha: 1)
        let ink = dark ? NSColor.white : NSColor(white: 0, alpha: 0.85)
        let bar = CGRect(x: 16 + CGFloat(j) * 320, y: top - 84, width: 300, height: 24)
        c.setFillColor(background.cgColor); c.fill(bar)
        var x = bar.minX + 12
        for draw in system.prefix(2) { tinted(mask(draw, pixels: 2), CGRect(x: x, y: bar.minY + 3, width: 18, height: 18), ink); x += 30 }
        tinted(retina, CGRect(x: x, y: bar.minY + 3, width: 18, height: 18), ink); x += 30
        for draw in system.suffix(2) { tinted(mask(draw, pixels: 2), CGRect(x: x, y: bar.minY + 3, width: 18, height: 18), ink); x += 30 }
        text("Mon 26 Oct 14:05", x + 4, bar.minY + 5, size: 12.5, weight: .medium, color: ink)
        // 1x: each pixel of a non-Retina display shown as one point.
        let one = CGRect(x: 670 + CGFloat(j) * 40, y: top - 81, width: 18, height: 18)
        c.setFillColor(background.cgColor); c.fill(one.insetBy(dx: -6, dy: -3))
        tinted(plain, one, ink, pixelated: true)
        // 2x pixels magnified.
        let detail = CGRect(x: 770 + CGFloat(j) * 100, y: top - 92, width: 90, height: 90)
        c.setFillColor(background.cgColor); c.fill(detail)
        tinted(retina, detail, dark ? .white : .black, pixelated: true)
    }
    if i == 0 {
        text("1x", 690, top - 52, size: 10, color: .init(white: 0.45, alpha: 1))
        text("2x pixels ×5", 830, top - 0, size: 10, color: .init(white: 0.45, alpha: 1))
    }
}
let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, c.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest), "Cannot write \(out.path)")
print("wrote \(out.path)")
