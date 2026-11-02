import AppKit
import QuartzCore
import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// Colours by name, as the theme and the verdicts say them.
enum SceneColors {
    static func ns(_ c: SceneColor, appearance: NSAppearance) -> NSColor {
        func plain(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 24 & 0xFF) / 255, green: CGFloat(v >> 16 & 0xFF) / 255, blue: CGFloat(v >> 8 & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
        }
        switch c {
        case .rgba(let v): return plain(v)
        case .adaptive(let light, let dark): return plain(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        case .token(let token):
            var resolved = NSColor.clear
            appearance.performAsCurrentDrawingAppearance {
                resolved = (NSColor(themed(token)).usingColorSpace(.sRGB) ?? .clear)
            }
            return resolved
        case .tuned(let token, let alpha, let brightness):
            let base = ns(.token(token), appearance: appearance)
            guard brightness != 0, let plain = base.usingColorSpace(.deviceRGB) else { return base.withAlphaComponent(base.alphaComponent * alpha) }
            return NSColor(deviceHue: plain.hueComponent, saturation: plain.saturationComponent, brightness: min(max(plain.brightnessComponent + brightness, 0), 1),
                           alpha: plain.alphaComponent * alpha)
        }
    }

    static func cg(_ c: SceneColor, appearance: NSAppearance) -> CGColor {
        var out = CGColor.clear
        appearance.performAsCurrentDrawingAppearance { out = ns(c, appearance: appearance).cgColor }
        return out
    }

    private static func themed(_ token: SceneColor.Token) -> SwiftUI.Color {
        switch token {
        case .ink: Theme.ink
        case .inkMuted: Theme.inkMuted
        case .inkFaint: Theme.inkFaint
        case .surface: Theme.surface
        case .surfaceSunken: Theme.surfaceSunken
        case .surfaceRaised: Theme.surfaceRaised
        case .line: Theme.line
        case .well: Theme.well
        case .accent: Theme.accent
        case .onAccent: Theme.onAccent
        case .accentSoft: Theme.accentSoft
        case .link: Theme.link
        case .success: Theme.success
        case .successSoft: Theme.successSoft
        case .warning: Theme.warning
        case .warningSoft: Theme.warningSoft
        case .info: Theme.link
        case .clear: .clear
        case .win: GameColors.color(.win)
        case .loss: GameColors.color(.loss)
        case .draw: GameColors.color(.draw)
        }
    }
}

enum SceneDrawing {
    /// The words as a bitmap, shrunk to fit their box down to `minScale`, then cut at their last line. Bitmaps rather
    /// than live text: the same shaping and bidi as everywhere in AppKit, and drawn once.
    static func text(_ words: String, style: SceneText, size: CGSize, color: NSColor, resolve: (SceneColor) -> NSColor = { _ in .labelColor }) -> CGImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let scale: CGFloat = 2
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let paragraph = NSMutableParagraphStyle()
        // By now these mean left and right: `mirrored()` has already turned them for a language that reads right to left.
        paragraph.alignment = switch style.align {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        paragraph.lineBreakMode = style.lines == 1 ? .byClipping : .byWordWrapping
        // As Text wraps everywhere else: no lone word on a last line.
        paragraph.lineBreakStrategy = .standard
        func attributed(_ points: CGFloat) -> NSAttributedString {
            var plain: [NSAttributedString.Key: Any] = [.font: font(style, points), .foregroundColor: color, .paragraphStyle: paragraph]
            if style.strike {
                plain[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                plain[.strikethroughColor] = color
            }
            guard !style.runs.isEmpty else { return NSAttributedString(string: words, attributes: plain) }
            let out = NSMutableAttributedString()
            for run in style.runs {
                var look = plain
                if let c = run.color { look[.foregroundColor] = resolve(c) }
                if let weight = run.weight {
                    var own = style
                    own.weight = weight
                    look[.font] = font(own, points)
                }
                out.append(NSAttributedString(string: run.text, attributes: look))
            }
            return out
        }
        var points = CGFloat(style.size)
        let least = points * CGFloat(style.minScale)
        var measured = attributed(points).boundingRect(with: CGSize(width: size.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        func tooBig() -> Bool {
            if style.lines == 1 {
                let line = attributed(points).boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
                return line.width > size.width
            }
            return measured.height > size.height
        }
        while points > least, tooBig() {
            points = max(points - 0.5, least)
            measured = attributed(points).boundingRect(with: CGSize(width: size.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        let used = min(measured.height, size.height)
        let top: CGFloat = switch style.vAlign {
        case .top: 0
        case .center: (size.height - used) / 2
        case .bottom: size.height - used
        }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        attributed(points).draw(with: CGRect(x: 0, y: top, width: size.width, height: size.height - top),
                                options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static func font(_ style: SceneText, _ points: CGFloat) -> NSFont {
        font(weight: style.weight, design: style.design, points: points, italic: style.italic, tabular: style.tabular)
    }

    static func font(weight: SceneText.Weight, design: SceneText.Design, points: CGFloat, italic: Bool = false, tabular: Bool = false) -> NSFont {
        let themed = design == .theme ? ThemeStore.shared.style.tokens.type : nil
        let points = themed.map { points * CGFloat($0.scale) } ?? points
        let system = NSFont.systemFont(ofSize: points, weight: nsWeight(weight))
        let face: NSFontDescriptor.SystemDesign = switch design {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        case .theme:
            switch themed?.display {
            case .rounded?: .rounded
            case .serif?: .serif
            default: .default
            }
        }
        var descriptor = system.fontDescriptor.withDesign(face) ?? system.fontDescriptor
        if tabular {
            let digits: [NSFontDescriptor.FeatureKey: Int] = [.typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector]
            descriptor = descriptor.addingAttributes([NSFontDescriptor.AttributeName.featureSettings: [digits]])
        }
        let made = NSFont(descriptor: descriptor, size: points) ?? system
        // By the font manager: a descriptor asked for the slant gives back the regular weight.
        return italic ? NSFontManager.shared.convert(made, toHaveTrait: .italicFontMask) : made
    }

    static func nsWeight(_ weight: SceneText.Weight) -> NSFont.Weight {
        switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }

    /// A figure in a box of its own: fitted whole, standing on the bottom edge if it should, in shades of one colour if it should.
    static func figure(_ image: CGImage, box: CGSize, look: SceneFigureLook, duotone: CGColor?) -> CGImage? {
        guard look.bottom || duotone != nil else { return image }
        let scale: CGFloat = 2, side = CGSize(width: box.width * scale, height: box.height * scale)
        guard side.width >= 1, side.height >= 1,
              let context = CGContext(data: nil, width: Int(side.width), height: Int(side.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let fit = min(side.width / CGFloat(image.width), side.height / CGFloat(image.height))
        let drawn = CGSize(width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
        let place = CGRect(x: (side.width - drawn.width) / 2, y: look.bottom ? 0 : (side.height - drawn.height) / 2, width: drawn.width, height: drawn.height)
        guard let duotone else {
            context.draw(image, in: place)
            return context.makeImage()
        }
        // Grey first, then the colour multiplied over it, inside the picture's own shape.
        let grey = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        grey?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(grey?.makeImage() ?? image, in: place)
        context.saveGState()
        context.clip(to: place, mask: image)
        context.setBlendMode(.multiply)
        context.setFillColor(duotone)
        context.fill(place)
        context.restoreGState()
        return context.makeImage()
    }

    static func path(_ form: SceneShape.Form, box: CGRect, corner: Double) -> CGPath {
        switch form {
        case .rect:
            let radius = min(CGFloat(corner), min(box.width, box.height) / 2)
            return radius > 0 ? CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil) : CGPath(rect: box, transform: nil)
        case .ellipse: return CGPath(ellipseIn: box, transform: nil)
        case .capsule:
            let radius = min(box.width, box.height) / 2
            return CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .path(let ops):
            let p = CGMutablePath()
            for op in ops {
                switch op {
                case .move(let x, let y): p.move(to: CGPoint(x: x, y: y))
                case .line(let x, let y): p.addLine(to: CGPoint(x: x, y: y))
                case .quad(let cx, let cy, let x, let y): p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
                case .cubic(let a, let b, let c, let d, let x, let y): p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: d))
                case .close: p.closeSubpath()
                }
            }
            return p
        }
    }

    static func gradient(_ g: SceneShape.Gradient, path: CGPath, size: CGSize, appearance: NSAppearance) -> CGImage? {
        let scale: CGFloat = 2
        guard size.width >= 1, size.height >= 1,
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: g.colors.map { SceneColors.cg($0, appearance: appearance) } as CFArray, locations: nil)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: g.fromX * size.width, y: g.fromY * size.height),
                                   end: CGPoint(x: g.toX * size.width, y: g.toY * size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return context.makeImage()
    }

    static func tinted(_ image: CGImage, _ color: CGColor) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.clip(to: box, mask: image)
        context.setFillColor(color)
        context.fill(box)
        return context.makeImage()
    }

    static func symbol(_ symbol: SceneSymbol, side: Double, color: NSColor, resolve: (SceneColor) -> NSColor) -> CGImage? {
        guard side >= 1, let base = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil) else { return nil }
        let colours: NSImage.SymbolConfiguration = if let second = symbol.secondary {
            .init(paletteColors: [color, resolve(second)])
        } else if symbol.mono {
            .init(paletteColors: [color])
        } else {
            .init(hierarchicalColor: color)
        }
        let image = base.withSymbolConfiguration(.init(pointSize: side * 0.8, weight: nsWeight(symbol.weight)).applying(colours)) ?? base
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: 2)])
    }
}

/// The pack's pictures, decoded when a node needs them and kept while the surface is open, within a budget. A picture that
/// can't be read draws nothing.
@MainActor
final class SceneImages {
    private let reader: PackAssetReader?
    private var cache: [String: (image: CGImage, side: Int, used: Int)] = [:]
    private var order: [String] = []
    private var bytes = 0

    init(reader: PackAssetReader?) {
        self.reader = reader
    }

    func image(_ path: String, side: Int) -> CGImage? {
        if let hit = cache[path], hit.side >= side {
            return hit.image
        }
        guard let reader, let image = reader.image(path, maxSide: side) else { return nil }
        store(path, image, side)
        return image
    }

    /// Decodes a scene's pictures away from the main thread, so a shown scene doesn't wait for a large backdrop.
    func preload(_ scene: SurfaceScene) async {
        guard let reader else { return }
        var wanted: [String: Int] = [:]
        func visit(_ node: SceneNode) {
            if case .image(let image) = node.kind {
                for path in [image.path, image.dark].compactMap({ $0 }) { wanted[path] = max(wanted[path] ?? 0, Int(max(node.width, node.height) * 2)) }
            }
            node.children.forEach(visit)
        }
        scene.nodes.forEach(visit)
        for run in scene.runs {
            for frames in run.frames {
                let side = scene.node(frames.target).map { Int(max($0.width, $0.height) * 2) } ?? 256
                for path in frames.paths { wanted[path] = max(wanted[path] ?? 0, side) }
            }
        }
        let missing = wanted.filter { (cache[$0.key]?.side ?? -1) < $0.value }
        guard !missing.isEmpty else { return }
        let decoded = await Task.detached(priority: .userInitiated) {
            missing.compactMap { path, side in reader.image(path, maxSide: side).map { (path, side, $0) } }
        }.value
        for (path, side, image) in decoded { store(path, image, side) }
    }

    private func store(_ path: String, _ image: CGImage, _ side: Int) {
        let used = image.bytesPerRow * image.height
        if let old = cache[path] { bytes -= old.used }
        order.removeAll { $0 == path }
        cache[path] = (image, side, used)
        order.append(path)
        bytes += used
        while bytes > PackAssets.maxDecodedBytes, order.count > 1 {
            let oldest = order.removeFirst()
            if let gone = cache.removeValue(forKey: oldest) { bytes -= gone.used }
        }
    }

    func emptied() {
        cache = [:]
        order = []
        bytes = 0
    }
}

/// The person's companion and the person, as Sidefolk draws them: a scene names them and gets back nothing.
struct SceneFigures {
    var companion: (SceneCompanionPose, Int, _ face: Bool) -> CGImage? = { _, _, _ in nil }
    var person: (Int) -> CGImage? = { _ in nil }
    var companionName = ""

    /// `{companion}` in an extension's words, filled in only where they are drawn.
    func fill(_ words: String) -> String { words.replacingOccurrences(of: "{companion}", with: companionName) }

    /// The friendly stand-in for someone with no account picture, as Sidefolk's own places draw it.
    @MainActor
    static func standIn(side: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: PlayerAvatar(picture: nil, size: side))
        renderer.scale = 2
        return renderer.cgImage
    }

    static func live(settings: AppSettings) -> SceneFigures {
        SceneFigures(companion: { pose, side, face in
            if face {
                var rect = CGRect(x: 0, y: 0, width: side * 2, height: side * 2)
                return CompanionArt.avatar(for: settings, side: CGFloat(side)).cgImage(forProposedRect: &rect, context: nil, hints: nil)
            }
            let state: CharacterState = switch pose {
            case .idle: .idle
            case .listening: .listening
            case .thinking: .thinking
            case .waiting: .waiting
            case .success: .success
            case .alert: .alert
            case .celebrating: .celebrating
            }
            var rect = CGRect(x: 0, y: 0, width: side * 2, height: side * 2)
            return GameFigures.trim(CompanionArt.portrait(for: settings, state: state, side: CGFloat(side)))?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }, person: { side in
            var rect = CGRect(x: 0, y: 0, width: side * 2, height: side * 2)
            if let picture = AccountPicture.current { return picture.cgImage(forProposedRect: &rect, context: nil, hints: nil) }
            return SceneFigures.standIn(side: CGFloat(side))
        }, companionName: settings.companionName)
    }
}
