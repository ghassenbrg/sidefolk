#if DEBUG
import AppKit
import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// A gallery of sixty companions for UISnapshots (D77): Sidefolk's eight and fifty-two made up, by
/// Sidefolk and by others, with sizes, dates and a few snapshots, to see the browser at the scale it is built for.
/// Their pictures are the 2D rigs drawn on coloured discs, written to a temporary folder; nothing is downloaded.
enum SampleCompanions {
    private static let made: [(name: String, tagline: String, official: Bool)] = [
        ("Acorn", "A tiny forest keeper", true), ("Bramble", "A prickly hedgehog with a soft heart", false),
        ("Biscuit", "A crumbly little bear", false), ("Cinder", "A sleepy dragon hatchling", true),
        ("Clover", "A lucky green rabbit", false), ("Comet", "A shooting star in a hurry", false),
        ("Dumpling", "A round and happy cat", false), ("Echo", "A bat who repeats your jokes", false),
        ("Fig", "A thoughtful little owl", true), ("Fizz", "A soda-pop robot", false),
        ("Gizmo", "A pocket inventor", false), ("Hazel", "A squirrel with a plan", false),
        ("Honey", "A busy bee who naps", false), ("Inky", "A shy octopus who draws", true),
        ("Jelly", "A wobbly jellyfish", false), ("Juniper", "A calm little pine", false),
        ("Kettle", "A teapot who loves breaks", false), ("Lumen", "A lamp that glows when it thinks", true),
        ("Maple", "A red panda in a scarf", false), ("Marble", "A rolling stone friend", false),
        ("Mango", "A sunny parrot", false), ("Moss", "A slow and gentle turtle", true),
        ("Nugget", "A golden hamster", false), ("Olive", "A cat who reads your mail", false),
        ("Otto", "An otter who juggles", false), ("Pebble", "A shy river stone", false),
        ("Pepper", "A spicy little fox", false), ("Pickle", "A crunchy green frog", false),
        ("Pixel", "An 8-bit ghost", true), ("Plum", "A sleepy purple sheep", false),
        ("Quill", "A porcupine poet", false), ("Radish", "A root with opinions", false),
        ("Ripple", "A little wave", false), ("Saffron", "A tiger cub", true),
        ("Sesame", "A seed that wants to grow", false), ("Sprout", "A plant that waves", false),
        ("Sundae", "A melting ice cream", false), ("Taffy", "A stretchy pink cat", false),
        ("Thistle", "A purple bird of the moors", false), ("Toffee", "A sticky little pup", true),
        ("Tumble", "A tumbleweed on the move", false), ("Velvet", "A soft mole", false),
        ("Waffle", "A crispy corgi", false), ("Whisk", "A kitchen helper", true),
        ("Willow", "A weeping little tree", false), ("Wren", "A small brown bird", false),
        ("Yuzu", "A zesty citrus sprite", false), ("Ziggy", "A lightning bolt", false),
        ("Zephyr", "A gentle breeze", true), ("Basil", "A herb who cooks", false),
        ("Cosmo", "A cat astronaut", false), ("Ducky", "A rubber duck debugger", true),
    ]
    private static let known: [CompanionChoice] = [.ember, .folio, .iris, .kiko, .nimbo, .nori, .purl, .rune]
    private static let rigs: [CompanionChoice] = [.mochi, .spark, .ember, .kiko, .nimbo, .folio, .iris, .nori, .purl, .rune]
    private static let discs: [NSColor] = [0xFFE9C7, 0xD9F2E6, 0xDDE7FF, 0xFFDCD6, 0xEDE3FF, 0xFFF3B8].map {
        NSColor(red: CGFloat($0 >> 16 & 0xFF) / 255, green: CGFloat($0 >> 8 & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1)
    }

    /// The catalog, its previews written under a temporary folder.
    static func catalog() throws -> AddonCatalog {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-sample-gallery-\(UUID().uuidString)",
                                                                                   isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("previews"), withIntermediateDirectories: true)
        var items: [[String: Any]] = []
        for (i, choice) in known.enumerated() {
            items.append(entry(id: "dev.sidefolk.companions.\(choice.rawValue)", name: choice.defaultName, companion: choice.rawValue,
                               tagline: CompanionArt.role(choice), author: "Sidefolk", index: i, version: "1.0.0"))
            try picture(choice, index: i, to: folder.appendingPathComponent("previews/\(choice.rawValue).png"))
        }
        for (i, m) in made.enumerated() {
            let n = i + known.count
            let slug = m.name.lowercased()
            let author = m.official ? "Sidefolk" : ["Lena K.", "Studio Kumo", "Tomás R.", "Aiko M.", "Pixel Garden"][i % 5]
            let id = m.official ? "dev.sidefolk.companions.\(slug)" : "io.github.\(author.lowercased().filter(\.isLetter)).\(slug)"
            // A few in snapshots, which Releases keeps out of sight (D65).
            let version = i % 9 == 4 ? "1.0.0-snapshot.\(i % 4 + 1)" : "1.\(i % 3).0"
            items.append(entry(id: id, name: m.name, companion: slug, tagline: m.tagline, author: author, index: n, version: version))
            try picture(rigs[n % rigs.count], index: n, to: folder.appendingPathComponent("previews/\(slug).png"))
        }
        let data = try JSONSerialization.data(withJSONObject: ["format": AddonCatalog.format, "addons": items])
        return try AddonCatalog.parse(data, folder: folder, fetched: Date())
    }

