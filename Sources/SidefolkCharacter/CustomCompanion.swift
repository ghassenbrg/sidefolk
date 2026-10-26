import Foundation
import QuartzCore

/// A companion made from data: a folder with `species.json` and optional `parts/*.svg`, drawn on a
/// soft rig like Mochi and the folks (docs/research/lively-companions.md, "Custom companions").
/// Loading reads numbers, colours and shapes; nothing in the folder is ever run.
public struct CustomCompanion: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let author: String?
    public let summary: String?
    let body: CompanionBody
}

/// What a custom companion's `species.json` and parts resolve to: plain values, checked.
struct CompanionBody: Equatable, Sendable {
    var colors: [RGBValue]
    var edge: RGBValue?
    var torso: [PathOp]
    var head: [PathOp]?
    var neck: CGPoint
    var scale: CGFloat
    var feet: [CGPoint]
    var foot: CGSize
    var footColors: [RGBValue]?
    var shoulders: [CGPoint]
    var arm: [PathOp]
    var eyes: [CGPoint]
    var mouth: CGPoint
    var nose: CGRect?
    var noseColor: RGBValue?
    var faceScale: CGFloat
    var cheeks: Bool
    var temper: Temper
    var ears: [Ear]
    var gear: [Worn]
    var collar: CollarSpec?
    var marks: [String: CGPoint]

    struct Ear: Equatable, Sendable {
        var shapes: [PartShape]
        var base: CGPoint
        var angle: CGFloat
        var side: CGFloat
        var floppiness: CGFloat
    }

    struct Worn: Equatable, Sendable {
        var shapes: [PartShape]
        var mount: String
    }

    struct CollarSpec: Equatable, Sendable {
        var center: CGPoint
        var halfWidth: CGFloat
        var sag: CGFloat
        var height: CGFloat
        var tail: CGFloat
    }
}

/// The result of reading one companion folder: the companion, or why not; and what looks off.
public struct CompanionReport: Sendable {
    public var folder: URL
    public var companion: CustomCompanion?
    public var errors: [String] = []
    public var warnings: [String] = []
}

@MainActor
public enum CustomCompanions {
    nonisolated public static let formatVersion = 1
    static let maxJSON = 64 * 1024
    static let maxParts = 16
    /// Where people put their own companions under Sidefolk's home folder.
    public static func folder(home: URL) -> URL { home.appendingPathComponent("companions", isDirectory: true) }

