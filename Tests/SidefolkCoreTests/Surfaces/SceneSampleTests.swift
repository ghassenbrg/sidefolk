import Foundation
import Testing
@testable import SidefolkCore
@testable import ext_scene_sample
import SidefolkExtensionKit

/// The Kit's Scene as Sidefolk reads it, and the sample program running in its sandbox from a pack (D99).
struct SceneSampleTests {
    /// A scene the Kit wrote, as Sidefolk reads it.
    static func read(_ scene: SidefolkExtensionKit.Scene) throws -> SurfaceScene {
        let data = try JSONSerialization.data(withJSONObject: scene.json)
        let parsed = try SurfaceScene.parse(try JSONValue.parse(String(decoding: data, as: UTF8.self)))
        #expect(parsed.notes.isEmpty, "nothing dropped: \(parsed.notes)")
        return parsed
    }

    @Test @MainActor func theSampleScenesReadCleanly() throws {
        let shuffle = try Self.read(Shuffle().scene())
        #expect(shuffle.areas.filter { $0.id == "pick" }.count == 3)
        #expect(shuffle.keys.map(\.match) == [.character("1"), .character("2"), .character("3")])
        #expect(shuffle.inputOpens(reduceMotion: false) > 2.5 && shuffle.inputOpens(reduceMotion: true) > 2.5, "the shuffle is the point: it plays under Reduce Motion")
        #expect(shuffle.runs.contains { $0.id == "round" && !$0.events.isEmpty })
        #expect(shuffle.nodes.contains { $0.kind == .companion(pose: .thinking, look: SceneFigureLook()) } && shuffle.nodes.contains { $0.kind == .person(look: SceneFigureLook()) })

        var picked = Shuffle()
        picked.pick(1)
        let result = try Self.read(picked.scene())
        #expect(result.over && result.outcome != nil && result.tally != nil)

        let drag = try Self.read(DragBoard().scene())
        #expect(drag.areas.first { $0.id == "pin" }?.drag?.mode == .free)
        #expect(drag.areas.first { $0.id == "field" }?.drag == SceneDrag(mode: .grid(rows: 4, columns: 8), ghost: "preview"))

        let keys = try Self.read(WordBoard().scene())
        #expect(keys.areas.filter { $0.id == "kb" }.count == 28)
        #expect(keys.keys.contains { $0.match == .named(.return) && $0.value == "↵" } && keys.keys.contains { $0.match == .named(.delete) })
        #expect(keys.areas.allSatisfy { !$0.label.isEmpty })

        let coin = try Self.read(Coin().scene())
        #expect(coin.runs.first?.curves.contains { $0.property == .flip } == true)
    }

