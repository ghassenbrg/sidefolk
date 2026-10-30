#!/usr/bin/env swift
// Draws the icons of the extensions Sidefolk ships, as one-page square PDFs (vector, a few KB each):
//   swift scripts/extension-icons.swift [--png <folder>] [extension folder names…]
// Name the ones you changed: a PDF records when it was written, so redrawing the others would change
// their files, and every Mac would reinstall them with the next app (BundledExtensions).
// Each icon is full-bleed; Sidefolk rounds the corners where it shows one. Colours are the folks'
// (Resources/Brand, Theme.folkColor). --png also writes 256 px previews for a look.
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let side: CGFloat = 512

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let white = rgb(0xFFFFFF)
let navy = rgb(0x0F2D5B)

/// A soft vertical wash: `top` above, `bottom` below.
func background(_ c: CGContext, top: UInt32, bottom: UInt32) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(top), rgb(bottom)] as CFArray,
                              locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [])
}

func stroke(_ c: CGContext, _ color: CGColor, width: CGFloat, _ build: (CGMutablePath) -> Void) {
    let path = CGMutablePath()
    build(path)
    c.addPath(path)
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.strokePath()
}

func dot(_ c: CGContext, _ center: CGPoint, radius: CGFloat, fill: CGColor, ring: CGColor? = nil, ringWidth: CGFloat = 0) {
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    c.setFillColor(fill)
    c.fillEllipse(in: rect)
    if let ring {
        c.setStrokeColor(ring)
        c.setLineWidth(ringWidth)
        c.strokeEllipse(in: rect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
    }
}

/// Git: a branch leaving the main line and coming back, three commits as rings (Byte's blue).
func git(_ c: CGContext) {
    background(c, top: 0x7CA0FA, bottom: 0x3D66DB)
    let low = CGPoint(x: 186, y: 128), high = CGPoint(x: 186, y: 384), side = CGPoint(x: 326, y: 330)
    stroke(c, white, width: 34) { p in
        p.move(to: CGPoint(x: low.x, y: low.y + 40))
        p.addLine(to: CGPoint(x: high.x, y: high.y - 40))
    }
    // The branch leaves the main line and turns up to its own commit.
    stroke(c, white, width: 34) { p in
        p.move(to: CGPoint(x: low.x, y: 212))
        p.addLine(to: CGPoint(x: side.x - 70, y: 212))
        p.addQuadCurve(to: CGPoint(x: side.x, y: 282), control: CGPoint(x: side.x, y: 212))
    }
    for point in [low, high, side] { dot(c, point, radius: 44, fill: rgb(0x3D66DB), ring: white, ringWidth: 30) }
}

/// World Clock: a globe whose meridians frame clock hands (Tempo's light blue, navy lines).
func worldClock(_ c: CGContext) {
    background(c, top: 0xC4E0FE, bottom: 0x7FB4F7)
    let center = CGPoint(x: 256, y: 256), r: CGFloat = 168
    dot(c, center, radius: r, fill: rgb(0xFFFFFF, 0.55))
    let faint = rgb(0x0F2D5B, 0.35)
    stroke(c, faint, width: 12) { p in
        p.addEllipse(in: CGRect(x: center.x - r * 0.45, y: center.y - r, width: r * 0.9, height: r * 2))
        p.move(to: CGPoint(x: center.x - r, y: center.y))
        p.addLine(to: CGPoint(x: center.x + r, y: center.y))
    }
    stroke(c, navy, width: 22) { p in p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)) }
    stroke(c, navy, width: 26) { p in
        p.move(to: center)
        p.addLine(to: CGPoint(x: center.x, y: center.y + r * 0.66))
        p.move(to: center)
        p.addLine(to: CGPoint(x: center.x + r * 0.5, y: center.y - r * 0.12))
    }
    dot(c, center, radius: 22, fill: navy)
}

