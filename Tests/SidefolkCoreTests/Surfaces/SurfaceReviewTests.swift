import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// What the review of snapshot A found about surfaces (D99, T40), each as the behaviour that must hold.
struct SurfaceReviewTests {
    /// A program whose tools answer with what they are asked to ask for (`sidefolk`), and whose surfaces record what they hear.
    static let fixture = #"""
    import json, sys, time
    def send(o):
        sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
    heard = []
    for line in sys.stdin:
        m = json.loads(line)
        if "id" not in m: continue
        meth, p = m["method"], m.get("params") or {}
        if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "g", "version": "1"}}
        elif meth == "tools/list":
            r = {"tools": [{"name": "start", "title": "Start", "description": "d", "inputSchema": {"type": "object", "properties": {"asks": {"type": "object"}}}}]}
        elif meth == "tools/call":
            r = {"content": [{"type": "text", "text": "started"}], "sidefolk": p["arguments"].get("asks", {})}
        elif meth == "sidefolk/surface.open":
            heard.append(p)
            if p.get("arguments", {}).get("slow"): time.sleep(0.6)
            r = {"session": "s" + str(len(heard)), "scene": {"size": [200, 100], "nodes": [{"type": "text", "text": json.dumps(p), "w": 190, "h": 40},
                 {"type": "group", "w": 10, "h": 10, "area": {"id": "go", "label": "Go"}}]}}
        elif meth == "sidefolk/surface.move":
            r = {"scene": {"size": [200, 100], "nodes": [{"type": "text", "text": json.dumps(heard), "w": 190, "h": 40}]}}
        elif meth == "sidefolk/surface.close": r = {}
        elif meth == "sidefolk/page.render":
            r = {"page": {"summary": {"title": "keys", "detail": " ".join(sorted(p.keys()))}, "sections": []}}
        else:
            send({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32601, "message": "nope"}}); continue
        send({"jsonrpc": "2.0", "id": m["id"], "result": r})
    """#

    static let surfaces: JSONValue = [
        "board": ["title": "Board", "say": ["open the board"], "ai": true, "arguments": ["level": ["easy", "hard"], "fresh": ["true"]]],
        "shy": ["title": "Shy", "kind": "overlay"],
    ]

    static func manifest(id: String = "dev.test.review", surfaces: JSONValue = surfaces, extra: [String: JSONValue] = [:]) -> JSONValue {
        var all: [String: JSONValue] = ["sidefolk": ">=0.1", "surfaces": surfaces, "pages": ["home": ["title": "Home"]]]
        all.merge(extra) { _, own in own }
        return ExtFixtures.manifest(id: id, tools: ["start": ["title": "Start", "risk": "low"]], extra: all)
    }

    func install(_ h: HostEnv, manifest: JSONValue = Self.manifest(), origin: ExtensionOrigin? = nil, name: String = "review") async throws -> ExtensionInfo {
        let source = try h.source(name, manifest: manifest, files: ["server.py": Self.fixture])
        return try await h.host.install(from: source, origin: origin)
    }

    func engine(_ spec: ToolSpec) -> GuardDecision {
        PermissionEngine().evaluate(spec: spec, input: [:], summary: "", scope: ToolScope(), caller: .agent(runId: "r"), tainted: true, policy: GuardPolicy(), grants: [], folders: [])
    }

    /// Nil when none came in time: a test here must fail, not wait for ever.
    func nextSurface(_ stream: AsyncStream<AppEvent>) async -> SurfaceRequest? {
        await first(stream) { if case .surface(let r) = $0 { r } else { nil } }
    }

    func first<T: Sendable>(_ stream: AsyncStream<AppEvent>, seconds: Double = 5, _ pick: @escaping @Sendable (AppEvent) -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                for await event in stream { if let found = pick(event) { return found } }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: A model's words don't reach a program through surfaces.open

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aModelPassesOnlyTheChoicesTheManifestLists() async throws {
        let h = try HostEnv()
        let info = try await install(h)
        let tool = SurfacesOpenTool(events: h.env.events, shelf: h.host.surfaceShelf)
        #expect(tool.spec.description.contains("level: easy|hard"), "the AI is told which values there are")
        let stream = h.env.events.stream()
        let input: JSONValue = ["surface": .string("\(info.id)/board"), "arguments": ["note": "the person's whole note", "level": "hard", "other": "easy", "fresh": true, "n": 1234]]

        // However a turn was steered, the free text never goes, and it isn't taken as a level.
        _ = try await tool.run(input, context: ToolContext(caller: .agent(runId: "r"), now: Date(), tainted: true))
        #expect(await nextSurface(stream)?.arguments == ["level": "hard", "fresh": true])
        _ = try await tool.run(input, context: ToolContext(caller: .external(client: "x"), now: Date()))
        #expect(await nextSurface(stream)?.arguments == ["level": "hard", "fresh": true])
        // The person's own click or the extension's own reply may say anything: it comes from them, or goes back to it.
        _ = try await tool.run(input, context: ToolContext(caller: .user, now: Date()))
        #expect(await nextSurface(stream)?.arguments["note"] == "the person's whole note")
        // And the card says what goes.
        #expect(tool.summary(for: ["surface": .string("\(info.id)/board"), "arguments": ["level": "hard"]]).contains("level: hard"))
    }

    @Test func theValidatorChecksWhatAModelMayPass() async throws {
        let h = try HostEnv()
        let dir = try ExtFixtures.tempDir("args").appendingPathComponent("fixture")
        let source = try ExtFixtures.makeExtension(at: dir, manifest: Self.manifest(surfaces: ["a": ["title": "A", "arguments": ["BAD": ["x"], "empty": []], "speaker_setting": "nope"]]),
                                                   files: ["server.py": Self.fixture])
        let wrong = await h.host.preview(folder: source).report.errors.map(\.description)
        #expect(wrong.contains { $0.contains("arguments.BAD") }, "\(wrong)")
        #expect(wrong.contains { $0.contains("arguments.empty") })
        #expect(wrong.contains { $0.contains("speaker_setting") })
    }

    // MARK: A tool's reply opens its own surface

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aToolReplyOpensOnlyItsOwnSurfaceAndOnlyForWhoMayOpenIt() async throws {
        let h = try HostEnv()
        let info = try await install(h)
        h.env.registry.register(SurfacesOpenTool(events: h.env.events, shelf: h.host.surfaceShelf))
        let stream = h.env.events.stream()
        let start = "ext.review.start"

        // The person's click: their keyboard, and whatever the program starts it with.
        let asks: JSONValue = ["asks": ["open_surface": ["surface": "board", "arguments": ["topic": "cats"]]]]
        #expect((await h.env.executor.execute(name: start, input: asks, caller: .user)).okText == "started")
        let byPerson = await nextSurface(stream)
        #expect(byPerson?.info.surface == "board" && byPerson?.focus == true && byPerson?.arguments["topic"] == "cats")

        // The person's sentence: a command of its own.
        _ = await h.env.executor.execute(name: start, input: asks, caller: .command(extensionId: info.id))
        #expect(await nextSurface(stream)?.focus == true)

        // The AI's call: a surface marked `ai`, waiting for a click.
        _ = await h.env.executor.execute(name: start, input: asks, caller: .agent(runId: "r"))
        #expect(await nextSurface(stream)?.focus == false)

        // What isn't offered to the AI, isn't declared, or is someone else's opens nothing.
        let shy: JSONValue = ["asks": ["open_surface": "shy", "hold_answer_ms": 900]]
        let denied = await h.env.executor.execute(name: start, input: shy, caller: .agent(runId: "r"))
        if case .ok(let r) = denied.status { #expect(r.card?.holdAnswer == 0.9, "and the answer waits as long as it asked") }
        _ = await h.env.executor.execute(name: start, input: ["asks": ["open_surface": "nope"]], caller: .user)
        _ = await h.env.executor.execute(name: start, input: ["asks": ["open_surface": "dev.other.x/board"]], caller: .user)
        _ = await h.env.executor.execute(name: start, input: asks, caller: .routine(id: "r"))
        _ = await h.env.executor.execute(name: start, input: ["asks": ["open_surface": "shy"]], caller: .user)
        let last = await nextSurface(stream)
        #expect(last?.info.surface == "shy" && last?.focus == true, "nothing else came before the person's own: \(String(describing: last))")
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aToolReplyShowsItsPageAndPutsItsSurfaceAway() async throws {
        let h = try HostEnv()
        let info = try await install(h)
        let stream = h.env.events.stream()
        _ = await h.env.executor.execute(name: "ext.review.start", input: ["asks": ["open_page": "nope", "close_surface": "nope"]], caller: .user)
        _ = await h.env.executor.execute(name: "ext.review.start", input: ["asks": ["open_page": "home"]], caller: .agent(runId: "r"))
        _ = await h.env.executor.execute(name: "ext.review.start", input: ["asks": ["close_surface": "board"]], caller: .agent(runId: "r"))
        _ = await h.env.executor.execute(name: "ext.review.start", input: ["asks": ["close_surface": true]], caller: .user)
        _ = await h.env.executor.execute(name: "ext.review.start", input: ["asks": ["open_page": "home"]], caller: .user)
        let seen = Mutex<[String?]>([])
        let page = await first(stream) { event -> String? in
            if case .surfaceAway(let id, let surface) = event, id == info.id { seen.withLock { $0.append(surface) } }
            if case .extensionPage(let id) = event { return id }
            return nil
        }
        #expect(seen.withLock { $0 } == ["board", nil], "\(seen.withLock { $0 })")
        #expect(page == "\(info.id)/home", "the AI can't send the person to a page, only their own click can")
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func anEntryCanOpenASurfaceDirectly() async throws {
        let h = try HostEnv()
        let manifest = Self.manifest(extra: ["entries": [["id": "go", "title": "Play", "places": ["companion"], "surface": "board", "input": ["level": "easy"]]]])
        let info = try await install(h, manifest: manifest)
        let entry = try #require(h.host.shelf.entries.first)
        #expect(entry.action == .surface(id: "\(info.id)/board", arguments: ["level": "easy"]))
        let source = try h.source("wrong", manifest: Self.manifest(id: "dev.test.wrong", extra: ["entries": [["id": "go", "title": "Play", "places": ["companion"], "surface": "nope"]]]), files: ["server.py": Self.fixture])
        #expect(await h.host.preview(folder: source).report.errors.contains { $0.description.contains("isn't one of its surfaces") })
    }

    // MARK: Caps that count what things cost

    @Test func aSceneOfGiantBitmapsIsRefused() throws {
        let many: [JSONValue] = (0..<40).map { _ in ["style": "s"] }
        let giant: JSONValue = ["size": [400, 400], "styles": ["s": ["type": "shape", "w": 2000, "h": 2000, "opacity": 0.01, "gradient": ["colors": ["accent", "ink"]]]], "nodes": .array(many)]
        #expect(throws: UserFacingError.self, "40 × 64 MB of gradient") { try SurfaceScene.parse(giant) }

        let words: [JSONValue] = (0..<40).map { _ in ["type": "text", "text": "x", "w": 2000, "h": 2000] }
        #expect(throws: UserFacingError.self, "a bitmap per text") { try SurfaceScene.parse(["nodes": .array(words)]) }

        // A tinted picture is a copy per node; the same picture plain is one.
        let tinted: [JSONValue] = (0..<40).map { _ in ["type": "image", "image": "a.png", "w": 2000, "h": 2000, "tint": "ink"] }
        #expect(throws: UserFacingError.self) { try SurfaceScene.parse(["nodes": .array(tinted)]) }
        let plain: [JSONValue] = (0..<40).map { _ in ["type": "image", "image": "a.png", "w": 2000, "h": 2000] }
        #expect(try SurfaceScene.parse(["nodes": .array(plain)]).drawnBytes == 64_000_000)

        // A real board is nowhere near it: 81 cells of words, a full-canvas backdrop.
        let board: [JSONValue] = (0..<81).map { _ in ["type": "text", "text": "9", "w": 40, "h": 40] }
        let backdrop: JSONValue = ["type": "shape", "w": 720, "h": 676, "gradient": ["colors": ["accent", "ink"]]]
        #expect(try SurfaceScene.parse(["nodes": .array([backdrop] + board)]).drawnBytes < SurfaceScene.maxDrawnBytes / 4)
    }

    @Test func aFlipIsCountedAsWhatItBecomes() throws {
        func flips(_ count: Int) -> JSONValue {
            let nodes: [JSONValue] = (0..<count).map { ["type": "flip", "id": .string("f\($0)"), "w": 10, "h": 10] }
            let animations: [JSONValue] = (0..<count).map { ["target": .string("f\($0)"), "keys": [["t": 0, "flip": -400], ["t": 1, "flip": 400]], "ms": 100, "repeat": 40, "autoreverse": true] }
            return ["nodes": .array(nodes), "animations": .array(animations)]
        }
        // 37 such nodes were 2,997 points and 18.8 million samples.
        #expect(throws: UserFacingError.self) { try SurfaceScene.parse(flips(37)) }
        #expect(throws: UserFacingError.self) { try SurfaceScene.parse(flips(1)) }
        // A coin spun a good few turns is well inside it.
        let coin: JSONValue = ["nodes": [["type": "flip", "id": "c", "w": 80, "h": 80]], "animations": [["target": "c", "to": ["flip": 9], "ms": 1400, "ease": "out"]]]
        let scene = try SurfaceScene.parse(coin)
        let curve = try #require(scene.runs.first?.curves.first)
        #expect(SceneFlipKeys.samples(curve) == SceneFlipKeys(curve).times.count)
    }

    @Test func aFieldStaysInsideTheCanvas() {
        let canvas = CGSize(width: 400, height: 300)
        #expect(SurfacePolicy.fieldFrame(CGRect(x: 0, y: -44, width: 400, height: 44), canvas: canvas) == nil, "not over the frame")
        #expect(SurfacePolicy.fieldFrame(CGRect(x: 10, y: 10, width: 100, height: 30), canvas: canvas) == CGRect(x: 10, y: 10, width: 100, height: 30))
        #expect(SurfacePolicy.fieldFrame(CGRect(x: 300, y: -20, width: 2000, height: 2000), canvas: canvas) == CGRect(x: 300, y: 0, width: 100, height: 300), "cut at its edge")
    }

    // MARK: Attention

    @Test func clocksAreNotAttention() {
        var a = SurfaceAttention(now: Date(timeIntervalSince1970: 0))
        let later = Date(timeIntervalSince1970: 500)
        let clock = a.admit(.timer("t"), now: later), next = a.admit(.next, now: later)
        #expect(clock && next)
        #expect(a.lastActive == Date(timeIntervalSince1970: 0), "a program's clock doesn't keep an overlay on the desktop")
        #expect(!a.used)
        _ = a.admit(.click(area: "a", value: nil, ms: nil), now: later)
        #expect(a.lastActive == later && a.used)
    }

    @Test func clocksRunOutWithNoOneThere() {
        var a = SurfaceAttention()
        var sent = 0
        for i in 0..<2000 where a.admit(i.isMultiple(of: 2) ? .timer("t") : .next) { sent += 1 }
        #expect(sent == SurfaceAttention.maxIdleMoves, "timers and nexts count together")
        let person = a.admit(.back), after = a.admit(.next)
        #expect(person, "the person is always heard")
        #expect(after, "and that starts the count again")
    }

    @Test func aSurfacePutAwayRunsNothing() {
        var a = SurfaceAttention()
        let shown = a.mayAnnounce()
        #expect(shown)
        a.hide()
        let (next, timer, back) = (a.admit(.next), a.admit(.timer("t")), a.admit(.back))
        #expect(!next && !timer && !back)
        let aloud = a.mayAnnounce(now: Date().addingTimeInterval(60))
        #expect(!aloud, "not aloud from a hidden panel")
        a.show()
        let again = a.admit(.next)
        #expect(again)
    }

    @Test func announcementsArePaced() {
        var a = SurfaceAttention()
        let now = Date()
        let first = a.mayAnnounce(now: now), soon = a.mayAnnounce(now: now.addingTimeInterval(0.1)), later = a.mayAnnounce(now: now.addingTimeInterval(SurfaceAttention.announceGap))
        #expect(first && !soon && later)
    }

    @Test func aProgramFlippingOverCanNotFillHistory() {
        var a = SurfaceAttention()
        let first = a.rowForScene(over: true)
        #expect(first, "the first ending writes its row")
        var flipped = 0
        for _ in 0..<50 {
            if a.rowForScene(over: false) { flipped += 1 }
            if a.rowForScene(over: true) { flipped += 1 }
        }
        #expect(flipped == 0, "no one moved, so no new row")
        // The person plays again: a new ending is a new row.
        _ = a.admit(.click(area: "again", value: nil, ms: nil))
        _ = a.rowForScene(over: false)
        let second = a.rowForScene(over: true), atEnd = a.rowAtEnd()
        #expect(second)
        #expect(!atEnd, "and closing after it adds no second row")
    }

    @Test func aSurfaceThatNeverEndedStillGetsOneRow() {
        var a = SurfaceAttention()
        let looked = a.rowAtEnd()
        #expect(!looked, "looked at, not used")
        _ = a.admit(.back)
        let used = a.rowAtEnd(), twice = a.rowAtEnd()
        #expect(used)
        #expect(!twice, "once, however many ways it ends")
    }

    // MARK: Over rate, updates, crashes and crossing opens

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func anOverRateMoveEndsNothing() async throws {
        let h = try HostEnv()
        _ = try await install(h)
        let board = try #require(h.host.surfaceShelf.all.first)
        let session = SurfaceSession(info: board, host: h.host, reduceMotion: false)
        _ = try await session.open(language: "en")
        let now = Date()
        var answered = 0, dropped = 0
        for i in 0..<30 {
            if try await session.move(.click(area: "go", value: nil, ms: nil), now: now.addingTimeInterval(Double(i) * 0.001)) == nil { dropped += 1 } else { answered += 1 }
        }
        // The fixture's next scene has no area, so only the first is offered at all: the rate is `OpenSurface`'s.
        #expect(answered + dropped == 30)
        var open = OpenSurface(info: board, session: "s")
        let allowed = (0..<30).filter { open.allow(at: now.addingTimeInterval(Double($0) * 0.001)) }.count
        #expect(allowed == ExtensionHost.surfaceMovesPerSecond)
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func anUpdateAndTheCrashLimitTakeTheSurfaceWithThem() async throws {
        let h = try HostEnv()
        let info = try await install(h)
        let board = try #require(h.host.surfaceShelf.all.first)
        let (session, _) = try await h.host.openSurface(board, language: "en")
        let stream = h.env.events.stream()
        _ = try await install(h, manifest: Self.manifest().setting("version", "2.0.0"), name: "review2")
        let gone = await first(stream) { event -> Bool? in if case .surfaceGone(let id) = event, id == info.id { true } else { nil } }
        #expect(gone == true, "an update closes it: the new program never opened that session")
        await #expect(throws: UserFacingError.self) { try await h.host.moveSurface(info: board, session: session, move: .click(area: "go", value: nil, ms: nil)) }
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aCrashTurningItOffClosesTheSurface() async throws {
        let h = try HostEnv { $0.crashLimit = 1 }
        let crasher = #"""
        import json, sys, os
        for line in sys.stdin:
            m = json.loads(line)
            if "id" not in m: continue
            meth, p = m["method"], m.get("params") or {}
            if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "g", "version": "1"}}
            elif meth == "tools/list": r = {"tools": []}
            elif meth == "sidefolk/surface.open": r = {"session": "s", "scene": {"size": [100, 100], "nodes": []}}
            else: os._exit(3)
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}) + "\n"); sys.stdout.flush()
        """#
        let source = try h.source("crasher", manifest: ExtFixtures.manifest(id: "dev.test.crasher", tools: [:], extra: ["sidefolk": ">=0.1", "surfaces": ["p": ["title": "P"]]]),
                                  files: ["server.py": crasher])
        let info = try await h.host.install(from: source)
        let panel = try #require(h.host.surfaceShelf.all.first)
        let (session, _) = try await h.host.openSurface(panel, language: "en")
        let stream = h.env.events.stream()
        _ = try? await h.host.moveSurface(info: panel, session: session, move: .next)
        let gone = await first(stream) { event -> Bool? in if case .surfaceGone(let id) = event, id == info.id { true } else { nil } }
        #expect(gone == true)
        #expect(await h.host.info(id: info.id)?.enabled == false)
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aSlowOpenLosesToANewerOneInItsPlace() async throws {
        let h = try HostEnv()
        _ = try await install(h)
        let board = try #require(h.host.surfaceShelf.all.first)
        let slow = Task { try await h.host.openSurface(board, language: "en", arguments: ["slow": true]) }
        try await Task.sleep(for: .milliseconds(150))
        let (fresh, _) = try await h.host.openSurface(board, language: "en")
        await #expect(throws: UserFacingError.self, "the slow one isn't wanted any more") { try await slow.value }
        let moved = try await h.host.moveSurface(info: board, session: fresh, move: .click(area: "go", value: nil, ms: nil))
        #expect(moved != nil, "the one on screen is the one open")
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func everyRequestCarriesTheSettings() async throws {
        let h = try HostEnv()
        let settings: JSONValue = [["key": "tone", "type": "choice", "title": "Tone", "default": "a", "options": [["value": "a", "title": "A"], ["value": "b", "title": "B"]]]]
        let info = try await install(h, manifest: Self.manifest(extra: ["settings": settings]))
        h.env.registry.register(ExtensionSettingTool(host: h.host))
        _ = await h.call(ExtensionSettingTool.name, ["extension": .string(info.id), "key": "tone", "value": "b"])
        let board = try #require(h.host.surfaceShelf.all.first)
        // A page render and a surface's opening name their own language, and were left without the rest.
        let page = try await h.host.renderPage(extensionId: info.id, page: "home", language: "fr")
        #expect(page.summary?.detail.contains("settings") == true, "\(page)")
        let (_, scene) = try await h.host.openSurface(board, language: "fr")
        guard case .text(let text)? = scene.nodes.first?.kind else { Issue.record("\(scene.nodes)"); return }
        #expect(text.text.contains(#""settings""#) && text.text.contains(#""tone""#) && text.text.contains(#""b""#) && text.text.contains(#""language": "fr""#), "\(text.text)")
    }

    // MARK: The speaker

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func theSpeakerIsADeclaredSettingOrTheSurfacesOwnAndGoesWithIt() async throws {
        let h = try HostEnv()
        let settings: JSONValue = [["key": "sounds", "type": "switch", "title": "Sounds", "default": true]]
        let surfaces: JSONValue = ["board": ["title": "Board", "speaker_setting": "sounds"], "shy": ["title": "Shy"]]
        let info = try await install(h, manifest: Self.manifest(surfaces: surfaces, extra: ["settings": settings]))
        h.env.registry.register(ExtensionSettingTool(host: h.host))
        let all = h.host.surfaceShelf.all
        let board = try #require(all.first { $0.surface == "board" }), shy = try #require(all.first { $0.surface == "shy" })
        #expect(board.speakerSetting == "sounds")

        #expect(await h.host.surfaceSpeaker(board, key: "sounds"), "its own setting's default")
        await h.host.setSurfaceSpeaker(board, key: "sounds", on: false)
        #expect(await !h.host.surfaceSpeaker(board, key: "sounds"))
        #expect(h.host.shelf.settings.first { $0.key == "sounds" }?.value == false, "one switch, wherever it shows")
        #expect(try await h.env.activity.recent(limit: 5, tool: ExtensionSettingTool.name).count == 1, "and History has it")

        #expect(await !h.host.surfaceSpeaker(shy, key: nil), "off until the person says so")
        await h.host.setSurfaceSpeaker(shy, key: nil, on: true)
        #expect(await h.host.surfaceSpeaker(shy, key: nil))
        // A scene naming something that isn't a switch of its own changes nothing.
        await h.host.setSurfaceSpeaker(shy, key: "nope", on: false)
        #expect(await !h.host.surfaceSpeaker(shy, key: nil))

        try await h.host.uninstall(id: info.id)
        _ = try await install(h, manifest: Self.manifest(surfaces: surfaces, extra: ["settings": settings]), name: "again")
        let back = try #require(h.host.surfaceShelf.all.first { $0.surface == "shy" })
        #expect(await !h.host.surfaceSpeaker(back, key: nil), "nothing of it stays after it goes")
    }
}

/// A scene's own abilities added for what today's screens do (D99).
struct SceneAbilityTests {
    func scene(_ nodes: [JSONValue], _ extra: [String: JSONValue] = [:]) throws -> SurfaceScene {
        var all = extra
        all["nodes"] = .array(nodes)
        return try SurfaceScene.parse(.object(all))
    }

    @Test func aPairOfFacesFitsTheCompanionCap() throws {
        let faces: [JSONValue] = (0..<SurfaceScene.maxPeople).map { _ in ["type": "companion", "figure": "face", "w": 30, "h": 30] }
        #expect(try scene(faces).nodes.count == SurfaceScene.maxPeople)
        #expect(throws: UserFacingError.self) { try scene(faces + [["type": "person", "w": 30, "h": 30]]) }
    }

    @Test func figuresSayHowTheySit() throws {
        let s = try scene([["type": "companion", "id": "c", "w": 104, "h": 100, "figure": "face", "align": "bottom", "duotone": "accent"],
                           ["type": "person", "id": "p", "w": 40, "h": 40, "duotone": "#F0C040"]])
        guard case .companion(_, let look)? = s.node("c")?.kind else { Issue.record("\(s.nodes)"); return }
        #expect(look.face && look.bottom && look.duotone == .token(.accent))
        guard case .person(let person)? = s.node("p")?.kind else { Issue.record("\(s.nodes)"); return }
        #expect(!person.face && !person.bottom && person.duotone != nil)
    }

    @Test func textTakesTodaysStyles() throws {
        let s = try scene([["type": "text", "id": "t", "text": "VS", "weight": "black", "italic": true, "tabular": true, "strike": true, "design": "theme"],
                           ["type": "text", "id": "r", "weight": "bold", "runs": [["text": "First ", "color": "ink"], ["text": "the rest", "color": "ink_muted", "weight": "regular"]], "lines": 2],
                           ["type": "text", "id": "w", "text": "x", "weight": "wobbly"],
                           ["type": "clock", "id": "k", "seconds": 4512]])
        guard case .text(let t)? = s.node("t")?.kind else { Issue.record("\(s.nodes)"); return }
        #expect(t.weight == .black && t.italic && t.tabular && t.strike && t.design == .theme)
        guard case .text(let r)? = s.node("r")?.kind else { Issue.record("\(s.nodes)"); return }
        #expect(r.text == "First the rest" && r.runs.count == 2 && r.runs[1].weight == .regular && r.runs[1].color == .token(.inkMuted))
        #expect(s.notes.contains { $0.contains("wobbly") }, "a weight it doesn't know is said, not silently regular")
        guard case .clock(let k)? = s.node("k")?.kind else { Issue.record("\(s.nodes)"); return }
        #expect(k.style.tabular, "a clock's digits don't jitter")
    }

    @Test func symbolsTakeAWeightAndColours() throws {
        let s = try scene([["type": "symbol", "id": "s", "name": "xmark", "weight": "black", "mode": "mono", "secondary": "accent"]])
        guard case .symbol(let symbol)? = s.node("s")?.kind else { Issue.record("\(s.nodes)"); return }
        #expect(symbol.weight == .black && symbol.mono && symbol.secondary == .token(.accent))
    }

    @Test func coloursCanBeATokenTuned() throws {
        #expect(SceneReader.color(["token": "accent", "alpha": 0.75, "brightness": -0.14]) == .tuned(.accent, alpha: 0.75, brightness: -0.14))
        #expect(SceneReader.color(["token": "nope"]) == nil)
        let s = try scene([["type": "keyset", "id": "k", "name": "keys", "lip_color": ["token": "success", "brightness": -0.1], "rows": [[["key": "a"]]]]])
        #expect(s.node("k") != nil, "and the helpers carry them")
    }

    @Test func aFieldCanBePlainAndAskForTheKeyboard() throws {
        let s = try scene([["type": "entry", "id": "e", "name": "answer", "w": 100, "h": 30, "focus": true, "plain": true, "weight": "semibold", "design": "rounded"],
                           ["type": "group", "id": "ok", "w": 40, "h": 30, "area": ["id": "ok", "label": "OK", "submits": "answer"]]])
        let entry = try #require(s.entries.first)
        #expect(entry.focus && entry.plain && entry.weight == .semibold && entry.design == .rounded)
        #expect(s.areas.first?.submits == "answer")
    }

    @Test func hoverCanGiveEachNodeItsOwnLook() throws {
        let s = try scene([["type": "group", "id": "card", "w": 100, "h": 100, "area": ["id": "card", "label": "Card", "highlight": ["other", ["id": "badge", "opacity": 1, "dy": -2, "rotate": 4], ["id": "pic", "scale": 1.07]]]]])
        let area = try #require(s.areas.first)
        #expect(area.highlight == ["other"])
        #expect(area.looks["badge"]?.absolute == true && area.looks["badge"]?.opacity == 1 && area.looks["badge"]?.rotate == 4)
        #expect(area.looks["pic"]?.absolute == false && area.looks["pic"]?.scale == 1.07)
    }

    @Test func aDragGhostCanStayInsideItsCells() throws {
        let s = try scene([["type": "group", "id": "g", "w": 100, "h": 100, "area": ["id": "g", "label": "G", "drag": ["mode": "grid", "rows": 4, "columns": 4, "ghost": "ghost", "inset": 3]]]])
        #expect(s.areas.first?.drag?.inset == 3)
    }

    @Test func aScrollBoxClipsAndKeepsItsTarget() throws {
        let s = try scene([["type": "scroll", "id": "list", "w": 300, "h": 200, "content_h": 800, "scroll_to": "row7", "children": [["type": "shape", "id": "row7", "y": 600, "w": 300, "h": 78]]]])
        let node = try #require(s.node("list"))
        guard case .scroll(let box) = node.kind else { Issue.record("\(node.kind)"); return }
        #expect(box.contentHeight == 800 && box.to == "row7" && node.clips)
        #expect(s.node("row7") != nil, "its children are nodes like any others")
    }

    @Test func aStillWaitAndASpeakerAreRead() throws {
        let s = try scene([], ["after_ms": 1500, "after_still_ms": 200, "speaker": "sounds"])
        #expect(s.after == 1.5 && s.afterStill == 0.2 && s.speaker == "sounds")
        #expect(try scene([], ["speaker": "NOT A KEY"]).speaker == nil)
    }

    @Test func aNodeMarkedLtrKeepsItsOwnColumns() throws {
        let s = try scene([["type": "group", "id": "plots", "ltr": true, "w": 100, "h": 100, "children": [["type": "group", "id": "inner", "w": 10, "h": 10]]],
                           ["type": "group", "id": "flowing", "w": 100, "h": 100]])
        #expect(!s.isMirrored("plots"), "its own drag comes back in its own terms")
        #expect(!s.isMirrored("inner"))
        #expect(s.isMirrored("flowing"))
    }

    @Test func accentsGoAtTheSoundsPaceAndOtherMovesAsBefore() {
        var limiter = CueLimiter()
        let now = Date()
        let wave = limiter.move(.accentWave, at: now), hop = limiter.move(.accentHop, at: now.addingTimeInterval(0.26))
        #expect(wave == .now)
        #expect(hop == .now, "a tempo of 280 ms keeps up")
        guard case .after = limiter.move(.accentSpin, at: now.addingTimeInterval(0.3)) else { Issue.record("faster than 4 a second waits"); return }
        let plain = limiter.move(.wave, at: now)
        #expect(plain == .now)
        guard case .after = limiter.move(.hop, at: now.addingTimeInterval(0.3)) else { Issue.record("a full move still waits its 0.8 s"); return }
    }
}
