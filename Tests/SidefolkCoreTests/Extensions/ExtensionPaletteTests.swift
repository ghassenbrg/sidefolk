import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// What D68 adds for Clipboard to replace Maccy, kept general for any extension: pictures from the extension's own data
/// folder on palettes and pages, the picked item in full, Maccy's keys, choices, fields and lists on pages, and which
/// app a copy came from. A fixture stands in for Clipboard, so the person's clipboard is never read or changed.
struct ExtensionPaletteTests {
    static let fixture = #"""
    import json, sys
    def send(o):
        sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
    told = None
    for line in sys.stdin:
        m = json.loads(line)
        if "id" not in m:
            if m.get("method") == "sidefolk/clipboard.source": told = m.get("params")
            continue
        meth, p = m["method"], m.get("params") or {}
        if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "f", "version": "1"}}
        elif meth == "tools/list": r = {"tools": [{"name": "noop", "description": "Does nothing.", "inputSchema": {"type": "object"}}]}
        elif meth == "sidefolk/palette.query":
            send({"jsonrpc": "2.0", "method": "sidefolk/clipboard.source", "params": {}})
            r = {"items": [{"id": "a", "title": "Picture 800 × 600", "kind": "image", "image": "thumbs/a.png", "section": "History",
                            "actions": ["alternate", "pin"]}],
                 "preview": True, "actions": ["clear", "clear_all", "format_disk"], "note": json.dumps(told)}
        elif meth == "sidefolk/palette.preview":
            r = {"text": "full text of " + p["item"], "image": "images/a.png", "facts": [{"label": "From", "value": "Notes"}]}
        else:
            send({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32601, "message": "nope"}}); continue
        send({"jsonrpc": "2.0", "id": m["id"], "result": r})
    """#

    @Test func paletteItemsCarryPicturesSwatchesAndSections() throws {
        let list = ExtensionPaletteList.parse(try ExtensionPageTests.json("""
            {"items": [{"id": "a", "title": "Shot", "kind": "image", "image": "thumbs/a.png", "section": "Pinned", "actions": ["alternate", "pin", "evil"]},
                       {"id": "b", "title": "Colour", "color": "#2ED4D9"},
                       {"id": "c", "title": "Escapes", "image": "../../secrets/key.png", "color": "red"},
                       {"id": "d", "title": "Absolute", "image": "/etc/a.png"},
                       {"id": "e", "title": "Hidden", "image": ".cache/a.png"},
                       {"id": "f", "title": "Not a picture", "image": "notes.txt"}],
             "preview": true, "actions": ["clear", "rm"]}
            """))
        #expect(list.items[0].image == "thumbs/a.png" && list.items[0].section == "Pinned" && list.items[0].actions == ["alternate", "pin"])
        #expect(list.items[1].color == "#2ED4D9")
        #expect(list.items.dropFirst(2).allSatisfy { $0.image == nil && $0.color == nil }, "only a plain name inside the data folder")
        #expect(list.preview && list.actions == ["clear"])

        let preview = try #require(ExtensionPalettePreview.parse(try ExtensionPageTests.json("""
            {"text": "line one\\nline two\\u202e", "code": true, "image": "images/a.png", "facts": [{"label": "From", "value": "Notes"}, {"label": ""}]}
            """)))
        #expect(preview.text == "line one\nline two" && preview.code && preview.image == "images/a.png" && preview.facts.map(\.label) == ["From"])
        #expect(ExtensionPalettePreview.parse(try ExtensionPageTests.json("{}")) == nil, "nothing to show is no preview")
    }

    @Test func picturesAreReadOnlyFromInsideTheDataFolder() throws {
        let root = try ExtFixtures.tempDir("pictures")
        let folder = root.appendingPathComponent("data", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        for dir in [folder.appendingPathComponent("thumbs"), outside] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("thumbs/ok.png"))
        try Data([9]).write(to: outside.appendingPathComponent("secret.png"))
        #expect(ExtensionDataFile.read("thumbs/ok.png", in: folder, limit: 10) == Data([1, 2, 3]))
        #expect(ExtensionDataFile.read("thumbs/ok.png", in: folder, limit: 2) == nil, "over its size cap")

        // A link the extension made to a file it can't read itself, by name, by a linked folder, or a hard link.
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("thumbs/link.png"), withDestinationURL: outside.appendingPathComponent("secret.png"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("away"), withDestinationURL: outside)
        #expect(link(outside.appendingPathComponent("secret.png").path, folder.appendingPathComponent("thumbs/hard.png").path) == 0)
        for name in ["thumbs/link.png", "away/secret.png", "thumbs/hard.png", "../outside/secret.png", "thumbs/missing.png"] {
            #expect(ExtensionDataFile.read(name, in: folder, limit: 1000) == nil, "\(name)")
        }
    }

    @Test func pagesHaveChoicesFieldsAndLists() throws {
        let page = try ExtensionPage.parse(try ExtensionPageTests.json("""
            {"sections": [{"blocks": [
              {"type": "choice", "label": "Keep up to", "options": [{"value": "200", "label": "200"}, {"value": "500", "label": "500"}],
               "selected": "500", "tool": "set_option", "input": {"option": "limit"}},
              {"type": "choice", "label": "One option", "options": [{"value": "a", "label": "A"}], "tool": "set_option"},
              {"type": "choice", "label": "Other's", "options": [{"value": "a", "label": "A"}, {"value": "b", "label": "B"}], "tool": "ext.x.y"},
              {"type": "field", "label": "Ignore an app", "button": "Ignore", "tool": "ignore", "key": "app"},
              {"type": "field", "label": "Bad key", "button": "Go", "tool": "ignore", "key": "on"},
              {"type": "list", "title": "Latest", "items": [
                {"title": "Shot", "image": "thumbs/a.png", "button": {"label": "Copy", "tool": "copy_again", "input": {"id": "a"}}},
                {"title": "Escape", "image": "../a.png", "color": "#12345", "button": {"label": "Copy", "tool": "other.ext"}}]}]}]}
            """))
        let blocks = page.sections[0].blocks
        #expect(blocks.count == 3, "a choice needs two options and its own tool; a field's text can't pose as the switch's on")
        guard case .choice(let choice) = blocks[0], case .field(let field) = blocks[1], case .list(let list) = blocks[2] else {
            Issue.record("\(blocks)")
            return
        }
        #expect(choice.selected == "500" && choice.input(picking: "200") == ["option": "limit", "value": "200"])
        #expect(field.input(typing: "  1Password \n") == ["app": "1Password"])
        #expect(list.rows[0].image == "thumbs/a.png" && list.rows[0].button?.tool == "copy_again" && list.rows[0].button?.input == ["id": "a"])
        #expect(list.rows[1].image == nil && list.rows[1].color == nil && list.rows[1].button == nil)
    }

    @Test func maccysKeysWork() {
        func key(_ code: UInt16, cmd: Bool = false, opt: Bool = false, shift: Bool = false) -> PaletteKeys.Command? {
            PaletteKeys.command(keyCode: code, command: cmd, option: opt, shift: shift, control: false)
        }
        #expect(key(36) == nil, "plain Return is the search field's")
        #expect(key(36, opt: true) == .item("alternate", index: nil) && key(36, shift: true) == .item("plain", index: nil))
        #expect(key(36, opt: true, shift: true) == .item("plain", index: nil))
        #expect(key(18, cmd: true) == .item("choose", index: 0) && key(25, cmd: true) == .item("choose", index: 8))
        #expect(key(19, opt: true) == .item("alternate", index: 1) && key(19, opt: true, shift: true) == .item("plain", index: 1))
        #expect(key(35, opt: true) == .item("pin", index: nil) && key(35, cmd: true) == .item("pin", index: nil) && key(35) == nil)
        #expect(key(51, opt: true) == .item("delete", index: nil) && key(51) == nil, "a plain ⌫ edits the search")
        #expect(key(51, cmd: true, opt: true) == .list("clear") && key(51, cmd: true, opt: true, shift: true) == .list("clear_all"))
        #expect(PaletteKeys.command(keyCode: 18, command: true, option: false, shift: false, control: true) == nil)
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func previewsAndTheAppACopyCameFrom() async throws {
        for clipboard in [true, false] {
            let h = try HostEnv()
            let stream = h.env.events.stream()
            let folder = try ExtFixtures.tempDir("palette-src").appendingPathComponent("fixture")
            let source = try ExtFixtures.makeExtension(at: folder, manifest: ExtFixtures.manifest(
                id: "dev.test.palette", tools: ["noop": ["risk": "medium"]], permissions: ["clipboard": .bool(clipboard)],
                extra: ["sidefolk": ">=0.1", "palettes": ["history": ["title": "History", "hotkey": "shift+cmd+c"]]]), files: ["server.py": Self.fixture])
            let info = try await h.host.install(from: source)
            let asked = Task {
                for await event in stream { if case .clipboardSource(let id) = event { return id } }
                return ""
            }
            let list = try await h.host.queryPalette(extensionId: info.id, palette: "history", query: "")
            #expect(list.preview && list.actions == ["clear", "clear_all"] && list.items.first?.image == "thumbs/a.png")
            let preview = try await h.host.previewPalette(extensionId: info.id, palette: "history", item: "a")
            #expect(preview?.text == "full text of a" && preview?.image == "images/a.png")
            #expect(h.host.dataFolder(extensionId: info.id).path.hasSuffix("/\(info.id)"))

            try await Task.sleep(for: .milliseconds(300))
            asked.cancel()
            let id = await asked.value
            #expect(id == (clipboard ? info.id : ""), "clipboard \(clipboard): only the clipboard permission asks which app")
            if clipboard {
                await h.host.tell(extensionId: info.id, "sidefolk/clipboard.source", ["change": 7, "app": "com.apple.Notes", "name": "Notes"])
                try await Task.sleep(for: .milliseconds(200))
                let note = try await h.host.queryPalette(extensionId: info.id, palette: "history", query: "").note ?? ""
                #expect(note.contains("com.apple.Notes") && note.contains("change"), "\(note)")
            }
            await h.host.shutdown()
        }
    }
}