    /// The Kit's board with the most on it, within the channel's 64 KB: 81 cells, each with its pencil notes.
    @Test func aFullBoardFitsTheChannel() throws {
        let cell = Node.rect(fill: .surfaceRaised, stroke: .line).style("c")
        let scene = Scene(width: 460, height: 460) {
            Node.grid(columns: 9, cell: (50, 50)) {
                for r in 0..<9 {
                    for c in 0..<9 {
                        Node.group {
                            cell
                            Node.text("123\n456\n789", size: 10, color: .inkMuted, lines: 3).style("n")
                        }
                        .area("cell", value: "\(r),\(c)", label: "Row \(r + 1), column \(c + 1)", hover: nil, press: nil)
                    }
                }
            }
        }
        .style("c", ["w": 50, "h": 50])
        .style("n", ["w": 50, "h": 50])
        let data = try JSONSerialization.data(withJSONObject: scene.json)
        #expect(data.count < SurfaceScene.maxBytes, "\(data.count)")
        let read = try SurfaceScene.parse(try JSONValue.parse(String(decoding: data, as: UTF8.self)))
        #expect(read.areas.count == 81)
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func theSampleRunsInItsSandboxFromThePack() async throws {
        let h = try HostEnv()
        let pack = try Self.samplePack()
        let info = try await h.host.install(from: pack)
        let all = h.host.surfaceShelf.all
        #expect(all.map(\.surface) == ["coin", "drag", "keys", "shuffle"])
        #expect(all.allSatisfy { $0.sounds })
        let reader = try #require(await h.host.assetReader(extensionId: info.id))
        #expect(reader.has("tile-star.png") && reader.has("ding.wav"))
        #expect(reader.image("tile-star.png", maxSide: 64)?.width == 64)
        #expect(reader.soundURL("ding.wav") != nil)
        let shuffle = try #require(all.first { $0.surface == "shuffle" })
        let session = SurfaceSession(info: shuffle, host: h.host, reduceMotion: false)
        let scene = try await session.open(language: "en")
        #expect(scene.areas.filter { $0.id == "pick" }.count == 3)
        #expect(session.inputOpen() == false, "moves wait for the shuffle")
        #expect(try await session.move(.click(area: "pick", value: "0", ms: nil)) == nil)
        session.holdInput(until: .distantPast)
        let picked = try #require(try await session.move(.click(area: "pick", value: "0", ms: nil)))
        #expect(picked.over)
        await session.close(.finished)
        #expect(await h.host.isRunning(info.id))
    }

    /// The sample put together as a pack: its manifest, assets and the built program.
    static func samplePack() throws -> URL {
        let source = ExtFixtures.repoRoot.appendingPathComponent("samples/scene-sample", isDirectory: true)
        let pack = try ExtFixtures.tempDir("scene-pack").appendingPathComponent("scenes", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: pack.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try fm.copyItem(at: source.appendingPathComponent(ExtensionManifest.fileName), to: pack.appendingPathComponent(ExtensionManifest.fileName))
        try fm.copyItem(at: source.appendingPathComponent("assets"), to: pack.appendingPathComponent("assets"))
        try fm.copyItem(at: ExtFixtures.products.appendingPathComponent("ext-scene-sample"), to: pack.appendingPathComponent("bin/ext-scene-sample"))
        return pack
    }
}

/// What the Kit writes for the review's abilities is what the app reads (D99, D100).
struct KitAbilityTests {
    @Test func theKitsNewPartsAreRead() throws {
        let scene = SidefolkExtensionKit.Scene(width: 300, height: 200) {
            Node.scroll(contentHeight: 600, scrollTo: "low") { Node.rect(fill: .accent.tuned(alpha: 0.5, brightness: -0.1)).id("low").at(0, 500).size(300, 40) }.id("list").size(300, 200)
            Node.text("VS", size: 20, weight: "black").textLook(italic: true, tabular: true, strike: true).id("vs").size(100, 30)
            Node.runs([(text: "First ", color: nil, weight: "bold"), (text: "the rest", color: .inkMuted, weight: nil)], lines: 2).id("runs").size(100, 30)
            Node.symbol("xmark").symbolLook(weight: "black", mono: true).id("mark").size(20, 20)
            Node.companion().figure(face: true, bottom: true, duotone: .hex("#F0C040")).id("coin").size(40, 40)
            Node.entry(name: "answer").fieldLook(focus: true, plain: true, weight: "semibold", design: "rounded").id("field").size(100, 30)
            Node.rect().id("ok").size(40, 30).area("ok", label: "OK", hover: nil, looks: ["vs": AreaLook(dy: -1, opacity: 1, rotate: 4)], submits: "answer", selected: true)
            Node.rect().id("plots").size(40, 30).area("plots", label: "Plots", drag: .cells(rows: 2, columns: 2, inset: 3))
        }.afterStill(ms: 200).speaker("sounds")
        let read = try SceneSampleTests.read(scene)
        guard case .scroll(let box)? = read.node("list")?.kind, case .shape(let fill)? = read.node("low")?.kind else { Issue.record("\(read.nodes)"); return }
        #expect(box.contentHeight == 600 && box.to == "low" && fill.fill == .tuned(.accent, alpha: 0.5, brightness: -0.1))
        guard case .text(let vs)? = read.node("vs")?.kind, case .text(let runs)? = read.node("runs")?.kind, case .symbol(let mark)? = read.node("mark")?.kind else { Issue.record("\(read.nodes)"); return }
        #expect(vs.italic && vs.tabular && vs.strike && vs.weight == .black && runs.runs.count == 2 && mark.mono && mark.weight == .black)
        guard case .companion(_, let look)? = read.node("coin")?.kind else { Issue.record("\(read.nodes)"); return }
        #expect(look.face && look.bottom && look.duotone != nil)
        #expect(read.entries.first?.focus == true && read.entries.first?.plain == true)
        let ok = try #require(read.areas.first { $0.id == "ok" })
        #expect(ok.submits == "answer" && ok.selected && ok.looks["vs"]?.absolute == true && ok.hover == nil)
        #expect(read.areas.first { $0.id == "plots" }?.drag?.inset == 3)
        #expect(read.afterStill == 0.2 && read.speaker == "sounds")
    }

    @Test func aPageSceneComesThroughThePage() throws {
        let block = PageSceneBlock(SidefolkExtensionKit.Scene(width: 300, height: 100) { Node.rect().id("go").size(50, 50).area("go", label: "Go") }, actions: ["go": (tool: "start", input: ["a": 1])])
        let data = try JSONSerialization.data(withJSONObject: ["sections": [["blocks": [block.json]]]])
        let json = try JSONValue.parse(String(decoding: data, as: UTF8.self))
        let page = try ExtensionPage.parse(json)
        guard case .scene(let scene)? = page.sections.first?.blocks.first else { Issue.record("\(page)"); return }
        #expect(scene.action(area: "go", value: nil)?.tool == "start")
    }
}
