import AppKit
import ImageIO
import SidefolkCharacter
import UniformTypeIdentifiers

// Dev tool: renders the character offscreen so changes can be reviewed without a screen.
// Run it from the repository: sprite companions are read from Resources/Companions.
//
//   sidefolk-render <outdir>                 contact sheets: states, accents, folks, gaze, menubar, icon,
//                                            and every sprite companion's states, badges, hit shapes and poses
//   sidefolk-render --icon <dir>             icon-macos-1024.png, Sidefolk.iconset/ and Sidefolk.icns
//   sidefolk-render --menu-bar <dir>         native template PNGs (1x/2x/3x) and vector PDF
//   sidefolk-render --brand-mascot <dir>     rabbit vector marks in navy and white
//   sidefolk-render --live <state> <secs> [companion]
//                                            a real window, for CPU checks ("cycle" walks every state)

let usage = "usage: sidefolk-render <outdir> | --icon <dir> | --menu-bar <dir> | --live <state|cycle> <seconds> [mochi|spark]"

MainActor.assumeIsolated {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "--brand-mascot" where args.count == 2:
        let dir = URL(fileURLWithPath: args[1])
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, ink) in [("navy", CGColor(srgbRed: 15/255, green: 45/255, blue: 91/255, alpha: 1)),
                                ("white", CGColor(gray: 1, alpha: 1))] {
                save(CharacterRenderer.mascotMark(size: CGSize(width: 520, height: 560), scale: 2, ink: ink),
                     dir.appendingPathComponent("mascot-\(name).png"))
                try CharacterRenderer.mascotPDF(size: CGSize(width: 260, height: 280), ink: ink)
                    .write(to: dir.appendingPathComponent("mascot-\(name).pdf"))
                try RabbitBrandMark.svg(ink: name == "white" ? "#FFFFFF" : "#0F2D5B")
                    .write(to: dir.appendingPathComponent("mascot-\(name).svg"), atomically: true, encoding: .utf8)
            }
        } catch { fatalError("Mascot export failed: \(error)") }
    case "--icon" where args.count == 2:
        Icons.write(to: URL(fileURLWithPath: args[1]))
    case "--menu-bar" where args.count == 2:
        let dir = URL(fileURLWithPath: args[1])
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let size = CGSize(width: 18, height: 18)
            for scale in 1...3 {
                let suffix = scale == 1 ? "" : "@\(scale)x"
                save(CharacterRenderer.menuBarTemplate(size: size, scale: CGFloat(scale)),
                     dir.appendingPathComponent("SidefolkMenuBar\(suffix).png"))
            }
            try CharacterRenderer.menuBarPDF(size: size).write(to: dir.appendingPathComponent("SidefolkMenuBar.pdf"))
            let svg = RabbitBrandMark.svg(ink: "#000000", menuBar: true)
            try svg.write(to: dir.appendingPathComponent("SidefolkMenuBar.svg"), atomically: true, encoding: .utf8)
        } catch {
            fatalError("Menu bar asset export failed: \(error)")
        }
    case "--live" where args.count == 3 || args.count == 4:
        let look: CharacterLook
        if args.count == 4 {
            guard let art = Companions.load(args[3]) else { print("no art for \(args[3]) in \(Companions.folder.path)"); exit(2) }
            look = .sprites(art)
        } else {
            look = .sidefolk(.aqua)
        }
        Live.run(state: args[1], seconds: Double(args[2]) ?? 10, look: look)
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
        let accentItems = CharacterAccent.allCases.flatMap { accent in
            [CharacterState.idle, .listening, .sleeping].map { s in
                ("\(accent.rawValue) · \(s.name)", {
                    CharacterRenderer.image(state: s, size: CGSize(width: 150, height: 150), scale: scale, look: .sidefolk(accent))
                })
            }
        }
        save(sheet(title: "Accent colours (Settings › Companion)", columns: 6, cell: CGSize(width: 160, height: 176), items: accentItems),
             dir.appendingPathComponent("accents.png"))
        save(menubarSheet(), dir.appendingPathComponent("menubar.png"))
        save(Icons.image(size: 1024), dir.appendingPathComponent("icon-1024.png"))
        save(iconSizes(), dir.appendingPathComponent("icon-sizes.png"))
        for name in Companions.names {
            guard let art = Companions.load(name) else { print("skipped \(name): art missing in \(Companions.folder.path)"); continue }
            writeSprites(art, to: dir)
        }
        print("wrote contact sheets to \(dir.path)")
    }

    /// A sprite companion in every state, small with badges, its hit shapes, and its raw poses.
    static func writeSprites(_ art: SpriteSet, to dir: URL) {
        let look = CharacterLook.sprites(art)
        let states = CharacterState.gallery
        let title = art.name.capitalized
        save(sheet(title: "\(title) states · 200 pt view (busy states show their first pose)", columns: 5,
                   cell: CGSize(width: 220, height: 236),
                   items: states.map { s in (s.name, { CharacterRenderer.image(state: s, size: CGSize(width: 200, height: 200), scale: scale, look: look) }) }),
             dir.appendingPathComponent("companion-\(art.name).png"))
        save(sheet(title: "\(title) at 104 pt, with badges", columns: 10, cell: CGSize(width: 116, height: 132),
                   items: states.map { s in (s.name, {
                       CharacterRenderer.image(state: s, size: CGSize(width: 104, height: 104), scale: scale,
                                               badges: s == .alert ? [.watching, .count(3)] : s == .thinking ? [.busy, .watching] : [.count(2)],
                                               look: look)
                   }) }), dir.appendingPathComponent("companion-\(art.name)-small.png"))
        save(sheet(title: "\(title) hit shapes (characterPath, from the pose's alpha) over the art", columns: 10,
                   cell: CGSize(width: 116, height: 132), items: states.map { s in (s.name, { hitImage(s, look: look) }) }),
             dir.appendingPathComponent("companion-\(art.name)-hit.png"))
        let poses = Companions.poseFiles(art.name)
        save(sheet(title: "\(title) poses as drawn (\(Companions.folder.lastPathComponent)/\(art.name))", columns: 8,
                   cell: CGSize(width: 150, height: 160), items: poses.map { file in
                       (file.deletingPathExtension().lastPathComponent, { Companions.poseImage(file, size: CGSize(width: 140, height: 127)) })
                   }), dir.appendingPathComponent("companion-\(art.name)-poses.png"))
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

    /// The state with its click-through outline drawn on top, as CharacterView reports it. A sprite's
    /// shape is a stack of pixel runs, so it is filled rather than outlined.
    static func hitImage(_ state: CharacterState, look: CharacterLook = .sidefolk(.aqua)) -> CGImage {
        let side: CGFloat = 104
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.look = look
        view.setState(state, animated: false)
        let art = CharacterRenderer.image(state: state, size: CGSize(width: side, height: side), scale: scale, look: look)
        let context = CGContext(data: nil, width: art.width, height: art.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(art, in: CGRect(x: 0, y: 0, width: art.width, height: art.height))
        context.scaleBy(x: scale, y: scale)
        context.addPath(view.characterPath)
        if case .sprites = look {
            context.setFillColor(NSColor.systemPink.withAlphaComponent(0.4).cgColor)
            context.fillPath()
        } else {
            context.setStrokeColor(NSColor.systemPink.cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
        // Bubbles and panels attach to this frame (characterFrameOnScreen in the app).
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(0.5)
        context.stroke(view.characterFrame)
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
                let image = Icons.image(size: s)
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
    /// Contact sheets and re-exports use the production artwork when run from the repository.
    /// The vector rig remains a fallback for standalone render-tool installations.
    static func image(size: Int) -> CGImage {
        let master = URL(fileURLWithPath: "Resources/Icon/icon-macos-1024.png")
        guard let source = CGImageSourceCreateWithURL(master as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return CharacterRenderer.appIcon(size: size)
        }
        let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.interpolationQuality = .high
        c.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return c.makeImage()!
    }

    static func write(to dir: URL) {
        let set = dir.appendingPathComponent("Sidefolk.iconset")
        try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        save(image(size: 1024), dir.appendingPathComponent("icon-macos-1024.png"))
        for points in [16, 32, 128, 256, 512] {
            save(image(size: points), set.appendingPathComponent("icon_\(points)x\(points).png"))
            save(image(size: points * 2), set.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
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
    static func run(state name: String, seconds: Double, look: CharacterLook) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 200, height: 200), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.look = look
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
            // Calm states should drop to zero running animations once they settle (D20).
            Task { @MainActor in
                for t in stride(from: 5, to: Int(seconds), by: 5) {
                    try? await Task.sleep(for: .seconds(5))
                    // Finished one-shots stay attached until the next commit; only "∞" ones keep drawing.
                    let keys = animationKeys(in: view.layer)
                    print("[live] \(t)s: \(keys.filter { $0.hasSuffix("∞") }.count) looping \(keys.sorted())")
                }
            }
        }
        print("[live] pid \(ProcessInfo.processInfo.processIdentifier) showing \(name) for \(seconds)s")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            NSApp.terminate(nil)
        }
        app.run()
    }

    /// Animations attached anywhere in the tree: loops should come and go with their state.
    static func animations(in layer: CALayer?) -> Int { animationKeys(in: layer).count }

    /// Keys of every attached animation, "∞" marking the repeating ones.
    static func animationKeys(in layer: CALayer?) -> [String] {
        guard let layer else { return [] }
        let own = (layer.animationKeys() ?? []).map { key in
            layer.animation(forKey: key)?.repeatCount == .infinity ? key + "∞" : key
        }
        return own + (layer.sublayers ?? []).flatMap { animationKeys(in: $0) }
    }
}

// MARK: Sprite companions

/// The sprite companions' art in the repository (the app bundles the same folders).
@MainActor
enum Companions {
    static let folder = URL(fileURLWithPath: "Resources/Companions", isDirectory: true)

    static var names: [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).sorted()
    }

    static func load(_ name: String) -> SpriteSet? { SpriteSet(folder: folder.appendingPathComponent(name)) }

    static func poseFiles(_ name: String) -> [URL] {
        let dir = folder.appendingPathComponent(name)
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "webp" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A pose file as drawn, on a faint checkerboard so its transparent margin shows.
    static func poseImage(_ file: URL, size: CGSize) -> CGImage {
        Sheets.draw(size) { context in
            for row in 0..<Int(size.height / 10) + 1 {
                for column in 0..<Int(size.width / 10) + 1 where (row + column) % 2 == 0 {
                    context.setFillColor(NSColor(white: 0, alpha: 0.04).cgColor)
                    context.fill(CGRect(x: CGFloat(column) * 10, y: CGFloat(row) * 10, width: 10, height: 10))
                }
            }
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
    }
}
