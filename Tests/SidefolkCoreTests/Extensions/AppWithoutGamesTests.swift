import Foundation
import Testing
@testable import SidefolkCore

/// D101: the app keeps no games. With no extension there is nothing of them anywhere; a copy from before stays listed and loses nothing;
/// installing and removing leaves nothing behind; something new needs no change here.
struct AppWithoutGamesTests {
    /// What the runtime hands the parser: tools that have sentences.
    private static func commandTools(_ h: HostEnv) -> [ExtensionTool] {
        h.env.registry.all.compactMap { $0 as? ExtensionTool }.filter { $0.commands != nil }
    }

    // MARK: Nothing installed

    /// Every word a person might use for what used to be built in: the parser takes none, so they go to the AI or get the plain "I can't", and none pretends.
    static let sentences = ["play a game", "let's play", "show me the games", "games", "play trivia", "let's play trivia", "quiz me", "sudoku", "daily word", "flip a coin",
                            "roll a die", "roll 2d20", "rock", "rock paper scissors", "rematch", "make it harder", "pause the game", "resume", "show my stats", "jouons au morpion",
                            "ゲームしよう", "クイズしよう", "لنلعب", "turn game sounds off"]

    @Test func noSentenceOpensAGameThatIsntThere() {
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")
        for sentence in Self.sentences {
            let parsed = parser.parse(sentence, now: TimeTest.wednesday10)?.intent
            if case .find? = parsed { continue }
            #expect(parsed == nil, "“\(sentence)” claims to be \(String(describing: parsed))")
        }
    }

