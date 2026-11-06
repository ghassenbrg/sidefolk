import CoreGraphics
import Foundation
import Testing
@testable import SidefolkCore

@Suite("Page parts: a tree and a workspace (D125, D126)")
struct ExtensionPageTreeTests {
    private func page(_ blocks: [JSONValue], extra: [String: JSONValue] = [:]) throws -> ExtensionPage {
        var object: [String: JSONValue] = ["sections": .array([.object(["blocks": .array(blocks)])])]
        object.merge(extra) { _, new in new }
        return try ExtensionPage.parse(.object(object))
    }

    private func node(_ id: String, state: String? = nil, branches: [JSONValue] = []) -> JSONValue {
        var o: [String: JSONValue] = ["id": .string(id), "title": .string("Do \(id)")]
        if let state { o["state"] = .string(state) }
        if !branches.isEmpty { o["branches"] = .array(branches) }
        return .object(o)
    }

    private func branch(_ id: String, _ nodes: [JSONValue], taken: Bool? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["id": .string(id), "label": .string(id), "nodes": .array(nodes)]
        if let taken { o["taken"] = .bool(taken) }
        return .object(o)
    }

    private func tree(_ nodes: [JSONValue], extra: [String: JSONValue] = [:]) throws -> ExtensionPage.Tree {
        var o: [String: JSONValue] = ["type": .string("tree"), "nodes": .array(nodes)]
        o.merge(extra) { _, new in new }
        guard case .tree(let tree)? = try page([.object(o)]).sections.first?.blocks.first else { throw TreeTestFailure.notATree }
        return tree
    }

    private enum TreeTestFailure: Error { case notATree }

    private func placed(_ id: String, x: Double, y: Double, branches: [JSONValue] = []) -> JSONValue {
        var o = node(id, branches: branches).objectValue ?? [:]
        o["at"] = ["x": .number(x), "y": .number(y)]
        return .object(o)
    }

    @Test func aPlaceIsPlainNumbersWithinReach() throws {
        var far = node("far").objectValue ?? [:]
        far["at"] = ["x": 1e9, "y": -5]
        var words = node("words").objectValue ?? [:]
        words["at"] = ["x": "10", "y": 4]
        let t = try tree([.object(far), .object(words), node("none")], extra: ["placed": ["tool": "ui", "key": "spot"]])
        #expect(t.reading.map(\.at) == [CGPoint(x: 4_000, y: -5), nil, nil], "clamped to ±4,000; anything not a number leaves it laid out")
        #expect(t.placed?.key == "spot")
    }

    @Test func aPlacedCardStandsThereAndTheOrderStays() throws {
        let t = try tree([node("a"), node("b"), placed("c", x: 900, y: 40)], extra: ["placed": ["tool": "ui", "key": "spot"]])
        let board = TreeLayout(t, editable: true, free: true)
        #expect(board.placed && !board.nudged)
        #expect(board.cards.map(\.node.id) == ["a", "b", "c"], "read, and heard by VoiceOver, in the tree's order wherever it stands")
        let c = try #require(board.cards.first { $0.node.id == "c" }).frame
        #expect(c.origin == CGPoint(x: 900 + board.origin.x, y: 40 + board.origin.y))
        let b = try #require(board.cards.first { $0.node.id == "b" }).frame
        #expect(board.lines.contains { $0.points.first == CGPoint(x: b.midX, y: b.maxY) && $0.points.last == CGPoint(x: c.midX, y: c.minY) }, "the line still runs from b to c")
        #expect(!TreeLayout(t, editable: true).placed, "a card's small drawing lays itself out")
    }