    /// Companions already here: Kiko, an older Ember with an update waiting, and Pebble, which this copy has no case for.
    static var installed: [InstalledCompanion] {
        let items: [[String: Any]] = [
            ["id": "dev.sidefolk.companions.kiko", "name": "Kiko", "companion": "kiko", "version": "1.0.0", "author": "Sidefolk"],
            ["id": "dev.sidefolk.companions.ember", "name": "Ember", "companion": "ember", "version": "0.9.0", "author": "Sidefolk"],
            ["id": "io.github.lenak.pebble", "name": "Pebble", "companion": "pebble", "version": "1.1.0", "author": "Lena K.",
             "tagline": "A shy river stone"],
        ]
        return items.compactMap { item in
            (try? JSONSerialization.data(withJSONObject: item)).flatMap { try? JSONDecoder().decode(InstalledCompanion.self, from: $0) }
        }
    }

    /// The "…" menu of one companion of each kind, drawn as lists (an open menu can't be drawn off screen).
    @MainActor static func menus(_ chooser: CompanionChooserModel) -> some View {
        let owned = chooser.owned
        let worn = chooser.worn(in: owned)
        let origins: [OwnedCompanion.Origin] = [.builtIn, .gallery, .made, .folder]
        let shown = origins.flatMap { origin in owned.filter { $0.origin == origin }.prefix(origin == .gallery ? 2 : 1) }
        return HStack(alignment: .top, spacing: Theme.Space.m) {
            ForEach(shown) { companion in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "\(companion.name) · \(CompanionWords.origin(companion.origin))").font(Theme.Font.captionStrong)
                        .foregroundStyle(Theme.inkMuted)
                    CompanionMenuItems(companion: companion, actions: chooser.actions(for: companion, worn: companion.wear == worn),
                                       perform: { _ in })
                }
                .buttonStyle(.plain)
                .labelStyle(.titleAndIcon)
                .font(Theme.Font.body)
                .padding(Theme.Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
        .padding(Theme.Space.m)
    }

    /// The confirmation before removing one of each kind, worn, as words (an alert can't be drawn off screen).
    @MainActor static func removals(_ chooser: CompanionChooserModel, settings: AppSettings) -> some View {
        let owned = chooser.owned
        let shown = owned.filter { $0.origin != .builtIn && !$0.fromExtension }
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(shown) { companion in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: CompanionRemovalWords.title(companion)).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    Text(verbatim: CompanionRemovalWords.message(companion, actions: chooser.actions(for: companion, worn: true),
                                                                 replacement: .mochi, owned: owned))
                        .font(Theme.Font.body).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
        .padding(Theme.Space.m)
    }

    private static func entry(id: String, name: String, companion: String, tagline: String, author: String, index: Int,
                              version: String) -> [String: Any] {
        let day = 1 + (index * 7) % 30
        return ["id": id, "kind": "companion", "name": name, "tagline": tagline, "author": author, "version": version,
                "description": "\(name) is \(tagline.prefix(1).lowercased() + tagline.dropFirst()). Now and then it does something only it would do, then settles back beside your work.",
                "file": "\(companion)-\(version).zip", "bytes": 1_200_000 + (index * 377_119) % 4_800_000,
                "sha256": String(repeating: "0", count: 64), "companion": companion, "engine": 1,
                "preview": "previews/\(companion).png", "published": String(format: "2026-10-%02d", day)]
    }

    /// A rig standing on a coloured disc, as a gallery's profile pictures look.
    private static func picture(_ choice: CompanionChoice, index: Int, to url: URL) throws {
        let side: CGFloat = 192
        let style = CompanionStyle(color: CompanionAccent.allCases[index % 4], accessory: index % 3 == 0 ? .scarf : .none)
        let rig = CompanionArt.preview(choice, style: style, threeD: false, side: side * 1.5)
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            discs[index % discs.count].setFill()
            rect.fill()
            rig.draw(in: NSRect(x: -side / 4, y: -side / 3, width: side * 1.5, height: side * 1.5))
            return true
        }
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return
        }
        try png.write(to: url)
    }
}
#endif
