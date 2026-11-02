import Foundation
import Testing
@testable import SidefolkCore

/// What the review of snapshot A found about what extensions declare (D98, D100, T41), each as the behaviour that must hold.
struct ExtensionReviewTests {
    static let program = SurfaceReviewTests.fixture

    func install(_ h: HostEnv, _ manifest: JSONValue, origin: ExtensionOrigin? = nil, name: String = "review") async throws -> ExtensionInfo {
        try await h.host.install(from: try h.source(name, manifest: manifest, files: ["server.py": Self.program]), origin: origin)
    }

    // MARK: Whose it is

    @Test func namesKeptForSidefolkAreFoundHoweverTheyAreWritten() {
        for name in ["Sidefolk", "SIDEFOLK", "Sïdefölk", "side folk", "Sidefolk Approvals", "Ѕidefolk", "Mochi", "mochi", "Kiko"] {
            #expect(ExtensionReservedNames.isReserved(name), "\(name)")
        }
        for name in ["Lantern Garden", "Side Notes", "Folk Songs", "Mochi Timer"] {
            #expect(!ExtensionReservedNames.isReserved(name), "\(name)")
        }
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func onlySidefolksOwnMayGoByItsName() async throws {
        let h = try HostEnv()
        let named = ExtFixtures.manifest(id: "local.probe", tools: [:]).setting("name", "Sidefolk")
        let source = try h.source("probe", manifest: named, files: ["server.py": Self.program])
        #expect(await h.host.preview(folder: source).report.errors.contains { $0.field == "name" }, "the sheet says so")
        await #expect(throws: UserFacingError.self) { try await h.host.install(from: source) }
        #expect(await h.host.preview(folder: source, origin: .official).canInstall, "a signed pack may")
        let authored = ExtFixtures.manifest(id: "local.probe2", tools: [:]).setting("author", "Sidefolk Team")
        await #expect(throws: UserFacingError.self) { try await install(h, authored, name: "probe2") }
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aTranslationCanNotTakeTheName() async throws {
        let h = try HostEnv()
        let source = try h.source("translated", manifest: ExtFixtures.manifest(id: "local.translated", tools: [:]), files: ["server.py": Self.program,
                                                                                                                        "strings/fr.json": #"{"name": "Sidefolk"}"#])
        let errors = await h.host.preview(folder: source).report.errors.map(\.field)
        #expect(errors.contains { $0.contains("fr") }, "\(errors)")
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func anUnsignedCopyStartsAfreshAndTheSheetSaysSo() async throws {
        let revoked = RevokedIds()
        let h = try HostEnv { $0.forgetGrants = { id in await revoked.add(id) } }
        let settings: JSONValue = [["key": "note", "type": "text", "title": "Note", "default": "x"]]
        let id = "dev.test.signed"
        let manifest = ExtFixtures.manifest(id: id, tools: [:], extra: ["settings": settings])
        _ = try await install(h, manifest, origin: .official, name: "signed")
        h.env.registry.register(ExtensionSettingTool(host: h.host))
        _ = await h.call(ExtensionSettingTool.name, ["extension": .string(id), "key": "note", "value": "the signed copy's"])
        #expect(h.host.shelf.settings.first?.value == "the signed copy's")

        let copy = try h.source("signed2", manifest: manifest.setting("version", "2.0.0"), files: ["server.py": Self.program])
        #expect(await h.host.preview(folder: copy, origin: .official).report.warnings.allSatisfy { !$0.contains("didn't sign") }, "the gallery's own update says nothing")
        #expect(await h.host.preview(folder: copy).report.warnings.contains { $0.contains("didn't sign") })
        _ = try await h.host.install(from: copy)
        #expect(h.host.shelf.settings.first?.value == "x", "what the person told the signed copy isn't owed to this one")
        #expect(await revoked.ids == [id], "nor what they always allowed")
    }

    actor RevokedIds {
        var ids: [String] = []
        func add(_ id: String) { ids.append(id) }
    }

    // MARK: Caps that count bytes

    @Test func marksOnOneCharacterDoNotPassACap() {
        let stack = "a" + String(repeating: "\u{0301}", count: 500_000)
        #expect(stack.count == 1)
        #expect(ExtensionText.clip(stack, 120).utf8.count < 100)
        #expect(ExtensionText.line(stack, characters: 120).utf8.count < 100)
        #expect(AIHelpQuestion(params: ["prompt": .string(stack)], extensionId: "x", purpose: "to test") == nil, "a request is bounded in bytes too")
        #expect(AIHelpQuestion(params: ["prompt": "Write a line about tea."], extensionId: "x", purpose: "to test") != nil)
        // Real writing keeps its marks.
        for word in ["Việt Nam", "résumé", "नमस्ते", "👩‍👩‍👧‍👦"] { #expect(ExtensionText.clip(word, 120) == word) }
    }

    @Test func aTextSettingIsBoundedInBytes() {
        let meta = ExtensionManifest.SettingMeta(key: "note", type: .text, title: "Note", length: 40)
        #expect(meta.checked(.string("a" + String(repeating: "\u{0301}", count: 400_000))) == nil)
        #expect(meta.checked("fine") == "fine")
    }

    // MARK: A program's settings

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aProgramCanNotFloodHistoryThroughItsSettings() async throws {
        let h = try HostEnv()
        let id = "dev.test.flood"
        let settings: JSONValue = [["key": "note", "type": "text", "title": "Note", "default": "start"]]
        _ = try await install(h, ExtFixtures.manifest(id: id, tools: [:], extra: ["settings": settings]), name: "flood")
        h.env.registry.register(ExtensionSettingTool(host: h.host))
        let now = Date()
        for i in 0..<200 { await h.host.programSetsSetting(id, params: ["key": "note", "value": .string("v\(i)")], now: now) }
        try await Task.sleep(for: .milliseconds(1300))
        let rows = try await h.env.activity.recent(limit: 300, tool: ExtensionSettingTool.name)
        #expect(rows.count <= 2, "one at once, then the last one a second later: \(rows.count)")
        #expect(h.host.shelf.settings.first?.value == "v199", "the last value wins")
        // Saying what it already holds writes nothing.
        await h.host.programSetsSetting(id, params: ["key": "note", "value": "v199"], now: Date().addingTimeInterval(5))
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await h.env.activity.recent(limit: 300, tool: ExtensionSettingTool.name).count == rows.count)
    }

    // MARK: Sidefolk's words first

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aSurfaceSentenceComesAfterSidefolksOwnAndIsReported() async throws {
        let h = try HostEnv()
        let sentences: JSONValue = ["remind me at 5 to stretch", "stop watching the deploy", "find my passport", "open the garden"]
        let manifest = SurfaceReviewTests.manifest(id: "dev.test.taker", surfaces: ["p": ["title": "P", "say": sentences]])
        let source = try h.source("taker", manifest: manifest, files: ["server.py": Self.program])
        let shadowed = await h.host.preview(folder: source).report.shadowed
        #expect(shadowed.contains("remind me at 5 to stretch") && shadowed.contains("find my passport"), "the author hears: \(shadowed)")
        _ = try await h.host.install(from: source)
        let now = Date()
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test", surfaces: h.host.surfaceShelf.all)
        func kind(_ text: String) -> String { String(describing: parser.parse(text, now: now)?.intent).components(separatedBy: "(").dropFirst().first ?? "" }
        if case .remind? = parser.parse("remind me at 5 to stretch", now: now)?.intent {} else { Issue.record("a reminder stays a reminder") }
        if case .stopWatch? = parser.parse("stop watching the deploy", now: now)?.intent {} else { Issue.record("stopping stays stopping") }
        if case .find? = parser.parse("find my passport", now: now)?.intent {} else { Issue.record("finding stays finding") }
        if case .surface? = parser.parse("open the garden", now: now)?.intent {} else { Issue.record("its own sentence still opens it: \(kind("open the garden"))") }
    }

    @Test func aSurfaceIsNotCalledAGame() {
        let parsed = ParsedIntent(intent: .surface(id: "x/y"), hint: "")
        let said = parsed.understanding(now: Date(), calendar: .current).sentence
        #expect(!said.lowercased().contains("play"), "\(said)")
    }

    // MARK: Approval words

    @Test func aReplyWordIsRefusedAtInstallKeptWorkingWhenInstalledAndNeverMatches() throws {
        let paths = SidefolkPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let manifest = ExtFixtures.manifest(id: "dev.test.reply", tools: ["echo": ["title": "Echo", "risk": "low", "commands": [["say": ["confirm"]], ["say": ["echo it"]]]]])
        let installed = try ExtFixtures.tempDir("reply").appendingPathComponent("dev.test.reply")
        _ = try ExtFixtures.makeExtension(at: installed, manifest: manifest, files: ["server.py": Self.program])
        let validator = ManifestValidator(paths: paths)
        let atInstall = validator.validate(folder: installed, mode: .source)
        #expect(atInstall.errors.contains { $0.description.contains("reply anyone might type") }, "\(atInstall.errors)")
        let already = validator.validate(folder: installed, mode: .installed)
        #expect(already.isValid, "an update of the app never turns off an extension: \(already.errors)")
        #expect(already.warnings.contains { $0.contains("reply anyone might type") })
        #expect(try CommandSentence("confirm").match("confirm") == nil, "and typing it never reaches it")
        #expect(try CommandSentence("echo it").match("echo it") != nil)
    }

    // MARK: Assets, seeds, a restore

    @Test func whatFinderLeavesIsNotAPicture() throws {
        let dir = try ExtFixtures.tempDir("ds")
        try PackAssetsTests.png().write(to: dir.appendingPathComponent("a.png"))
        try Data([0, 1]).write(to: dir.appendingPathComponent(".DS_Store"))
        #expect(PackAssets.check(folder: dir.path).problems.isEmpty)
    }

    @Test func aPageOnlyDecodesPlainPictures() throws {
        #expect(PackAssets.isPlainPicture(PackAssetsTests.png()))
        #expect(!PackAssets.isPlainPicture(Data("%PDF-1.7".utf8)), "a PDF named .png")
        #expect(!PackAssets.isPlainPicture(Data("GIF89a".utf8)))
        #expect(!PackAssets.isPlainPicture(Data("II*\0".utf8)), "TIFF")
    }

    @Test func aSeedWaitingItsTurnDoesNotComeBackOnceRemoved() throws {
        let h = try HostEnv()
        SeedPacks.restored(["dev.test.a", "dev.test.b"], paths: h.paths)
        SeedPacks.removed("dev.test.a", paths: h.paths)
        let file = h.paths.addons.appendingPathComponent(SeedPacks.ledgerFile)
        let left = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))["pending"]?.arrayValue?.compactMap(\.stringValue)
        #expect(left == ["dev.test.b"])
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func anExtensionBeingInstalledIsNotThereForAnyoneYet() async throws {
        let slow = #"""
        import json, sys, time
        for line in sys.stdin:
            m = json.loads(line)
            if "id" not in m: continue
            time.sleep(0.3)
            r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "g", "version": "1"}} if m["method"] == "initialize" else {"tools": []}
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}) + "\n"); sys.stdout.flush()
        """#
        let h = try HostEnv()
        let id = "dev.test.slowstart"
        let source = try h.source("slowstart", manifest: ExtFixtures.manifest(id: id, tools: [:]), files: ["server.py": slow])
        let installing = Task { try await h.host.install(from: source) }
        try await Task.sleep(for: .milliseconds(150))
        // What a restore's follow-up polls for: seeing it now, it would switch it off in the middle.
        #expect(await h.host.info(id: id) == nil)
        _ = try await installing.value
        #expect(await h.host.info(id: id)?.enabled == true)
    }

    // MARK: What the app kept

    static let carrier = #"""
    import json, sys
    heard = {}
    for line in sys.stdin:
        m = json.loads(line)
        if "id" not in m: continue
        meth, p = m["method"], m.get("params") or {}
        if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "g", "version": "1"}}
        elif meth == "tools/list": r = {"tools": [{"name": "heard", "title": "Heard", "description": "d", "inputSchema": {"type": "object"}}]}
        elif meth == "sidefolk/settings.carry":
            heard = p
            r = {"settings": {"sounds": p.get("values", {}).get("sounds", False)}, "ai": False}
        elif meth == "tools/call": r = {"content": [{"type": "text", "text": json.dumps(heard)}]}
        else: r = {}
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}) + "\n"); sys.stdout.flush()
    """#

    static func carrierManifest(id: String) -> JSONValue {
        ExtFixtures.manifest(id: id, tools: ["heard": ["title": "Heard", "risk": "low"]], extra: [
            "settings_from": "old", "carries": ["store": ["old.score", "old.none"], "history": ["old.play"]],
            "settings": [["key": "sounds", "type": "switch", "title": "Sounds", "default": false]],
            "permissions": ["ai": ["purpose": "to write", "daily_cap": 3]],
        ])
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func recordsAndAnOptOutCarryOverOnceToSidefolksOwn() async throws {
        let row = ActivityEntry(at: Date(timeIntervalSince1970: 1000), caller: "user", tool: "old.play", risk: "low", decision: .auto, summary: "Played", args: ["game": "x"])
        let h = try HostEnv {
            $0.carriedSettings = { _ in ["sounds": true] }
            $0.carriedStore = { $0 == "old.score" ? ["won": 7] : nil }
            $0.carriedHistory = { $0 == "old.play" ? [row] : [] }
            $0.aiName = { "Scripted" }
        }
        let id = "dev.test.carrier"
        let source = try h.source("carrier", manifest: Self.carrierManifest(id: id), files: ["server.py": Self.carrier])
        _ = try await h.host.install(from: source, origin: .official)
        try await Task.sleep(for: .milliseconds(400))
        let text = await h.call("ext.carrier.heard").okText ?? ""
        #expect(text.contains(#""old.score""#) && text.contains(#""won""#), "\(text)")
        #expect(!text.contains("old.none"), "what isn't there isn't said")
        #expect(text.contains(#""old.play""#) && text.contains("Played") && text.contains("1000"), "\(text)")
        #expect(h.host.shelf.settings.first?.value == true)
        #expect(await h.host.info(id: id)?.ai?.on == false, "a person's no to the AI stays a no")
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func nobodyElseGetsWhatTheAppKept() async throws {
        let h = try HostEnv { $0.carriedStore = { _ in ["won": 7] } }
        let source = try h.source("carrier", manifest: Self.carrierManifest(id: "dev.test.carrier"), files: ["server.py": Self.carrier])
        _ = try await h.host.install(from: source)
        try await Task.sleep(for: .milliseconds(300))
        #expect(await h.call("ext.carrier.heard").okText?.contains("won") == false)
    }

    @Test func theValidatorChecksWhatMayBeCarried() {
        let m = ExtensionManifest.Carries(store: ["ok.name", "bad name"], history: Array(repeating: "x", count: 9))
        var manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: Data(ExtFixtures.manifest(id: "dev.test.c", tools: [:]).jsonString.utf8))
        manifest?.carries = m
        let issues = manifest.map(ExtensionAbilityRules.check) ?? []
        #expect(issues.contains { $0.field == "carries.store" })
        #expect(issues.contains { $0.field == "carries.history" })
    }

    // MARK: Who else's AGENTS.md

    @Test func aCodexInstructionsFileIsSeenWhereverItIs() throws {
        let home = try ExtFixtures.tempDir("codex")
        #expect(!CodexBackend.hasUserInstructions(environment: [:], home: home.path), "none yet")
        let folder = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("AGENTS.md"))
        #expect(!CodexBackend.hasUserInstructions(environment: [:], home: home.path), "an empty one says nothing")
        try Data("my token".utf8).write(to: folder.appendingPathComponent("AGENTS.md"))
        #expect(CodexBackend.hasUserInstructions(environment: [:], home: home.path))
        let other = try ExtFixtures.tempDir("codex-home")
        #expect(!CodexBackend.hasUserInstructions(environment: ["CODEX_HOME": other.path], home: home.path), "CODEX_HOME moves it")
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func whileHeldBackTheAIIsNotAskedAndTheSwitchSaysWhy() async throws {
        let id = "dev.test.carrier"
        let h = try HostEnv {
            $0.aiName = { "Codex" }
            $0.aiHeldBack = { "Not while…" }
        }
        let source = try h.source("carrier", manifest: Self.carrierManifest(id: id), files: ["server.py": Self.carrier])
        _ = try await h.host.install(from: source)
        #expect(await h.host.info(id: id)?.ai?.heldBack == "Not while…")
    }

    // MARK: History

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func rowsInAnExtensionsOwnWordsGoWithItAndToolRowsStay() async throws {
        let activity = try TestEnv().activity
        _ = try await activity.log(ActivityEntry(at: Date(), caller: "x", tool: ExtensionActivityTool.name, risk: "low", decision: .auto, summary: "its words", args: ["extension": "a"]))
        _ = try await activity.log(ActivityEntry(at: Date(), caller: "x", tool: ExtensionActivityTool.name, risk: "low", decision: .auto, summary: "another's", args: ["extension": "b"]))
        _ = try await activity.log(ActivityEntry(at: Date(), caller: "x", tool: "ext.a.go", risk: "low", decision: .auto, summary: "what it did", args: ["extension": "a"]))
        #expect(try await activity.delete(tool: ExtensionActivityTool.name, extensionId: "a") == 1)
        #expect(try await activity.recent(limit: 10).map(\.summary).sorted() == ["another's", "what it did"])
    }

    // MARK: A scene in a page

    @Test func aPageCanDrawAScene() throws {
        let block: JSONValue = ["type": "scene", "scene": ["size": [600, 200], "nodes": [["type": "group", "id": "tile", "w": 100, "h": 100, "area": ["id": "open", "value": "sudoku", "label": "Open"]]]],
                                "actions": ["open": ["tool": "start", "input": ["from": "center"]], "bad": ["tool": "ext.other.go"]]]
        let page = try ExtensionPage.parse(["sections": [["blocks": [block]]]])
        guard case .scene(let scene)? = page.sections.first?.blocks.first else { Issue.record("\(page.sections)"); return }
        #expect(scene.scene.size.width == 600)
        #expect(scene.actions["bad"] == nil, "only the extension's own tool")
        let action = try #require(scene.action(area: "open", value: "sudoku"))
        #expect(action.tool == "start" && action.input == ["from": "center", "value": "sudoku"])
        #expect(scene.action(area: "elsewhere", value: nil) == nil)
        // The same caps as a surface's: past them, the block isn't there.
        let giant: [JSONValue] = (0..<40).map { _ in ["type": "text", "text": "x", "w": 2000, "h": 2000] }
        let refused = try ExtensionPage.parse(["sections": [["blocks": [["type": "scene", "scene": ["nodes": .array(giant)]]]]]])
        #expect(refused.sections.allSatisfy { $0.blocks.isEmpty })
    }
}
