import Foundation
import Testing
@testable import SidefolkCore

/// The Scene (D99): what is read, what is refused, what the helpers make, how time is flattened, and what mirrors.
struct SceneTests {
    func parse(_ json: JSONValue) throws -> SurfaceScene { try SurfaceScene.parse(json) }
    func scene(_ nodes: [JSONValue], _ extra: [String: JSONValue] = [:]) throws -> SurfaceScene {
        var o: [String: JSONValue] = ["size": [300, 200], "nodes": .array(nodes)]
        o.merge(extra) { _, b in b }
        return try parse(.object(o))
    }

    @Test func readsTheKindsAndClipsTheirValues() throws {
        let s = try scene([
            ["type": "image", "id": "a", "image": "cups/cup.png", "dark": "cups/cup-night.webp", "w": 80, "h": 90, "x": 5, "y": 9000, "fit": "cover", "tint": "accent"],
            ["type": "text", "id": "b", "text": "Hi\u{202E}", "w": 80, "h": 20, "size": 9999, "weight": "heavy", "design": "rounded", "color": "#112233", "lines": 2],
            ["type": "shape", "id": "c", "shape": "path", "path": "M0 0 L10 0 Q5 5 10 10 C1 2 3 4 5 6 Z", "fill": ["light": "#000000", "dark": "#FFFFFF"], "w": 10, "h": 10],
            ["type": "symbol", "id": "d", "name": "star.fill", "color": "win"],
            ["type": "companion", "id": "e", "pose": "thinking", "w": 40, "h": 40],
            ["type": "person", "id": "f", "w": 40, "h": 40],
            ["type": "clock", "id": "g", "seconds": 90, "running": true, "w": 40, "h": 20],
            ["type": "entry", "id": "h", "name": "word", "placeholder": "Type", "max": 999, "w": 200, "h": 30],
            ["type": "somethingNew", "id": "z"],
        ])
        #expect(s.nodes.count == 8, "an unknown type is skipped, the rest stands: \(s.nodes.map(\.id))")
        guard case .image(let image) = s.nodes[0].kind else { Issue.record("image"); return }
        #expect(image.path == "cups/cup.png" && image.dark == "cups/cup-night.webp" && image.fit == .cover && image.tint == .token(.accent))
        #expect(s.nodes[0].y == 4000, "a place is clamped")
        guard case .text(let text) = s.nodes[1].kind else { Issue.record("text"); return }
        #expect(text.size == 160 && !text.text.contains("\u{202E}"), "sizes are capped, hidden direction marks cleaned")
        #expect(text.color == .rgba(0x112233FF))
        guard case .shape(let shape) = s.nodes[2].kind, case .path(let ops) = shape.form else { Issue.record("shape"); return }
        #expect(ops.count == 5 && shape.fill == .adaptive(light: 0x0000_00FF, dark: 0xFFFF_FFFF))
        #expect(s.nodes[4].kind == .companion(pose: .thinking, look: SceneFigureLook()) && s.nodes[5].kind == .person(look: SceneFigureLook()))
        guard case .entry(let entry) = s.nodes[7].kind else { Issue.record("entry"); return }
        #expect(entry.max == 120 && s.entries.map(\.id) == ["word"])
    }

    @Test func aPictureOutsideThePackIsNoPicture() throws {
        for bad in ["/etc/passwd", "../secret.png", "a/../../b.png", "https://x.example/a.png", "file:///a.png", ".hidden.png", "a//b.png", "cup.svg", "cup.gif", "cup.pdf", "c\\d.png"] {
            let s = try scene([["type": "image", "id": "a", "image": .string(bad), "w": 10, "h": 10]])
            #expect(s.nodes.isEmpty, "\(bad)")
            #expect(s.notes.count == 1)
        }
        let reader = PackAssetReader(root: "/nowhere", prefix: "assets", pins: ["assets/in.png": "x"])
        let s = try SurfaceScene.parse(["nodes": [["type": "image", "image": "in.png"], ["type": "image", "image": "notpinned.png"]]], assets: reader)
        #expect(s.nodes.count == 1, "only what was installed")
    }

