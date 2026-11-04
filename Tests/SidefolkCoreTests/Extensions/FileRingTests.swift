import Foundation
import Testing
@testable import SidefolkCore

/// The ring of what a file can become (D152): what it offers, and which slice a point is on.
struct FileRingTests {
    private func offer(_ key: String, patterns: [String], tag: String? = nil, input: [String: JSONValue] = ["files": .string("{values}")],
                       menu: [ExtensionManifest.DropMeta.MenuItem] = [], extensionId: String = "dev.x.one") -> ExtensionDropAction {
        ExtensionDropAction(extensionId: extensionId, extensionName: "One", key: key, title: key.capitalized, kinds: [.file], patterns: patterns, tool: "ext.one.go", input: input,
                            menu: menu, tag: tag)
    }

    private func item(_ title: String, skip: [String] = [], detail: String? = nil) -> ExtensionManifest.DropMeta.MenuItem {
        .init(title: title, input: ["target": .string(title.lowercased())], tag: title.uppercased() == title ? title : nil, detail: detail, skip: skip)
    }

    @Test func everyOfferThenEveryChoiceOnTheirMenus() {
        let drops = [offer("a", patterns: ["*.png"], tag: "JPEG", menu: [item("PNG", skip: ["*.png"], detail: "Keeps every detail"), item("TIFF", detail: "For print")]),
                     offer("b", patterns: ["*.png"], tag: "PDF"), offer("c", patterns: ["*.mp3"])]
        let choices = DropChoices.ringChoices(forFiles: ["/x/a.png"], among: drops)
        #expect(choices.map(\.tag) == ["JPEG", "PDF", "TIFF"])
        #expect(choices.map(\.title) == ["A", "B", "For print"])
        #expect(choices[2].item?.title == "TIFF")
    }

    @Test func aChoiceStaysForAMixedBatchThatStillNeedsIt() {
        let drop = offer("a", patterns: ["*.png", "*.jpg"], menu: [item("PNG", skip: ["*.png"])])
        #expect(drop.menu(forFiles: ["/x/a.png"]).isEmpty)
        #expect(drop.menu(forFiles: ["/x/a.png", "/x/b.jpg"]).count == 1)
        #expect(DropChoices.ringChoices(forFiles: ["/x/a.png", "/x/b.jpg"], among: [drop]).count == 2)
    }

    @Test func itHoldsTheSameRulesAsTheCard() throws {
        let many = offer("many", patterns: ["*.png"]), one = offer("one", patterns: ["*.png"], input: ["file": .string("{value}")])
        #expect(DropChoices.ringChoices(forFiles: ["/x/a.png", "/x/b.png"], among: [many, one]).map(\.offer.key) == ["many"])
        #expect(DropChoices.ringChoices(forFiles: [], among: [many]).isEmpty)
        #expect(DropChoices.ringChoices(forFiles: (0...ExtensionOutputs.maxFiles).map { "/x/\($0).png" }, among: [many]).isEmpty)

        // A link's name says nothing of what would be read.
        let folder = NSTemporaryDirectory() + "ring-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try FileManager.default.createSymbolicLink(atPath: folder + "/holiday.png", withDestinationPath: "/etc/hosts")
        #expect(DropChoices.ringChoices(forFiles: [folder + "/holiday.png"], among: [many]).isEmpty)
    }

    @Test func extensionsTakeTurnsSoOneCantFillTheRing() {
        let many = (0..<20).map { offer("o\($0)", patterns: ["*.png"]) }
        let other = offer("x", patterns: ["*.png"], extensionId: "dev.x.two")
        let choices = DropChoices.ringChoices(forFiles: ["/x/a.png"], among: many + [other])
        #expect(choices.count == 16)
        #expect(choices[1].offer.extensionId == "dev.x.two")
    }

    @Test func wherePointerAlreadyIsChoosesNothing() {
        // On a slice from the start, as at a screen's edge, with no move: nothing lights and nothing runs, however long it waits.
        var aim = RingAim(openedAt: 0, x: 100, y: 100)
        #expect(aim.follow(x: 100, y: 100, slice: 3, at: 0.1) == nil)
        #expect(aim.follow(x: 105, y: 100, slice: 3, at: 2) == nil)
        #expect(aim.ready(at: 3) == nil)
    }

    @Test func aSliceCountsAfterAMoveOntoItAndAMoment() {
        var aim = RingAim(openedAt: 0, x: 100, y: 100)
        #expect(aim.follow(x: 100, y: 130, slice: 2, at: 0.5) == 2)
        #expect(aim.ready(at: 0.55) == nil, "too soon on this slice")
        #expect(aim.ready(at: 0.7) == 2)
        #expect(aim.follow(x: 100, y: 160, slice: 3, at: 0.8) == 3)
        #expect(aim.ready(at: 0.85) == nil, "moved to another")
        #expect(aim.follow(x: 100, y: 100, slice: nil, at: 1.2) == nil)
        #expect(aim.ready(at: 2) == nil, "the middle chooses nothing")
    }

    @Test func tooSoonAfterOpeningCountsForNothing() {
        var aim = RingAim(openedAt: 10, x: 0, y: 0)
        #expect(aim.follow(x: 0, y: 30, slice: 0, at: 10.05) == 0)
        #expect(aim.ready(at: 10.3) == nil)
        #expect(aim.ready(at: 10.45) == 0)
    }

