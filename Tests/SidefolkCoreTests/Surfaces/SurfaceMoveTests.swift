import Foundation
import Testing
@testable import SidefolkCore

/// An extension hears only what its scene offered (D99).
struct SurfaceMoveTests {
    let scene = try! SurfaceScene.parse([
        "size": [300, 200],
        "nodes": [
            ["type": "group", "id": "a", "w": 10, "h": 10, "area": ["id": "pick", "value": "1", "label": "One"]],
            ["type": "group", "id": "b", "w": 10, "h": 10, "area": ["id": "pick", "value": "2", "label": "Two", "disabled": true]],
            ["type": "group", "id": "c", "w": 10, "h": 10, "area": ["id": "paw", "label": "Paw", "always": true]],
            ["type": "group", "id": "d", "w": 10, "h": 10, "area": ["id": "field", "label": "Field", "drag": ["mode": "grid", "rows": 3, "columns": 4]]],
            ["type": "group", "id": "e", "w": 10, "h": 10, "area": ["id": "pin", "label": "Pin", "drag": ["mode": "free"]]],
            ["type": "entry", "id": "f", "name": "word", "max": 5, "w": 10, "h": 10],
            ["type": "entry", "id": "g", "name": "closed", "locked": true, "w": 10, "h": 10],
        ],
        "keys": [["key": "h", "id": "hint"], ["key": "letter", "id": "type"], ["key": "digit", "id": "num"], ["key": "space", "id": "go", "always": true]],
        "timers": [["id": "t", "ms": 1000]],
        "after_ms": 200,
        "back": true,
    ])

    @Test func onlyWhatWasOfferedIsOffered() {
        #expect(SurfaceMove.click(area: "pick", value: "1", ms: nil).offered(by: scene))
        #expect(!SurfaceMove.click(area: "pick", value: "2", ms: nil).offered(by: scene), "disabled")
        #expect(!SurfaceMove.click(area: "pick", value: "3", ms: nil).offered(by: scene), "no such value")
        #expect(!SurfaceMove.click(area: "pick", value: nil, ms: nil).offered(by: scene))
        #expect(!SurfaceMove.click(area: "other", value: nil, ms: nil).offered(by: scene))

        #expect(SurfaceMove.dragGrid(area: "field", value: nil, fromRow: 0, fromColumn: 0, toRow: 2, toColumn: 3).offered(by: scene))
        #expect(!SurfaceMove.dragGrid(area: "field", value: nil, fromRow: 0, fromColumn: 0, toRow: 3, toColumn: 3).offered(by: scene), "off the grid")
        #expect(!SurfaceMove.dragGrid(area: "pin", value: nil, fromRow: 0, fromColumn: 0, toRow: 1, toColumn: 1).offered(by: scene), "a free drag isn't cells")
        #expect(SurfaceMove.dragFree(area: "pin", value: nil, fromX: 1, fromY: 1, toX: 299, toY: 199).offered(by: scene))
        #expect(!SurfaceMove.dragFree(area: "pin", value: nil, fromX: 1, fromY: 1, toX: 900, toY: 199).offered(by: scene), "off the canvas")
        #expect(!SurfaceMove.dragFree(area: "field", value: nil, fromX: 1, fromY: 1, toX: 2, toY: 2).offered(by: scene))
        #expect(!SurfaceMove.dragFree(area: "pin", value: nil, fromX: .nan, fromY: 1, toX: 2, toY: 2).offered(by: scene))

        #expect(SurfaceMove.key(id: "hint", character: "h", ms: nil).offered(by: scene))
        #expect(!SurfaceMove.key(id: "hint", character: "x", ms: nil).offered(by: scene))
        #expect(SurfaceMove.key(id: "type", character: "ب", ms: nil).offered(by: scene))
        #expect(!SurfaceMove.key(id: "type", character: "1", ms: nil).offered(by: scene))
        #expect(SurfaceMove.key(id: "num", character: "7", ms: nil).offered(by: scene))
        #expect(!SurfaceMove.key(id: "nope", character: nil, ms: nil).offered(by: scene))

        #expect(SurfaceMove.entry(id: "word", text: "hello").offered(by: scene))
        #expect(!SurfaceMove.entry(id: "word", text: "too long").offered(by: scene))
        #expect(!SurfaceMove.entry(id: "word", text: "").offered(by: scene))
        #expect(!SurfaceMove.entry(id: "closed", text: "x").offered(by: scene))
        #expect(!SurfaceMove.entry(id: "other", text: "x").offered(by: scene))

        #expect(SurfaceMove.timer("t").offered(by: scene) && !SurfaceMove.timer("u").offered(by: scene))
        #expect(SurfaceMove.next.offered(by: scene) && SurfaceMove.back.offered(by: scene))
        let bare = SurfaceScene(size: SceneSize(width: 1, height: 1))
        #expect(!SurfaceMove.next.offered(by: bare) && !SurfaceMove.back.offered(by: bare))
    }

