import AppKit
import ImageIO
import SidefolkCharacter
import UniformTypeIdentifiers

// Dev tool: renders the character offscreen so changes can be reviewed without a screen.
//
//   sidefolk-render <outdir>                 contact sheets: states, folks, gaze, menubar, icon
//   sidefolk-render --icon <dir>             icon-1024.png, Sidefolk.iconset/ and Sidefolk.icns
//   sidefolk-render --live <state> <secs>    a real window, for CPU checks ("cycle" walks every state)

let usage = "usage: sidefolk-render <outdir> | --icon <dir> | --live <state|cycle> <seconds>"

MainActor.assumeIsolated {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "--icon" where args.count == 2:
        Icons.write(to: URL(fileURLWithPath: args[1]))
    case "--live" where args.count == 3:
        Live.run(state: args[1], seconds: Double(args[2]) ?? 10)
    case let dir? where !dir.hasPrefix("-"):
        Sheets.write(to: URL(fileURLWithPath: dir))
    default:
        print(usage)
        exit(2)
    }
}

// MARK: Contact sheets

@MainActor
enum Sheets {
    static let scale: CGFloat = 2
    static let paper = NSColor(srgbRed: 0.945, green: 0.953, blue: 0.97, alpha: 1)
    static let ink = NSColor(srgbRed: 0.1, green: 0.13, blue: 0.25, alpha: 1)

    static func write(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let states = CharacterState.gallery
        save(sheet(title: "Sidefolk states · 200 pt view (character ≈ 124 pt)", columns: 5, cell: CGSize(width: 220, height: 236),
                   items: states.map { s in (s.name, { CharacterRenderer.image(state: s, size: CGSize(width: 200, height: 200), scale: scale) }) })
             , dir.appendingPathComponent("states.png"))
        save(sheet(title: "At 104 pt view (character ≈ 64 pt), with badges", columns: 10, cell: CGSize(width: 116, height: 132),
                   items: states.map { s in (s.name, {
                       CharacterRenderer.image(state: s, size: CGSize(width: 104, height: 104), scale: scale,
                                               badges: s == .idle ? [.watching, .count(3)] : s == .thinking ? [.busy, .watching] : [])
                   }) }), dir.appendingPathComponent("states-small.png"))
        save(sheet(title: "The Folk Family", columns: 5, cell: CGSize(width: 200, height: 232),
                   items: Folk.allCases.map { f in ("\(f.displayName) · \(f.role)", { CharacterRenderer.folkImage(f, size: CGSize(width: 180, height: 180), scale: scale) }) }),
             dir.appendingPathComponent("folks.png"))
        let directions: [CGVector?] = [CGVector(dx: -1, dy: 1), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 1),
                                       CGVector(dx: -1, dy: 0), nil, CGVector(dx: 1, dy: 0),
                                       CGVector(dx: -1, dy: -1), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: -1)]
        let gazeItems = [CharacterState.idle, .listening].flatMap { state in
            directions.map { v in
                ("\(state.name) \(v.map { "(\(Int($0.dx)), \(Int($0.dy)))" } ?? "center")",
                 { CharacterRenderer.image(state: state, size: CGSize(width: 150, height: 150), scale: scale, gaze: v) })
            }
        }
        save(sheet(title: "Gaze", columns: 9, cell: CGSize(width: 160, height: 176), items: gazeItems), dir.appendingPathComponent("gaze.png"))
        save(sheet(title: "Hit shapes (characterPath) over the art", columns: 10, cell: CGSize(width: 116, height: 132),
                   items: states.map { s in (s.name, { hitImage(s) }) }), dir.appendingPathComponent("hit.png"))
        save(menubarSheet(), dir.appendingPathComponent("menubar.png"))
        save(CharacterRenderer.appIcon(size: 1024), dir.appendingPathComponent("icon-1024.png"))
        save(iconSizes(), dir.appendingPathComponent("icon-sizes.png"))
        print("wrote contact sheets to \(dir.path)")
    }

    /// A labelled grid. Each item renders lazily so failures point at the cell.
    static func sheet(title: String, columns: Int, cell: CGSize, items: [(String, () -> CGImage)]) -> CGImage {
        let rows = (items.count + columns - 1) / columns
        let header: CGFloat = 40
        let size = CGSize(width: CGFloat(columns) * cell.width, height: CGFloat(rows) * cell.height + header)
        return draw(size) { context in
            paper.setFill()
            NSRect(origin: .zero, size: size).fill()
            label(title, at: CGPoint(x: 16, y: size.height - 28), size: 15, weight: .semibold)
            for (i, (name, make)) in items.enumerated() {
                let col = CGFloat(i % columns), row = CGFloat(i / columns)
                let origin = CGPoint(x: col * cell.width, y: size.height - header - (row + 1) * cell.height)
                let image = make()
                let w = CGFloat(image.width) / scale, h = CGFloat(image.height) / scale
                context.draw(image, in: CGRect(x: origin.x + (cell.width - w) / 2, y: origin.y + cell.height - h - 4, width: w, height: h))
                label(name, at: CGPoint(x: origin.x + 8, y: origin.y + 6), size: 11, weight: .medium, width: cell.width - 16)
            }
        }
    }

    /// The state with its click-through outline drawn on top, as CharacterView reports it.
    static func hitImage(_ state: CharacterState) -> CGImage {
        let side: CGFloat = 104
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.setState(state, animated: false)
        let art = CharacterRenderer.image(state: state, size: CGSize(width: side, height: side), scale: scale)
        let context = CGContext(data: nil, width: art.width, height: art.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(art, in: CGRect(x: 0, y: 0, width: art.width, height: art.height))
        context.scaleBy(x: scale, y: scale)
        context.addPath(view.characterPath)
        context.setStrokeColor(NSColor.systemPink.cgColor)
        context.setLineWidth(1)
        context.strokePath()
        return context.makeImage()!
    }

    static func menubarSheet() -> CGImage {
        let size = CGSize(width: 520, height: 170)
        return draw(size) { context in
            paper.setFill()
            NSRect(origin: .zero, size: size).fill()
            label("Menu bar template · 18 pt @1x and @2x, light and dark bars, then 8× magnified", at: CGPoint(x: 12, y: 148), size: 12, weight: .semibold)
            for (i, dark) in [false, true].enumerated() {
                let bar = CGRect(x: 12, y: 88 - CGFloat(i) * 44, width: 220, height: 30)
                (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill()
                for (j, s) in [1.0, 2.0].enumerated() {
                    let image = CharacterRenderer.menuBarTemplate(size: CGSize(width: 18, height: 18), scale: s)
                    let rect = CGRect(x: bar.minX + 20 + CGFloat(j) * 40, y: bar.minY + 6, width: 18, height: 18)
                    tint(image, in: rect, context: context, color: dark ? .white : .black)
                }
            }
            let big = CharacterRenderer.menuBarTemplate(size: CGSize(width: 18, height: 18), scale: 2)
            context.interpolationQuality = .none
            tint(big, in: CGRect(x: 260, y: 8, width: 144, height: 144), context: context, color: .black)
            let smooth = CharacterRenderer.menuBarTemplate(size: CGSize(width: 100, height: 100), scale: 1)
            tint(smooth, in: CGRect(x: 412, y: 30, width: 100, height: 100), context: context, color: ink)
        }
    }

    static func iconSizes() -> CGImage {
        let sizes = [16, 32, 64, 128, 256]
        let size = CGSize(width: 620, height: 300)
        return draw(size) { context in
            paper.setFill()
            NSRect(origin: .zero, size: size).fill()
            label("App icon at its real pixel sizes", at: CGPoint(x: 12, y: 276), size: 12, weight: .semibold)
            var x: CGFloat = 12
            for s in sizes {
                let image = CharacterRenderer.appIcon(size: s)
                context.draw(image, in: CGRect(x: x, y: 12, width: CGFloat(s), height: CGFloat(s)))
                x += CGFloat(s) + 14
            }
        }
    }

    static func tint(_ mask: CGImage, in rect: CGRect, context: CGContext, color: NSColor) {
        context.saveGState()
        context.clip(to: rect, mask: mask)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.restoreGState()
    }

    static func label(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, width: CGFloat = 1000) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: CGRect(x: point.x, y: point.y, width: width, height: size * 1.4), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink, .paragraphStyle: style,
        ])
    }

    static func draw(_ size: CGSize, _ body: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        body(context)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
}