/// System Vitals: a pulse line across a calm wash (Seed's mint into aqua).
func systemVitals(_ c: CGContext) {
    background(c, top: 0x8FE3C0, bottom: 0x2EBFC4)
    stroke(c, white, width: 34) { p in
        p.move(to: CGPoint(x: 72, y: 250))
        p.addLine(to: CGPoint(x: 176, y: 250))
        p.addLine(to: CGPoint(x: 214, y: 330))
        p.addLine(to: CGPoint(x: 266, y: 150))
        p.addLine(to: CGPoint(x: 308, y: 300))
        p.addLine(to: CGPoint(x: 336, y: 250))
        p.addLine(to: CGPoint(x: 440, y: 250))
    }
}

/// Hello Folk: a speech bubble saying "…" (Pip's coral).
func helloFolk(_ c: CGContext) {
    background(c, top: 0xFFA195, bottom: 0xF2685A)
    let bubble = CGMutablePath()
    bubble.addRoundedRect(in: CGRect(x: 96, y: 170, width: 320, height: 220), cornerWidth: 70, cornerHeight: 70)
    bubble.move(to: CGPoint(x: 170, y: 190))
    bubble.addLine(to: CGPoint(x: 140, y: 110))
    bubble.addLine(to: CGPoint(x: 240, y: 180))
    c.addPath(bubble)
    c.setFillColor(white)
    c.fillPath()
    for x in [186, 256, 326] as [CGFloat] { dot(c, CGPoint(x: x, y: 280), radius: 24, fill: rgb(0xF2685A)) }
}

/// Weather: a sun behind a cloud (Scout's sun into a summer sky).
func weather(_ c: CGContext) {
    background(c, top: 0x9CCBFA, bottom: 0x4E95EA)
    let sun = CGPoint(x: 310, y: 330)
    stroke(c, rgb(0xFFC93C), width: 22) { p in
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4
            p.move(to: CGPoint(x: sun.x + cos(angle) * 104, y: sun.y + sin(angle) * 104))
            p.addLine(to: CGPoint(x: sun.x + cos(angle) * 134, y: sun.y + sin(angle) * 134))
        }
    }
    dot(c, sun, radius: 78, fill: rgb(0xFFC93C))
    let cloud = CGMutablePath()
    cloud.addRoundedRect(in: CGRect(x: 96, y: 128, width: 300, height: 112), cornerWidth: 56, cornerHeight: 56)
    cloud.addEllipse(in: CGRect(x: 140, y: 168, width: 140, height: 140))
    cloud.addEllipse(in: CGRect(x: 236, y: 156, width: 118, height: 118))
    c.addPath(cloud)
    c.setFillColor(white)
    c.fillPath()
}

func fill(_ c: CGContext, _ color: CGColor, _ build: (CGMutablePath) -> Void) {
    let path = CGMutablePath()
    build(path)
    c.addPath(path)
    c.setFillColor(color)
    c.fillPath()
}

/// Calculator: a white calculator, a display and nine keys (Nova's lilac).
func calculator(_ c: CGContext) {
    background(c, top: 0xD9C4FA, bottom: 0x9B7BE6)
    fill(c, white) { $0.addRoundedRect(in: CGRect(x: 136, y: 88, width: 240, height: 336), cornerWidth: 44, cornerHeight: 44) }
    fill(c, navy) { $0.addRoundedRect(in: CGRect(x: 168, y: 318, width: 176, height: 70), cornerWidth: 16, cornerHeight: 16) }
    for row in 0..<3 { for col in 0..<3 {
        let key = CGRect(x: 168 + CGFloat(col) * 62, y: 124 + CGFloat(row) * 62, width: 50, height: 50)
        fill(c, row == 0 && col == 2 ? rgb(0x9B7BE6) : rgb(0x0F2D5B, 0.18)) { $0.addRoundedRect(in: key, cornerWidth: 12, cornerHeight: 12) }
    } }
}

