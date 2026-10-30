import AppKit
import ImageIO
import SidefolkCharacter
import UniformTypeIdentifiers

// Dev tool: renders the character offscreen so changes can be reviewed without a screen.
// Run it from the repository: the comparison sheets read the reference art in Resources/Brand and folk-family.
//
//   sidefolk-render <outdir> [--only <id>]   contact sheets: states, folks, gaze, menubar, icon, every companion
//                                            at rest, and for every companion (or just <id>): states, badges, hit
//                                            shapes, gaze, styles and a comparison with its reference art
//   sidefolk-render --icon <dir>             icon-macos-1024.png, Sidefolk.iconset/ and Sidefolk.icns
//   sidefolk-render --menu-bar <dir>         native template PNGs (1x/2x/3x) and vector PDF
//   sidefolk-render --brand-mascot <dir>     rabbit vector marks in navy and white
//   sidefolk-render --antics <dir> [--only <id>]
//                                            the moments of life: a frame strip per companion and a GIF per moment
//   sidefolk-render --live <state|cycle|demo> <secs> [<id>] [--liveliness L] [--pace n] [--backdrop] [--film dir]
//                                            a real window, for CPU checks ("cycle" walks every state, "demo"
//                                            plays every moment); click, stroke, drag or throw it
//   sidefolk-render --check-companion <folder>
//                                            reads a custom companion (species.json + parts) and says what is wrong
//
// Wherever an <id> is taken, a custom companion works too: a folder path (companions/miso), or the id
// of one in $SIDEFOLK_HOME/companions/.

let usage = "usage: sidefolk-render <outdir> [--only <id>] | --icon <dir> | --menu-bar <dir> | --antics <dir> [--only <id>]"
    + " | --live <state|cycle|demo> <seconds> [<id>] [\(LiveOptions.usage)] | --check-companion <folder>"