    @Test func finderAnswersAreReadSafely() {
        #expect(FinderSelection.answer("[\"file:///Users/a/My%20Photo.png\"]\n") == .files(["/Users/a/My Photo.png"]))
        #expect(FinderSelection.answer("[]") == .files([]))
        #expect(FinderSelection.answer("too many") == .tooMany)
        #expect(FinderSelection.answer("[\"afp://server/x\"]") == .files([]))
        #expect(FinderSelection.answer("nonsense") == .failed)
    }

    @Test func theFinderProgramCompiles() throws {
        // Only compiled, never run: running it would ask macOS for Automation and read this Mac's selection.
        let out = NSTemporaryDirectory() + "ring-" + UUID().uuidString + ".scpt", input = out + ".js"
        try FinderSelection.program.write(toFile: input, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: input)
            try? FileManager.default.removeItem(atPath: out)
        }
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        compile.arguments = ["-l", "JavaScript", "-o", out, input]
        try compile.run()
        compile.waitUntilExit()
        #expect(compile.terminationStatus == 0)
    }

    @Test func anExtensionThatCanWriteDragsGetsNoFileOffers() {
        var able = offer("a", patterns: ["*.png"])
        able.canWriteDrags = true
        #expect(DropChoices.offers(forFiles: ["/x/a.png"], among: [able]).isEmpty)
        #expect(DropChoices.ringChoices(forFiles: ["/x/a.png"], among: [able]).isEmpty)
    }

    @Test func twoSetsOfEightAtMost() {
        let drops = (0..<20).map { offer("o\($0)", patterns: ["*.png"]) }
        #expect(DropChoices.ringChoices(forFiles: ["/x/a.png"], among: drops).count == 16)
    }

    @Test(arguments: 1...8)
    func everySliceIsWhereItIsDrawn(count: Int) throws {
        for index in 0..<count {
            let at = RingGeometry.centre(of: index, count: count, radius: 140)
            #expect(RingGeometry.slice(dx: at.dx, dy: at.dy, count: count, inner: 76, outer: 214) == index)
        }
    }

    @Test func theFirstSliceIsStraightUpAndTheOthersGoClockwise() {
        #expect(RingGeometry.slice(dx: 0, dy: 140, count: 8, inner: 76, outer: 214) == 0)
        #expect(RingGeometry.slice(dx: 140, dy: 0, count: 8, inner: 76, outer: 214) == 2)
        #expect(RingGeometry.slice(dx: 0, dy: -140, count: 8, inner: 76, outer: 214) == 4)
        #expect(RingGeometry.slice(dx: -140, dy: 0, count: 8, inner: 76, outer: 214) == 6)
    }

    @Test func theMiddleAndTheOutsideChooseNothing() {
        #expect(RingGeometry.slice(dx: 0, dy: 40, count: 8, inner: 76, outer: 214) == nil)
        #expect(RingGeometry.slice(dx: 0, dy: 0, count: 8, inner: 76, outer: 214) == nil)
        #expect(RingGeometry.slice(dx: 300, dy: 0, count: 8, inner: 76, outer: 214) == nil)
        #expect(RingGeometry.slice(dx: 0, dy: 140, count: 0, inner: 76, outer: 214) == nil)
    }

    @Test(arguments: stride(from: 0.0, to: 1.0, by: 0.05).map { $0 })
    func whiteWordsReadOnTheVividSliceInEveryHue(hue: Double) {
        let pixel = FrostMeasure.vivid(hue: hue)
        #expect(FrostMeasure.worst([pixel], scrim: 0) >= 4.5)
        #expect(max(pixel.r, pixel.g, pixel.b) - min(pixel.r, pixel.g, pixel.b) > 0.25)
    }

    @Test func theVividSliceTakesThePicturesHue() throws {
        let orange = try #require(FrostMeasure.vivid([(0.9, 0.5, 0.1), (0.8, 0.4, 0.1)]))
        #expect(orange.r > orange.g && orange.g > orange.b)
        let blue = try #require(FrostMeasure.vivid([(0.1, 0.2, 0.9)]))
        #expect(blue.b > blue.r && blue.b > blue.g)
        #expect(FrostMeasure.vivid([(0.5, 0.5, 0.5), (0.2, 0.2, 0.2)]) == nil)
    }

    @Test func offSettingsAreTheDefaultAndAnOldOrBrokenFileKeepsThem() throws {
        let plain = try JSONDecoder().decode(FileRingSettings.self, from: Data("{}".utf8))
        #expect(!plain.enabled && plain.dragKey == .option)
        let odd = try JSONDecoder().decode(FileRingSettings.self, from: Data(#"{"enabled": true, "dragKey": "shift"}"#.utf8))
        #expect(odd.enabled && odd.dragKey == .option)
        #expect(!AppSettings().fileRing.enabled)
    }

    @Test func menuWordsAreCheckedAsAnOffersAre() throws {
        let json = """
        {"id":"a","title":"A","kinds":["file"],"patterns":["*.png"],"tool":"go","input":{"files":"{values}"},"menu_title":"Another format",
         "menu":[{"title":"PNG","tag":"PNG","detail":"Keeps every detail","skip":["*.png"],"input":{"target":"png"}}]}
        """
        let drop = try JSONDecoder().decode(ExtensionManifest.DropMeta.self, from: Data(json.utf8))
        #expect(drop.menuTitle == "Another format")
        #expect(drop.menu[0].tag == "PNG" && drop.menu[0].detail == "Keeps every detail" && drop.menu[0].skip == ["*.png"])
        let unknown = #"{"title":"PNG","nope":1,"input":{}}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ExtensionManifest.DropMeta.MenuItem.self, from: Data(unknown.utf8)) }
    }
}