    @Test func nodeAndResourceLimitsRefuseTheScene() throws {
        func rects(_ n: Int) -> [JSONValue] { (0..<n).map { _ in ["type": "shape", "w": 1, "h": 1] } }
        #expect(throws: UserFacingError.self) { try scene(rects(70000), [:]) }

        var deep: JSONValue = ["type": "group"]
        for _ in 0..<(SurfaceScene.maxDepth + 1) { deep = ["type": "group", "children": [deep]] }
        #expect(throws: UserFacingError.self) { try scene([deep]) }

        // Many nodes under 64 KB, by way of a style.
        let many = (0..<(SurfaceScene.maxNodes + 1)).map { _ in JSONValue.object(["style": "s"]) }
        #expect(throws: UserFacingError.self) { try SurfaceScene.parse(["nodes": .array(many), "styles": ["s": ["type": "group"]]]) }

        let pictures = (0..<(SurfaceScene.maxAssets + 1)).map { JSONValue.object(["type": "image", "image": .string("a\($0).png")]) }
        #expect(throws: UserFacingError.self) { try scene(pictures) }

        let people = (0..<(SurfaceScene.maxPeople + 1)).map { _ in JSONValue.object(["type": "companion"]) }
        #expect(throws: UserFacingError.self) { try scene(people) }

        let timers = (0..<(SurfaceScene.maxTimers + 1)).map { JSONValue.object(["id": .string("t\($0)"), "ms": 1000]) }
        #expect(throws: UserFacingError.self) { try scene([], ["timers": .array(timers)]) }

        let areas = (0..<(SurfaceScene.maxAreas + 1)).map { _ in JSONValue.object(["style": "a"]) }
        #expect(throws: UserFacingError.self) {
            try SurfaceScene.parse(["nodes": .array(areas), "styles": ["a": ["type": "group", "area": ["id": "x", "label": "X"]]]])
        }
        let keys = (0..<(SurfaceScene.maxKeys + 1)).map { _ in JSONValue.object(["key": "a", "id": "k"]) }
        #expect(throws: UserFacingError.self) { try scene([], ["keys": .array(keys)]) }