    /// Every companion under `home`: `companions/<id>/`, and `Extensions/<ext>/companion/` (an
    /// installed extension may bring one; still data only). Sorted by name; broken ones reported.
    public static func loadAll(home: URL) -> [CompanionReport] {
        let fm = FileManager.default
        var folders: [URL] = []
        for root in [folder(home: home)] {
            let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            folders += items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        let extensions = home.appendingPathComponent("Extensions", isDirectory: true)
        for ext in (try? fm.contentsOfDirectory(at: extensions, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
            let companion = ext.appendingPathComponent("companion", isDirectory: true)
            if fm.fileExists(atPath: companion.appendingPathComponent("species.json").path) { folders.append(companion) }
        }
        var seen = Set<String>()
        return folders.map { load(folder: $0) }.map { report in
            guard let id = report.companion?.id else { return report }
            guard seen.insert(id).inserted else {
                var duplicate = report
                duplicate.companion = nil
                duplicate.errors.append("another companion already uses the id \"\(id)\"")
                return duplicate
            }
            return report
        }
        .sorted { ($0.companion?.name ?? $0.folder.lastPathComponent) < ($1.companion?.name ?? $1.folder.lastPathComponent) }
    }

    /// Reads, resolves and checks one folder. A companion comes back only without errors.
    public static func load(folder: URL) -> CompanionReport {
        var report = CompanionReport(folder: folder)
        do {
            let file = try readFile(folder.appendingPathComponent("species.json"), in: folder, limit: maxJSON)
            let json = try JSONSerialization.jsonObject(with: file)
            if let unknown = SpeciesFile.schema.unknownKey(in: json) { throw Invalid("\(unknown) isn't a known key") }
            let spec = try JSONDecoder().decode(SpeciesFile.self, from: file)
            var parts: [String: [PartShape]] = [:]
            func part(_ path: String) throws -> [PartShape] {
                if let shapes = parts[path] { return shapes }
                guard parts.count < maxParts else { throw Invalid("more than \(maxParts) part files") }
                guard path.range(of: #"^parts/[A-Za-z0-9._-]{1,64}\.svg$"#, options: .regularExpression) != nil, !path.contains("..") else {
                    throw Invalid("\(path): parts are files in the parts folder, like parts/ear.svg")
                }
                do {
                    let shapes = try SVGPart.read(try readFile(folder.appendingPathComponent(path), in: folder, limit: SVGPart.maxBytes))
                    parts[path] = shapes
                    return shapes
                } catch let error as PartError {
                    throw Invalid("\(path): \(error)")
                }
            }
            let body = try spec.resolve(part: part)
            if spec.id != folder.lastPathComponent, folder.lastPathComponent != "companion" {
                report.warnings.append("the folder is called \(folder.lastPathComponent) but the id is \(spec.id)")
            }
            let companion = CustomCompanion(id: spec.id, name: spec.name, author: spec.author, summary: spec.description, body: body)
            let (errors, warnings) = check(companion)
            report.errors += errors
            report.warnings += warnings
            if errors.isEmpty { report.companion = companion }
        } catch let error as Invalid {
            report.errors.append(error.why)
        } catch let error as DecodingError {
            report.errors.append(describe(error))
        } catch {
            report.errors.append(error.localizedDescription)
        }
        return report
    }

    /// The companion drawn in every state stays in its window, has its face on its head and its
    /// feet on the floor.
    static func check(_ companion: CustomCompanion) -> (errors: [String], warnings: [String]) {
        var errors: [String] = [], warnings: [String] = []
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.look = CharacterLook(custom: companion)
        let room = CGRect(x: 0, y: 0, width: 200, height: 200)
        for state in CharacterState.gallery {
            view.setState(state, animated: false)
            guard room.contains(view.characterPath.boundingBoxOfPath) else {
                errors.append("it leaves the window when \(state.name): make it smaller (body.scale) or lower its ears")
                break
            }
        }
        view.setState(.idle, animated: false)
        let drawn = Director(CharacterLook(custom: companion), live: false).bodyBounds
        if !room.insetBy(dx: 1, dy: 1).contains(drawn) {
            errors.append("something it wears or holds is outside the 200 × 200 canvas")
        } else if drawn.maxY > 190 {
            warnings.append("its top is \(Int(200 - drawn.maxY)) units under the window's edge: hops will be small")
        }
        let body = companion.body
        let face = PathOp.path(body.head ?? body.torso)
        if !body.eyes.allSatisfy({ face.contains($0) }) || !face.contains(body.mouth) {
            errors.append("its eyes and mouth must be on its \(body.head == nil ? "body" : "head")")
        }
        let soles = body.feet.map { $0.y - body.foot.height / 2 }
        if let lowest = soles.min(), !(14...26).contains(lowest) {
            warnings.append("its feet don't stand on the floor (y = 20): their bottoms are at \(Int(lowest))")
        }
        return (errors, warnings)
    }

    // MARK: Reading

    struct Invalid: Error {
        let why: String
        init(_ why: String) { self.why = why }
    }

    /// A regular file inside `folder` (no links out, no devices), at most `limit` bytes.
    static func readFile(_ url: URL, in folder: URL, limit: Int) throws -> Data {
        let name = url.path.replacingOccurrences(of: folder.path + "/", with: "")
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values?.isSymbolicLink != true else { throw Invalid("\(name) is a link: copy the file in instead") }
        guard let values, values.isRegularFile == true else { throw Invalid("\(name) is missing") }
        let base = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base) else { throw Invalid("\(name) is outside the folder") }
        guard (values.fileSize ?? 0) <= limit else { throw Invalid("\(name) is bigger than \(limit / 1024) KiB") }
        return try Data(contentsOf: url)
    }

    static func describe(_ error: DecodingError) -> String {
        func place(_ path: [CodingKey]) -> String {
            let text = path.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return text.isEmpty ? "species.json" : String(text.drop { $0 == "." })
        }
        switch error {
        case .keyNotFound(let key, let context): return "\(place(context.codingPath + [key])) is missing"
        case .typeMismatch(_, let context), .valueNotFound(_, let context): return "\(place(context.codingPath)) has the wrong kind of value"
        case .dataCorrupted(let context): return "\(place(context.codingPath)): \(context.debugDescription)"
        @unknown default: return "species.json can't be read"
        }
    }
}

extension CharacterLook {
    /// A companion made from data, in a colour and with something to wear like any other.
    /// `species` stays Mochi's wherever the app needs a built-in one (it isn't a folk on duty).
    public init(custom: CustomCompanion, style: CharacterStyle? = nil) {
        self.init(.mochi, style: style ?? CharacterStyle(color: .aqua, accessory: .none))
        self.custom = custom
    }
}

// MARK: Building the body

extension Species {
    /// A soft rig's description from a custom companion: its shading from its colours, its parts
    /// drawn with that shading or their own fills (`currentColor` takes the style colour).
    init(_ companion: CustomCompanion) {
        let b = companion.body
        let stops = b.colors.indices.map { CGFloat($0) / CGFloat(max(b.colors.count - 1, 1)) }
        let shading = Shading(colors: b.colors.map(\.rgb), locations: stops, center: CGPoint(x: 0.34, y: 0.76),
                              reach: CGSize(width: 0.98, height: 1.05))
        let limbShading = Shading(colors: b.colors.map(\.rgb), locations: stops, center: CGPoint(x: 0.35, y: 0.7),
                                  reach: CGSize(width: 0.9, height: 0.9))
        let edge = b.edge?.rgb
        let torso = PathOp.path(b.torso), head = b.head.map { PathOp.path($0) }
        let feetRects = b.feet.map { CGRect(x: $0.x - b.foot.width / 2, y: $0.y - b.foot.height / 2, width: b.foot.width, height: b.foot.height) }
        let ears = b.ears.map { ear -> AppendageSpec in
            let upright = CGAffineTransform(scaleX: 1, y: -1)
            let outline = ear.shapes.map { PathOp.path($0.ops, upright) }.reduce(CGMutablePath() as CGPath) { $0.union($1) }
            return AppendageSpec(base: ear.base, angle: ear.angle, side: ear.side, layers: { accent in
                Self.draw(ear.shapes, upright, body: shading, accent: accent, edge: edge)
            }, outline: outline, floppiness: ear.floppiness)
        }
        let canvas = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: Canvas.size.height)
        let gear = b.gear.map { worn -> Gear in
            let mount: Gear.Mount = switch worn.mount {
            case "back": .back
            case "head": .head
            case "face": .face
            default: .body
            }
            return Gear(mount: mount, draw: { accent in Self.draw(worn.shapes, canvas, body: shading, accent: accent, edge: edge) },
                        outline: worn.shapes.map { PathOp.path($0.ops, canvas) }.reduce(CGMutablePath() as CGPath) { $0.union($1) })
        }
        var frame = feetRects.reduce(torso.boundingBoxOfPath) { $0.union($1) }
        if let head { frame = frame.union(head.boundingBoxOfPath) }
        for ear in ears { frame = frame.union(Paths.transformed(ear.outline, CGAffineTransform(translationX: ear.base.x, y: ear.base.y)
            .rotated(by: ear.angle)).boundingBoxOfPath) }
        frame = CGRect(x: frame.minX, y: Canvas.floor, width: frame.width, height: frame.maxY - Canvas.floor)
        let top = torso.boundingBoxOfPath
        let collar = b.collar.map { Collar(center: $0.center, halfWidth: $0.halfWidth, sag: $0.sag, height: $0.height, tail: $0.tail) }
            ?? Collar(center: pt(top.midX, top.maxY - 4), halfWidth: top.width * 0.46, sag: 4.5, height: 17, tail: 1.45)
        var marks: [Effect: CGPoint] = [:]
        for (name, offset) in b.marks { if let effect = Effect.named(name) { marks[effect] = offset } }
        self.init(
            shading: shading, edge: edge, torso: torso, head: head, neck: b.neck, feet: b.feet, foot: b.foot,
            footShading: b.footColors.map { Shading(colors: $0.map(\.rgb), locations: stops) },
            shoulders: (b.shoulders[0], b.shoulders[1]),
            arm: ArmStyle(shape: PathOp.path(b.arm), shading: limbShading, edge: edge.map { ($0, 0.4) }),
            face: SoftFace(kind: .ink, eyes: (b.eyes[0], b.eyes[1]), mouth: b.mouth, nose: b.nose, scale: b.faceScale, cheeks: b.cheeks,
                           temper: b.temper, noseColor: b.noseColor?.rgb),
            appendages: ears, gear: gear, collar: collar, restingFrame: frame, markOffsets: marks, scale: b.scale)
    }