    @Test func nothingIsOfferedOrListed() async throws {
        let h = try HostEnv()
        await h.host.start()
        for place in [ExtensionManifest.EntryMeta.Place.companion, .pocket, .ask] { #expect(h.host.shelf.entries(in: place).isEmpty) }
        #expect(h.host.surfaceShelf.all.isEmpty && h.host.shelf.settings.isEmpty && h.host.shelf.drops.isEmpty)
        let pages = await h.host.pages()
        #expect(pages.isEmpty)
    }

    /// The model is told of no game: the only way to play left is the companion's own catch-me (its life, not an extension's).
    @Test func theAIIsOfferedNoGameTool() throws {
        let env = try TestEnv()
        let names = BuiltinTools.make(notebook: NotebookStore(env.db), platform: NullPlatform(), events: env.events).map(\.spec.name)
        for gone in ["games.open", "games.settings", "companion.toss"] { #expect(!names.contains(gone), "\(gone)") }
        #expect(names.contains("companion.play"))
    }

    /// Menus, the Pocket, Ask's tabs, Settings and its search all draw from the catalog's words: the words of what left aren't in it.
    @Test func theCatalogHoldsNoWordOfThem() throws {
        let url = ExtFixtures.repoRoot.appendingPathComponent("Resources/Localization/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let keys = Set((catalog?["strings"] as? [String: Any] ?? [:]).keys)
        for gone in ["Games", "Games…", "All Games…", "Flip a Coin", "Roll a Die", "Quick Throw", "Call Heads", "Game sounds", "Sneaky", "When it wins",
                     "Make new trivia questions with AI", "The companion's lines while you play.", "Heads or tails…", "Rolling…", "Natural 20!"] {
            #expect(!keys.contains(gone), "“\(gone)” is still in the catalog")
        }
        #expect(keys.contains("Catch me!"), "the companion's own stays")
    }

    @Test func whatThePersonChoseWaitsForItsExtension() throws {
        // Settings as the old app wrote them: the section it retired stays until the extension receives it, and an old row in the attention table is dropped quietly.
        let old = #"{"companionName": "Mochi", "games": {"tone": "gentle", "sounds": true, "aiTrivia": false, "levels": {"dev.sidefolk.x/y": "hard"}},"#
            + #" "interruptions": {"games": "off", "reminders": "whisper"}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(settings.companionName == "Mochi")
        #expect(settings.section("games")?["aiTrivia"]?.boolValue == false)
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(again.section("games")?["tone"]?.stringValue == "gentle", "kept through a save, however many")
        #expect(again.interruptions.level(for: .reminders) == .whisper)
    }

    // MARK: A copy from before: the real manifest of the last one that named `games`

    static let id = "dev.sidefolk.playtime"
    static let oldCopy = ExtFixtures.repoRoot.appendingPathComponent("Tests/Fixtures/playtime-snapshot-8", isDirectory: true)

    /// As the old app left it: its files in place and pinned, and its record, with its data and what the person chose beside it.
    private func olderCopy(_ h: HostEnv, enabled: Bool = true) async throws {
        let source = h.root.appendingPathComponent("old/\(Self.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.oldCopy, to: source)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 3\n".utf8).write(to: source.appendingPathComponent("bin/ext-playtime"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.appendingPathComponent("bin/ext-playtime").path)
        try Data("%PDF-1.4\n".utf8).write(to: source.appendingPathComponent("icon.pdf"))
        let installer = ExtensionInstaller(paths: h.paths)
        let staged = try installer.stage(source: source, id: Self.id, quarantine: .none)
        let committed = try installer.commit(staged)
        var record = ExtensionRecord(id: Self.id, version: "1.0.0-snapshot.8", path: committed.folder, enabled: enabled, kind: .sidefolk)
        record.manifestHash = ExtensionFiles.aggregateHash(staged.pins)
        let pin = ExtensionPin(name: "Playtime", description: "Games", tagline: "Games", folk: "play", author: "Sidefolk", origin: .official,
                               permissions: ExtensionPermissions(), files: staged.pins)
        record.granted = try JSONValue.from(pin)
        try await h.store.save(record)
        let data = h.host.dataFolder(extensionId: Self.id)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data(#"{"plays": 41}"#.utf8).write(to: data.appendingPathComponent("records.json"))
    }

    @Test func anOlderCopyStaysListedAndSaysWhatToDo() async throws {
        let h = try HostEnv()
        try await olderCopy(h)
        await h.host.start()
        let info = try #require(await h.host.info(id: Self.id))
        #expect(info.needsAnUpdate && info.lastError == nil, "not broken: \(info.lastError ?? "")")
        #expect(info.name == "Playtime" && info.version == "1.0.0-snapshot.8" && info.origin == .official)
        #expect(info.enabled, "the person's switch is kept for the update")
        // It stands where it stood, and nothing of it runs or is offered.
        let page = try #require(await h.host.pages().first)
        #expect(page.needsAnUpdate && !page.widget && !page.history)
        #expect(h.host.surfaceShelf.all.isEmpty && h.host.shelf.entries(in: .companion).isEmpty)
        #expect(h.env.registry.specs.filter { $0.name.hasPrefix("ext.playtime") }.isEmpty)
        #expect(info.running == false)
        await #expect(throws: (any Error).self) { try await h.host.setEnabled(true, id: Self.id) }
        // Reading it didn't change what's stored: a later Sidefolk or a downgrade finds it as it was.
        #expect(try await h.store.all().first?.enabled == true)
        #expect(try await h.store.all().first?.lastError == nil)
    }

    @Test func anOlderCopyTurnedOffStaysOffAndHasNoPage() async throws {
        let h = try HostEnv()
        try await olderCopy(h, enabled: false)
        await h.host.start()
        let info = try #require(await h.host.info(id: Self.id))
        #expect(info.needsAnUpdate && !info.enabled)
        #expect(await h.host.pages().isEmpty)
    }

    @Test func aPackFromBeforeCantBeInstalledAndSaysSo() throws {
        let h = try HostEnv()
        let report = ManifestValidator(paths: h.paths).validate(folder: Self.oldCopy)
        #expect(report.needsAnUpdate && !report.isValid && !report.needsNewerSidefolk)
        #expect(report.errors.map(\.field) == ["games"])
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func theUpdateLosesNothing() async throws {
        let row = ActivityEntry(at: Date(timeIntervalSince1970: 1000), caller: "user", tool: "games.play", risk: "low", decision: .auto, summary: "Played Trivia", args: ["game": "trivia"])
        let h = try HostEnv {
            $0.carriedSettings = { $0 == "games" ? ["sounds": true, "aiTrivia": false] : nil }
            $0.carriedStore = { $0 == "companion.handsScore" ? ["wins": 7] : nil }
            $0.carriedHistory = { $0 == "games.play" ? [row] : [] }
            $0.aiName = { "Scripted" }
        }
        try await olderCopy(h)
        await h.host.start()
        #expect(await h.host.info(id: Self.id)?.needsAnUpdate == true)
        // The newer version, with the ways it receives what the app kept for it.
        let program = #"""
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
                r = {"settings": {"sounds": p.get("values", {}).get("sounds", False)}, "ai": p.get("values", {}).get("aiTrivia", True)}
            elif meth == "tools/call": r = {"content": [{"type": "text", "text": json.dumps(heard)}]}
            else: r = {}
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}) + "\n"); sys.stdout.flush()
        """#
        let manifest = ExtFixtures.manifest(id: Self.id, tools: ["heard": ["title": "Heard", "risk": "low"]], extra: [
            "name": "Playtime", "version": "1.0.0-snapshot.9", "settings_from": "games", "carries": ["store": ["companion.handsScore"], "history": ["games.play"]],
            "settings": [["key": "sounds", "type": "switch", "title": "Sounds", "default": false]],
            "permissions": ["ai": ["purpose": "to write", "daily_cap": 3]],
        ])
        let source = try h.source("playtime", manifest: manifest, files: ["server.py": program])
        let preview = await h.host.preview(folder: source, origin: .official)
        #expect(preview.canInstall && preview.update?.widens == true, "what it adds still waits for the person")
        let updated = try await h.host.install(from: source, origin: .official)
        #expect(!updated.needsAnUpdate && updated.enabled && updated.version == "1.0.0-snapshot.9")
        // Its own records, where the program keeps them.
        let records = h.host.dataFolder(extensionId: Self.id).appendingPathComponent("records.json")
        #expect(String(decoding: try Data(contentsOf: records), as: UTF8.self).contains("41"))
        // And what the app kept: the person's choices, its score, History's rows, and a no to the AI stays a no.
        try await Task.sleep(for: .milliseconds(400))
        let text = await h.call("ext.playtime.heard").okText ?? ""
        #expect(text.contains("companion.handsScore") && text.contains("wins") && text.contains("Played Trivia"), "\(text)")
        #expect(h.host.shelf.settings.first?.value == true)
        #expect(await h.host.info(id: Self.id)?.ai?.on == false)
    }

    // MARK: Installing and removing

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func installThenUninstallLeavesNothing() async throws {
        let h = try HostEnv()
        let installed = try await h.host.install(from: ExtFixtures.builtIn("playtime"), origin: .official)
        try await Task.sleep(for: .milliseconds(200))
        // Installed: everything comes with it.
        #expect(h.host.surfaceShelf.all.contains { $0.surface == "play" } && h.host.surfaceShelf.all.contains { $0.surface == "toss" })
        #expect(!h.host.shelf.entries(in: .companion).isEmpty && !h.host.shelf.entries(in: .pocket).isEmpty && !h.host.shelf.entries(in: .ask).isEmpty)
        #expect(!h.host.shelf.settings.isEmpty)
        #expect(await h.host.pages().contains { $0.extensionId == installed.id })
        let tools = h.env.registry.specs.map(\.name).filter { $0.hasPrefix("ext.playtime.") }
        #expect(tools.contains("ext.playtime.open"))
                let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test", commandTools: Self.commandTools(h), surfaces: h.host.surfaceShelf.all)
        if case .extensionCommand? = parser.parse("let's play sudoku", now: TimeTest.wednesday10)?.intent {} else { Issue.record("its own sentence opens it") }
        if case .extensionCommand? = parser.parse("flip a coin", now: TimeTest.wednesday10)?.intent {} else { Issue.record("its own sentence tosses") }

        try await h.host.uninstall(id: installed.id)

        for place in [ExtensionManifest.EntryMeta.Place.companion, .pocket, .ask] { #expect(h.host.shelf.entries(in: place).isEmpty, "\(place)") }
        #expect(h.host.surfaceShelf.all.isEmpty && h.host.shelf.settings.isEmpty && h.host.shelf.drops.isEmpty)
        #expect(await h.host.pages().isEmpty)
        #expect(await h.host.extensions().isEmpty)
        #expect(h.env.registry.specs.filter { $0.name.hasPrefix("ext.playtime.") }.isEmpty)
        #expect(try await h.store.all().isEmpty)
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: ExtensionInstaller(paths: h.paths).installedFolder(installed.id)), "its pack and its strings")
        #expect(!fm.fileExists(atPath: h.host.dataFolder(extensionId: installed.id).path), "its records")
        let after = IntentParser(when: TimeTest.parser(), home: "/Users/test", commandTools: Self.commandTools(h), surfaces: h.host.surfaceShelf.all)
        #expect(after.parse("let's play sudoku", now: TimeTest.wednesday10) == nil)
        #expect(after.parse("flip a coin", now: TimeTest.wednesday10) == nil)
    }

    // MARK: Something new

    /// A game the app has never heard of, a page, a menu, words and a sentence, all from one extension's folder (its own test in the gallery adds one to Playtime itself).
    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aNewGameNeedsNoChangeHere() async throws {
        let program = #"""
        import json, sys
        scene = {"size": [300, 200], "title": "Marbles", "nodes": [{"type": "group", "id": "m", "w": 40, "h": 40, "area": {"id": "marble", "label": "Flick"}}]}
        for line in sys.stdin:
            m = json.loads(line)
            if "id" not in m: continue
            meth, p = m["method"], m.get("params") or {}
            if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "g", "version": "1"}}
            elif meth == "tools/list": r = {"tools": [{"name": "open", "title": "Open", "description": "d", "inputSchema": {"type": "object"}}]}
            elif meth == "tools/call": r = {"content": [{"type": "text", "text": "ok"}], "sidefolk": {"open_surface": "marbles"}}
            elif meth == "sidefolk/surface.open": r = {"session": "s1", "scene": scene}
            elif meth == "sidefolk/surface.move": r = {"scene": scene}
            elif meth == "sidefolk/page": r = {"sections": [{"blocks": [{"type": "stats", "items": [{"label": "Flicks", "value": "3"}]}]}]}
            else: r = {}
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}) + "\n"); sys.stdout.flush()
        """#
        let manifest = ExtFixtures.manifest(id: "dev.test.marbles", tools: ["open": ["title": "Open", "risk": "low", "commands": [["say": ["play marbles"]]]]], extra: [
            "name": "Marbles", "surfaces": ["marbles": ["title": "Marbles", "symbol": "circle.fill", "width": 300, "height": 200, "say": ["show the marbles"]]],
            "pages": ["marbles": ["title": "Marbles", "symbol": "circle.fill"]],
            "entries": [["id": "play", "title": "Marbles", "places": ["companion", "pocket", "ask"], "tool": "open"]],
        ])
        let h = try HostEnv()
        let source = try h.source("marbles", manifest: manifest, files: ["server.py": program])
        let report = ManifestValidator(paths: h.paths).validate(folder: source)
        #expect(report.isValid, "\(report.errors)")
        let info = try await h.host.install(from: source)
        // Offered everywhere an extension's things are, by its own words.
        #expect(h.host.shelf.entries(in: .companion).map(\.title).contains { $0.contains("Marbles") })
        #expect(h.host.shelf.entries(in: .pocket).count == 1 && h.host.shelf.entries(in: .ask).count == 1)
        #expect(await h.host.pages().map(\.title) == ["Marbles"])
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test", commandTools: Self.commandTools(h), surfaces: h.host.surfaceShelf.all)
        if case .extensionCommand? = parser.parse("play marbles", now: TimeTest.wednesday10)?.intent {} else { Issue.record("its sentence") }
        if case .surface? = parser.parse("show the marbles", now: TimeTest.wednesday10)?.intent {} else { Issue.record("its surface's sentence") }
        // And it plays.
        let surface = try #require(h.host.surfaceShelf.all.first)
        let (session, scene) = try await h.host.openSurface(surface, language: "en")
        #expect(scene.areas.map(\.id) == ["marble"])
        let next = try await h.host.moveSurface(info: surface, session: session, move: .click(area: "marble", value: nil, ms: nil))
        #expect(next?.title == "Marbles")
        await h.host.closeSurface(info: surface, session: session, reason: .finished)
        try await h.host.uninstall(id: info.id)
        #expect(h.host.shelf.entries(in: .companion).isEmpty && h.host.surfaceShelf.all.isEmpty)
    }
}