        let longText = String(repeating: "x", count: 400)
        let words = (0..<80).map { _ in JSONValue.object(["style": "t"]) }
        #expect(throws: UserFacingError.self) {
            try SurfaceScene.parse(["nodes": .array(words), "styles": ["t": ["type": "text", "text": .string(longText)]]])
        }
        #expect(throws: UserFacingError.self) { try parse(["size": [10, 10]]) }
    }

    @Test func theCanvasStaysWithinWhatWasAskedFor() throws {
        let s = try SurfaceScene.parse(["size": [5000, 5000], "nodes": []], within: SceneSize(width: 300, height: 200))
        #expect(s.size == SceneSize(width: 300, height: 200))
        let free = try parse(["size": [5000, 5000], "nodes": []])
        #expect(free.size.width == SurfaceLimits.maxWidth && free.size.height == SurfaceLimits.maxHeight)
    }

    @Test func everyAreaSaysWhatItIsOrIsNoArea() throws {
        let s = try scene([
            ["type": "group", "id": "a", "w": 10, "h": 10, "area": ["id": "ok", "label": "Tile one", "value": "1", "key": "1", "hover": ["scale": 1.1], "press": ["dy": 2],
                                                                     "highlight": ["b"], "timed_from_ms": 300, "sound": "tick.wav", "always": true]],
            ["type": "group", "id": "b", "w": 10, "h": 10, "area": ["id": "mute"]],
            ["type": "group", "id": "c", "w": 10, "h": 10, "area": ["id": "BAD ID", "label": "x"]],
            ["type": "group", "id": "d", "w": 10, "h": 10, "area": ["id": "s", "label": "y", "sound": "../x.wav"]],
        ])
        #expect(s.areas.map(\.id) == ["ok", "s"])
        let a = s.areas[0]
        #expect(a.label == "Tile one" && a.value == "1" && a.hover?.scale == 1.1 && a.press?.dy == 2 && a.highlight == ["b"] && a.timedFrom == 0.3 && a.always && a.sound == "tick.wav")
        #expect(s.areas[1].sound == nil, "a sound outside the pack is no sound")
        #expect(s.keys == [SceneKey(match: .character("1"), id: "ok", area: "ok", value: "1", timedFrom: 0.3, always: true)])
        #expect(s.notes.contains { $0.contains("mute") })
    }

    @Test func aStyleSavesRepeating() throws {
        let s = try parse(["styles": ["cell": ["type": "shape", "fill": "line", "w": 7, "h": 8]], "nodes": [["style": "cell", "x": 3], ["style": "cell", "h": 2], ["style": "none", "type": "group"]]])
        #expect(s.nodes.map(\.height) == [8, 2, 200 * 0 + s.size.height])
        #expect(s.nodes[0].x == 3 && s.nodes[1].width == 7)
    }

    @Test func helpersPlaceTheirChildren() throws {
        let s = try scene([
            ["type": "row", "id": "r", "gap": 4, "items": [["type": "group", "w": 10, "h": 20], ["type": "group", "w": 30, "h": 10]]],
            ["type": "column", "id": "c", "gap": 2, "align": "end", "w": 50, "items": [["type": "group", "w": 10, "h": 5], ["type": "group", "w": 20, "h": 5]]],
            ["type": "grid", "id": "g", "columns": 2, "cell": [10, 20], "gap": [1, 2], "items": [["type": "group"], ["type": "group"], ["type": "group", "x": 3]]],
        ])
        let (r, c, g) = (s.nodes[0], s.nodes[1], s.nodes[2])
        #expect(r.width == 44 && r.height == 20 && r.children.map(\.x) == [0, 14] && r.children.map(\.y) == [0, 5])
        #expect(c.height == 12 && c.children.map(\.y) == [0, 7] && c.children.map(\.x) == [40, 30])
        #expect(g.width == 21 && g.height == 42 && g.children.map(\.x) == [0, 11, 3] && g.children.map(\.y) == [0, 0, 22] && g.children[0].width == 10 && g.children[0].height == 20)
    }

    @Test func aKeysetIsCapsAreasAndKeys() throws {
        let s = try scene([[
            "type": "keyset", "id": "k", "name": "kb", "key": [30, 40], "gap": [2, 4], "sound": "tick.wav",
            "rows": [[["key": "a"], ["key": "ب", "fill": "win", "faded": true]], [["key": "↵", "typed": "return", "w": 62, "spoken": "Send"], ["key": "x", "disabled": true]]],
        ]])
        let k = s.nodes[0]
        #expect(k.width == 94 && k.height == 84)
        #expect(k.children.count == 4 && k.children[0].x == 16, "a short row is centred")
        #expect(s.areas.map(\.value) == ["a", "ب", "↵", "x"] && s.areas.allSatisfy { $0.id == "kb" && $0.sound == "tick.wav" })
        #expect(s.areas[2].label == "Send" && s.areas[3].disabled && k.children[1].opacity < 1)
        #expect(s.keys.map(\.match) == [.character("a"), .character("ب"), .named(.return)], "a disabled key isn't taken")
        #expect(s.keys.allSatisfy { $0.area == "kb" })
    }

    // MARK: Time

    func curve(_ s: SurfaceScene, _ target: String, _ p: SceneProperty) -> SceneCurve? {
        s.runs.flatMap(\.curves).first { $0.target == target && $0.property == p }
    }

    let box: JSONValue = ["type": "group", "id": "a", "x": 10, "y": 20, "w": 40, "h": 40]
    let other: JSONValue = ["type": "group", "id": "b", "x": 100, "y": 20, "w": 40, "h": 40]

    @Test func sequencesFollowOneAnotherAndHoldBetween() throws {
        let s = try scene([box], ["animations": [["sequence": [
            ["target": "a", "to": ["x": 50], "ms": 1000, "ease": "linear"],
            ["wait_ms": 500],
            ["sound": "tick.wav"],
            ["target": "a", "to": ["x": 90], "ms": 500],
            ["react": ["move": "hop", "effect": "stars", "look": "you"], "announce": "Done"],
        ]]]])
        let c = try #require(curve(s, "a", .x))
        #expect(c.times == [0, 1, 1.5, 2] && c.values == [10, 50, 50, 90] && c.eases.count == 3)
        let run = s.runs[0]
        #expect(run.duration == 2)
        #expect(run.events.map(\.at) == [1.5, 2] && run.events[0].sound == "tick.wav")
        #expect(run.events[1].react == SceneReaction(move: .cue(.hop), effect: .stars, look: .you) && run.events[1].announce == "Done")
    }

    @Test func staggerSpreadsAndRepeatFlattens() throws {
        let s = try scene([box, other], ["animations": [
            ["stagger": ["targets": ["a", "b"], "step_ms": 200], "to": ["opacity": 0], "ms": 100, "ease": "linear"],
            ["target": "b", "to": ["rotate": 90], "ms": 100, "repeat": 2, "autoreverse": true],
        ]])
        #expect(curve(s, "a", .opacity)?.times == [0, 0.1])
        #expect(curve(s, "b", .opacity)?.times.map { ($0 * 1000).rounded() } == [0, 200, 300])
        let r = try #require(curve(s, "b", .rotate))
        #expect(r.values == [0, 90, 0, 90, 0], "\(r.values)")
        #expect(r.times.last == 0.4)
    }

    @Test func aPathStartsAtItsFirstKeyHoweverItStarts() throws {
        let s = try scene([box, other], ["animations": [
            ["target": "a", "keys": [["t": 0, "scale": 0.5], ["t": 1, "scale": 1]], "ms": 100, "ease": "linear"],
            ["target": "b", "keys": [["t": 0, "opacity": 0], ["t": 1, "opacity": 1]], "ms": 100, "delay_ms": 200, "ease": "linear"],
        ]])
        // From the first frame: not from where the node rests, which is where it ends.
        let a = try #require(curve(s, "a", .scale))
        #expect(a.values == [1, 0.5, 1] && a.times[1] < 0.001 && a.times.last == 0.1)
        // A delayed step rests until its moment, then starts where it says.
        let b = try #require(curve(s, "b", .opacity))
        #expect(b.values == [1, 1, 0, 1] && b.times[1] == 0.2 && b.times[2] < 0.201 && b.eases[2 - 1] == .step)
        // Keys at the same moment never run backwards.
        let same = try scene([box], ["animations": [["target": "a", "keys": [["t": 0, "scale": 0.5], ["t": 0, "scale": 0.5], ["t": 1, "scale": 1]], "ms": 100]]])
        let times = try #require(curve(same, "a", .scale)).times
        #expect(times == times.sorted())
    }

    @Test func whatSendsAFieldIsDimWhileThereIsNothingToSend() throws {
        let s = try scene([["type": "group", "id": "send", "w": 40, "h": 40, "opacity": 0.8, "area": ["id": "send", "label": "Send", "submits": "word"]]])
        let node = try #require(s.node("send"))
        #expect(SurfacePolicy.submitOpacity(node, typed: "") == 0.4 && SurfacePolicy.submitOpacity(node, typed: "  ") == 0.4)
        #expect(SurfacePolicy.submitOpacity(node, typed: "a") == 0.8)
    }

    @Test func nothingRunsForEver() throws {
        // A repeat is capped, and the whole timeline, so a surface always comes to rest.
        let s = try scene([box], ["animations": [["target": "a", "to": ["x": 5], "ms": 100, "repeat": 100000]]])
        #expect(s.runs[0].duration == 100 * 0.001 * Double(SurfaceScene.maxRepeats))
        #expect(throws: UserFacingError.self) {
            try scene([box], ["animations": [["target": "a", "to": ["x": 5], "ms": 60000, "repeat": 40]]])
        }
        #expect(throws: UserFacingError.self) {
            let steps: [JSONValue] = (0..<40).map { _ in ["target": "a", "to": ["x": 5], "ms": 10000] }
            return try scene([box], ["animations": [["sequence": .array(steps)]]])
        }
    }

    @Test func aNamedRunKeepsItsOwnPathAndAnUnnamedOneJoinsTheScene() throws {
        let s = try scene([box, other], ["animations": [
            ["id": "shuffle", "target": "a", "to": ["x": 1], "ms": 100],
            ["target": "b", "to": ["x": 2], "ms": 100],
            ["target": "missing", "to": ["x": 2], "ms": 100],
        ]])
        #expect(s.runs.map(\.id) == [nil, "shuffle"])
        #expect(s.runs[0].curves.map(\.target) == ["b"], "an animation naming no node does nothing")
    }

    @Test func whatMustPlayHoldsMovesAndTheRestDoesNotUnderReduceMotion() throws {
        let s = try scene([box], ["animations": [
            ["target": "a", "to": ["x": 1], "ms": 1000, "blocks_input": true],
            ["id": "shuffle", "target": "a", "to": ["y": 1], "ms": 2000, "blocks_input": true, "essential": true],
        ], "input_after_ms": 500])
        #expect(s.inputOpens(reduceMotion: false) == 2)
        #expect(s.inputOpens(reduceMotion: true) == 2, "an essential shuffle still plays")
        let t = try scene([box], ["animations": [["target": "a", "to": ["x": 1], "ms": 1000, "blocks_input": true]], "input_after_ms": 500])
        #expect(t.inputOpens(reduceMotion: false) == 1)
        #expect(t.inputOpens(reduceMotion: true) == 0.5, "with Reduce Motion the end shows at once, so nothing waits for it")
        #expect(s.runs.flatMap(\.curves).first { $0.property == .y }?.essential == true)
        #expect(s.runs.flatMap(\.curves).first { $0.property == .x }?.essential == false)
    }

    @Test func theModelHoldsTheEnd() throws {
        let s = try scene([box, ["type": "image", "id": "die", "image": "d1.png", "w": 9, "h": 9]], ["animations": [
            ["sequence": [["target": "a", "to": ["x": 50, "scale": 2], "ms": 100], ["target": "a", "to": ["x": 70, "opacity": 0], "ms": 100]]],
            ["target": "die", "frames": ["d3.png", "d6.png"], "frame_ms": 70],
        ]])
        let end = s.settled()
        let a = try #require(end.node("a"))
        #expect(a.x == 70 && a.y == 20 && a.scaleX == 2 && a.opacity == 0)
        if case .image(let i)? = end.node("die")?.kind { #expect(i.path == "d6.png") } else { Issue.record("die") }
    }

    @Test func aFlipLandsOnTheFaceItSays() throws {
        let s = try scene([["type": "flip", "id": "coin", "w": 40, "h": 40, "front": ["type": "image", "image": "h.png"], "back": ["type": "image", "image": "t.png"], "showing": "front"]],
                          ["animations": [["target": "coin", "to": ["flip": 11], "ms": 1000]]])
        #expect(s.node("coin")?.children.count == 2)
        let c = try #require(curve(s, "coin", .flip))
        let keys = SceneFlipKeys(c)
        #expect(keys.times.count == keys.squash.count && keys.times.count > 40)
        #expect(keys.faceTimes.last?.back == true, "eleven half turns land on the back")
        #expect(keys.squash.last! > 0.9)
        #expect(keys.faceTimes.count == 12, "the face changes once each half turn: \(keys.faceTimes.count)")
        if case .flip(let f)? = s.settled().node("coin")?.kind { #expect(SceneFlipKeys.state(f.turns).back) } else { Issue.record("settled") }
        #expect(SceneFlipKeys.state(0).back == false && SceneFlipKeys.state(2).back == false && SceneFlipKeys.state(1).back)
    }

    // MARK: Right to left

    @Test func aSceneMaySayTheDirectionOfItsOwnWords() throws {
        let node: JSONValue = .object(["type": .string("shape"), "form": .string("rect"), "w": .number(10), "h": .number(10)])
        func parsed(_ extra: [String: JSONValue]) throws -> SurfaceScene {
            try SurfaceScene.parse(.object(["width": .number(100), "height": .number(100), "nodes": .array([node])].merging(extra) { $1 }))
        }
        #expect(try parsed([:]).rightToLeft == nil, "the app's, unless it says")
        #expect(try parsed(["direction": .string("rtl")]).rightToLeft == true)
        #expect(try parsed(["direction": .string("ltr")]).rightToLeft == false)
        #expect(try parsed(["direction": .string("sideways")]).rightToLeft == nil, "anything else means nothing")
        // The reader takes the keys it knows, so a copy from before this draws such a scene in the app's direction rather than refusing it.
        #expect(try parsed(["a_key_from_later": .string("rtl")]).rightToLeft == nil)
    }

    @Test func mirroringRunsFromTheFarSideExceptWhatStaysLeftToRight() throws {
        let s = try scene([
            ["type": "group", "id": "g", "x": 10, "w": 100, "h": 50, "children": [
                ["type": "text", "id": "t", "text": "Hi", "x": 5, "w": 20, "h": 20, "align": "leading"],
                ["type": "group", "id": "pic", "x": 40, "w": 40, "h": 40, "ltr": true, "children": [["type": "group", "id": "inner", "x": 3, "w": 5, "h": 5]]],
            ]],
            ["type": "shape", "id": "s", "shape": "path", "path": "M0 0 L10 0", "x": 0, "w": 10, "h": 10, "rotate": 30],
        ], ["animations": [["target": "s", "to": ["x": 100, "rotate": 90], "ms": 100]]])
        let m = s.mirrored()
        #expect(m.node("g")?.x == 190)
        #expect(m.node("t")?.x == 75)
        if case .text(let t)? = m.node("t")?.kind { #expect(t.align == .trailing) } else { Issue.record("text") }
        #expect(m.node("pic")?.x == 20)
        #expect(m.node("inner")?.x == 3, "under a left-to-right node nothing moves")
        #expect(m.isMirrored("t") && !m.isMirrored("inner"))
        if case .shape(let shape)? = m.node("s")?.kind, case .path(let ops) = shape.form {
            #expect(ops == [.move(10, 0), .line(0, 0)])
        } else { Issue.record("shape") }
        #expect(m.node("s")?.rotate == -30)
        let c = try #require(m.runs.flatMap(\.curves).first { $0.property == .x })
        #expect(c.values == [290, 190], "an animation mirrors with its node")
        #expect(m.runs.flatMap(\.curves).first { $0.property == .rotate }?.values == [-30, -90])

        let fixed = try scene([["type": "group", "id": "g", "x": 10, "w": 100, "h": 50]], ["mirror": false])
        #expect(fixed.mirrored().node("g")?.x == 10)
    }

    @Test func colorsAreNamedOrPlain() throws {
        #expect(SceneReader.color("accent") == .token(.accent))
        #expect(SceneReader.color("win") == .token(.win))
        #expect(SceneReader.color("#ABCDEF") == .rgba(0xABCDEFFF))
        #expect(SceneReader.color("#ABCDEF80") == .rgba(0xABCDEF80))
        #expect(SceneReader.color("danger") == nil, "the danger red has no name here (D78)")
        #expect(SceneReader.color("url(x)") == nil)
        #expect(SceneReader.color(["light": "#000000", "dark": "nope"]) == nil)
    }

    @Test func aPathIsOnlyItsSmallLanguage() {
        #expect(SceneReader.path("M0 0 L1 1 Z")?.count == 3)
        #expect(SceneReader.path("L1 1") == nil, "starts with a move")
        #expect(SceneReader.path("M0") == nil)
        #expect(SceneReader.path("M99999 0") == nil)
        #expect(SceneReader.path(String(repeating: "L1 1 ", count: 300).replacingOccurrences(of: "^", with: "M0 0 ", options: .regularExpression)) == nil)
    }

    @Test func aReactionHasNoWords() throws {
        let r = try #require(SceneReaction.parse(["move": "cheer", "line": "you_win", "text": "Buy now!", "effect": "nope", "prop": "balloons(3)"]))
        #expect(r == SceneReaction(move: .cue(.cheer), prop: .balloons(3)))
        #expect(SceneReaction.parse(["say": "Hello"]) == nil)
        #expect(SceneReaction(move: SceneReaction.Move("flick")).move == .flick)
        #expect(SceneReaction.Move("speak") == nil)
    }
}
