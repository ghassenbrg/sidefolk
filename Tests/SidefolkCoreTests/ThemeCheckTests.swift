import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SidefolkCore

/// Theme files (D58): a starter that is Harbor exactly, problems said in words, values kept within limits, and images
/// that are checked, then decoded and written again before Sidefolk keeps them.
@Suite struct ThemeCheckTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-theme-\(UUID().uuidString)", isDirectory: true)

    func write(_ file: ThemeFile) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try file.encoded().write(to: folder.appendingPathComponent("theme.json"))
    }

    func png(_ name: String, side: Int = 8) throws {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.8, green: 0.7, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(out, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(out))
    }

    func messages(_ report: ThemeReport) -> String { report.problems.map(\.description).joined(separator: "\n") }

    @Test func aNewThemeIsHarborUnderItsOwnName() throws {
        _ = try ThemeLibrary.start("Sunset Glow", at: folder)
        let report = ThemeCheck.check(folder: folder)
        #expect(report.isUsable, "\(messages(report))")
        #expect(report.problems.isEmpty, "\(messages(report))")
        #expect(report.tokens.id == "com.example.sunset-glow" && report.tokens.name == "Sunset Glow")
        var expected = ThemeTokens.harbor
        expected.id = report.tokens.id
        expected.name = report.tokens.name
        #expect(report.tokens == expected)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("README.md").path))
    }

    @Test func textThatDoesNotReadIsRefusedInWords() throws {
        var file = ThemeFile(.harbor, id: "com.you.pale", name: "Pale")
        file.colors?["light"]?["inkFaint"] = "#D0D0D0"
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(!report.isUsable)
        #expect(messages(report).contains("inkFaint on surface is 1.54:1 in light; text needs 4.5:1."))
    }

    @Test func whatIsMissingOrOutOfReachIsFixedAndSaid() throws {
        var file = ThemeFile(.harbor, id: "com.you.loose", name: "Loose")
        file.colors?["dark"]?["link"] = nil
        file.type?.scale = 2
        file.shape?.card = 60
        file.layout?.navigation = "carousel"
        file.motion = "wobbly"
        file.companion?.suggests = "dragon"
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(report.isUsable, "\(messages(report))")
        let said = messages(report)
        #expect(said.contains("Harbor's colour is used for dark.link."))
        #expect(said.contains("type.scale 2.0 is kept between 0.9 and 1.15.") && report.tokens.type.scale == 1.15)
        #expect(said.contains("shape.card 60.0 is kept between 0.0 and 28.0.") && report.tokens.radius.card == 28)
        #expect(said.contains("layout.navigation “carousel” isn't one of sidebar, ") && said.contains("; sidebar is used."))
        #expect(said.contains("motion “wobbly”") && report.tokens.motion == .calm)
        #expect(said.contains("companion.suggests “dragon”") && report.tokens.nook.suggests == nil)
    }

    @Test func aBrokenFileOrABorrowedNameIsRefused() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ \"format\": 1, \"name\": \"No id\" }".utf8).write(to: folder.appendingPathComponent("theme.json"))
        #expect(messages(ThemeCheck.check(folder: folder)).contains("“id” is missing."))

        let library = ThemeLibrary(paths: SidefolkPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-themes-\(UUID().uuidString)")))
        for id in ["harbor", "dev.sidefolk.theme.night-shift"] {
            try write(ThemeFile(.harbor, id: id, name: "Borrowed"))
            #expect(throws: UserFacingError.self) { try library.install(from: folder) }
        }
        #expect(throws: Never.self) { try library.install(from: folder, own: true) }

        try Data(repeating: 32, count: ThemeFile.maxBytes + 1).write(to: folder.appendingPathComponent("theme.json"))
        #expect(messages(ThemeCheck.check(folder: folder)).contains("64 KB at most"))
    }

    @Test func imagesMustBeSmallPNGsInsideTheFolder() throws {
        var file = ThemeFile(.harbor, id: "com.you.paper", name: "Paper")
        file.material?.grain = "../outside.png"
        file.companion?.backdrop = "art/huge.png"
        file.art = ThemeFile.Art(empty: "art/fake.png")
        try write(file)
        try png("art/huge.png", side: 2100)
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("art/fake.png"))
        let said = messages(ThemeCheck.check(folder: folder))
        #expect(said.contains("material.grain: “../outside.png” must be a .png inside the theme's folder."))
        #expect(said.contains("companion.backdrop: “art/huge.png” is 2100×2100"))
        #expect(said.contains("art.empty: “art/fake.png” isn't a PNG image."))
    }

    @Test func installingKeepsAFreshCopyOfEveryImage() throws {
        var file = ThemeFile(.harbor, id: "com.you.paper", name: "Paper")
        file.material?.grain = "grain.png"
        try write(file)
        try png("grain.png")
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-themes-\(UUID().uuidString)", isDirectory: true)
        let library = ThemeLibrary(paths: SidefolkPaths(home: home))

        let (theme, _) = try library.install(from: folder)
        let kept = try #require(theme.images["material.grain"])
        #expect(kept.path.hasPrefix(home.path) && kept.lastPathComponent == "grain.png")
        #expect(theme.tokens.material.grain)
        #expect(library.all().map(\.id) == ["harbor", "com.you.paper"])
        #expect(library.theme(id: "com.you.paper").tokens.name == "Paper")

        try library.remove(id: "com.you.paper")
        #expect(library.theme(id: "com.you.paper").id == "harbor")
    }

    // MARK: Layout (D64)

    func layout(_ today: [[ThemeFile.ColumnSection]]?, preset: String? = nil) throws -> ThemeReport {
        var file = ThemeFile(.harbor, id: "com.you.layout", name: "Layout")
        file.layout = ThemeFile.LayoutSection(preset: preset, today: today)
        try write(file)
        return ThemeCheck.check(folder: folder)
    }

    @Test func aStarterWritesHarborsLayoutOutInFull() throws {
        let section = try #require(ThemeFile(.harbor, id: "com.you.a", name: "A").layout)
        #expect(section.today?.count == 2)
        #expect(section.today?[1].first == .column(width: 2, blocks: ["queue:rows", "day:rail"]))
        let encoded = String(decoding: try JSONEncoder().encode(section), as: UTF8.self)
        #expect(encoded.contains("\"header:line\""), "a lone block is written as its name")
    }

    @Test func blocksArrangeAsWritten() throws {
        let report = try layout([[.block("header")], [.column(width: 3, blocks: ["queue:rows"]), .block("watching")]])
        #expect(report.problems.isEmpty, "\(messages(report))")
        let today = report.tokens.layout.today
        #expect(today.count == 2 && today[1].count == 2 && today[1][0].width == 3)
        #expect(today[1][1].blocks == [ThemeLayout.Block(.watching, "tiles")], "a bare name gets the first style")
    }

    @Test func whatCantBeDrawnIsLeftOutAndSaid() throws {
        let report = try layout([[.block("queue"), .block("queue:rows"), .block("weather"),
                                  .column(width: nil, blocks: ["day:sticky", "extension:com.x/clock"]),
                                  .column(width: 9, blocks: ["recent"])]])
        let said = messages(report)
        #expect(said.contains("layout.today has queue twice; the second is left out."))
        #expect(said.contains("“weather” isn't one of"))
        #expect(said.contains("“day:sticky”: day comes as rail, list,") && said.contains("; rail is used."))
        #expect(said.contains("blocks from extensions aren't supported yet"))
        #expect(said.contains("A row of layout.today has 5 columns; the first 4 are used."))
        #expect(report.tokens.layout.today[0].map { $0.blocks.map(\.kind) } == [[.queue], [.day]])
    }

    @Test func whatNeedsYouAlwaysHasAPlace() throws {
        let report = try layout([[.block("header")], [.block("watching")]])
        #expect(messages(report).contains("it's added at the top"))
        #expect(report.tokens.layout.today.map { $0.flatMap(\.blocks).map(\.kind) } == [[.header], [.queue], [.watching]])
    }

    @Test func anUnknownPresetOrAnEmptyLayoutFallsBackToHarbors() throws {
        let unknown = try layout(nil, preset: "cockpit")
        #expect(messages(unknown).contains("layout.preset “cockpit” isn't one of board, console, desk, planner, stage; desk is used."))
        #expect(unknown.tokens.layout == .desk)
        let empty = try layout([[.block("weather")]])
        #expect(messages(empty).contains("has no block Sidefolk can draw"))
        #expect(empty.tokens.layout == .desk)
    }

    /// Every preset is a layout a theme could have written: written out and read back, it is the same, with no problem.
    @Test func everyPresetReadsBackAsItself() throws {
        for (name, preset) in ThemeLayout.presets {
            var tokens = ThemeTokens.harbor
            tokens.layout = preset
            try write(ThemeFile(tokens, id: "com.you.\(name)", name: name))
            let report = ThemeCheck.check(folder: folder)
            #expect(report.problems.isEmpty, "\(name): \(messages(report))")
            #expect(report.tokens.layout == preset, "\(name)")
        }
    }

    /// The themes Sidefolk ships (Resources/Themes) all pass their own check, contrast included, and come in order.
    @Test func theBuiltInsPassTheirCheck() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes", isDirectory: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: resources.path) where !name.hasPrefix(".") {
            let report = ThemeCheck.check(folder: resources.appendingPathComponent(name))
            #expect(report.isUsable && report.problems.isEmpty, "\(name): \(messages(report))")
            #expect(report.tokens.id.hasPrefix(ThemeLibrary.ownPrefix), "\(name)")
        }
        let library = ThemeLibrary(paths: SidefolkPaths(home: folder), bundled: resources)
        #expect(library.builtIns().map(\.id) == ThemeLibrary.builtInOrder)
    }
}