    @Test func whileAnAnimationHoldsMovesOnlyWhatSaysAlwaysGoesThrough() {
        #expect(!SurfaceMove.click(area: "pick", value: "1", ms: nil).offered(by: scene, inputOpen: false))
        #expect(SurfaceMove.click(area: "paw", value: nil, ms: nil).offered(by: scene, inputOpen: false))
        #expect(!SurfaceMove.key(id: "hint", character: "h", ms: nil).offered(by: scene, inputOpen: false))
        #expect(SurfaceMove.key(id: "go", character: nil, ms: nil).offered(by: scene, inputOpen: false))
        #expect(!SurfaceMove.dragGrid(area: "field", value: nil, fromRow: 0, fromColumn: 0, toRow: 1, toColumn: 1).offered(by: scene, inputOpen: false))
        #expect(SurfaceMove.timer("t").offered(by: scene, inputOpen: false), "a clock isn't the person")
    }

    @Test func movesAreSmallAndSayNothingElse() {
        #expect(SurfaceMove.click(area: "pick", value: "1", ms: nil).json == ["click": ["area": "pick", "value": "1"]])
        #expect(SurfaceMove.click(area: "go", value: nil, ms: -120).json == ["click": ["area": "go", "ms": -120]])
        #expect(SurfaceMove.dragGrid(area: "f", value: nil, fromRow: 1, fromColumn: 2, toRow: 3, toColumn: 4).json
                == ["drag": ["area": "f", "mode": "cells", "from": [1, 2], "to": [3, 4]]])
        #expect(SurfaceMove.dragFree(area: "p", value: nil, fromX: 1.4, fromY: 2, toX: 3, toY: 4.6).json
                == ["drag": ["area": "p", "mode": "points", "from": [1, 2], "to": [3, 5]]])
        #expect(SurfaceMove.key(id: "k", character: "a", ms: 5).json == ["key": ["id": "k", "char": "a", "ms": 5]])
        #expect(SurfaceMove.entry(id: "w", text: "x").json == ["entry": ["id": "w", "text": "x"]])
        #expect(SurfaceMove.timer("t").json == ["timer": "t"] && SurfaceMove.next.json == ["next": true] && SurfaceMove.back.json == ["back": true])
        #expect(SurfaceMove.typed(" a\u{202E}b ") == "ab" && SurfaceMove.typed("  ") == nil && SurfaceMove.typed("a\nb") == nil)
    }
}

/// The rules that keep a surface in its place and the person in charge (D75's focus rules, T40).
struct SurfacePolicyTests {
    let info = SurfaceInfo(extensionId: "dev.x.y", extensionName: "Y", surface: "s", title: "S")
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let anchor = CGRect(x: 1200, y: 40, width: 160, height: 160)

    @Test func theKeyboardIsTakenOnlyWhenThePersonOpenedIt() {
        #expect(SurfaceRequest(info: info, focus: true).takesKeyboard)
        #expect(!SurfaceRequest(info: info, focus: false).takesKeyboard, "the AI's waits for a click")
        var overlay = info
        overlay.presentation = .overlay
        #expect(!SurfaceRequest(info: overlay, focus: true).takesKeyboard, "an overlay never does")
    }