    @Test func noPlacedCardCoversAnother() throws {
        // c put right on top of a, and d on top of where c then lands.
        let first = TreeLayout(try tree([node("a"), node("b")]), editable: true).cards[0].frame
        let t = try tree([node("a"), node("b"), placed("c", x: first.minX, y: first.minY), placed("d", x: first.minX + 20, y: first.minY + 10)],
                         extra: ["placed": ["tool": "ui", "key": "spot"]])
        let board = TreeLayout(t, editable: true, free: true)
        #expect(board.nudged, "the board says it moved them")
        let frames = board.cards.map(\.frame)
        for (i, one) in frames.enumerated() {
            for other in frames[(i + 1)...] { #expect(!one.insetBy(dx: -8, dy: -8).intersects(other), "\(one) and \(other)") }
        }
    }

    @Test func everyCardIsOnTheBoardWhereverItWasPut() throws {
        let t = try tree([node("a"), placed("b", x: -10_000, y: -10_000), placed("c", x: 10_000, y: 10_000)], extra: ["placed": ["tool": "ui", "key": "spot"]])
        let board = TreeLayout(t, editable: true, free: true)
        for card in board.cards {
            #expect(card.frame.minX >= 0 && card.frame.minY >= 0 && card.frame.maxX <= board.size.width && card.frame.maxY <= board.size.height)
        }
        #expect(board.size.width < 9_000 && board.size.height < 9_000, "bounded by how far a card may be put")
    }

    @Test func aHundredAndTwentyEightCardsOnOneSpotStayBoundedAndApart() throws {
        let t = try tree((0..<128).map { placed("n\($0)", x: 0, y: 0) }, extra: ["placed": ["tool": "ui", "key": "spot"]])
        let board = TreeLayout(t, editable: true, free: true)
        #expect(board.cards.count == 128 && board.nudged)
        #expect(board.size.width < 12_000 && board.size.height < 12_000, "\(board.size): the next column, not an ever taller one")
        let frames = board.cards.map(\.frame)
        for (i, one) in frames.enumerated() { for other in frames[(i + 1)...] { #expect(!one.intersects(other)) } }
    }

    @Test func aCardIsNotPutWhereTheSpotAboveItCoversAFoldButton() throws {
        // c right under a, as close as a card's own frame allows: the + spot over c would sit on a's fold button.
        let auto = TreeLayout(try tree([node("a", branches: [branch("then:a", [node("x")])]), node("b")]), editable: true)
        let a = try #require(auto.cards.first { $0.node.id == "a" }).frame
        let t = try tree([node("a", branches: [branch("then:a", [node("x")])]), node("b"), placed("c", x: a.minX, y: a.maxY + 28)],
                         extra: ["placed": ["tool": "ui", "key": "spot"]])
        let board = TreeLayout(t, editable: true, free: true)
        let placedA = try #require(board.cards.first { $0.node.id == "a" }).frame
        let c = try #require(board.cards.first { $0.node.id == "c" }).frame
        #expect(board.nudged)
        let fold = CGRect(x: placedA.midX - 30, y: placedA.maxY - 9, width: 60, height: 18)
        for spot in board.adds { #expect(!CGRect(x: spot.point.x - 18, y: spot.point.y - 18, width: 36, height: 36).intersects(fold) || spot.target == "a", "\(spot.target)") }
        #expect(!c.intersects(placedA.insetBy(dx: -12, dy: -12)))
    }

    @Test func aDropIsKeptTheSameWayWhicheverWayTheBoardReads() throws {
        let t = try tree([node("a"), placed("b", x: 600, y: 300)], extra: ["placed": ["tool": "ui", "key": "spot"]])
        let board = TreeLayout(t, editable: true, free: true)
        let left = board.corner(forDropAt: CGPoint(x: 700, y: 400), of: "b", rightToLeft: false)
        let mirrored = board.corner(forDropAt: CGPoint(x: board.size.width - 700, y: 400), of: "b", rightToLeft: true)
        #expect(left != nil && left == mirrored, "right to left the board is drawn mirrored, so the same place is the mirrored point")
        #expect(board.corner(forDropAt: CGPoint(x: 1e7, y: -1e7), of: "b", rightToLeft: false) == CGPoint(x: 4_000, y: -4_000), "kept within reach")
    }

    @Test func onlyTheCardThisBoardPickedUpLands() throws {
        let t = try tree([node("a"), node("b"), node("c")], extra: ["reorder": ["tool": "ui", "key": "move"]])
        let picked = ExtensionPage.Tree.Carry(id: "b", on: t)
        let words = [ExtensionPage.Tree.dragPrefix + "b"]
        #expect(t.dropped(words, carried: picked) == "b")
        #expect(t.dropped(words, carried: nil) == nil, "the same words from another app or window, with nothing picked up here")
        #expect(t.dropped([ExtensionPage.Tree.dragPrefix + "c"], carried: picked) == nil, "words naming another card than the one carried")
        #expect(t.dropped(["b"], carried: picked) == nil)
        let changed = try tree([node("a"), node("b"), node("x"), node("c")], extra: ["reorder": ["tool": "ui", "key": "move"]])
        #expect(changed.dropped(words, carried: picked) == nil, "a tree whose cards changed while it was carried")
        let other = try tree([node("b"), node("z")], extra: ["reorder": ["tool": "ui", "key": "move"]])
        #expect(other.dropped(words, carried: picked) == nil, "another tree with a card of the same id")
    }

    @Test func everySpotACardCanGoToIsListedWithoutTheOnesItCant() throws {
        var start = node("start").objectValue ?? [:]
        start["fixed"] = true
        let t = try tree([.object(start), node("a"), node("b", branches: [branch("then:b", [node("c")]), branch("else:b", [])]), node("e")], extra: ["reorder": ["tool": "ui", "key": "move"]])
        let forE = t.spots(for: "e").map(\.id)
        #expect(forE == ["start", "a", "then:b", "c", "else:b"], "not b: it's already right after it")
        let forB = t.spots(for: "b").map(\.id)
        #expect(!forB.contains("then:b") && !forB.contains("c") && !forB.contains("else:b"), "never inside itself")
        #expect(t.spots(for: "start").isEmpty)
        #expect(t.neighbour(of: "a", by: 1) == "b")
        #expect(t.neighbour(of: "b", by: 1) == "c", "as it's read, into the branch")
        #expect(t.neighbour(of: "start", by: -1) == nil)
        #expect(t.neighbour(of: nil, by: 1) == "start")
    }

    @Test func foldingHidesWhatHangsFromACardAndSaysHowMuch() throws {
        let t = try tree([node("a"), node("b", branches: [branch("y", [node("c"), node("d", branches: [branch("z", [node("e")])])]), branch("n", [node("f")])]), node("g")])
        let shown = t.folding(["b"])
        #expect(shown.reading.map(\.id) == ["a", "b", "g"])
        #expect(shown.reading[1].folded == 4)
        #expect(t.folding(["d"]).reading.map(\.id) == ["a", "b", "c", "d", "f", "g"], "deep inside too")
        #expect(t.folding([]) == t)
        #expect(t.folding(["a"]) == t, "a card with nothing inside has nothing to fold")
    }

    @Test func findingGoesByWhatACardSays() throws {
        let t = try tree([node("a"), node("b")])
        #expect(t.matching("do B") == ["b"])
        #expect(t.matching("do") == ["a", "b"])
        #expect(t.matching("  ").isEmpty)
    }

    @Test func aPageTakesOnlyTheKeysOnTheList() throws {
        let page = try page([.object(["type": "note", "text": "x"])], extra: ["shortcuts": [
            ["key": "cmd+s", "label": "Save", "tool": "ui", "input": ["op": "save"]],
            ["key": "cmd+q", "label": "Quit it", "tool": "ui"],
            ["key": "cmd+w", "label": "Close it", "tool": "ui"],
            ["key": "cmd+z", "label": "Undo", "tool": "not a tool name!"],
            ["key": "cmd+d", "tool": "ui"],
        ]])
        #expect(page.shortcuts.map(\.key) == [.save])
        #expect(page.shortcuts.first?.label == "Save")
        #expect(ExtensionPage.Shortcut.Key.undo.belongsToText)
        #expect(!ExtensionPage.Shortcut.Key.save.belongsToText)
    }

    @Test func whatSetsItOffStaysAndTheRestMove() throws {
        var start = node("start").objectValue ?? [:]
        start["fixed"] = true
        let hook: JSONValue = ["tool": "ui", "key": "move"]
        let t = try tree([.object(start), node("a"), node("b", branches: [branch("then:b", [node("c"), node("d")]), branch("else:b", [])]), node("e")], extra: ["reorder": hook, "remove": ["tool": "ui", "key": "step"]])
        #expect(t.remove?.key == "step")
        #expect(t.reading.first?.fixed == true)
        #expect(t.move("a", by: -1) == nil, "nothing goes above what sets it off")
        #expect(t.move("start", by: 1) == nil, "and it doesn't move")
        #expect(t.move("a", by: 1) == ["id": "a", "before": "e"])
        #expect(t.move("e", by: -1) == ["id": "e", "before": "b"])
        #expect(t.place("start", after: "e") == nil)
        #expect(t.place("e", after: "start") == ["id": "e", "after": "start"], "a drag may go anywhere")
        #expect(t.place("a", after: "then:b") == ["id": "a", "after": "then:b"], "into a branch too")
        #expect(t.place("c", after: "b") == ["id": "c", "after": "b"], "and out of one")
        #expect(t.place("a", after: "start") == nil, "where it is already")
        #expect(t.place("c", after: "then:b") == nil, "the first of its branch already")
        #expect(t.place("b", after: "c") == nil, "not inside itself")
        #expect(t.place("b", after: "else:b") == nil, "nor its own branch")
        #expect(t.place("nothing", after: "a") == nil)
    }

    @Test("A tree reads back in order, and a repeated id or an empty tree is dropped")
    func parsing() throws {
        let t = try tree([node("a"), node("a"), node("b", branches: [branch("yes", [node("c")]), branch("no", [node("d", state: "skipped")], taken: false)])])
        #expect(t.reading.map(\.id) == ["a", "b", "c", "d"])
        #expect(t.nodes[1].branches[1].taken == false)
        #expect(t.nodes[1].branches[1].nodes[0].state == .skipped)
        #expect(try page([.object(["type": .string("tree"), "nodes": .array([])])]).sections.isEmpty)
    }

    @Test("A tree holds 128 cards at most, and hooks name only the extension's own tools")
    func limits() throws {
        let t = try tree((0..<200).map { node("n\($0)") }, extra: ["select": ["tool": "ext.other.tool", "key": "target"], "insert": ["tool": "ui", "key": "target"]])
        #expect(t.nodes.count == 128)
        #expect(t.select == nil)
        #expect(t.insert?.tool == "ui")
    }

    @Test("Cards in a run stand on one line and don't touch, each joined to the next")
    func run() throws {
        let t = try tree([node("a"), node("b"), node("c")])
        let l = TreeLayout(t, editable: false)
        #expect(Set(l.cards.map(\.frame.midX)).count == 1)
        for (above, below) in zip(l.cards, l.cards.dropFirst()) { #expect(above.frame.maxY < below.frame.minY) }
        #expect(l.lines.count == 2)
        #expect(l.adds.isEmpty)
    }

    @Test("Editable, there's a + between cards and after the last, and each names the card before it")
    func adds() throws {
        let l = TreeLayout(try tree([node("a"), node("b")]), editable: true)
        #expect(l.adds.map(\.target) == ["a", "b"])
        #expect(l.size.height > (l.cards.last?.frame.maxY ?? 0))
    }

    @Test("Branches stand side by side, as far either side of their parent, without overlapping, and join again under the longest")
    func branches() throws {
        let t = try tree([node("top", branches: [branch("yes", [node("y1"), node("y2")]), branch("no", [node("n1")])]), node("end")])
        let l = TreeLayout(t, editable: false)
        func frame(_ id: String) throws -> CGRect { try #require(l.cards.first { $0.node.id == id }?.frame) }
        let top = try frame("top"), y1 = try frame("y1"), y2 = try frame("y2"), n1 = try frame("n1"), end = try frame("end")
        #expect(abs((top.midX - y1.midX) - (n1.midX - top.midX)) < 0.5)
        #expect(!y1.intersects(n1))
        #expect(end.midX == top.midX)
        #expect(end.minY > y2.maxY)
        #expect(l.labels.map(\.branch.id) == ["yes", "no"])
    }

    @Test("A branch inside a branch makes room, so nothing overlaps at any depth")
    func nested() throws {
        let inner = node("in", branches: [branch("a", [node("a1")]), branch("b", [node("b1")])])
        let t = try tree([node("top", branches: [branch("yes", [inner]), branch("no", [node("n1")])])])
        let l = TreeLayout(t, editable: true)
        let frames = l.cards.map(\.frame)
        for (i, f) in frames.enumerated() { for g in frames[(i + 1)...] { #expect(!f.intersects(g)) } }
        #expect(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= l.size.width && $0.maxY <= l.size.height })
    }

    @Test("An empty branch still has somewhere to add, under its own name")
    func emptyBranch() throws {
        let l = TreeLayout(try tree([node("top", branches: [branch("yes", []), branch("no", [node("n1")])])]), editable: true)
        #expect(l.adds.contains { $0.target == "yes" && !$0.quiet })
        #expect(l.adds.contains { $0.target == "no" && $0.quiet })
    }

    @Test("The line says what the card says: not done is dashed, a path not taken faded, what's happening live")
    func lineStyles() throws {
        let t = try tree([node("a"), node("b", state: "pending"), node("c", state: "active"), node("d", branches: [branch("no", [node("e", state: "skipped")], taken: false)])])
        let styles = TreeLayout(t, editable: false).lines.map(\.style)
        #expect(styles.prefix(3) == [.dashed, .live, .solid])
        #expect(styles.dropFirst(3).allSatisfy { $0 == .faded })
    }

    @Test("Moving a card says what it now stands before, within its own run only")
    func moving() throws {
        let t = try tree([node("a"), node("b"), node("c", branches: [branch("yes", [node("y1"), node("y2")])])])
        #expect(t.move("b", by: -1) == ["id": "b", "before": "a"])
        #expect(t.move("b", by: 1) == ["id": "b", "before": .null])
        #expect(t.move("a", by: -1) == nil)
        #expect(t.move("y1", by: 1) == ["id": "y1", "before": .null])
        #expect(t.siblings(of: "y2").map(\.id) == ["y1", "y2"])
    }

    @Test("A workspace is only for a bare page; the small parts read back")
    func workspace() throws {
        #expect(try page([], extra: ["workspace": true, "summary": ["title": "x"]]).workspace == false)
        let press: JSONValue = ["label": "Open", "go": ["set": [:]]]
        let p = try page([
            ["type": "bar", "title": "Morning brief", "pill": ["text": "Practiced", "tone": "good"], "detail": "Every weekday",
             "actions": [["label": "A", "tool": "ui", "style": "primary"], ["label": "B", "tool": "ui", "style": "primary"]]],
            ["type": "nav", "brand": true, "items": [["id": "a", "title": "Flows", "selected": true, "press": press]]],
            ["type": "notice", "title": "Your morning", "body": "Three lines", "time": "08:30"],
            ["type": "ticks", "items": [["tone": "good", "label": "Monday, done"], ["tone": "neutral", "label": "Tuesday, missed", "hollow": true]]],
        ], extra: ["bare": true, "workspace": true, "companion": true])
        #expect(p.workspace && p.companion)
        guard case .bar(let bar) = p.sections[0].blocks[0], case .nav(let nav) = p.sections[0].blocks[1], case .notice(let notice) = p.sections[0].blocks[2], case .ticks(let ticks) = p.sections[0].blocks[3] else {
            Issue.record("parts")
            return
        }
        #expect(bar.pill?.text == "Practiced")
        #expect(bar.actions[0].style == .primary && bar.actions[1].style == .secondary, "one primary a page")
        #expect(nav.items.first?.selected == true)
        #expect(notice.time == "08:30")
        #expect(ticks.items[1].hollow)
    }

    @Test("A picker reads back, and one with nothing in it is dropped")
    func picker() throws {
        let p: JSONValue = ["key": "kind", "placeholder": "What next?", "categories": [["id": "all", "label": "All"]],
                            "items": [["id": "tool:notes.save", "title": "Save a note", "meta": "Changes things", "categories": ["all"]]]]
        #expect(try tree([node("a")], extra: ["picker": p]).picker?.items.first?.id == "tool:notes.save")
        #expect(try tree([node("a")], extra: ["picker": ["key": "kind", "items": []]]).picker == nil)
    }

    @Test("Kit's tiny drawing fits a small card")
    func mini() throws {
        let t = try tree([node("a"), node("b", branches: [branch("y", [node("c")]), branch("n", [node("d")])])])
        let l = TreeLayout(t, editable: false, metrics: .mini)
        #expect(l.size.height < 100)
        #expect(l.size.width < 120)
    }
}
