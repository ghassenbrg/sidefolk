import AppKit
import Testing
@testable import SidefolkCharacter

/// Companions made from data: the format is strict, parts are only shapes, nothing leaves its
/// folder, and what loads draws in every state inside its window.
@MainActor @Suite struct CustomCompanionTests {
    static let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("companions")

    /// A scratch copy of the template, changed by `edit` (its JSON as a dictionary) and `files`.
    func scratch(_ edit: (inout [String: Any]) -> Void = { _ in }, files: [String: String] = [:]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-companion-\(UUID().uuidString)")
            .appendingPathComponent("bun")
        try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.examples.appendingPathComponent("template"), to: dir)
        let url = dir.appendingPathComponent("species.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["id"] = "bun"
        edit(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        for (name, text) in files { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        return dir
    }

    func errors(_ folder: URL) -> String { CustomCompanions.load(folder: folder).errors.joined(separator: " | ") }

    @Test(arguments: ["template", "miso"])
    func theExamplesLoadAndLiveInTheirWindow(_ name: String) throws {
        let report = CustomCompanions.load(folder: Self.examples.appendingPathComponent(name))
        #expect(report.errors.isEmpty, "\(report.errors)")
        let companion = try #require(report.companion)
        #expect(companion.id == name)
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.look = CharacterLook(custom: companion, style: CharacterStyle(color: .coral, accessory: .scarf))
        for state in CharacterState.gallery {
            view.setState(state, animated: false)
            #expect(CGRect(x: 0, y: 0, width: 200, height: 200).contains(view.characterPath.boundingBoxOfPath), "\(state.name)")
        }
        // Switching between a custom companion and a built-in one rebuilds the body; restyling doesn't.
        let stage = view.layer?.sublayers?.first
        view.look = CharacterLook(custom: companion, style: CharacterStyle(color: .mint, accessory: .none))
        #expect(view.layer?.sublayers?.first === stage)
        view.look = CharacterLook(.mochi)
        #expect(view.layer?.sublayers?.first !== stage)
    }

    @Test func unknownKeysAndBadValuesAreRefused() throws {
        #expect(errors(try scratch { $0["colour"] = "red" }).contains("colour isn't a known key"))
        #expect(errors(try scratch { json in
            var body = json["body"] as! [String: Any]
            body["scale"] = 3
            json["body"] = body
        }).contains("body.scale"))
        #expect(errors(try scratch { $0["id"] = "mochi" }).contains("already has"))
        #expect(errors(try scratch { $0["id"] = "../x" }).contains("id"))
        #expect(errors(try scratch { $0["format"] = 2 }).contains("format"))
        #expect(errors(try scratch { $0["sidefolk"] = "0.1" }).contains("sidefolk: the oldest version"))
        #expect(errors(try scratch { $0["sidefolk"] = ">=0.1" }).isEmpty)
        #expect(errors(try scratch { $0["name"] = "Bun\u{7}" }).contains("name"))
    }

    @Test func partsAreOnlyShapes() throws {
        let ear = { (svg: String) in try self.scratch(files: ["parts/ear.svg": svg]) }
        #expect(errors(try ear(#"<svg><script>alert(1)</script><circle r="9"/></svg>"#)).contains("<script> isn't allowed"))
        #expect(errors(try ear(#"<svg><image href="x.png"/></svg>"#)).contains("isn't allowed"))
        #expect(errors(try ear(#"<svg><path d="M0 0 A 5 5 0 0 1 10 0 Z"/></svg>"#)).contains("arcs"))
        #expect(errors(try ear(#"<svg><g transform="scale(2)"><circle r="9"/></g></svg>"#)).contains("transforms"))
        #expect(errors(try ear(#"<svg><circle r="9" onclick="x()"/></svg>"#)).contains("event handlers"))
        #expect(errors(try ear(#"<svg><circle r="9" fill="red"/></svg>"#)).contains("#RRGGBB"))
        #expect(errors(try ear("<svg></svg>")).contains("no path"))
        #expect(errors(try ear(#"<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><svg><circle r="&x;"/></svg>"#)) != "")
    }

    @Test func nothingIsReadFromOutsideTheFolder() throws {
        let outside = try scratch { json in
            var ears = json["ears"] as! [[String: Any]]
            ears[0]["part"] = "parts/../../secret.svg"
            json["ears"] = ears
        }
        #expect(errors(outside).contains("parts are files in the parts folder"))
        // A part that is a link is refused, even to a harmless file.
        let linked = try scratch()
        let ear = linked.appendingPathComponent("parts/ear.svg")
        let real = linked.deletingLastPathComponent().appendingPathComponent("real.svg")
        try FileManager.default.moveItem(at: ear, to: real)
        try FileManager.default.createSymbolicLink(at: ear, withDestinationURL: real)
        #expect(errors(linked).contains("is a link"))
        // Too big.
        let big = try scratch(files: ["parts/ear.svg": "<svg><circle r=\"9\"/>" + String(repeating: " ", count: 300_000) + "</svg>"])
        #expect(errors(big).contains("bigger than"))
    }

    @Test func aCompanionTooTallForItsWindowIsRefused() throws {
        let tall = try scratch { json in
            var ears = json["ears"] as! [[String: Any]]
            for i in ears.indices { ears[i]["base"] = [i == 0 ? 72 : 128, 186] }
            json["ears"] = ears
        }
        #expect(errors(tall).contains("leaves the window") || errors(tall).contains("outside the 200 × 200 canvas"))
        let faceless = try scratch { json in
            var face = json["face"] as! [String: Any]
            face["eyes"] = [[20, 180], [180, 180]]
            json["face"] = face
        }
        #expect(errors(faceless).contains("eyes and mouth"))
    }

    @Test func theHomeFolderAndExtensionsAreSearched() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-home-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: CustomCompanions.folder(home: home), withIntermediateDirectories: true)
        try fm.copyItem(at: Self.examples.appendingPathComponent("miso"), to: CustomCompanions.folder(home: home).appendingPathComponent("miso"))
        let ext = home.appendingPathComponent("Extensions/dev.example.pets")
        try fm.createDirectory(at: ext, withIntermediateDirectories: true)
        try fm.copyItem(at: Self.examples.appendingPathComponent("template"), to: ext.appendingPathComponent("companion"))
        // The same id twice: the second is reported, not loaded.
        try fm.copyItem(at: Self.examples.appendingPathComponent("miso"), to: CustomCompanions.folder(home: home).appendingPathComponent("miso2"))
        let reports = CustomCompanions.loadAll(home: home)
        #expect(Set(reports.compactMap(\.companion?.id)) == ["miso", "template"])
        #expect(reports.contains { $0.errors.contains { $0.contains("already uses the id") } })
    }

    @Test func pathDataReadsEveryCommandButArcs() throws {
        let ops = try PathData.parse("M10 10 l5 0 h5 v5 c1 1 2 2 3 3 s4 4 5 5 q1 1 2 2 t3 3 L0,0z m1-1 2 2")
        #expect(ops.first == .move(CGPoint(x: 10, y: 10)))
        #expect(ops[1] == .line(CGPoint(x: 15, y: 10)))
        #expect(ops[3] == .line(CGPoint(x: 20, y: 15)))
        #expect(ops.contains(.close))
        // After z, the pen is back at the start; "m1-1 2 2" is a move then an implicit line.
        #expect(ops.suffix(2) == [.move(CGPoint(x: 11, y: 9)), .line(CGPoint(x: 13, y: 11))])
        #expect(throws: PartError.self) { try PathData.parse("L 1 2") }
        #expect(throws: PartError.self) { try PathData.parse("M 1") }
        #expect(throws: PartError.self) { try PathData.parse("M 1 2 X 3") }
    }
}
