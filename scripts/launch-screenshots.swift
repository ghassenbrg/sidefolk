// Builds the launch screenshots in docs/launch/screenshots/ from the app's own UI snapshots.
//
//   swift scripts/launch-screenshots.swift              render the snapshots (English, French, Japanese, Arabic), then pick
//   swift scripts/launch-screenshots.swift <snapsdir>   pick from snapshots already rendered into <snapsdir>/<language>/
//
// Run it from the repository root. Rendering takes a few minutes; it runs `swift run SidefolkApp --ui-snapshots`, which draws
// every page offscreen with sample data (English sample data in every language). The hero pictures put real snapshots on a
// plain backdrop beside Mochi's brand art; everything else is a snapshot copied as it is, or scaled down when it is large.
import AppKit
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("docs/launch/screenshots")
let languages = ["en", "fr", "ja", "ar"]

/// Snapshot (without its -light/-dark suffix) → name in the kit. Both appearances unless `lightOnly`.
let picks: [(from: String, to: String, lightOnly: Bool)] = [
    ("window-home-now", "home-now", false),
    ("window-home-notebook", "home-notebook", false),
    ("window-home-activity", "home-activity", false),
    ("desktop-ask", "ask-panel", false),
    ("desktop-ask-apple-notes", "ask-apple-notes", false),
    ("desktop-ask-question", "ask-reply", true),
    ("desktop-ask-listening", "ask-listening", false),
    ("desktop-ask-spoken", "ask-spoken", true),
    ("desktop-bubble-reminder", "bubble-reminder", false),
    ("desktop-bubble-job-failed", "bubble-command-failed", false),
    ("desktop-readouts", "live-values", false),
    ("window-settings-companion", "settings-companion", false),
    ("window-settings-ai", "settings-ai", false),
    ("window-settings-agents", "settings-agents", false),
    ("window-settings-privacy", "settings-approvals", true),
    ("window-settings-voice", "settings-voice", true),
    ("window-settings-extensions", "settings-extensions", true),
    ("window-about", "about", true),
]
/// The same Home page in other languages; Arabic shows the layout right to left.
let translated = ["fr", "ja", "ar"].map { (language: $0, from: "window-home-now", to: "home-now-\($0)") }
/// Pictures wider than this many pixels are scaled down (they are 2x renders; 1600 px still reads sharply at 800 pt).
let maxWidth = 1600

let snaps: URL
if CommandLine.arguments.count > 1 {
    snaps = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    snaps = root.appendingPathComponent("build/launch-snapshots")
    for language in languages {
        var args = ["run", "SidefolkApp", "--ui-snapshots", snaps.appendingPathComponent(language).path]
        if language != "en" { args += ["--language", language] }
        let swift = Process()
        swift.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        swift.arguments = ["swift"] + args
        var env = ProcessInfo.processInfo.environment
        env["SIDEFOLK_RESOURCES"] = root.appendingPathComponent("Resources").path // provider logos and brand art
        swift.environment = env
        try swift.run()
        swift.waitUntilExit()
        guard swift.terminationStatus == 0 else { fatalError("ui-snapshots failed for \(language)") }
    }
}

func load(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("can't read \(url.path)") }
    return image
}

