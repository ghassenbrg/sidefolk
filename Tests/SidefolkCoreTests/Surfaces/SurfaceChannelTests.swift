import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// The surface channel (D99): `sidefolk/surface.open|move|close` with the game channel's limits, the manifest's keys,
/// `surfaces.open` and its sentences.
struct SurfaceChannelTests {
    static let fixture = #"""
    import json, sys, time
    def send(o):
        sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
    moves = []
    closed = []
    scene = lambda text: {"size": [200, 100], "nodes": [
        {"type": "text", "id": "t", "text": text, "w": 200, "h": 40},
        {"type": "group", "id": "go", "w": 50, "h": 50, "y": 50, "area": {"id": "go", "label": "Go"}},
        {"type": "image", "id": "pic", "image": "a.png", "w": 20, "h": 20}]}
    for line in sys.stdin:
        m = json.loads(line)
        if "id" not in m: continue
        meth, p = m["method"], m.get("params") or {}
        if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "g", "version": "1"}}
        elif meth == "tools/list": r = {"tools": []}
        elif meth == "sidefolk/surface.open":
            r = {"session": "s-1", "scene": scene(p.get("language", "?") + " " + json.dumps(sorted(p.keys())) + json.dumps(p.get("arguments")))}
        elif meth == "sidefolk/surface.move":
            mv = p.get("move", {})
            moves.append(mv)
            if mv.get("click", {}).get("area") == "go" and len(moves) == 2: time.sleep(3)
            if mv.get("next"): r = {"scene": {"nodes": [{"type": "text", "text": "x" * 70000}]}}
            else: r = {"scene": scene("moves " + json.dumps(moves) + " closed " + ",".join(closed))}
        elif meth == "sidefolk/surface.close":
            closed.append(p.get("reason", "")); r = {}
        else:
            send({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32601, "message": "nope"}}); continue
        send({"jsonrpc": "2.0", "id": m["id"], "result": r})
    """#

    static func manifest(_ surfaces: JSONValue, assets: JSONValue? = "assets") -> JSONValue {
        var extra: [String: JSONValue] = ["sidefolk": ">=0.1", "surfaces": surfaces]
        if let assets { extra["assets"] = assets }
        return ExtFixtures.manifest(id: "dev.test.surfaces", tools: [:], extra: extra)
    }

    func folder(_ surfaces: JSONValue = ["board": ["title": "Board", "say": ["open the board"], "ai": true, "width": 300, "height": 300],
                                         "quiet": ["title": "Quiet", "kind": "overlay"]],
                assets: [String: Data] = ["a.png": PackAssetsTests.png()]) throws -> URL {
        let dir = try ExtFixtures.tempDir("surface-src").appendingPathComponent("fixture")
        let source = try ExtFixtures.makeExtension(at: dir, manifest: Self.manifest(surfaces), files: ["server.py": Self.fixture])
        for (path, data) in assets {
            let url = source.appendingPathComponent("assets/\(path)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return source
    }

    func validate(_ surfaces: JSONValue, assets: JSONValue?, files: [String: Data]) async throws -> ValidationReport {
        let h = try HostEnv()
        let dir = try ExtFixtures.tempDir("surface-val").appendingPathComponent("fixture")
        let source = try ExtFixtures.makeExtension(at: dir, manifest: Self.manifest(surfaces, assets: assets), files: ["server.py": Self.fixture])
        for (path, data) in files {
            let url = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return await h.host.preview(folder: source).report
    }

    // MARK: The manifest

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func theValidatorChecksSurfacesAndAssets() async throws {
        let fine = try await validate(["a": ["title": "A", "kind": "overlay", "width": 200, "height": 200]], assets: "assets", files: ["assets/a.png": PackAssetsTests.png()])
        #expect(fine.errors.isEmpty, "\(fine.errors)")
        #expect(fine.text.contains("Surfaces: A"))

        func errors(_ surfaces: JSONValue, assets: JSONValue? = nil, files: [String: Data] = [:]) async throws -> String {
            try await validate(surfaces, assets: assets, files: files).errors.map(\.description).joined(separator: "\n")
        }
        do { let found = try await errors(["BAD": ["title": "A"]]); #expect(found.contains("valid surface name"), "\(found)") }
        do { let found = try await errors(["a": ["title": ""]]); #expect(found.contains("title"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A", "width": 900]]); #expect(found.contains("width"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A", "height": 700]]); #expect(found.contains("height"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A", "kind": "overlay", "width": 600]]); #expect(found.contains("width"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A", "width": 50]]); #expect(found.contains("width"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A", "say": ["open {thing}"]]]); #expect(found.contains("slots"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A", "symbol": "NOT A SYMBOL"]]); #expect(found.contains("symbol"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A", "unheard": true]]); #expect(found.contains("known key"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A", "kind": "fullscreen"]]); #expect(found.isEmpty == false, "\(found)") }

        do { let found = try await errors(["a": ["title": "A"]], assets: "../up"); #expect(found.contains("assets"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A"]], assets: "nope"); #expect(found.contains("isn't a folder"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A"]], assets: "assets", files: ["assets/run.sh": Data("x".utf8)]); #expect(found.contains("assets/run.sh"), "\(found)") }
        do { let found = try await errors(["a": ["title": "A"]], assets: "assets", files: ["assets/x.png": Data("x".utf8)]); #expect(found.contains("assets/x.png"), "\(found)") }
    }

    // MARK: The channel

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aSurfaceIsUsedOverTheChannelWithinItsLimits() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: folder())
        let shelf = h.host.surfaceShelf.all
        #expect(shelf.map(\.id) == ["\(info.id)/board", "\(info.id)/quiet"])
        let board = try #require(shelf.first)
        #expect(board.width == 300 && board.presentation == .panel && board.ai && board.title == "Board")
        #expect(shelf[1].presentation == .overlay && !shelf[1].ai)

        let session = SurfaceSession(info: board, host: h.host, reduceMotion: false)
        let scene = try await session.open(language: "de", arguments: ["topic": "cups"])
        guard case .text(let text)? = scene.nodes.first?.kind else { Issue.record("\(scene.nodes)"); return }
        #expect(text.text.hasPrefix("de "), "the extension hears the person's language")
        #expect(!text.text.contains("companion") && !text.text.contains("person"), "and nothing of who they are: \(text.text)")
        #expect(text.text.contains("cups"))
        #expect(scene.nodes.contains { $0.id == "pic" }, "a picture in the pack is drawn")

        // A move the scene didn't offer never goes out.
        #expect(try await session.move(.click(area: "elsewhere", value: nil, ms: nil)) == nil)
        #expect(try await session.move(.back) == nil)
        let moved = try #require(try await session.move(.click(area: "go", value: nil, ms: nil)))
        guard case .text(let m)? = moved.nodes.first?.kind else { Issue.record("\(moved.nodes)"); return }
        #expect(m.text.contains(#""go""#) && !m.text.contains("elsewhere"))

        // A slow answer ends it, and the extension's name says who.
        await #expect(throws: UserFacingError.self) { try await session.move(.click(area: "go", value: nil, ms: nil)) }
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func hugeAnswersRatesAndOtherSessionsAreRefused() async throws {
        let h = try HostEnv()
        _ = try await h.host.install(from: folder())
        let board = try #require(h.host.surfaceShelf.all.first)
        let (session, _) = try await h.host.openSurface(board, language: "en")
        await #expect(throws: UserFacingError.self) {
            try await h.host.moveSurface(info: board, session: "other", move: .click(area: "go", value: nil, ms: nil))
        }
        await #expect(throws: UserFacingError.self, "over 64 KB") {
            try await h.host.moveSurface(info: board, session: session, move: .next)
        }
        let now = Date()
        var refused = 0
        for i in 0..<25 {
            do { _ = try await h.host.moveSurface(info: board, session: session, move: .timer("t"), now: now.addingTimeInterval(Double(i) * 0.001)) } catch { refused += 1 }
        }
        #expect(refused >= 5, "at most 20 a second: \(refused)")
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aSurfaceGoesWithItsExtensionAndOnlyOneStandsInItsPlace() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: folder())
        let board = try #require(h.host.surfaceShelf.all.first)
        let (first, _) = try await h.host.openSurface(board, language: "en")
        let (second, _) = try await h.host.openSurface(board, language: "en")
        #expect(first == second, "the fixture reuses its session name")
        let stream = h.env.events.stream()
        try await h.host.setEnabled(false, id: info.id)
        #expect(h.host.surfaceShelf.all.isEmpty, "turned off, nothing of it can open")
        var gone = false
        for await event in stream {
            if case .surfaceGone(let id) = event, id == info.id { gone = true; break }
        }
        #expect(gone, "what was open closes at once")
        await #expect(throws: (any Error).self) { try await h.host.moveSurface(info: board, session: first, move: .click(area: "go", value: nil, ms: nil)) }
        await #expect(throws: (any Error).self) { try await h.host.openSurface(board, language: "en") }
        try await h.host.setEnabled(true, id: info.id)
        #expect(!h.host.surfaceShelf.all.isEmpty)
        try await h.host.uninstall(id: info.id)
        #expect(h.host.surfaceShelf.all.isEmpty)
    }

    // MARK: The tool and the sentences

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func theToolOpensForThePersonAndForTheAIOnlyWhatItIsOffered() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: folder())
        let tool = SurfacesOpenTool(events: h.env.events, shelf: h.host.surfaceShelf)
        #expect(tool.spec.description.contains("\(info.id)/board") && !tool.spec.description.contains("\(info.id)/quiet"), "the AI is told only what is offered to it")
        #expect(tool.spec.risk == .low)

        let stream = h.env.events.stream()
        func requests() async -> SurfaceRequest? {
            for await event in stream { if case .surface(let r) = event { return r } }
            return nil
        }
        _ = try await tool.run(["surface": .string("\(info.id)/board")], context: ToolContext(caller: .agent(runId: "r"), now: Date()))
        let byAI = await requests()
        #expect(byAI?.focus == false, "the AI's waits for a click")
        _ = try await tool.run(["surface": .string("\(info.id)/quiet")], context: ToolContext(caller: .user, now: Date()))
        let byPerson = await requests()
        #expect(byPerson?.focus == true && byPerson?.takesKeyboard == false, "an overlay never takes the keyboard")
        await #expect(throws: (any Error).self) { try await tool.run(["surface": .string("\(info.id)/quiet")], context: ToolContext(caller: .agent(runId: "r"), now: Date())) }
        await #expect(throws: (any Error).self) { try await tool.run(["surface": "dev.nope.x/y"], context: ToolContext(caller: .user, now: Date())) }

        let args = SurfacesOpenTool.arguments(["topic": "cups\u{202E}", "count": 3, "on": true, "nested": ["x": 1], "BAD KEY": "y"])
        #expect(args == ["topic": "cups", "count": 3, "on": true], "small plain values only, cleaned: \(args)")

        let parser = IntentParser(when: WhenParser(), surfaces: h.host.surfaceShelf.all)
        #expect(parser.surface("open the board")?.intent == .surface(id: "\(info.id)/board"))
        #expect(parser.surface("open the moon") == nil)
    }
}
