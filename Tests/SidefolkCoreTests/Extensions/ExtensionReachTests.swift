import Foundation
import Testing
@testable import SidefolkCore

/// What a flow can reach beyond what was there before (D127 to D129): a whole job for the companion, Focus and Quiet, and hearing what happens.
@Suite("An extension's wider reach", .serialized)
struct ExtensionReachTests {
    private static let listener = """
    import json, os, sys
    def send(o): sys.stdout.write(json.dumps(o) + "\\n"); sys.stdout.flush()
    for line in sys.stdin:
        m = json.loads(line)
        if m.get("method") == "initialize":
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "t", "version": "1"}}})
        elif m.get("method") == "tools/list":
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"tools": [{"name": "heard", "description": "", "inputSchema": {"type": "object", "properties": {}}}]}})
        elif m.get("method") == "sidefolk/happened":
            open(os.path.join(os.environ["SIDEFOLK_DATA_DIR"], "heard.json"), "w").write(json.dumps(m["params"]))
        elif m.get("method") == "tools/call":
            path = os.path.join(os.environ["SIDEFOLK_DATA_DIR"], "heard.json")
            words = open(path).read() if os.path.exists(path) else "nothing"
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"content": [{"type": "text", "text": words}]}})
        elif "id" in m:
            send({"jsonrpc": "2.0", "id": m["id"], "result": {}})
    """

    private func heard(_ permissions: JSONValue, name: String) async throws -> String {
        let h = try HostEnv()
        let manifest: JSONValue = ["id": .string("com.example.\(name)"), "name": .string(name), "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]],
                                   "permissions": permissions, "tools": ["heard": ["title": "Heard", "risk": "low", "mutates": false]]]
        try await h.host.install(from: h.source(name, manifest: manifest, files: ["server.py": Self.listener]))
        _ = await h.call("ext.\(name).heard")
        await h.host.tell(Happening(name: "reminder.fired", title: "Call the bank"))
        for _ in 0..<40 {
            if let text = (await h.call("ext.\(name).heard")).okText, text != "nothing" { return text }
            try await Task.sleep(for: .milliseconds(50))
        }
        return ""
    }

    @Test func anExtensionThatCantReachOutHearsTheWords() async throws {
        let words = try await heard(["events": ["purpose": "to start what you set up"]], name: "inside")
        #expect(words.contains("reminder.fired"))
        #expect(words.contains("Call the bank"))
    }

    @Test func oneThatCanReachOutHearsTheWordsToo() async throws {
        let words = try await heard(["network": true, "network_purpose": "to look things up", "events": ["purpose": "to start what you set up"]], name: "outside")
        #expect(words.contains("reminder.fired"))
        #expect(words.contains("Call the bank"), "the founder's choice (D129)")
    }

    @Test func withoutThePermissionNothingIsHeard() async throws {
        let h = try HostEnv()
        let manifest: JSONValue = ["id": "com.example.deaf", "name": "deaf", "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]],
                                   "tools": ["heard": ["title": "Heard", "risk": "low", "mutates": false]]]
        try await h.host.install(from: h.source("deaf", manifest: manifest, files: ["server.py": Self.listener]))
        _ = await h.call("ext.deaf.heard")
        await h.host.tell(Happening(name: "reminder.fired", title: "Call the bank"))
        try await Task.sleep(for: .milliseconds(200))
        #expect((await h.call("ext.deaf.heard")).okText == "nothing")
    }

    @Test func whatAnExtensionDidDoesntCountAsSomethingHappening() {
        func activity(_ caller: Caller, _ tool: String) -> ToolActivity { ToolActivity(id: "a", tool: tool, title: tool, summary: "Saved", category: .notes, caller: caller) }
        #expect(Happening(activity(.user, "notes.save"))?.name == "note.saved")
        #expect(Happening(activity(.agent(runId: "r"), "reminders.create"))?.name == "reminder.created")
        #expect(Happening(activity(.extension(id: "com.example.a"), "notes.save")) == nil, "or a flow could set itself off")
        #expect(Happening(activity(.user, "web.fetch")) == nil)
    }

    @Test func theInstallSheetSaysItHearsAndWhetherItGetsTheWords() {
        let inside = PermissionSummary.forExtension(ExtensionPermissions(events: ExtensionPurpose(purpose: "to start what you set up")))
        let line = inside.lines.first { $0.kind == .events }
        #expect(line?.caution == true)
        #expect(line?.note?.contains("titles") == true)
        let outside = PermissionSummary.forExtension(ExtensionPermissions(network: true, events: ExtensionPurpose(purpose: "to start what you set up")))
        #expect(outside.lines.first { $0.kind == .events }?.note?.contains("could send them on") == true, "and the install sheet says so")
    }