/// Currency: two coins, one in front of the other, each with its raised rim (Seed's mint).
func currency(_ c: CGContext) {
    background(c, top: 0xA6EDCF, bottom: 0x3BBF8F)
    dot(c, CGPoint(x: 206, y: 306), radius: 118, fill: rgb(0xFFFFFF, 0.55), ring: rgb(0x0F2D5B, 0.25), ringWidth: 14)
    dot(c, CGPoint(x: 306, y: 206), radius: 118, fill: white, ring: navy, ringWidth: 18)
    dot(c, CGPoint(x: 306, y: 206), radius: 78, fill: rgb(0x3BBF8F, 0.25), ring: rgb(0x3BBF8F), ringWidth: 12)
}

/// Playtime: a die showing five (Play's red).
func playtime(_ c: CGContext) {
    background(c, top: 0xFF9C8F, bottom: 0xE0464B)
    fill(c, white) { $0.addRoundedRect(in: CGRect(x: 116, y: 116, width: 280, height: 280), cornerWidth: 64, cornerHeight: 64) }
    for (x, y) in [(186, 186), (326, 186), (256, 256), (186, 326), (326, 326)] as [(CGFloat, CGFloat)] {
        dot(c, CGPoint(x: x, y: y), radius: 30, fill: rgb(0xE0464B))
    }
}

/// Images: a picture with a sun over two hills (Melody's purple).
func images(_ c: CGContext) {
    background(c, top: 0xCDB2FA, bottom: 0x8A5CE6)
    fill(c, white) { $0.addRoundedRect(in: CGRect(x: 92, y: 120, width: 328, height: 272), cornerWidth: 40, cornerHeight: 40) }
    dot(c, CGPoint(x: 330, y: 312), radius: 34, fill: rgb(0xFFC93C))
    fill(c, rgb(0x8A5CE6)) { p in
        p.move(to: CGPoint(x: 120, y: 150)); p.addLine(to: CGPoint(x: 220, y: 290)); p.addLine(to: CGPoint(x: 300, y: 190))
        p.addLine(to: CGPoint(x: 340, y: 240)); p.addLine(to: CGPoint(x: 392, y: 150)); p.closeSubpath()
    }
}

/// PDF Tools: a page with its corner folded and lines of text (Pip's coral).
func pdf(_ c: CGContext) {
    background(c, top: 0xFFA195, bottom: 0xF2685A)
    fill(c, white) { p in
        p.move(to: CGPoint(x: 140, y: 80)); p.addLine(to: CGPoint(x: 372, y: 80)); p.addLine(to: CGPoint(x: 372, y: 350))
        p.addLine(to: CGPoint(x: 296, y: 432)); p.addLine(to: CGPoint(x: 140, y: 432)); p.closeSubpath()
    }
    fill(c, rgb(0xF2685A, 0.45)) { p in p.move(to: CGPoint(x: 296, y: 432)); p.addLine(to: CGPoint(x: 296, y: 350)); p.addLine(to: CGPoint(x: 372, y: 350)); p.closeSubpath() }
    stroke(c, rgb(0xF2685A), width: 20) { p in
        for (y, end) in [(300, 260), (244, 330), (188, 330), (132, 290)] as [(CGFloat, CGFloat)] { p.move(to: CGPoint(x: 182, y: y)); p.addLine(to: CGPoint(x: end, y: y)) }
    }
}

/// QR Codes: three finder squares and a scatter of modules (Byte's blue).
func qrCodes(_ c: CGContext) {
    background(c, top: 0x7CA0FA, bottom: 0x3D66DB)
    fill(c, white) { $0.addRoundedRect(in: CGRect(x: 96, y: 96, width: 320, height: 320), cornerWidth: 36, cornerHeight: 36) }
    for (x, y) in [(128, 288), (288, 288), (128, 128)] as [(CGFloat, CGFloat)] {
        fill(c, navy) { $0.addRoundedRect(in: CGRect(x: x, y: y, width: 96, height: 96), cornerWidth: 18, cornerHeight: 18) }
        fill(c, white) { $0.addRoundedRect(in: CGRect(x: x + 18, y: y + 18, width: 60, height: 60), cornerWidth: 10, cornerHeight: 10) }
        fill(c, navy) { $0.addRoundedRect(in: CGRect(x: x + 32, y: y + 32, width: 32, height: 32), cornerWidth: 6, cornerHeight: 6) }
    }
    for (x, y) in [(288, 128), (336, 160), (304, 208), (352, 240), (256, 176), (240, 240), (368, 128)] as [(CGFloat, CGFloat)] {
        fill(c, navy) { $0.addRoundedRect(in: CGRect(x: x, y: y, width: 32, height: 32), cornerWidth: 6, cornerHeight: 6) }
    }
}