// Line by line even into a pipe or a log, so a live run's window id and progress show as they happen.
setvbuf(stdout, nil, _IOLBF, 0)

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
            try MochiMenuGlyph.svg().write(to: dir.appendingPathComponent("SidefolkMenuBar.svg"), atomically: true, encoding: .utf8)
        } catch {
            fatalError("Menu bar asset export failed: \(error)")
        }
    case "--live" where args.count >= 3:
        let hasId = args.count > 3 && !args[3].hasPrefix("--")
        let who = Companion.named(hasId ? args[3] : "sidefolk")
        guard let options = LiveOptions(Array(args.dropFirst(hasId ? 4 : 3))) else { print(usage); exit(2) }
        Live.run(state: args[1], seconds: Double(args[2]) ?? 10, look: who.look, options: options)
    case "--antics" where args.count == 2 || (args.count == 4 && args[2] == "--only"):
        let who = args.count == 4 ? [Companion.named(args[3])] : CharacterSpecies.drawn2D.map(Companion.init)
        AnticSheets.write(to: URL(fileURLWithPath: args[1]), looks: who.map { ($0.id, $0.name, $0.look) })
    case "--check-companion" where args.count == 2:
        let report = CustomCompanions.load(folder: URL(fileURLWithPath: args[1]))
        report.errors.forEach { print("error: \($0)") }
        report.warnings.forEach { print("warning: \($0)") }
        guard let companion = report.companion else { exit(1) }
        print("ok: \(companion.name) (\(companion.id)) draws in every state")
    case let dir? where !dir.hasPrefix("-") && (args.count == 1 || (args.count == 3 && args[1] == "--only")):
        Sheets.write(to: URL(fileURLWithPath: dir), only: args.count == 3 ? Companion.named(args[2]) : nil)
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

    static func write(to dir: URL, only: Companion?) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let only {
            writeCompanion(only, to: dir)
            print("wrote \(only.id) sheets to \(dir.path)")
            return
        }
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
        let gazeItems = [CharacterState.idle, .listening].flatMap { state in
            directions.map { v in
                (directionName(state, v), { CharacterRenderer.image(state: state, size: CGSize(width: 150, height: 150), scale: scale, gaze: v) })
            }
        }
        save(sheet(title: "Gaze", columns: 9, cell: CGSize(width: 160, height: 176), items: gazeItems), dir.appendingPathComponent("gaze.png"))
        save(sheet(title: "Hit shapes (characterPath) over the art", columns: 10, cell: CGSize(width: 116, height: 132),
                   items: states.map { s in (s.name, { hitImage(s) }) }), dir.appendingPathComponent("hit.png"))
        save(sheet(title: "Every companion at rest (★ offered in Settings)", columns: 7, cell: CGSize(width: 160, height: 176),
                   items: CharacterSpecies.drawn2D.map { s in
                       ("\(CharacterSpecies.available.contains(s) ? "★ " : "")\(s.displayName)", {
                           CharacterRenderer.image(state: .idle, size: CGSize(width: 150, height: 150), scale: scale, look: CharacterLook(s))
                       })
                   }), dir.appendingPathComponent("companions.png"))
        save(menubarSheet(), dir.appendingPathComponent("menubar.png"))
        save(Icons.image(size: 1024), dir.appendingPathComponent("icon-1024.png"))
        save(iconSizes(), dir.appendingPathComponent("icon-sizes.png"))
        CharacterSpecies.drawn2D.forEach { writeCompanion(Companion($0), to: dir) }
        print("wrote contact sheets to \(dir.path)")
    }

    /// One companion in every state, small with badges, its hit shapes, its gaze, its styles, and
    /// beside its reference art.
    static func writeCompanion(_ who: Companion, to dir: URL) {
        let look = who.look
        let states = CharacterState.gallery
        let name = who.name, id = who.id
        func image(_ state: CharacterState, _ side: CGFloat, badges: Set<CharacterBadge> = [], gaze: CGVector? = nil,
                   look: CharacterLook = look) -> CGImage {
            CharacterRenderer.image(state: state, size: CGSize(width: side, height: side), scale: scale, badges: badges, gaze: gaze, look: look)
        }
        save(sheet(title: "\(name) states · 200 pt view", columns: 5, cell: CGSize(width: 220, height: 236),
                   items: states.map { s in (s.name, { image(s, 200) }) }), dir.appendingPathComponent("companion-\(id).png"))
        save(sheet(title: "\(name) at 104 pt, with badges", columns: 10, cell: CGSize(width: 116, height: 132),
                   items: states.map { s in (s.name, {
                       image(s, 104, badges: s == .alert ? [.watching, .count(3)] : s == .thinking ? [.busy, .watching] : [.count(2)])
                   }) }), dir.appendingPathComponent("companion-\(id)-small.png"))
        save(sheet(title: "\(name) hit shapes (pink) and the frame bubbles attach to (blue)", columns: 10,
                   cell: CGSize(width: 116, height: 132), items: states.map { s in (s.name, { hitImage(s, look: look) }) }),
             dir.appendingPathComponent("companion-\(id)-hit.png"))
        save(sheet(title: "\(name) gaze: the pointer at each side", columns: 9, cell: CGSize(width: 160, height: 176),
                   items: [CharacterState.idle, .listening].flatMap { state in
                       directions.map { v in (directionName(state, v), { image(state, 150, gaze: v) }) }
                   }), dir.appendingPathComponent("companion-\(id)-gaze.png"))
        let styles = CharacterAccessory.allCases.flatMap { accessory in
            CharacterAccent.allCases.map { color in
                ("\(color.rawValue) · \(accessory.rawValue)", {
                    var styled = look
                    styled.style = CharacterStyle(color: color, accessory: accessory)
                    return image(.idle, 150, look: styled)
                })
            }
        }
        save(sheet(title: "\(name) styles: colour × what it wears", columns: 4, cell: CGSize(width: 160, height: 176), items: styles),
             dir.appendingPathComponent("companion-\(id)-styles.png"))
        if let species = who.species, let reference = Reference.image(for: species) {
            save(compare(name, reference: reference,
                         renders: [CharacterState.idle, .listening, .success, .sleeping].map { ($0.name, image($0, 300)) }),
                 dir.appendingPathComponent("compare-\(id).png"))
            save(overlay(reference, image(.idle, 400)), dir.appendingPathComponent("overlay-\(id).png"))
        }
    }

    static let directions: [CGVector?] = [CGVector(dx: -1, dy: 1), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 1),
                                          CGVector(dx: -1, dy: 0), nil, CGVector(dx: 1, dy: 0),
                                          CGVector(dx: -1, dy: -1), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: -1)]

    static func directionName(_ state: CharacterState, _ v: CGVector?) -> String {
        "\(state.name) \(v.map { "(\(Int($0.dx)), \(Int($0.dy)))" } ?? "center")"
    }

    /// The rig at rest over its target, side by side and then one over the other at half strength: a target cut in
    /// canvas units (companions-2d/targets) lines up with the render point for point.
    static func overlay(_ target: CGImage, _ render: CGImage) -> CGImage {
        let side: CGFloat = 300
        return draw(CGSize(width: side * 3, height: side)) { context in
            let box = { (i: CGFloat) in CGRect(x: side * i, y: 0, width: side, height: side) }
            context.draw(target, in: box(0))
            context.setFillColor(NSColor(srgbRed: 0.91, green: 0.93, blue: 0.96, alpha: 1).cgColor)
            context.fill(box(1))
            context.draw(render, in: box(1))
            context.draw(target, in: box(2))
            context.setAlpha(0.55)
            context.draw(render, in: box(2))
        }
    }

    /// The reference art at the left, then the renders, all the same height.
    static func compare(_ name: String, reference: CGImage, renders: [(String, CGImage)]) -> CGImage {
        let side: CGFloat = 300
        let size = CGSize(width: side * CGFloat(renders.count + 1) + 20, height: side + 70)
        return draw(size) { context in
            paper.setFill()
            NSRect(origin: .zero, size: size).fill()
            label("\(name): reference (left) and the live rig", at: CGPoint(x: 16, y: size.height - 28), size: 15, weight: .semibold)
            context.interpolationQuality = .high
            context.draw(reference, in: CGRect(x: 10, y: 24, width: side - 10, height: side - 10))
            label("reference", at: CGPoint(x: 18, y: 6), size: 11, weight: .medium)
            for (i, (title, image)) in renders.enumerated() {
                let x = side * CGFloat(i + 1) + 10
                context.draw(image, in: CGRect(x: x, y: 24, width: side, height: side))
                label(title, at: CGPoint(x: x + 8, y: 6), size: 11, weight: .medium)
            }
        }
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
    static func hitImage(_ state: CharacterState, look: CharacterLook = CharacterLook(.mochi)) -> CGImage {
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
        context.setStrokeColor(NSColor.systemPink.cgColor)
        context.setLineWidth(1)
        context.strokePath()
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

// MARK: Reference art

/// The founder's concept renders each companion is drawn after (read from the repository).
enum Reference {
    static func image(for species: CharacterSpecies) -> CGImage? {
        // The companions' 2D style target, cut out in canvas units (companions-2d/targets.py); the folks' own art.
        let target = "companions-2d/targets/\(species.rawValue).webp"
        let path = FileManager.default.fileExists(atPath: target) ? target : "folk-family/\(species.rawValue)/\(species.rawValue).png"
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: Who

/// A companion to draw: one of Sidefolk's own, or a custom one made from data.
struct Companion {
    var id: String
    var name: String
    var look: CharacterLook
    var species: CharacterSpecies?

    init(_ species: CharacterSpecies) {
        self.init(id: species.rawValue, name: species.displayName, look: CharacterLook(species), species: species)
    }

    init(id: String, name: String, look: CharacterLook, species: CharacterSpecies? = nil) {
        self.id = id
        self.name = name
        self.look = look
        self.species = species
    }

    /// A built-in id, a custom companion's folder (anything with a "/"), or the id of one in
    /// $SIDEFOLK_HOME/companions/. Exits with the reasons when it can't be drawn.
    @MainActor
    static func named(_ name: String) -> Companion {
        if let species = CharacterSpecies(rawValue: name) { return Companion(species) }
        let report: CompanionReport?
        if name.contains("/") {
            report = CustomCompanions.load(folder: URL(fileURLWithPath: name))
        } else if let home = ProcessInfo.processInfo.environment["SIDEFOLK_HOME"] {
            report = CustomCompanions.loadAll(home: URL(fileURLWithPath: home)).first { $0.companion?.id == name || $0.folder.lastPathComponent == name }
        } else {
            report = nil
        }
        guard let report else {
            print("no companion called \(name) (custom ones: a folder path, or an id in $SIDEFOLK_HOME/companions)")
            exit(2)
        }
        guard let custom = report.companion else {
            report.errors.forEach { print("error: \($0)") }
            exit(2)
        }
        report.warnings.forEach { print("warning: \($0)") }
        return Companion(id: custom.id, name: custom.name, look: CharacterLook(custom: custom))
    }
}