    @Test func aPlanCantStandOnAnUpdateThatAddsHearing() throws {
        #expect(ExtensionPermissions(events: ExtensionPurpose(purpose: "to x")).widens(ExtensionPermissions()))
    }

    @Test func focusAndQuietAlwaysEnd() async throws {
        let env = try TestEnv()
        let settings = await SettingsStore(db: env.db, events: env.events)
        let attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        let tool = AttentionSetTool(settings: settings, attention: attention, events: env.events)
        let context = ToolContext(caller: .user, now: Date())
        await #expect(throws: (any Error).self) { _ = try await tool.run(["mode": "quiet"], context: context) }
        await #expect(throws: (any Error).self) { _ = try await tool.run(["mode": "focus", "minutes": 100_000], context: context) }
        _ = try await tool.run(["mode": "quiet", "minutes": 30], context: context)
        #expect(settings.current.quietUntil != nil)
        #expect(settings.current.quietUntil != Date.distantFuture)
        _ = try await tool.run(["mode": "open"], context: context)
        #expect(settings.current.quietUntil == nil)
    }

    @Test func focusAndQuietMayStandOnAPlanButOnlyWrittenOut() async throws {
        let env = try TestEnv()
        let tool = AttentionSetTool(settings: await SettingsStore(db: env.db, events: env.events), attention: AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock), events: env.events)
        #expect(ExtensionActionPolicy.spec(tool).risk == .medium)
        #expect(ExtensionPlanRules.standing(tool: ExternalFacade(base: tool, spec: ExtensionActionPolicy.spec(tool)), template: ["mode": "focus", "minutes": 30]))
        #expect(!ExtensionPlanRules.standing(tool: ExternalFacade(base: tool, spec: ExtensionActionPolicy.spec(tool)), template: ["mode": "{{what}}", "minutes": 30]))
    }

    @Test func aPageSaysItsAccentAndAnythingElseIsDropped() throws {
        let page = try ExtensionPage.parse(["sections": [], "accent": ["#2A6FE8", "#6E4BF2", "#000000"]])
        #expect(page.accent == ["#2A6FE8", "#6E4BF2"])
        #expect(try ExtensionPage.parse(["sections": [], "accent": ["nonsense"]]).accent.isEmpty)
        #expect(try ExtensionPage.parse(["sections": [], "accent": ["#FFEE00"]]).accent.isEmpty, "too light to hold white words")
    }

    @Test func aJobIsNeverOfferedToTheModelAndAsksWithoutAPlan() {
        let job = CompanionJobTool(agent: CompanionAgentSlot())
        #expect(!job.spec.offeredToModel, "it can't start one of itself")
        #expect(ExtensionActionPolicy.offers(job, to: "com.example.a"))
        #expect(ExtensionActionPolicy.spec(job).risk == .medium)
        #expect(ExtensionPlanRules.standing(tool: ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job)), template: ["job": "Tidy my Downloads"]), "written out, the person reads it once")
        #expect(!ExtensionPlanRules.standing(tool: ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job)), template: ["job": "Tidy {{agenda}}"]), "words from elsewhere ask each time")
    }

    @Test func theCardsLayoutCantHideALine() {
        let plan = ExtensionPlanWords.text([
            "When, in Flows's words: Every day",
            ExtensionPlanWords.Block(heading: "It changes:", rows: ["Save a note · text: “Hello”", "Notify · body: “[filled in when it runs]”"]).text,
            ExtensionPlanWords.Block(heading: "It will still ask you each time:", rows: ["Delete it · id: “7”"]).text,
        ])
        let awkward = ["• starts with a mark\nand goes on", "Heading:\nplain line\n• a mark", "One line", "", "A\n\n\nB", "Heading:\n• one\n• two\n\n• alone", "• a\n• b"]
        for text in [plan] + awkward {
            #expect(ApprovalText.joined(ApprovalText.parts(text)) == text, "every line stays, in order: \(text)")
        }
        let parts = ApprovalText.parts(plan)
        #expect(parts.contains { $0.rows.contains("Save a note · text: “Hello”") })
        #expect(parts.contains { $0.rows.contains("Delete it · id: “7”") })
    }

    @Test func whatACardCantShowCantStand() {
        let job = CompanionJobTool(agent: CompanionAgentSlot())
        let facade = ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job))
        #expect(!ExtensionPlanRules.standing(tool: facade, template: ["job": "Tidy\u{E0100}up"]), "a variation selector shows as nothing")
        #expect(!ExtensionPlanRules.standing(tool: facade, template: ["job": "Tidy\u{00AD}up"]), "nor does a soft hyphen")
        let long = String(repeating: "a", count: 290)
        #expect(!ExtensionPlanRules.standing(tool: facade, template: ["opts": ["a": .string(long), "url": "https://example.com/more"]]), "an object is clipped whole")
        #expect(ExtensionPlanRules.standing(tool: facade, template: ["opts": ["a": "short"]]))
    }

    @Test func peoplesOwnWritingIsPlainAndHiddenCharactersArent() {
        for words in ["Tidy up ❤️ today", "👩‍💻 at work", "❤️‍🔥 hot", "می‌خواهم", "क्‍ष", "Hello"] { #expect(ExtensionPlanRules.plain(words), "\(words)") }
        for words in ["a\u{200D}", "\u{200D}a", "a\u{200D}\u{200D}b", "a\u{200C} b", "\u{FE0F}a", "a\u{FE0F}\u{FE0F}b", "a\u{00AD}b", "a\u{E0100}b", "a\u{202E}b", "a\u{200B}b"] {
            #expect(!ExtensionPlanRules.plain(words), "\(words.unicodeScalars.map { String($0.value, radix: 16) })")
        }
    }

    @Test func aJobThatWouldBeRefusedDoesntStand() {
        let job = CompanionJobTool(agent: CompanionAgentSlot())
        let facade = ExternalFacade(base: job, spec: ExtensionActionPolicy.spec(job))
        #expect(!ExtensionPlanRules.standing(tool: facade, template: ["job": .string(String(repeating: "a", count: CompanionJobTool.longest + 1))]))
        #expect(ExtensionPlanRules.standing(tool: facade, template: ["job": .string(String(repeating: "a", count: CompanionJobTool.longest))]))
    }

    @Test func aFailedJobNobodyReadStaysMarkedAsOutsideWords() async throws {
        let (world, runtime, _) = try await world([.failure(UserFacingError("No."))])
        let job = await runtime.submit(AgentRequest(text: "Tidy up", job: AgentRequest.Job(read: false)))
        for await _ in job.events {}
        let first = try await world.exchanges.conversation(job.threadId).first
        #expect(first?.meta?["tainted"]?.boolValue == true)
    }

    @Test func aJobThatsTooLongOrHidesCharactersIsRefused() async throws {
        let tool = CompanionJobTool(agent: CompanionAgentSlot())
        let context = ToolContext(caller: .user, now: Date())
        await #expect(throws: (any Error).self) { _ = try await tool.run(["job": .string(String(repeating: "a", count: CompanionJobTool.longest + 1))], context: context) }
        await #expect(throws: (any Error).self) { _ = try await tool.run(["job": "Tidy\u{202E}up"], context: context) }
    }

    @Test func whatAJobDoesDoesntCountAsSomethingHappening() {
        let activity = ToolActivity(id: "a", tool: "notes.save", title: "x", summary: "Saved", category: .notes, caller: .agent(runId: AgentRuntime.jobPrefix + "1"))
        #expect(Happening(activity) == nil)
    }

    @Test func aSearchWithWordsFilledInMayStand() throws {
        let env = try TestEnv()
        let probe = ProbeTool(name: "notes.search", risk: .low, capabilities: [.notebook], result: { _ in ToolResult(text: "") })
        env.registry.register(probe)
        #expect(ExtensionPlanRules.standing(tool: ExternalFacade(base: probe, spec: ExtensionActionPolicy.spec(probe)), template: ["query": "{{trigger}}"]), "the founder's choice (D127)")
    }

    @Test func aCommandsAnswerStaysOutOfHistoryForOneThatCouldHoldThePersonsWords() async throws {
        let answer = """
        import json, sys
        def send(o): sys.stdout.write(json.dumps(o) + "\\n"); sys.stdout.flush()
        for line in sys.stdin:
            m = json.loads(line)
            if m.get("method") == "initialize":
                send({"jsonrpc": "2.0", "id": m["id"], "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "t", "version": "1"}}})
            elif m.get("method") == "tools/list":
                send({"jsonrpc": "2.0", "id": m["id"], "result": {"tools": [{"name": n, "description": "", "inputSchema": {"type": "object", "properties": {}}} for n in ("say", "fails", "breaks")]}})
            elif m.get("method") == "tools/call" and m["params"]["name"] == "breaks":
                send({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32000, "message": "the answer"}})
            elif m.get("method") == "tools/call":
                send({"jsonrpc": "2.0", "id": m["id"], "result": {"content": [{"type": "text", "text": "the answer"}], "isError": m["params"]["name"] == "fails"}})
            elif "id" in m:
                send({"jsonrpc": "2.0", "id": m["id"], "result": {}})
        """
        let purpose: JSONValue = ["purpose": "to test"]
        for (name, permissions, kept) in [("plain", JSONValue.object([:]), true), ("acting", ["act": purpose], false), ("hearing", ["events": purpose], false)] {
            let h = try HostEnv()
            let manifest: JSONValue = ["id": .string("com.example.\(name)"), "name": .string(name), "version": "1.0.0", "run": ["command": "python3", "args": ["server.py"]],
                                       "permissions": permissions, "tools": ["say": ["title": "Say", "risk": "low", "mutates": false], "fails": ["title": "Fails", "risk": "low", "mutates": false], "breaks": ["title": "Breaks", "risk": "low", "mutates": false]]]
            try await h.host.install(from: h.source(name, manifest: manifest, files: ["server.py": answer]))
            let out = await h.env.executor.execute(name: "ext.\(name).say", input: .object([:]), caller: .command(extensionId: "com.example.\(name)"))
            #expect(out.okText == "the answer", "\(name)")
            let row = try await h.env.activity.recent(limit: 1, tool: "ext.\(name).say").first
            #expect(row?.outcome?.contains("the answer") == kept, "\(name): \(row?.outcome ?? "")")
            // Nor as a failure, whichever way it fails.
            for failing in ["fails", "breaks"] {
                _ = await h.env.executor.execute(name: "ext.\(name).\(failing)", input: .object([:]), caller: .command(extensionId: "com.example.\(name)"))
                let failed = try await h.env.activity.recent(limit: 1, tool: "ext.\(name).\(failing)").first
                #expect(failed?.decision == .failed, "\(name) \(failing)")
                #expect(failed?.error?.contains("the answer") == kept, "\(name) \(failing): \(failed?.error ?? "")")
            }
        }
    }

    @Test func aStepThatFilledWordsInIsKeptAsWritten() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "test.probe", risk: .low, result: { _ in ToolResult(text: "Found: note words") }))
        env.registry.register(ProbeTool(name: "test.failing", risk: .low, result: { _ in ToolResult(text: "Couldn't use note words", isError: true) }))
        _ = await env.executor.execute(name: "test.probe", input: ["x": "note words"], caller: .extension(id: "e"), standing: true, written: ["x": "{{found}}"])
        let row = try #require(try await env.activity.recent(limit: 1, tool: "test.probe").first)
        #expect(row.summary == "Probe {{found}}")
        #expect(row.args?["x"]?.stringValue == "{{found}}")
        #expect(row.outcome?.contains("10") == true)
        _ = await env.executor.execute(name: "test.failing", input: ["x": "note words"], caller: .extension(id: "e"), standing: true, written: ["x": "{{found}}"])
        let failed = try #require(try await env.activity.recent(limit: 1, tool: "test.failing").first)
        let kept = [row, failed].flatMap { [$0.summary, $0.args?.jsonString, $0.outcome, $0.error] }.compactMap { $0 }.joined()
        #expect(!kept.contains("note words"), "\(kept)")
    }

    @Test func aNoticeAStepFilledInStaysOutOfHistoryAndStillShows() async throws {
        let env = try TestEnv()
        var context = ToolContext(caller: .extension(id: "com.example.routines"), now: Date())
        context.filledIn = true
        let attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        _ = try await NotifyUserTool(attention: attention).run(["title": "Standup", "body": "note words"], context: context)
        let item = try #require(await attention.open().first)
        #expect(item.body == "note words", "it still shows, on the desktop and in Today")
        let history = HistoryTimeline.merge(activity: [], conversations: [], alerts: [item], sessions: [])
        guard case .alert(let shown)? = history.first?.kind else { Issue.record("no row"); return }
        #expect(shown.body == nil)
        #expect(!shown.title.contains("Standup"))
        #expect(shown.title.contains("a notice"))
        let row = try #require(history.first)
        #expect(!HistoryTimeline.shows(row, filter: .all, query: "words"), "search doesn't find what it filled in")
        #expect(!HistoryTimeline.shows(row, filter: .all, query: "Standup"))
        #expect(HistoryTimeline.shows(row, filter: .all, query: "notice"))
    }

    @Test func theCardThatSumsUpHeldNoticesKeepsTheirWordsOutOfHistory() async throws {
        let env = try TestEnv()
        let attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        await attention.update { $0.away = true }
        for title in ["first words", "second words"] {
            _ = await attention.post(AttentionRequest(level: .attention, source: "extension:e", title: title, refKind: "notify", historyTitle: "E: a notice"))
        }
        await attention.update { $0.away = false }
        var items: [AttentionItem] = []
        for _ in 0..<60 where !items.contains(where: { $0.source == "summary" }) {
            try await Task.sleep(for: .milliseconds(50))
            items = try await AttentionStore(env.db).recent()
        }
        #expect(items.contains { $0.source == "summary" }, "the card that sums them up")
        let history = HistoryTimeline.merge(activity: [], conversations: [], alerts: items, sessions: [])
        for row in history { #expect(!HistoryTimeline.shows(row, filter: .all, query: "words"), "\(row.searchable)") }
    }

    @Test func aRefusalKeepsItsReasonWhenWordsWereFilledIn() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "test.refused", risk: .high, result: { _ in ToolResult(text: "") }))
        let answer = env.autoAnswer(.deny)
        _ = await env.executor.execute(name: "test.refused", input: ["x": "note words"], caller: .extension(id: "e"), written: ["x": "{{found}}"])
        _ = await answer.value
        let row = try #require(try await env.activity.recent(limit: 1, tool: "test.refused").first)
        #expect(row.decision == .denied)
        #expect(row.error?.contains("reported a problem") == false, "\(row.error ?? "")")
        #expect(row.args?["x"]?.stringValue == "{{found}}")
    }

    @Test func whoseWordsHistoryLeavesOut() {
        let purpose = ExtensionPurpose(purpose: "to test")
        var permissions = ExtensionPermissions()
        #expect(!ExtensionHost.holdsThePersonsWords(permissions))
        permissions.clipboard = true
        #expect(ExtensionHost.holdsThePersonsWords(permissions))
        permissions = ExtensionPermissions()
        permissions.act = purpose
        #expect(ExtensionHost.holdsThePersonsWords(permissions))
        permissions = ExtensionPermissions()
        permissions.events = purpose
        #expect(ExtensionHost.holdsThePersonsWords(permissions))
    }

    @Test func aReminderFilledInMayNotHoldNotesAndAProgramsWordIsBounded() throws {
        let env = try TestEnv()
        let probe = ProbeTool(name: "reminders.create", risk: .low, result: { _ in ToolResult(text: "") })
        env.registry.register(probe)
        let facade = ExternalFacade(base: probe, spec: ExtensionActionPolicy.spec(probe))
        #expect(ExtensionPlanRules.standing(tool: facade, template: ["title": "{{x}}"]))
        #expect(!ExtensionPlanRules.standing(tool: facade, template: ["notes": "{{x}}"]), "they'd show in History when it fires")
        let short: JSONValue = ["title": "{{x}}"]
        #expect(ExtensionPlanRules.readable(written: short, for: ["title": "words"], tool: "notify.user"))
        #expect(!ExtensionPlanRules.readable(written: .object(["title": .string("{{x}}" + String(repeating: "a", count: 400))]), for: ["title": "words"], tool: "notify.user"))
        #expect(!ExtensionPlanRules.readable(written: short, for: .object(["title": .string(String(repeating: "a", count: 70_000))]), tool: "notify.user"))
    }

    @Test func aPlansCardKeepsTheSpacesAroundWhatItFillsIn() throws {
        let probe = ProbeTool(name: "notify.user", risk: .low, result: { _ in ToolResult(text: "") })
        let line = ExtensionPlanWords.line(tool: probe, template: ["body": "Got {{m}} and {{s}}"])
        #expect(line.contains("Got [filled in when it runs] and [filled in when it runs]"), "\(line)")
    }

    @Test func aLineIsSaidWithItsExtensionsNameAndNotInFocusOrQuiet() async throws {
        let env = try TestEnv()
        let settings = await SettingsStore(db: env.db, events: env.events)
        let tool = VoiceSayTool(settings: settings, events: env.events)
        let stream = env.events.stream()
        _ = try await tool.run(["text": "Time to stretch"], context: ToolContext(caller: .extension(id: "com.example.a"), now: Date()))
        var said: String?
        for await event in stream { if case .speak(let line) = event { said = line; break } }
        #expect(said?.contains("Time to stretch") == true)
        #expect(said?.contains("com.example.a says") == true, "a voice can't carry a name any other way: \(said ?? "")")
        await settings.update { $0.quietUntil = Date().addingTimeInterval(600) }
        let quiet = try await tool.run(["text": "Hello"], context: ToolContext(caller: .user, now: Date()))
        #expect(quiet.text.contains("Not said"))
        await settings.update { $0.quietUntil = nil; $0.focusUntil = Date().addingTimeInterval(600) }
        let focused = try await tool.run(["text": "Hello"], context: ToolContext(caller: .user, now: Date()))
        #expect(focused.text.contains("Not said"))
        await settings.update { $0.focusUntil = nil }
        let stream2 = env.events.stream()
        let run = AgentRuntime.jobRunId("1", extensionId: "com.example.a")
        _ = try await tool.run(["text": "Time to stretch"], context: ToolContext(caller: .agent(runId: run), now: Date()))
        var fromAJob: String?
        for await event in stream2 { if case .speak(let line) = event { fromAJob = line; break } }
        #expect(fromAJob?.contains("com.example.a says") == true, "a job an extension handed over says whose: \(fromAJob ?? "")")
    }

    @Test func whatThePersonMadeIsntAnExtensionsOrItsJobsToTakeOff() async throws {
        let env = try TestEnv()
        let settings = await SettingsStore(db: env.db, events: env.events)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sf-own-\(UUID().uuidString)", isDirectory: true)
        let paths = SidefolkPaths(home: home)
        let folder = paths.themes.appendingPathComponent("paper-garden", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ThemeFile(ThemeTokens.sidefolk, id: "dev.sidefolk.theme.paper-garden", name: "Paper Garden").encoded().write(to: folder.appendingPathComponent("theme.json"))
        let tool = AppearanceTool(settings: settings, themes: ThemeLibrary(paths: paths), installedCompanions: { [] }, events: env.events)
        await settings.update { $0.themeFolder = "/somewhere/mine" }
        for caller in [Caller.extension(id: "e"), .agent(runId: AgentRuntime.jobPrefix + "1")] {
            await #expect(throws: (any Error).self) { _ = try await tool.run(["theme": "Paper Garden"], context: ToolContext(caller: caller, now: Date())) }
            #expect(settings.current.themeFolder == "/somewhere/mine")
        }
        _ = try await tool.run(["theme": "Paper Garden"], context: ToolContext(caller: .user, now: Date()))
        #expect(settings.current.themeFolder == nil, "the person may")

        await settings.update { $0.localCompanion = "mine" }
        let spark = try #require(CompanionChoice(rawValue: "spark"))
        for caller in [Caller.extension(id: "e"), .agent(runId: AgentRuntime.jobPrefix + "1")] {
            await #expect(throws: (any Error).self) { _ = try await tool.run(["companion": .string(spark.rawValue)], context: ToolContext(caller: caller, now: Date())) }
            #expect(settings.current.localCompanion == "mine")
        }
    }

    /// What a person calls a theme comes first: the word "harbor" once was the old default's id, and now names the painted theme (D130).
    @Test func aThemeIsFoundByWhatItsCalledBeforeWhatItOnceWas() async throws {
        let env = try TestEnv()
        let settings = await SettingsStore(db: env.db, events: env.events)
        let paths = SidefolkPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent("sf-word-\(UUID().uuidString)", isDirectory: true))
        let folder = paths.themes.appendingPathComponent("painted", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ThemeFile(ThemeTokens.sidefolk, id: "dev.sidefolk.theme.harbor", name: "Harbor").encoded().write(to: folder.appendingPathComponent("theme.json"))
        let tool = AppearanceTool(settings: settings, themes: ThemeLibrary(paths: paths), installedCompanions: { [] }, events: env.events)
        let said = try await tool.run(["theme": "harbor"], context: ToolContext(caller: .user, now: Date()))
        #expect(settings.current.theme == "dev.sidefolk.theme.harbor")
        #expect(said.text.contains("dev.sidefolk.theme.harbor"), "it says where it landed: \(said.text)")
        _ = try await tool.run(["theme": "dev.sidefolk.theme.daylight"], context: ToolContext(caller: .user, now: Date()))
        #expect(settings.current.theme == ThemeTokens.sidefolk.id, "an old id follows on")
    }

    @Test func aVoiceKeepsToHowFarThePersonLetsAnExtensionInterrupt() async throws {
        let env = try TestEnv()
        let settings = await SettingsStore(db: env.db, events: env.events)
        let tool = VoiceSayTool(settings: settings, events: env.events)
        let id = "com.example.quiet"
        await settings.update { $0.interruptions.set(.off, for: .extension(id)) }
        let out = try await tool.run(["text": "Hello"], context: ToolContext(caller: .extension(id: id), now: Date()))
        #expect(out.text.contains("Not said"), "\(out.text)")
        // Nor through a job it handed the companion, for a voice or a notice.
        let run = AgentRuntime.jobRunId("1", extensionId: id)
        let job = try await tool.run(["text": "Hello"], context: ToolContext(caller: .agent(runId: run), now: Date()))
        #expect(job.text.contains("Not said"), "\(job.text)")
        #expect(AgentFacingTools.source(for: .agent(runId: run)) == "extension:\(id)")
        #expect(AgentFacingTools.source(for: .agent(runId: AgentRuntime.jobRunId("2", extensionId: nil))) == "agent")
        #expect(AgentFacingTools.source(for: .agent(runId: "plain-run")) == "agent")
        #expect(AgentRuntime.jobOwner(of: "plain~com.example.a") == nil, "only a job's run has an owner")
    }

    @Test func howItLooksChangesOnlyToWhatIsThere() async throws {
        let env = try TestEnv()
        let settings = await SettingsStore(db: env.db, events: env.events)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sf-look-\(UUID().uuidString)", isDirectory: true)
        let paths = SidefolkPaths(home: home)
        let tool = AppearanceTool(settings: settings, themes: ThemeLibrary(paths: paths), installedCompanions: { ["ember"] }, events: env.events)
        let context = ToolContext(caller: .user, now: Date())
        // Not there yet: nothing is set, and it says so. Themes come and go from the app, so this one is the test's own.
        let themeless = settings.current.theme
        await #expect(throws: (any Error).self) { _ = try await tool.run(["theme": "Paper Garden", "mode": "dark"], context: context) }
        #expect(settings.current.theme == themeless)
        #expect(settings.current.appearance != .dark)
        let folder = paths.themes.appendingPathComponent("paper-garden", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ThemeFile(ThemeTokens.sidefolk, id: "dev.sidefolk.theme.paper-garden", name: "Paper Garden").encoded().write(to: folder.appendingPathComponent("theme.json"))
        _ = try await tool.run(["mode": "dark", "theme": "Paper Garden", "companion": "spark"], context: context)
        #expect(settings.current.appearance == .dark)
        #expect(settings.current.theme == "dev.sidefolk.theme.paper-garden", "by the name a person sees")
        await settings.update { $0.theme = ThemeTokens.sidefolk.id }
        _ = try await tool.run(["theme": "dev.sidefolk.theme.field-notes"], context: context)
        #expect(settings.current.theme == "dev.sidefolk.theme.paper-garden", "an old id saved in a plan follows on")
        #expect(settings.current.companion == .spark)
        _ = try await tool.run(["companion": "ember"], context: context)
        #expect(settings.current.companion == .ember)
        await #expect(throws: (any Error).self) { _ = try await tool.run(["companion": "kiko"], context: context) }
        await #expect(throws: (any Error).self) { _ = try await tool.run(["companion": "guard"], context: context) }
        await #expect(throws: (any Error).self) { _ = try await tool.run(["theme": "nonsense"], context: context) }
        await #expect(throws: (any Error).self) { _ = try await tool.run(["mode": "nonsense"], context: context) }
        await #expect(throws: (any Error).self) { _ = try await tool.run(.object([:]), context: context) }
    }

    @Test func howItLooksIsAllASettingsToolCanChange() async throws {
        let env = try TestEnv()
        let tool = AppearanceTool(settings: await SettingsStore(db: env.db, events: env.events), themes: ThemeLibrary(paths: SidefolkPaths(home: URL(fileURLWithPath: "/tmp"))), installedCompanions: { [] }, events: env.events)
        #expect((tool.spec.inputSchema["properties"]?.objectValue ?? [:]).keys.sorted() == ["companion", "mode", "theme"])
    }

    @Test func aTreeOnACardIsReadAsAPagePartAndTooMuchIsLeftOut() throws {
        let manifest = try ExtensionManifest.decode(Data(#"{"id":"com.example.a","name":"A","version":"1.0.0","run":{"command":"python3","args":["s.py"]},"tools":{}}"#.utf8))
        let tree: JSONValue = ["type": "tree", "nodes": [["id": "a", "title": "Start"]]]
        #expect(ExtensionToolAsks(["tree": tree], manifest: manifest)?.tree != nil)
        #expect(ExtensionToolAsks(["tree": ["nodes": []], "row": "x"], manifest: manifest)?.tree == nil)
        let huge: JSONValue = ["nodes": [["id": "a", "title": .string(String(repeating: "a", count: 20_000))]]]
        #expect(ExtensionToolAsks(["tree": huge, "row": "x"], manifest: manifest)?.tree == nil)
    }

    @Test func noBrainMeansNoJob() async throws {
        let tool = CompanionJobTool(agent: CompanionAgentSlot())
        await #expect(throws: (any Error).self) { _ = try await tool.run(["job": "Tidy up"], context: ToolContext(caller: .user, now: Date())) }
    }

    // MARK: A job, in a real turn

    private func world(_ steps: [ScriptedModel.Step]) async throws -> (SidefolkRuntime, AgentRuntime, ScriptedModel) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-job-\(UUID().uuidString)", isDirectory: true)
        let clock = ManualClock(TestEnv.referenceDate)
        let runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: clock)
        let model = ScriptedModel(steps)
        var settings = await runtime.settings.current
        settings.provider.kind = .anthropic
        let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
        let context = ContextBuilder(notebook: runtime.notebook, exchanges: runtime.exchanges, clock: clock)
        let agent = AgentRuntime(executor: runtime.executor, db: runtime.db, events: runtime.events, context: context, factory: factory, settings: { [settings] in settings }, clock: clock)
        return (runtime, agent, model)
    }

    @Test func aJobStaysOutOfThePersonsConversationAndSaysWhatItIs() async throws {
        let (world, runtime, _) = try await world([.turn(.reply("Nothing to report.")), .turn(.reply("Hi."))])
        let job = await runtime.submit(AgentRequest(text: "Tidy up", job: AgentRequest.Job(read: true)))
        for await _ in job.events {}
        #expect(job.threadId.hasPrefix(AgentRuntime.jobPrefix))
        #expect(job.runId.hasPrefix(AgentRuntime.jobPrefix))
        #expect(AgentRuntime.jobOwner(of: job.runId) == nil)
        let next = await runtime.submit(AgentRequest(text: "Hello"))
        for await _ in next.events {}
        #expect(next.threadId != job.threadId, "the person's next words don't continue it")
        let said = try await world.exchanges.conversation(job.threadId).first?.content
        #expect(said?.contains("Tidy up") == true && said != "Tidy up", "in the record as someone else's words")
    }

    @Test func aJobCarriesTheExtensionThatHandedItOver() async throws {
        let (_, runtime, _) = try await world([.turn(.reply("Done.")), .turn(.reply("Done."))])
        let slot = CompanionAgentSlot()
        slot.use(runtime)
        let answer = try await CompanionJobTool(agent: slot).run(["job": "Tidy up"], context: ToolContext(caller: .extension(id: "com.example.a"), now: Date()))
        #expect(!answer.text.isEmpty, "it ran, as the extension's job")
        let job = await runtime.submit(AgentRequest(text: "Tidy up", job: AgentRequest.Job(read: true, extensionId: "com.example.a")))
        #expect(AgentRuntime.jobOwner(of: job.runId) == "com.example.a")
        for await _ in job.events {}
    }

    @Test func aJobCanUseWhatThePersonsOwnTurnCan() async throws {
        let (world, runtime, model) = try await world([.turn(.reply("Nothing to report.")), .turn(.reply("Hi."))])
        let spec = ToolSpec(name: "ext.mcp.exec", title: "x", description: "", inputSchema: .object([:]), risk: .medium, capabilities: [.network, .extensions], category: .extensions, mutates: true)
        world.registry.register(ExtensionTool(spec: spec, extensionId: "mcp.x", extensionName: "x", remoteName: "exec", sandboxed: false) { _, _ in ToolResult(text: "") })
        for await _ in await runtime.submit(AgentRequest(text: "Tidy up", job: AgentRequest.Job(read: true))).events {}
        for await _ in await runtime.submit(AgentRequest(text: "Hello", newThread: true)).events {}
        #expect(model.requests[0].tools.contains { $0.name == "ext.mcp.exec" }, "the founder's choice (D128): under their trust settings")
        #expect(model.requests[1].tools.contains { $0.name == "ext.mcp.exec" })
    }

    @Test func aJobNobodyReadStartsAsOutsideWordsAndOneOnAPlanDoesnt() async throws {
        func tainted(_ read: Bool) async throws -> Bool? {
            let (_, runtime, _) = try await world([.turn(.reply("Nothing to report."))])
            var said: Bool?
            for await event in await runtime.submit(AgentRequest(text: "Tidy up", job: AgentRequest.Job(read: read))).events {
                if case .reply(let reply) = event { said = reply.tainted }
                if case .failed(let problem) = event { Issue.record("\(problem.message)") }
            }
            return said
        }
        #expect(try await tainted(false) == true)
        #expect(try await tainted(true) == false)
    }
}