    @Test func aSurfaceStandsBesideTheCompanionInsideTheScreenAndClearOfCards() {
        let size = CGSize(width: 400, height: 500)
        let beside = SurfacePolicy.place(size: size, presentation: .panel, beside: anchor, screen: screen, avoiding: [])
        #expect(screen.contains(beside) && !beside.intersects(anchor) && beside.maxX <= anchor.minX)

        let card = CGRect(x: 780, y: 60, width: 420, height: 300)
        let clear = SurfacePolicy.place(size: size, presentation: .panel, beside: anchor, screen: screen, avoiding: [card])
        #expect(!clear.intersects(card) && screen.contains(clear), "\(clear)")

        let above = SurfacePolicy.place(size: CGSize(width: 200, height: 240), presentation: .overlay, beside: anchor, screen: screen, avoiding: [])
        #expect(above.minY >= anchor.maxY && abs(above.midX - anchor.midX) <= 1)
        #expect(screen.contains(above))
    }

    @Test func aSmallScreenScalesTheCanvasDownNeverUp() {
        let small = CGRect(x: 0, y: 0, width: 900, height: 500)
        let fit = SurfacePolicy.fit(canvas: CGSize(width: 720, height: 676), presentation: .panel, screen: small)
        #expect(fit.scale < 1 && fit.size.height + SurfacePolicy.headerHeight <= 500 - 16 + 1)
        #expect(SurfacePolicy.fit(canvas: CGSize(width: 300, height: 200), presentation: .panel, screen: screen).scale == 1)
    }

    @Test func commandKeysAndClosingAreNeverTheExtensions() throws {
        let plain = SurfaceScene(size: SceneSize(width: 1, height: 1))
        let takesEscape = try SurfaceScene.parse(["nodes": [], "keys": [["key": "escape", "id": "letgo"], ["key": "w", "id": "w"]], "back": true])
        let now = Date()
        #expect(SurfacePolicy.route("escape", command: false, scene: plain, lastEscape: nil, now: now) == .close)
        #expect(SurfacePolicy.route("escape", command: false, scene: takesEscape, lastEscape: nil, now: now) == .scene)
        #expect(SurfacePolicy.route("escape", command: false, scene: takesEscape, lastEscape: now.addingTimeInterval(-0.5), now: now) == .close, "twice always closes")
        #expect(SurfacePolicy.route("escape", command: false, scene: takesEscape, lastEscape: now.addingTimeInterval(-5), now: now) == .scene)
        #expect(SurfacePolicy.route("w", command: true, scene: takesEscape, lastEscape: nil, now: now) == .close)
        #expect(SurfacePolicy.route("q", command: true, scene: takesEscape, lastEscape: nil, now: now) == .system)
        #expect(SurfacePolicy.route("[", command: true, scene: takesEscape, lastEscape: nil, now: now) == .back)
        #expect(SurfacePolicy.route("[", command: true, scene: plain, lastEscape: nil, now: now) == .system)
        #expect(SurfacePolicy.route("a", command: false, scene: plain, lastEscape: nil, now: now) == .scene)
        #expect(!SurfacePolicy.takesInput(approvalWaiting: true) && SurfacePolicy.takesInput(approvalWaiting: false))
    }

    @Test func aKeyFindsTheExactOneBeforeAClass() throws {
        let scene = try SurfaceScene.parse(["nodes": [], "keys": [
            ["key": "letter", "id": "any"], ["key": "digit", "id": "num"], ["key": "h", "id": "hint"], ["key": "return", "id": "go"], ["key": "a", "id": "left", "seat": true],
        ]])
        #expect(SurfacePolicy.match("h", seat: nil, in: scene)?.id == "hint")
        #expect(SurfacePolicy.match("z", seat: nil, in: scene)?.id == "any")
        #expect(SurfacePolicy.match("ب", seat: nil, in: scene)?.id == "any")
        #expect(SurfacePolicy.match("3", seat: nil, in: scene)?.id == "num")
        #expect(SurfacePolicy.match("return", seat: nil, in: scene)?.id == "go")
        #expect(SurfacePolicy.match("space", seat: nil, in: scene) == nil)
        #expect(SurfacePolicy.match("ش", seat: "a", in: scene)?.id == "left", "a seat goes by where the key sits, on any layout")
        #expect(SurfaceMove.key(id: "left", character: "ش", ms: 12).offered(by: scene), "and what that key types on this layout doesn't turn its move away")
        #expect(!SurfaceMove.key(id: "hint", character: "ش", ms: nil).offered(by: scene), "a key by what it types still has to type it")
    }
}
