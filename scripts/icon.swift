// Code-native app icon; run with `swift scripts/icon.swift` on macOS.
import AppKit
import Foundation

let target = URL(fileURLWithPath: "assets/sidefolk.iconset")
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
func draw(_ size: Int, _ name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size)
    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { NSColor(red: r, green: g, blue: b, alpha: 1).setFill() }
    func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) { NSBezierPath(ovalIn: NSRect(x: x*scale, y: y*scale, width: w*scale, height: h*scale)).fill() }
    color(0.95, 0.96, 0.91)
    NSBezierPath(roundedRect: NSRect(x: scale*0.06, y: scale*0.06, width: scale*0.88, height: scale*0.88), xRadius: scale*0.2, yRadius: scale*0.2).fill()
    color(0.64, 0.73, 0.55)
    oval(0.24,0.58,0.19,0.31); oval(0.57,0.58,0.19,0.31); oval(0.17,0.21,0.66,0.55)
    color(0.82,0.86,0.72); oval(0.28,0.68,0.09,0.14); oval(0.63,0.68,0.09,0.14)
    color(0.96,0.95,0.87); oval(0.29,0.29,0.42,0.24)
    color(0.21,0.27,0.19); oval(0.35,0.5,0.052,0.075); oval(0.60,0.5,0.052,0.075)
    color(0.88,0.69,0.60); oval(0.28,0.43,0.08,0.035); oval(0.65,0.43,0.08,0.035)
    let smile = NSBezierPath(); smile.move(to:NSPoint(x:0.43*scale,y:0.41*scale)); smile.curve(to:NSPoint(x:0.57*scale,y:0.41*scale),controlPoint1:NSPoint(x:0.47*scale,y:0.36*scale),controlPoint2:NSPoint(x:0.53*scale,y:0.36*scale)); smile.lineWidth=0.012*scale
    NSColor(red:0.30,green:0.36,blue:0.25,alpha:1).setStroke(); smile.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent(name))
}
for size in [16,32,128,256,512] { try draw(size, "icon_\(size)x\(size).png"); try draw(size*2, "icon_\(size)x\(size)@2x.png") }
