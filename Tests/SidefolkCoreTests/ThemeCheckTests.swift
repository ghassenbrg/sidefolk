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

    @Test func aNewThemeIsTheDefaultUnderItsOwnNameWithoutItsPictures() throws {
        _ = try ThemeLibrary.start("Sunset Glow", at: folder)
        let report = ThemeCheck.check(folder: folder)
        #expect(report.isUsable, "\(messages(report))")
        #expect(report.problems.isEmpty, "\(messages(report))")
        #expect(report.tokens.id == "com.example.sunset-glow" && report.tokens.name == "Sunset Glow")
        var expected = ThemeTokens.sidefolk
        expected.id = report.tokens.id
        expected.name = report.tokens.name
        // The pictures are the default's own; a new theme adds its own or goes without.
        expected.material.scene = false
        expected.nook.header = false
        expected.nook.logo = false
        #expect(report.tokens == expected)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("README.md").path))
    }

    @Test func textThatDoesNotReadIsRefusedInWords() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.pale", name: "Pale")
        file.colors?["light"]?["inkFaint"] = "#D0D0D0"
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(!report.isUsable)
        #expect(messages(report).contains("inkFaint on surface is 1.50:1 in light; text needs 4.5:1."))
    }

    @Test func whatIsMissingOrOutOfReachIsFixedAndSaid() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.loose", name: "Loose")
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
        #expect(said.contains("The default theme's colour is used for dark.link."))
        #expect(said.contains("type.scale 2.0 is kept between 0.9 and 1.15.") && report.tokens.type.scale == 1.15)
        #expect(said.contains("shape.card 60.0 is kept between 0.0 and 28.0.") && report.tokens.radius.card == 28)
        #expect(!said.contains("navigation"), "a retired layout key passes unsaid (D84)")
        #expect(said.contains("motion “wobbly”") && report.tokens.motion == .calm)
        #expect(said.contains("companion.suggests “dragon”") && report.tokens.nook.suggests == nil)
    }

    @Test func aBrokenFileOrABorrowedNameIsRefused() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ \"format\": 1, \"name\": \"No id\" }".utf8).write(to: folder.appendingPathComponent("theme.json"))
        #expect(messages(ThemeCheck.check(folder: folder)).contains("“id” is missing."))

        let library = ThemeLibrary(paths: SidefolkPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-themes-\(UUID().uuidString)")))
        for id in ["sidefolk", "harbor", "dev.sidefolk.theme.night-studio"] {
            try write(ThemeFile(.sidefolk, id: id, name: "Borrowed"))
            #expect(throws: UserFacingError.self) { try library.install(from: folder) }
        }
        #expect(throws: Never.self) { try library.install(from: folder, own: true) }

        try Data(repeating: 32, count: ThemeFile.maxBytes + 1).write(to: folder.appendingPathComponent("theme.json"))
        #expect(messages(ThemeCheck.check(folder: folder)).contains("64 KB at most"))
    }

    @Test func imagesMustBeSmallPNGsInsideTheFolder() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.paper", name: "Paper")
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
        var file = ThemeFile(.sidefolk, id: "com.you.paper", name: "Paper")
        file.material?.grain = "grain.png"
        try write(file)
        try png("grain.png")
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-themes-\(UUID().uuidString)", isDirectory: true)
        let library = ThemeLibrary(paths: SidefolkPaths(home: home))

        let (theme, _) = try library.install(from: folder)
        let kept = try #require(theme.images["material.grain"])
        #expect(kept.path.hasPrefix(home.path) && kept.lastPathComponent == "grain.png")
        #expect(theme.tokens.material.grain)
        #expect(library.all().map(\.id) == ["sidefolk", "com.you.paper"])
        #expect(library.theme(id: "com.you.paper").tokens.name == "Paper")

        try library.remove(id: "com.you.paper")
        #expect(library.theme(id: "com.you.paper").id == "sidefolk")
    }

    // MARK: Layout (D64, retired by D84 but for the icons)

    /// A theme made for D64 still loads with every layout key it wrote, and none of them is a problem: only its icons
    /// (said, or its preset's) are read.
    @Test func anOlderLayoutLoadsAndOnlyItsIconsAreRead() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.layout", name: "Layout")
        file.layout = ThemeFile.LayoutSection(preset: "stage", navigation: "pills", nook: "none",
                                              today: [[.block("queue:cards"), .column(width: 9, blocks: ["weather"])]],
                                              activity: "diary", editor: "markdown")
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(report.problems.isEmpty, "\(messages(report))")
        #expect(report.tokens.layout.icons == .colorful, "the stage preset chose colourful icons")
        file.layout?.preset = "cockpit"
        try write(file)
        #expect(ThemeCheck.check(folder: folder).tokens.layout == .desk)
    }

    @Test func aStarterWritesOnlyItsIcons() throws {
        let section = try #require(ThemeFile(.sidefolk, id: "com.you.a", name: "A").layout)
        #expect(section == ThemeFile.LayoutSection(icons: "simple"))
    }

    /// Simple or colourful icons in Home (D67); anything else is said.
    @Test func iconsAreSimpleOrColorful() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.icons", name: "Icons")
        file.layout?.icons = "colorful"
        try write(file)
        #expect(ThemeCheck.check(folder: folder).tokens.layout.icons == .colorful)
        file.layout?.icons = "glossy"
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(report.tokens.layout.icons == .simple)
        #expect(messages(report).contains("layout.icons “glossy” isn't one of simple, colorful; simple is used."))
    }

    /// Colours have meanings: a theme can't paint a win red, an error green or a warning grey.
    @Test func aStatusColourKeepsItsMeaning() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.upside", name: "Upside")
        file.colors?["light"]?["success"] = "#C93F33"
        file.colors?["dark"]?["danger"] = "#7DD3A7"
        file.colors?["light"]?["warning"] = "#6B6B6B"
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(!report.isUsable)
        let text = messages(report)
        #expect(text.contains("success in light must look green"), "\(text)")
        #expect(text.contains("danger in dark must look red"), "\(text)")
        #expect(text.contains("warning in light must look amber"), "\(text)")
        // Rust reds, ochres and sage greens are still the right families.
        #expect(ThemeCheck.meaningProblems(ThemeTokens.sidefolk.colors).isEmpty)
    }

    /// Every role drawn as text is held to 4.5:1 where it is drawn: success on the surfaces (a "Connected" label) and
    /// each chip's words on its own soft fill.
    @Test func everyRoleDrawnAsTextMustRead() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.faint", name: "Faint")
        file.colors?["light"]?["success"] = "#4CC48A"
        file.colors?["dark"]?["dangerSoft"] = "#B04A42"
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(!report.isUsable)
        let text = messages(report)
        #expect(text.contains("success on surfaceRaised is"), "\(text)")
        #expect(text.contains("success on successSoft is"), "\(text)")
        #expect(text.contains("danger on dangerSoft is"), "\(text)")
        let labels = Set(ThemeCheck.contrastRows(ThemeTokens.sidefolk.colors).map(\.label))
        for pair in ["success on well", "link on accentSoft", "warning on warningSoft", "success on successSoft"] {
            #expect(labels.contains(pair), "\(pair)")
        }
    }

    /// A soft fill carries its status's hue: a purple danger fill would read as news. A grey one says nothing either
    /// way and passes.
    @Test func aSoftFillKeepsItsStatusHue() throws {
        var c = ThemeTokens.sidefolk.colors
        c.dangerSoft.dark = 0x3A2240
        c.warningSoft.light = 0xE3F4EA
        #expect(ThemeCheck.meaningProblems(c).isEmpty)
        #expect(ThemeCheck.softMeaningProblems(c) == [
            "dangerSoft in dark must look red or grey: it means an error or a real risk everywhere in Sidefolk.",
            "warningSoft in light must look amber or grey: it means something waiting or needing a look everywhere in Sidefolk.",
        ])
        c.dangerSoft.dark = 0x2A2A2C
        c.warningSoft.light = 0xF2F2F2
        #expect(ThemeCheck.softMeaningProblems(c).isEmpty)
    }

    /// A hand-made theme from before D130: its pale accent wouldn't mark a selected row, and its author never wrote one, so
    /// the stand-in moves toward its ink, keeping its colour, instead of refusing the theme over a role it doesn't have.
    @Test func aPaleAccentIsNotRefusedOverARoleItNeverWrote() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.pale", name: "Pale")
        for appearance in ["light", "dark"] {
            for role in ThemeTokens.Colors.optionalRoles { file.colors?[appearance]?[role] = nil }
        }
        file.colors?["light"]?["accent"] = "#D9E6F2"
        file.colors?["light"]?["onAccent"] = "#1C1C1E"
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(report.isUsable && report.problems.isEmpty, "\(messages(report))")
        let c = report.tokens.colors
        #expect(c.sidebar.light == c.surface.light)
        #expect(ThemeCheck.contrast(c.sidebarSelected.light, c.sidebar.light) >= ThemeCheck.stateContrast)
        #expect(ThemeCheck.contrast(c.onSidebarSelected.light, c.sidebarSelected.light) >= ThemeCheck.textContrast)
        #expect(c.sidebarSelected.light != c.accent.light && c.sidebarSelected.light != c.ink.light)
        // The dark side's accent stood out already, so it is untouched.
        #expect(c.sidebarSelected.dark == c.accent.dark)
    }

    /// A role written for one appearance only: the other takes the stand-in, and what was written stays.
    @Test func aRoleWrittenForOneAppearanceKeepsIt() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.half", name: "Half")
        for role in ["sidebar", "sidebarInk", "sidebarInkMuted", "sidebarSelected", "onSidebarSelected"] { file.colors?["dark"]?[role] = nil }
        let written = try #require(file.colors?["light"]?["sidebar"])
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(report.isUsable, "\(messages(report))")
        #expect(report.tokens.colors.sidebar.light == ThemeFile.colour(written))
        #expect(report.tokens.colors.sidebar.dark == report.tokens.colors.surface.dark)
    }

    /// A required colour left out comes from the default, which can change under a theme. Adding it says which role to
    /// write; a copy already kept stays, rather than vanishing for the default with no word. A colour the theme did write
    /// is still refused either way.
    @Test func aColourLeftOutNeverTakesAKeptThemeAway() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.sunny", name: "Sunny")
        file.colors?["light"]?["accent"] = "#F2C94C"
        file.colors?["light"]?["onAccent"] = nil
        try write(file)
        let strict = ThemeCheck.check(folder: folder)
        #expect(!strict.isUsable)
        #expect(messages(strict).contains("This theme doesn't set onAccent: write it in theme.json."), "\(messages(strict))")
        let lenient = ThemeCheck.check(folder: folder, strict: false)
        #expect(lenient.isUsable, "\(messages(lenient))")
        #expect(messages(lenient).contains("Warning: onAccent on accent is"), "\(messages(lenient))")

        file.colors?["light"]?["onAccent"] = "#FFFFFF"
        try write(file)
        #expect(!ThemeCheck.check(folder: folder, strict: false).isUsable)
    }

    /// The rules added on 2026-11-01 refuse a theme being made or added from a folder, but a copy Sidefolk already
    /// keeps (it passed when it was added) stays, with warnings, until its update comes.
    @Test func aKeptThemeOutlivesANewerRule() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.minty", name: "Minty")
        file.colors?["light"]?["success"] = "#4CC48A"
        file.colors?["dark"]?["dangerSoft"] = "#3A2240"
        try write(file)
        #expect(!ThemeCheck.check(folder: folder).isUsable)
        let lenient = ThemeCheck.check(folder: folder, strict: false)
        #expect(lenient.isUsable, "\(messages(lenient))")
        #expect(messages(lenient).contains("Warning: success on surfaceRaised is"), "\(messages(lenient))")
        #expect(messages(lenient).contains("Warning: dangerSoft in dark must look red or grey"), "\(messages(lenient))")

        let home = folder.appendingPathComponent("home", isDirectory: true)
        let library = ThemeLibrary(paths: SidefolkPaths(home: home))
        #expect(throws: UserFacingError.self) { try library.install(from: folder) }
        let kept = SidefolkPaths(home: home).themes.appendingPathComponent(file.id, isDirectory: true)
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        try file.encoded().write(to: kept.appendingPathComponent("theme.json"))
        #expect(library.all().contains { $0.id == file.id })
        #expect(try library.install(from: folder, own: true).theme.id == file.id)
    }

    /// The gallery's themes (sidefolk-addons `themes/`, when a checkout is there) can be used as Sidefolk reads its own
    /// gallery. The strict check runs there, in its `scripts/check.sh`, so the two repositories can merge in any order.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: ExtFixtures.addonsRepo.appendingPathComponent("themes").path),
                   ExtFixtures.noAddons))
    func theGalleryThemesCanBeUsed() throws {
        let root = ExtFixtures.addonsRepo.appendingPathComponent("themes", isDirectory: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) where !name.hasPrefix(".") {
            let report = ThemeCheck.check(folder: root.appendingPathComponent(name), strict: false)
            #expect(report.isUsable, "\(name): \(messages(report))")
        }
    }

    /// A theme made before the warning roles still works: Harbor's amber stands in (it reads on every gallery theme's
    /// surfaces too), and the check says so.
    @Test func aThemeWithoutTheWarningRolesStillWorks() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.older", name: "Older")
        for appearance in ["light", "dark"] {
            for role in ["warning", "warningSoft", "onWarning"] { file.colors?[appearance]?[role] = nil }
        }
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(report.isUsable, "\(messages(report))")
        #expect(report.tokens.colors.warning == ThemeTokens.sidefolk.colors.warning)
        #expect(messages(report).contains("light.warning"))
    }

    /// A theme made before Lantern (D84) has no well or lights: it keeps its own sunken surface for wells and gets
    /// Harbor's lights, and nothing is said, since nothing is wrong.
    @Test func aThemeWithoutTheLanternRolesKeepsItsLook() throws {
        var file = ThemeFile(.sidefolk, id: "com.you.older", name: "Older")
        file.colors?["light"]?["surfaceSunken"] = "#EFEAE0"
        for appearance in ["light", "dark"] {
            for role in ThemeTokens.Colors.optionalRoles { file.colors?[appearance]?[role] = nil }
        }
        try write(file)
        let report = ThemeCheck.check(folder: folder)
        #expect(report.isUsable && report.problems.isEmpty, "\(messages(report))")
        #expect(report.tokens.colors.well.light == 0xEFEAE0)
        #expect(report.tokens.colors.well.dark == ThemeTokens.sidefolk.colors.surfaceSunken.dark)
        #expect(report.tokens.colors.glow == ThemeTokens.sidefolk.colors.glow)
    }

    /// The themes Sidefolk ships (Resources/Themes) all pass their own check, contrast included, and come in order.
    @Test func theBuiltInsPassTheirCheck() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes", isDirectory: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: resources.path) where !name.hasPrefix(".") {
            let report = ThemeCheck.check(folder: resources.appendingPathComponent(name))
            #expect(report.isUsable && report.problems.isEmpty, "\(name): \(messages(report))")
            #expect(ThemeLibrary.isOwn(report.tokens.id), "\(name)")
        }
        let library = ThemeLibrary(paths: SidefolkPaths(home: folder), bundled: resources)
        #expect(library.builtIns().map(\.id) == ThemeLibrary.builtInOrder)
    }
}