func context(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ image: CGImage, _ name: String) {
    let url = out.appendingPathComponent("\(name).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "can't write \(url.path)")
}

func scaledToFit(_ image: CGImage) -> CGImage {
    guard image.width > maxWidth else { return image }
    let height = Int((Double(image.height) * Double(maxWidth) / Double(image.width)).rounded())
    let c = context(maxWidth, height)
    c.interpolationQuality = .high
    c.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
    return c.makeImage()!
}

func snapshot(_ language: String, _ name: String, dark: Bool) -> URL {
    snaps.appendingPathComponent(language).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
}

try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for pick in picks {
    for dark in pick.lightOnly ? [false] : [false, true] {
        save(scaledToFit(load(snapshot("en", pick.from, dark: dark))), "\(pick.to)-\(dark ? "dark" : "light")")
    }
}
for pick in translated {
    save(scaledToFit(load(snapshot(pick.language, pick.from, dark: false))), "\(pick.to)-light")
}

// MARK: Hero

/// The bubble, the value pills and the Ask panel are rendered on the page's plain background, and their insides share its
/// colour; only the background around them touches the picture's edges (their outlines close them off). A flood fill from
/// the edges takes that background away. Where a view's own soft shadow darkens it, the pixel is the background times
/// some shade, so it becomes black at the matching opacity: the shadow is kept, now over the hero's backdrop.
func cutOut(_ image: CGImage) -> CGImage {
    let width = image.width, height = image.height
    let c = context(width, height)
    c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = c.data!.bindMemory(to: UInt8.self, capacity: c.bytesPerRow * height)
    let row = c.bytesPerRow
    let key = [Double(pixels[0]), Double(pixels[1]), Double(pixels[2])]
    /// How much of the background shows through at `i` (1: all of it), or nil when the pixel is something else.
    func shade(_ i: Int) -> Double? {
        guard pixels[i + 3] == 255 else { return nil } // already cleared, or not part of the opaque page
        let t = (Double(pixels[i]) + Double(pixels[i + 1]) + Double(pixels[i + 2])) / key.reduce(0, +)
        guard t >= 0.5, t <= 1.02, (0..<3).allSatisfy({ abs(Double(pixels[i + $0]) - key[$0] * t) <= 3 }) else { return nil }
        return min(t, 1)
    }
    var stack = (0..<width).flatMap { [($0, 0), ($0, height - 1)] } + (0..<height).flatMap { [(0, $0), (width - 1, $0)] }
    while let (x, y) = stack.popLast() {
        let i = y * row + x * 4
        guard let t = shade(i) else { continue }
        for k in 0..<3 { pixels[i + k] = 0 }
        pixels[i + 3] = UInt8(((1 - t) * 255).rounded())
        if x > 0 { stack.append((x - 1, y)) }
        if x < width - 1 { stack.append((x + 1, y)) }
        if y > 0 { stack.append((x, y - 1)) }
        if y < height - 1 { stack.append((x, y + 1)) }
    }
    return c.makeImage()!
}

/// A desktop-like scene: Home on the left, the Ask panel beside Mochi, a live value and a reminder over Mochi's head.
/// Coordinates are in pixels, origin at the bottom left (Core Graphics).
func hero(dark: Bool) -> CGImage {
    let width = 2400, height = 1300
    let c = context(width, height)
    c.interpolationQuality = .high
    let top = dark ? CGColor(srgbRed: 0.07, green: 0.13, blue: 0.25, alpha: 1) : CGColor(srgbRed: 0.90, green: 0.96, blue: 0.98, alpha: 1)
    let bottom = dark ? CGColor(srgbRed: 0.04, green: 0.08, blue: 0.16, alpha: 1) : CGColor(srgbRed: 0.86, green: 0.91, blue: 0.98, alpha: 1)
    let wash = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(wash, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])

    /// Draws `image` with its top-left corner at (x, top); a window snapshot is rounded off with `radius`, and the
    /// shadow follows what is drawn.
    func place(_ image: CGImage, x: Double, top y: Double, scale: Double, radius: Double = 0, shadow: Bool = true) {
        let rect = CGRect(x: x, y: Double(height) - y - Double(image.height) * scale,
                          width: Double(image.width) * scale, height: Double(image.height) * scale)
        c.saveGState()
        if shadow { c.setShadow(offset: CGSize(width: 0, height: -16), blur: 56, color: CGColor(gray: 0, alpha: dark ? 0.6 : 0.2)) }
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        if radius > 0 { c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); c.clip() }
        c.draw(image, in: rect)
        c.endTransparencyLayer()
        c.restoreGState()
    }

    let suffix = dark ? "dark" : "light"
    let home = load(snaps.appendingPathComponent("en/window-home-now-small-\(suffix).png"))
    let ask = cutOut(load(snaps.appendingPathComponent("en/desktop-ask-\(suffix).png")))
    let bubble = cutOut(load(snaps.appendingPathComponent("en/desktop-bubble-reminder-\(suffix).png")))
    // The sample's first two values (CPU, the weather); the third is a paused one whose text runs out of room.
    let allPills = load(snaps.appendingPathComponent("en/desktop-readouts-\(suffix).png"))
    let pills = cutOut(allPills.cropping(to: CGRect(x: 0, y: 0, width: allPills.width, height: allPills.height * 2 / 3))!)
    let mochi = load(root.appendingPathComponent("Resources/Brand/exports/mascot-color.png"))

    place(home, x: 70, top: 120, scale: 0.70, radius: 22)
    place(ask, x: 1170, top: 330, scale: 0.80)
    // The companion stands on the bottom edge of the screen, as it does on the desktop, values above its head.
    let mochiHeight = 440.0, mochiTop = Double(height) - 50 - mochiHeight, mochiX = 2010.0
    place(mochi, x: mochiX, top: mochiTop, scale: mochiHeight / Double(mochi.height), shadow: false)
    place(pills, x: mochiX + 10, top: mochiTop - 110, scale: 1, shadow: false)
    place(bubble, x: 1830, top: 250, scale: 0.85, shadow: false)
    return c.makeImage()!
}

save(hero(dark: false), "hero-light")
save(hero(dark: true), "hero-dark")
print("Wrote \(out.path)")
