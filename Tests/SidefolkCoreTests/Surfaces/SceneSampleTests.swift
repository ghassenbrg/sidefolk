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
        #expect(shuffle.nodes.contains { $0.kind == .companion(pose: .thinking) } && shuffle.nodes.contains { $0.kind == .person })

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