/// Archives: a parcel with a zip down its middle (Brew's tan).
func archives(_ c: CGContext) {
    background(c, top: 0xF3DDB8, bottom: 0xC99A5B)
    fill(c, white) { $0.addRoundedRect(in: CGRect(x: 112, y: 104, width: 288, height: 304), cornerWidth: 40, cornerHeight: 40) }
    fill(c, rgb(0xC99A5B)) { $0.addRect(CGRect(x: 236, y: 104, width: 40, height: 304)) }
    for i in 0..<6 {
        let y = 360 - CGFloat(i) * 40
        fill(c, navy) { $0.addRoundedRect(in: CGRect(x: i.isMultiple(of: 2) ? 226 : 256, y: y, width: 30, height: 18), cornerWidth: 6, cornerHeight: 6) }
    }
    fill(c, navy) { $0.addRoundedRect(in: CGRect(x: 228, y: 136, width: 56, height: 64), cornerWidth: 14, cornerHeight: 14) }
}

/// Dev Toolbox: angle brackets around a slash (Byte's blue, a shade deeper).
func devToolbox(_ c: CGContext) {
    background(c, top: 0x5A7FE8, bottom: 0x23409E)
    stroke(c, white, width: 38) { p in
        p.move(to: CGPoint(x: 196, y: 350)); p.addLine(to: CGPoint(x: 112, y: 256)); p.addLine(to: CGPoint(x: 196, y: 162))
        p.move(to: CGPoint(x: 316, y: 350)); p.addLine(to: CGPoint(x: 400, y: 256)); p.addLine(to: CGPoint(x: 316, y: 162))
    }
    stroke(c, rgb(0xFFC93C), width: 34) { p in p.move(to: CGPoint(x: 284, y: 372)); p.addLine(to: CGPoint(x: 228, y: 140)) }
}

