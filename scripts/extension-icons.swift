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

let icons: [(folder: String, draw: (CGContext) -> Void)] = [
    ("git", git), ("world-clock", worldClock), ("system-vitals", systemVitals), ("hello-folk", helloFolk), ("weather", weather),
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
