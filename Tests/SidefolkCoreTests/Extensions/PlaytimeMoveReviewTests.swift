import CoreGraphics
import Synchronization
import Foundation
import Testing
@testable import SidefolkCore

/// What comparing the moved games with the old ones found in the app's general abilities (D101), each as the behaviour that must hold. Everything here is fictional
/// except where the real pack's size is the point.
struct PlaytimeMoveReviewTests {
    // MARK: Listing extensions costs nothing

    /// Everything from an AI request to a backup lists the extensions; a large extension's sentences are compiled once, not at every listing.
    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func listingARealLargeExtensionIsCheap() async throws {
        let h = try HostEnv()
        let installed = try await h.host.install(from: ExtFixtures.builtIn("playtime"), origin: .official)
        _ = await h.host.extensions()
        let start = Date()
        for _ in 0..<5 { _ = await h.host.extensions() }
        let took = Date().timeIntervalSince(start)
        #expect(took < 0.5, "five listings took \(took) s")
        let info = try #require(await h.host.info(id: installed.id))
        #expect(info.tools.contains { !$0.commands.isEmpty }, "and they still show its sentences")
    }

    /// Many commands name one part, in every language: one compile, whichever asks.
    @Test func aPartIsCompiledOnceAndAPhraseSaidInTwoLanguagesIsOnePhrase() throws {
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: JSONSerialization.data(withJSONObject: [
            "id": "dev.test.parts", "name": "Parts", "version": "1.0.0", "sidefolk": ">=0.1", "description": "d", "icon": "icon.pdf", "run": ["command": "bin/x"],
            "parts": ["level": ["say": ["{level:level}"]]], "choices": ["level": ["hard": ["hard"]]],
        ] as [String: Any]))
        var french = ExtensionStrings.Words()
        french.parts["level"] = ["{level:level}"]
        let strings = ExtensionStrings(tables: ["fr": french])
        let v = CommandVocabulary(manifest: manifest, strings: strings)
        let part = try #require(v.compiledPart("level"))
        #expect(part.phrases.count == 1)
        #expect(v.compiledPart("nope") == nil)
    }

    // MARK: No result before the build-up

    private static let program = #"""
    import json, sys
    for line in sys.stdin:
        m = json.loads(line)
        if "id" not in m: continue
        meth, p = m["method"], m.get("params") or {}
        if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "g", "version": "1"}}
        elif meth == "tools/list": r = {"tools": [{"name": "spin", "title": "Spin", "description": "d", "inputSchema": {"type": "object", "properties": {"words": {"type": "string"}}}}]}
        elif meth == "tools/call": r = {"content": [{"type": "text", "text": "Landed: " + json.dumps(p["arguments"])}], "sidefolk": {"hold_answer_ms": 1500, "row": "Spun a wheel"}}
        else: r = {}
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}) + "\n"); sys.stdout.flush()
    """#

    private static func wheel(mutates: Bool = false, extra: [String: JSONValue] = [:]) -> JSONValue {
        ExtFixtures.manifest(id: "dev.test.wheel", tools: ["spin": JSONValue.object(["title": "Spin", "risk": "low", "mutates": .bool(mutates),
                                                                                       "commands": [["say": ["spin the wheel"]]]].merging(extra) { _, own in own })])
    }

    @Test func anAnswerWaitsAsLongAsAnyToolOfTheRunAsked() {
        var hold = AnswerHold()
        let now = Date(timeIntervalSince1970: 1000)
        #expect(hold.remaining(now: now) == 0, "nothing to wait for")
        hold.note(ResultCard(kind: .info, title: "no hold"), now: now)
        #expect(hold.remaining(now: now) == 0)
        var held = ResultCard(kind: .extensionResult, title: "Landed")
        held.holdAnswer = 2
        hold.note(held, now: now)
        #expect(hold.remaining(now: now) == 2)
        #expect(hold.remaining(now: now.addingTimeInterval(3)) == 0, "and it ends")
        held.holdAnswer = 1
        hold.note(held, now: now)
        #expect(hold.remaining(now: now) == 2, "a shorter one doesn't cut a longer one short")
    }

    /// The AI's road: a read-only tool's card is never shown, so its hold has to come from the finished tool whatever it does.
    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aReadOnlyToolsHoldReachesTheAIsAnswer() async throws {
        let h = try HostEnv()
        _ = try await h.host.install(from: try h.source("wheel", manifest: Self.wheel(), files: ["server.py": Self.program]))
        let outcome = await h.env.executor.execute(name: "ext.wheel.spin", input: [:], caller: .agent(runId: "r"))
        #expect(outcome.activity.mutates == false && outcome.activity.card?.holdAnswer == 1.5)
    }

    /// The person's road: what the runner hands Ask carries the hold over, as it builds a card of its own.
    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aCommandsCardKeepsItsHold() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-hold-\(UUID().uuidString)", isDirectory: true)
        let runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: ManualClock(TestEnv.referenceDate))
        let source = try ExtFixtures.makeExtension(at: ExtFixtures.tempDir("hold").appendingPathComponent("wheel"), manifest: Self.wheel(), files: ["server.py": Self.program])
        _ = try await runtime.extensions.install(from: source)
        let runner = LocalIntentRunner(runtime: runtime)
        let parsed = try #require(await runner.parse("spin the wheel"))
        switch await runner.run(parsed.intent) {
        case .answer(let card, _), .card(let card, _, _): #expect(card.holdAnswer == 1.5)
        default: Issue.record("not an answer")
        }
    }

    // MARK: An overlay stays where it is

    @Test func anOverlayThatChangesSizeStaysWhereItStands() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900), anchor = CGRect(x: 1000, y: 200, width: 120, height: 140)
        let flying = SurfacePolicy.place(size: CGSize(width: 240, height: 380), presentation: .overlay, beside: anchor, screen: screen, avoiding: [])
        let landed = SurfacePolicy.resized(flying, to: CGSize(width: 200, height: 220), beside: anchor, screen: screen, avoiding: [])
        #expect(landed?.minY == flying.minY && landed?.midX == flying.midX, "still above the companion, on the same edge")
        // Below it, it keeps its top; what no longer fits or would cover a card is placed anew.
        let below = CGRect(x: 950, y: 20, width: 220, height: 170)
        #expect(SurfacePolicy.resized(below, to: CGSize(width: 220, height: 120), beside: anchor, screen: screen, avoiding: [])?.maxY == below.maxY)
        #expect(SurfacePolicy.resized(flying, to: CGSize(width: 240, height: 800), beside: anchor, screen: screen, avoiding: []) == nil)
        #expect(SurfacePolicy.resized(flying, to: flying.size, beside: anchor, screen: screen, avoiding: [flying.insetBy(dx: 10, dy: 10)]) == nil)
    }

    // MARK: Sentences

    private static func commands(_ command: [String: Any], parts: [String: Any], carry: [String: Any] = [:], choices: [String: Any] = [:]) throws -> (ToolCommands, CommandVocabulary) {
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: JSONSerialization.data(withJSONObject: [
            "id": "dev.test.words", "name": "Words", "version": "1.0.0", "sidefolk": ">=0.1", "description": "d", "icon": "icon.pdf", "run": ["command": "bin/x"],
            "parts": parts, "carry": carry, "choices": choices, "tools": ["go": ["commands": [command]]],
        ] as [String: Any]))
        let v = CommandVocabulary(manifest: manifest, strings: nil)
        let meta = try #require(manifest.tools["go"])
        return (try #require(ToolCommands(meta.commands, vocabulary: v)), v)
    }

    /// A whole sentence with parts around it: as strict as the sentence alone, so its words aren't carrying ones.
    @Test func partsStandAroundAWholeSentence() throws {
        let parts: [String: Any] = ["again": ["say": ["for me", "again"]], "call": ["say": ["i call {side:side}"]]]
        let (go, _) = try Self.commands(["say": ["spin a wheel"], "with": ["again", "call"]], parts: parts, choices: ["side": ["red": ["red"], "blue": ["blue"]]])
        let (many, _) = try Self.commands(["say": ["spin {n:integer:1-5} wheels"], "with": ["again"], "input": ["n": "{n}"]], parts: parts, choices: ["side": ["red": ["red"], "blue": ["blue"]]])
        #expect(go.input(for: "spin a wheel") != nil)
        #expect(go.input(for: "spin a wheel for me") != nil)
        #expect(go.input(for: "spin a wheel, again") != nil)
        #expect(go.input(for: "spin a wheel i call red")?["side"]?.stringValue == "red")
        #expect(many.input(for: "spin 3 wheels for me")?["n"]?.intValue == 3)
        #expect(many.input(for: "again spin 3 wheels")?["n"]?.intValue == 3)
        for no in ["spin wheel for me", "spin a wheel for my friend", "spin a wheel to decide", "for me"] { #expect(go.input(for: no) == nil, "\(no)") }
    }

    /// The companion's name carries a sentence, as a fictional extension's name does; nothing else changes.
    @Test func theCompanionsNameCarriesASentence() throws {
        let (go, _) = try Self.commands(["names": ["marbles"], "with": ["level"]], parts: ["level": ["say": ["{level:level}"]]],
                                        carry: ["words": ["with", "play"], "lead": ["play"]], choices: ["level": ["hard": ["hard"]]])
        #expect(go.input(for: "play marbles with mochi") == nil, "the extension can't know the name")
        #expect(go.input(for: "play marbles with mochi", companion: ["mochi"]) != nil)
        #expect(go.input(for: "mochi play marbles", companion: ["mochi"]) != nil)
        #expect(go.input(for: "mochi marbles", companion: ["mochi"]) == nil, "a bare name still needs a word saying it is meant")
        #expect(go.input(for: "play marbles with pip", companion: ["mochi"]) == nil)
    }

    @Test func theParserPassesTheCompanionsNames() throws {
        let (go, _) = try Self.commands(["names": ["marbles"]], parts: [:], carry: ["words": ["with", "play"], "lead": ["play"]])
        let tool = ExtensionTool(spec: ToolSpec(name: "ext.words.go", title: "Go", description: "d", inputSchema: Schema.object([:]), risk: .low, capabilities: [], category: .extensions, mutates: false),
                                 extensionId: "dev.test.words", extensionName: "Words", remoteName: "go", commands: go) { _, _ in ToolResult(text: "ok") }
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test", companionNames: ["sidefolk", "pip", "Mochi"], commandTools: [tool])
        if case .extensionCommand? = parser.parse("play marbles with mochi", now: TimeTest.wednesday10)?.intent {} else { Issue.record("named companion") }
        #expect(parser.parse("play marbles with tom", now: TimeTest.wednesday10) == nil)
    }

    // MARK: Settings that follow another

    private static let followers: JSONValue = [
        ["key": "all", "type": "switch", "title": "All", "default": false],
        ["key": "one", "type": "switch", "title": "One", "follows": "all", "listed": false],
        ["key": "two", "type": "switch", "title": "Two", "follows": "all", "listed": false],
    ]

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func oneChoiceForAllIsOneWriteAndClearsWhatEachHadChosen() async throws {
        let h = try HostEnv()
        let manifest = ExtFixtures.manifest(id: "dev.test.follow", tools: ["spin": ["title": "Spin", "risk": "low"]], extra: ["settings": Self.followers])
        let info = try await h.host.install(from: try h.source("follow", manifest: manifest, files: ["server.py": Self.program]))
        func value(_ key: String) -> Bool? { h.host.shelf.settings.first { $0.key == key }?.value.boolValue }
        #expect(value("one") == false)
        _ = try await h.host.setSetting(extensionId: info.id, key: "all", value: true)
        #expect(value("one") == true && value("two") == true, "it reads the one it follows")
        _ = try await h.host.setSetting(extensionId: info.id, key: "one", value: false)
        #expect(value("one") == false && value("two") == true && value("all") == true, "a change of its own is its own")
        _ = try await h.host.setSetting(extensionId: info.id, key: "all", value: false)
        _ = try await h.host.setSetting(extensionId: info.id, key: "all", value: true)
        #expect(value("one") == true, "and a change to all clears it")
        let wrong: JSONValue = [["key": "a", "type": "switch", "title": "A", "follows": "b"], ["key": "b", "type": "choice", "title": "B", "options": [["value": "x", "title": "X"], ["value": "y", "title": "Y"]]],
                                ["key": "c", "type": "switch", "title": "C", "follows": "nope"], ["key": "d", "type": "switch", "title": "D", "follows": "d"]]
        let bad = try h.source("wrong", manifest: ExtFixtures.manifest(id: "dev.test.wrong", tools: ["spin": ["title": "Spin", "risk": "low"]], extra: ["settings": wrong]), files: ["server.py": Self.program])
        let errors = ManifestValidator(paths: h.paths).validate(folder: bad).errors.map(\.field).filter { $0.hasSuffix(".follows") }
        #expect(errors.count == 3, "\(errors)")
    }

    // MARK: Free words after outside content

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aTrustedOnlyArgumentGoesInATaintedTurnAndOnlyThere() async throws {
        let h = try HostEnv()
        let manifest = Self.wheel(extra: ["trusted_only": ["words"]])
        _ = try await h.host.install(from: try h.source("wheel", manifest: manifest, files: ["server.py": Self.program]))
        let tool = try #require(h.env.registry.tool(named: "ext.wheel.spin") as? ExtensionTool)
        func said(_ caller: Caller, tainted: Bool) async throws -> String {
            try await tool.run(["words": "free"], context: ToolContext(caller: caller, now: Date(), tainted: tainted, folders: [], site: nil)).text
        }
        #expect(try await said(.agent(runId: "r"), tainted: false).contains("free"), "a clean turn")
        #expect(try await said(.user, tainted: true).contains("free"), "the person's own")
        #expect(try await said(.command(extensionId: "dev.test.wheel"), tainted: true).contains("free"))
        #expect(!(try await said(.agent(runId: "r"), tainted: true).contains("free")), "after outside content")
        #expect(!(try await said(.external(client: "c"), tainted: true).contains("free")))
        let bad = try h.source("bad", manifest: ExtFixtures.manifest(id: "dev.test.bad", tools: ["spin": ["title": "Spin", "risk": "low", "trusted_only": ["Not A Name"]]]), files: ["server.py": Self.program])
        #expect(ManifestValidator(paths: h.paths).validate(folder: bad).errors.contains { $0.field.hasSuffix("trusted_only") })
    }

    // MARK: History

    /// A signed pack's reply says what happened; nobody else's is believed; and a surface a tool opened has no row of its own.
    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aRowIsTheToolsOwnAndOnlyOneRow() async throws {
        let h = try HostEnv()
        _ = try await h.host.install(from: try h.source("wheel", manifest: Self.wheel(), files: ["server.py": Self.program]), origin: .official)
        #expect((await h.env.executor.execute(name: "ext.wheel.spin", input: [:], caller: .user)).activity.summary == "Spun a wheel")
        let plain = try HostEnv()
        _ = try await plain.host.install(from: try plain.source("wheel", manifest: Self.wheel(), files: ["server.py": Self.program]))
        #expect((await plain.env.executor.execute(name: "ext.wheel.spin", input: [:], caller: .user)).activity.summary != "Spun a wheel")

        let surface = SurfaceInfo(extensionId: "dev.test.wheel", extensionName: "Wheel", surface: "board", title: "Board")
        let shelf = SurfaceShelf()
        shelf.set([surface])
        let open = SurfacesOpenTool(events: h.env.events, shelf: shelf)
        let input: JSONValue = ["surface": .string(surface.id)]
        #expect(open.leavesNoRow(for: input, caller: .extension(id: "dev.test.wheel")))
        #expect(!open.leavesNoRow(for: input, caller: .extension(id: "dev.test.other")))
        #expect(!open.leavesNoRow(for: input, caller: .user))
        #expect(!open.leavesNoRow(for: input, caller: .agent(runId: "r")))
    }

    // MARK: A scene with no sound

    @Test func aSceneCanSayItHasNoSpeaker() throws {
        let plain = try SurfaceScene.parse(["size": [200, 100], "nodes": []])
        #expect(!plain.hidesSpeaker)
        let silent = try SurfaceScene.parse(["size": [200, 100], "nodes": [], "speaker": false])
        #expect(silent.hidesSpeaker && silent.speaker == nil)
        let named = try SurfaceScene.parse(["size": [200, 100], "nodes": [], "speaker": "sounds"])
        #expect(!named.hidesSpeaker && named.speaker == "sounds")
    }

    // MARK: Pacing

    @Test func burstsAndPropsArePaced() {
        var limiter = CueLimiter()
        let now = Date(timeIntervalSince1970: 1000)
        let first = limiter.burst(at: now), soon = limiter.burst(at: now.addingTimeInterval(0.05)), later = limiter.burst(at: now.addingTimeInterval(CueLimiter.accentGap + 0.01))
        #expect(first && later)
        #expect(!soon, "a throw every 50 ms is dropped")
        let free = limiter.prop(at: now), waits = limiter.prop(at: now.addingTimeInterval(0.05)), turn = limiter.prop(at: now.addingTimeInterval(CueLimiter.accentGap + 0.01))
        #expect(free == 0 && turn == 0)
        #expect(waits > 0, "it waits, and the newest wins")
    }

    // MARK: Page parts an extension dresses

    @Test func pagePartsCarryWhatTheyAreGivenAndDropWhatIsOff() throws {
        let json: JSONValue = ["sections": [
            ["blocks": [["type": "hero", "title": "H", "symbol": "bird", "tile": ["#112233", "#445566", "#778899"], "wash": ["nope"], "figure": ["companion": "full"], "says": "Hi",
                         "actions": [["type": "button", "label": "Go", "tool": "go", "style": "primary"]]]]],
            ["title": "Banded", "detail": "A day", "banner": ["tint": "#112233", "symbol": "bird"], "wide": true, "blocks": [
                ["type": "stats", "items": [["label": "L", "value": "1", "color": "#FFC93C"], ["label": "M", "value": "2", "color": "red"]]],
                ["type": "cards", "items": [["title": "C", "actions": [["type": "button", "label": "Back to it", "tool": "go", "style": "accent"], ["type": "button", "label": "Run", "tool": "go", "symbol": "play.fill", "shape": "round"]]]]],
                ["type": "settings", "keys": ["a", "b"], "grid": true, "pictures": ["a": ["pack": "art/a.png"], "z": ["pack": "art/z.png"]], "ai": true, "ai_title": "Own words", "ai_detail": "More"],
            ]],
            ["title": "No band", "banner": ["tint": "red"], "blocks": [["type": "note", "text": "x"]]],
        ]]
        let page = try ExtensionPage.parse(json)
        guard case .hero(let hero)? = page.sections[0].blocks.first else { Issue.record("no hero"); return }
        #expect(hero.tile == ["#112233", "#445566"] && hero.wash.isEmpty, "two at most, and what isn't a colour goes")
        let banded = page.sections[1]
        #expect(banded.banner?.tint == "#112233" && banded.wide && banded.detail == "A day")
        #expect(page.sections[2].banner == nil && !page.sections[2].wide)
        guard case .stats(let stats) = banded.blocks[0], case .cards(let cards) = banded.blocks[1], case .settings(let rows) = banded.blocks[2] else { Issue.record("parts"); return }
        #expect(stats.items.map(\.color) == ["#FFC93C", nil])
        #expect(cards.items[0].actions[0].style == .accent && cards.items[0].actions[1].round)
        #expect(cards.items[0].actions[0].style != .primary, "it isn't the page's one primary, which stays the hero's")
        guard case .hero(let kept)? = page.sections[0].blocks.first else { return }
        #expect(kept.actions[0].style == .primary)
        #expect(rows.grid && rows.pictures.keys.sorted() == ["a"] && rows.aiTitle == "Own words" && rows.aiDetail == "More")
    }

    @Test func aSectionWideByItsOwnSay() {
        let plain = ExtensionPage.Section(title: "S", blocks: [.settings(ExtensionPage.SettingsRows(title: nil, keys: [], ai: false))])
        #expect(!plain.isWide)
        var wide = plain
        wide.wide = true
        #expect(wide.isWide)
    }

    @Test func aSegmentedSettingIsForAFewChoices() throws {
        let h = try HostEnv()
        func options(_ n: Int) -> JSONValue { .array((0..<n).map { ["value": .string("v\($0)"), "title": .string("V\($0)")] }) }
        let good: JSONValue = [["key": "a", "type": "choice", "title": "A", "options": options(3), "segmented": true]]
        let long: JSONValue = [["key": "a", "type": "choice", "title": "A", "options": options(6), "segmented": true], ["key": "b", "type": "switch", "title": "B", "segmented": true]]
        func errors(_ settings: JSONValue, _ name: String) throws -> [String] {
            let source = try h.source(name, manifest: ExtFixtures.manifest(id: "dev.test.\(name)", tools: ["spin": ["title": "Spin", "risk": "low"]], extra: ["settings": settings]), files: ["server.py": Self.program])
            return ManifestValidator(paths: h.paths).validate(folder: source).errors.map(\.field).filter { $0.hasSuffix("segmented") }
        }
        #expect(try errors(good, "good").isEmpty)
        #expect(try errors(long, "long").count == 2)
    }

    // MARK: The install sheet's count

    @Test func aPermissionThatGrantsNothingIsntCounted() {
        func review(_ p: ExtensionPermissions) -> InstallReview {
            InstallReview(source: .folder, tone: .careful, lines: PermissionSummary.forExtension(p).lines, cautions: [], update: nil, next: [])
        }
        #expect(review(ExtensionPermissions()).granted == 0, "“No access to your files” is the opposite of a permission")
        #expect(review(ExtensionPermissions(network: true)).granted == 1)
    }

    // MARK: A card that settles

    /// Above, a card has its tail and is 8 points taller; under the companion it isn't. Near the screen's top, judged by its size just now, it flipped for ever and took the app down.
    @Test func aCardNearTheTopOfTheScreenSettles() {
        let tail: CGFloat = 8, screenTop: CGFloat = 950, plain: CGFloat = 284
        for top in stride(from: CGFloat(600), through: 700, by: 1) {
            var showing = true, changes = 0
            for _ in 0..<40 {
                let above = CardPlacement.standsAbove(top: top, height: plain + (showing ? tail : 0), roomAbove: showing ? 0 : tail, screenTop: screenTop)
                if above != showing { changes += 1 }
                showing = above
            }
            #expect(changes <= 1, "at \(top): \(changes) changes")
        }
        // At the height that crashed: the anchor's top less the gap, as measured from a real crash.
        #expect(!CardPlacement.standsAbove(top: 661.8, height: 284, roomAbove: 8, screenTop: 950), "without its tail it fits, with it it wouldn't: it stands under")
        #expect(CardPlacement.standsAbove(top: 600, height: 292, roomAbove: 0, screenTop: 950))
    }

    // MARK: Carrying once, for good

    /// Removing it leaves nothing, and installing it again doesn't bring back numbers from before: what was carried is gone from the app, and not carried twice.
    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func whatWasCarriedDoesNotComeBackOnReinstall() async throws {
        let forgotten = LockedList(), asked = LockedList()
        let row = ActivityEntry(at: Date(timeIntervalSince1970: 1000), caller: "user", tool: "old.play", risk: "low", decision: .auto, summary: "Played", args: nil)
        let h = try HostEnv {
            $0.carriedStore = { name in asked.add(name); return ["wins": 7] }
            $0.forgetCarriedStore = { forgotten.add($0) }
            $0.carriedHistory = { name in asked.add(name); return [row] }
        }
        let program = #"""
        import json, sys
        for line in sys.stdin:
            m = json.loads(line)
            if "id" not in m: continue
            meth = m["method"]
            if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "g", "version": "1"}}
            elif meth == "tools/list": r = {"tools": [{"name": "spin", "title": "Spin", "description": "d", "inputSchema": {"type": "object"}}]}
            elif meth == "tools/call": r = {"content": [{"type": "text", "text": "ok"}]}
            else: r = {}
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}) + "\n"); sys.stdout.flush()
        """#
        let manifest = ExtFixtures.manifest(id: "dev.test.carry", tools: ["spin": ["title": "Spin", "risk": "low"]], extra: ["carries": ["store": ["old.score"], "history": ["old.play"]]])
        let source = try h.source("carry", manifest: manifest, files: ["server.py": program])
        let first = try await h.host.install(from: source, origin: .official)
        _ = await h.call("ext.carry.spin")
        try await Task.sleep(for: .milliseconds(400))
        #expect(asked.items.contains("old.score") && asked.items.contains("old.play"))
        #expect(forgotten.items == ["old.score"], "nothing of it is left in the app")
        let before = asked.items.count

        try await h.host.uninstall(id: first.id)
        _ = try await h.host.install(from: source, origin: .official)
        _ = await h.call("ext.carry.spin")
        try await Task.sleep(for: .milliseconds(400))
        #expect(asked.items.count == before, "installed again, it starts clean: \(asked.items)")
    }
}

private final class LockedList: Sendable {
    private let list = Mutex<[String]>([])
    func add(_ s: String) { list.withLock { $0.append(s) } }
    var items: [String] { list.withLock { $0 } }
}