/// Feeds: the feed symbol, a dot and two waves (Scout's sun into orange).
func feeds(_ c: CGContext) {
    background(c, top: 0xFFD46B, bottom: 0xF2913C)
    dot(c, CGPoint(x: 164, y: 164), radius: 44, fill: white)
    stroke(c, white, width: 44) { p in
        p.addArc(center: CGPoint(x: 140, y: 140), radius: 150, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        p.move(to: CGPoint(x: 140 + 264, y: 140))
        p.addArc(center: CGPoint(x: 140, y: 140), radius: 264, startAngle: 0, endAngle: .pi / 2, clockwise: false)
    }
}

/// Clipboard: a board with its clip and three lines of text, a copy stacked behind (Pip's mint into teal).
func clipboard(_ c: CGContext) {
    background(c, top: 0x7FE0C0, bottom: 0x1E9C9A)
    let back = CGPath(roundedRect: CGRect(x: 176, y: 86, width: 232, height: 290), cornerWidth: 34, cornerHeight: 34, transform: nil)
    c.addPath(back)
    c.setFillColor(rgb(0xFFFFFF, 0.45))
    c.fillPath()
    let board = CGPath(roundedRect: CGRect(x: 112, y: 118, width: 248, height: 306), cornerWidth: 38, cornerHeight: 38, transform: nil)
    c.addPath(board)
    c.setFillColor(white)
    c.fillPath()
    let clip = CGPath(roundedRect: CGRect(x: 180, y: 392, width: 112, height: 58), cornerWidth: 22, cornerHeight: 22, transform: nil)
    c.addPath(clip)
    c.setFillColor(rgb(0x0F6E73))
    c.fillPath()
    stroke(c, rgb(0x1E9C9A), width: 26) { p in
        for (y, end) in [(330.0, 300.0), (270.0, 300.0), (210.0, 250.0)] {
            p.move(to: CGPoint(x: 162, y: y))
            p.addLine(to: CGPoint(x: end, y: y))
        }
    }
}

/// Keep Awake: a cup with steam rising (Tempo's sun into a coffee brown).
func keepAwake(_ c: CGContext) {
    background(c, top: 0xFFC97A, bottom: 0xC0703A)
    let cup = CGMutablePath()
    cup.move(to: CGPoint(x: 112, y: 280))
    cup.addLine(to: CGPoint(x: 352, y: 280))
    cup.addCurve(to: CGPoint(x: 232, y: 110), control1: CGPoint(x: 352, y: 170), control2: CGPoint(x: 310, y: 110))
    cup.addCurve(to: CGPoint(x: 112, y: 280), control1: CGPoint(x: 154, y: 110), control2: CGPoint(x: 112, y: 170))
    cup.closeSubpath()
    c.addPath(cup)
    c.setFillColor(white)
    c.fillPath()
    stroke(c, white, width: 30) { p in
        p.addArc(center: CGPoint(x: 352, y: 222), radius: 44, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
    }
    stroke(c, white, width: 24) { p in
        p.move(to: CGPoint(x: 112, y: 86))
        p.addLine(to: CGPoint(x: 352, y: 86))
    }
    stroke(c, rgb(0xFFFFFF, 0.85), width: 22) { p in
        for x in [176.0, 248.0] {
            p.move(to: CGPoint(x: x, y: 318))
            p.addCurve(to: CGPoint(x: x, y: 430), control1: CGPoint(x: x + 34, y: 350), control2: CGPoint(x: x - 34, y: 398))
        }
    }
}

let icons: [(folder: String, draw: (CGContext) -> Void)] = [
    ("git", git), ("world-clock", worldClock), ("system-vitals", systemVitals), ("hello-folk", helloFolk), ("weather", weather),
    ("calculator", calculator), ("currency", currency), ("playtime", playtime), ("images", images), ("pdf", pdf), ("qr-codes", qrCodes),
    ("archives", archives), ("dev-toolbox", devToolbox), ("feeds", feeds), ("clipboard", clipboard), ("keep-awake", keepAwake),
]

let arguments = Array(CommandLine.arguments.dropFirst())
let pngIndex = arguments.firstIndex(of: "--png")
let pngFolder = pngIndex.map { URL(fileURLWithPath: arguments[$0 + 1]) }
let named = Set(arguments.enumerated().filter { pngIndex == nil || ($0.offset != pngIndex! && $0.offset != pngIndex! + 1) }.map(\.element))
for icon in icons where named.isEmpty || named.contains(icon.folder) {
    let url = root.appendingPathComponent("extensions/\(icon.folder)/icon.pdf")
    var box = CGRect(x: 0, y: 0, width: side, height: side)
    let pdf = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextCreator: "Sidefolk extension-icons.swift"] as CFDictionary)!
    pdf.beginPDFPage(nil)
    icon.draw(pdf)
    pdf.endPDFPage()
    pdf.closePDF()
    print("wrote extensions/\(icon.folder)/icon.pdf")
    if let pngFolder, let image = NSImage(contentsOf: url) {
        try? FileManager.default.createDirectory(at: pngFolder, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(x: 0, y: 0, width: 256, height: 256)
        NSBezierPath(roundedRect: rect, xRadius: 56, yRadius: 56).addClip()
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        try? bitmap.representation(using: .png, properties: [:])?.write(to: pngFolder.appendingPathComponent("\(icon.folder).png"))
    }
}