    /// Shapes of a part in canvas units: the body's own shading, the style colour, or their own colour.
    private static func draw(_ shapes: [PartShape], _ t: CGAffineTransform, body: Shading, accent: RGB, edge: RGB?) -> CALayer {
        let root = Layers.canvas()
        for (i, shape) in shapes.enumerated() {
            let path = PathOp.path(shape.ops, t)
            let soft: SoftShape = switch shape.fill {
            case .body: SoftShape(path, shading: body)
            case .accent: SoftShape(path, shading: .tinted(accent))
            case .color(let color): SoftShape(path, shading: .tinted(color.rgb))
            }
            // The first shape is the part's outline: it gets the soft drop shadow and the body's edge.
            if i == 0 {
                soft.shadow(radius: 3, opacity: 0.14, offset: CGSize(width: 0, height: -1))
                if let edge { soft.outline(edge, alpha: 0.4, width: 0.8) }
            }
            root.addSublayer(soft.layer)
        }
        return root
    }
}

extension Effect {
    static func named(_ name: String) -> Effect? {
        switch name {
        case "zzz": .zzz
        case "dots": .dots
        case "exclaim": .exclaim
        case "question": .question
        case "sparkles": .sparkles
        case "sweat": .sweat
        case "waves": .waves
        case "confetti": .confetti
        case "ticks": .ticks
        default: nil
        }
    }
}
