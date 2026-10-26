#!/usr/bin/env swift
// Converts the provider logos in Resources/Brand/third-party/simple-icons/ (Simple Icons SVGs, kept as
// downloaded; see the README there) into the vector PDFs the app draws (D36): one 24 × 24 pt page per
// logo, one black shape that the app tints as a template, so it reads in light and dark. macOS's own
// SVG renderer draws the paths, so nothing is retraced. Run from the repository root:
// swift scripts/provider-logos.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sources = root.appendingPathComponent("Resources/Brand/third-party/simple-icons")
let out = root.appendingPathComponent("Resources/Brand/third-party/logos")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let svgs = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "svg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
for svg in svgs {
    guard let image = NSImage(contentsOf: svg), image.representations.contains(where: { "\(type(of: $0))".contains("SVG") }) else {
        fatalError("\(svg.lastPathComponent) isn't an SVG macOS can draw")
    }
    let pdf = out.appendingPathComponent(svg.deletingPathExtension().lastPathComponent + ".pdf")
    var box = CGRect(x: 0, y: 0, width: 24, height: 24)
    guard let context = CGContext(pdf as CFURL, mediaBox: &box, nil) else { fatalError("can't write \(pdf.path)") }
    context.beginPDFPage(nil)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: box)
    NSGraphicsContext.current = nil
    context.endPDFPage()
    context.closePDF()
    print("wrote \(pdf.path.replacingOccurrences(of: root.path + "/", with: ""))")
}