func save(_ image: CGImage, _ url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(url.path)") }
}

// MARK: Icon assets

@MainActor
enum Icons {
    static func write(to dir: URL) {
        let set = dir.appendingPathComponent("Sidefolk.iconset")
        try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        save(CharacterRenderer.appIcon(size: 1024), dir.appendingPathComponent("icon-1024.png"))
        for points in [16, 32, 128, 256, 512] {
            save(CharacterRenderer.appIcon(size: points), set.appendingPathComponent("icon_\(points)x\(points).png"))
            save(CharacterRenderer.appIcon(size: points * 2), set.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", set.path, "-o", dir.appendingPathComponent("Sidefolk.icns").path]
        do {
            try iconutil.run()
            iconutil.waitUntilExit()
        } catch {
            print("iconutil failed: \(error)")
        }
        print("wrote icon assets to \(dir.path)")
    }
}

// MARK: Live harness

@MainActor
enum Live {
    static func run(state name: String, seconds: Double) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 200, height: 200), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        window.contentView = view
        window.orderFrontRegardless()

        let states = CharacterState.gallery
        if name == "cycle" {
            Task { @MainActor in
                for state in states {
                    view.state = state
                    try? await Task.sleep(for: .seconds(1.5))
                    print("[live] \(state.name): \(animations(in: view.layer)) animations running")
                }
            }
        } else if let state = states.first(where: { $0.name == name }) {
            view.state = state
        }
        print("[live] pid \(ProcessInfo.processInfo.processIdentifier) showing \(name) for \(seconds)s")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            NSApp.terminate(nil)
        }
        app.run()
    }

    /// Animations attached anywhere in the tree: loops should come and go with their state.
    static func animations(in layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        return (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + animations(in: $1) }
    }
}
