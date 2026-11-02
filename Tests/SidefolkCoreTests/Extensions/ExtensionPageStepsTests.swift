import Foundation
@testable import SidefolkCore
import Testing

/// A rail of things in order, a value edited in place, several of a few options (D113): generic parts, with made-up content that isn't anyone's product.
struct ExtensionPageStepsTests {
    static func blocks(_ text: String) throws -> [ExtensionPage.Block] {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(("{\"sections\": [{\"blocks\": [" + text + "]}]}").utf8))
        return try ExtensionPage.parse(json).sections.first?.blocks ?? []
    }

    static let recipe = """
    {"type": "steps", "title": "Soup", "selected": "stir", "line": ["#5B8DEF", "not a colour", "#0B7783"],
     "select": {"tool": "pick", "input": {"recipe": "soup"}, "key": "step"},
     "reorder": {"tool": "move", "key": "move"},
     "insert": {"tool": "add", "key": "after", "label": "Add a step"},
     "items": [
       {"id": "start", "title": "Heat the pot", "state": "done", "locked": true, "symbol": "flame", "color": "#F2B33D"},
       {"id": "stir", "title": "Stir", "state": "running", "result": "Going", "badge": {"text": "Slow", "tone": "warn"}},
       {"id": "taste", "title": "Taste", "state": "nonsense", "tone": "bad", "output": "Needs salt"},
       {"id": "salt", "title": "Add salt", "depth": 1, "label": "If bland"},
       {"id": "pepper", "title": "Add pepper", "depth": 1},
       {"id": "serve", "title": "Serve", "depth": 7},
       {"id": "start", "title": "A row with an id already used"},
       {"id": "bad id!", "title": "A row with a bad id"},
       {"id": "untitled"}
     ]}
    """

    private func rail() throws -> ExtensionPage.Steps {
        guard case .steps(let steps)? = try Self.blocks(Self.recipe).first else { throw Problem() }
        return steps
    }

    private struct Problem: Error {}

    @Test func whatIsOffIsDroppedAndTheRestKept() throws {
        let steps = try rail()
        #expect(steps.items.map(\.id) == ["start", "stir", "taste", "salt", "pepper", "serve"])
        #expect(steps.line == ["#5B8DEF", "#0B7783"])
        #expect(steps.items[0].locked)
        #expect(steps.items[1].state == .running)
        #expect(steps.items[2].state == .none, "a state it doesn't know is none")
        #expect(steps.items[5].depth == 2, "two levels at most")
        #expect(steps.select?.input(.string("stir")) == ["recipe": "soup", "step": "stir"])
    }

    @Test func aRailWithNothingOnItIsNoRail() throws {
        #expect(try Self.blocks(#"{"type": "steps", "items": []}"#).isEmpty)
    }

    @Test func aHookNamesOnlyAToolOfItsOwn() throws {
        let parts = try Self.blocks(#"{"type": "steps", "select": {"tool": "ext.other.thing", "key": "x"}, "insert": {"tool": "add", "key": "on"}, "items": [{"id": "a", "title": "A"}]}"#)
        guard case .steps(let steps)? = parts.first else { Issue.record("no rail"); return }
        #expect(steps.select == nil)
        #expect(steps.insert == nil, "`on` is a switch's")
    }

    @Test func aRowMovesOnlyAmongItsOwn() throws {
        let steps = try rail()
        #expect(steps.siblings(of: "stir").map(\.id) == ["stir", "taste"], "what starts the rail stays, a branch isn't its own")
        #expect(steps.siblings(of: "salt").map(\.id) == ["salt", "pepper"])
        #expect(steps.move("stir", by: -1) == nil)
        #expect(steps.move("taste", by: -1) == ["id": "taste", "before": "stir"])
        #expect(steps.move("stir", by: 1) == ["id": "stir", "before": .null], "to the end of its own")
        #expect(steps.move("salt", by: 1) == ["id": "salt", "before": .null])
    }

    @Test func aFieldWithAnIdIsEditedInPlaceAndKeepsItsLines() throws {
        let long = String(repeating: "word ", count: 1000)
        let parts = try Self.blocks("""
            {"type": "field", "id": "a.b", "label": "Prompt", "value": "line one\\nline two", "kind": "multiline", "tool": "save", "tokens": [{"label": "Earlier", "value": "{{x}}", "symbol": "sparkles"}, {"label": "Nothing"}]},
            {"type": "field", "id": "long", "label": "Long", "value": "\(long)", "tool": "save"},
            {"type": "field", "label": "As before", "button": "Send", "tool": "save"},
            {"type": "field", "label": "No button, no id", "tool": "save"}
            """)
        #expect(parts.count == 3, "without an id it still needs its button")
        guard case .field(let edit) = parts[0], case .field(let longField) = parts[1], case .field(let plain) = parts[2] else { Issue.record("not fields"); return }
        #expect(edit.value == "line one\nline two")
        #expect(edit.kind == .multiline)
        #expect(edit.tokens.map(\.value) == ["{{x}}"])
        #expect(edit.button.isEmpty)
        #expect(longField.input(typing: long)["text"]?.stringValue?.count ?? 0 > 4000, "a whole prompt fits")
        #expect(plain.id == nil)
        #expect(plain.input(typing: long)["text"]?.stringValue?.count == 500, "a plain field keeps its limit")
    }

    @Test func aFieldThatMovesThePageIsNeverEditedInPlace() throws {
        guard case .field(let live)? = try Self.blocks(#"{"type": "field", "id": "x", "label": "Find", "button": "Clear", "go": {"set": {}}, "live": true, "value": "cat"}"#).first else {
            Issue.record("no field")
            return
        }
        #expect(live.id == nil, "`go` and `live` are their own thing")
        #expect(live.live)
    }

    @Test func severalOfAFewGoAsASetInTheirOrder() throws {
        guard case .choice(let days)? = try Self.blocks(#"{"type": "choice", "multiple": true, "label": "Days", "selected_all": ["fri", "mon", "gone"], "tool": "set", "key": "days", "options": [{"value": "mon", "label": "Mon"}, {"value": "tue", "label": "Tue"}, {"value": "fri", "label": "Fri"}]}"#).first else {
            Issue.record("no choice")
            return
        }
        #expect(days.multiple)
        #expect(days.selectedAll == ["fri", "mon"])
        #expect(days.input(pickingAll: ["fri", "mon"])["days"] == ["mon", "fri"])
    }

    @Test func aRailTakesAColumnBesideItsNeighbours() throws {
        let section = ExtensionPage.Section(blocks: try Self.blocks(Self.recipe))
        #expect(!section.isWide)
    }
}
