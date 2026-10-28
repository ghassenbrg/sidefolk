#if DEBUG
import AppKit
import SidefolkCore
import SwiftUI

/// Renders the Home and Settings windows, the Ask panel and bubbles with sample data to PNGs, in light
/// and dark, then exits:
/// `SidefolkApp --ui-snapshots <dir> [--language fr]`. Lets agents (who can't see the screen) review the
/// UI, in any language (SnapshotLanguage). Uses an in-memory database, a temp home and fixture services:
/// no real data is read or touched. The sample notes, reminders and activity are content, so they stay
/// English in every language.
///
/// - `window-*`: the real windows, titlebar and toolbar included, as the controllers build them.
/// - `page-*`: a page at its full height, to review everything below the fold.
/// - `sheet-*`: sheets on their own.
/// - `desktop-*`: the Ask panel and bubbles (on a plain background, without the desktop behind them).
enum UISnapshots {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--ui-snapshots"), flag + 1 < args.count else { return }
        if let status = SnapshotLanguage.relaunchIfNeeded(args) { exit(status) }
        let dir = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        let app = NSApplication.shared
        // Prohibited: no Dock icon, no menu bar, never takes focus from the user.
        app.setActivationPolicy(.prohibited)
        Task {
            do {
                try await render(into: dir)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("ui-snapshots failed: \(error)\n".utf8))
                exit(1)
            }
        }
        app.run()
    }

    private static func render(into dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (full, filled) = try await makeHome(empty: false)
        let (empty, _) = try await makeHome(empty: true)
        let (settings, fixtures) = try await makeSettings()
        guard let sample = filled else { return }

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            func file(_ name: String) -> URL { dir.appendingPathComponent("\(name)-\(suffix).png") }

            // Home, as a real window.
            let home = SnapshotWindow()
            HomeWindowController.configure(home, model: full)
            func homeShot(_ name: String, size: CGSize = CGSize(width: 1100, height: 720)) async throws {
                try await capture(home, size: size, dark: dark, to: file("window-home-\(name)"))
            }
            full.selection = .now
            try await homeShot("now")
            await full.reveal(sample.selectedItem)
            try await homeShot("notebook")
            await full.reveal(sample.profileItem)
            try await homeShot("about-you")
            full.selection = .trash
            try await homeShot("trash")
            full.selection = .activity
            try await homeShot("activity")
            // The smallest window Home allows, to catch clipping and overflow.
            let small = CGSize(width: 860, height: 560)
            try await homeShot("activity-small", size: small)
            full.selection = .now
            try await homeShot("now-small", size: small)
            await full.reveal(sample.selectedItem)
            try await homeShot("notebook-small", size: small)
            home.orderOut(nil)

            let blank = SnapshotWindow()
            HomeWindowController.configure(blank, model: empty)
            empty.selection = .now
            try await capture(blank, size: CGSize(width: 1100, height: 720), dark: dark, to: file("window-home-now-empty"))
            if let inbox = empty.notebook.inboxId {
                empty.selection = .collection(inbox)
                await empty.notebook.show(collectionId: inbox)
            }
            try await capture(blank, size: CGSize(width: 1100, height: 720), dark: dark, to: file("window-home-notebook-empty"))
            empty.selection = .activity
            try await capture(blank, size: CGSize(width: 1100, height: 720), dark: dark, to: file("window-home-activity-empty"))
            blank.orderOut(nil)

            // Settings, as a real window, one picture per tab.
            let settingsWindow = SnapshotWindow()
            let tabs = SettingsWindowController.configure(settingsWindow, model: settings)
            for (index, tab) in SettingsTab.allCases.enumerated() {
                tabs.selectedTabViewItemIndex = index
                try await capture(settingsWindow, size: CGSize(width: SettingsWindowController.width, height: 620), dark: dark,
                                  to: file("window-settings-\(tab.rawValue)"))
            }
            settingsWindow.orderOut(nil)

            let aboutWindow = SnapshotWindow()
            AboutWindowController.configure(aboutWindow)
            try await capture(aboutWindow, size: CGSize(width: 380, height: 470), dark: dark, to: file("window-about"))
            aboutWindow.orderOut(nil)

            // Full pages.
            func page(_ name: String, _ view: some View, width: CGFloat) async throws {
                try await capturePage(view, width: width, dark: dark, to: file(name))
            }
            try await page("page-now", NowView(model: full.now), width: 870)
            // With Full access on, Now leads with it (D37).
            let homePolicy = try await full.services.runtime.permissions.policy()
            try await full.services.runtime.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
            await full.now.reload()
            try await page("page-now-full-access", NowView(model: full.now), width: 870)
            try await full.services.runtime.permissions.setPolicy(homePolicy)
            await full.now.reload()
            let width = SettingsWindowController.width
            for tab in SettingsTab.allCases {
                try await page("page-settings-\(tab.rawValue)", SettingsTabContent(tab: tab, model: settings), width: width)
            }
            // How much Sidefolk asks, set to Full access and to stopping after 30 minutes (D37).
            let policy = settings.policy
            await settings.setPolicy { $0.mode = .fullAccess; $0.unanswered = UnansweredRule(action: .stop, minutes: 30) }
            try await page("page-settings-privacy-full-access", SettingsTabContent(tab: .privacy, model: settings), width: width)
            await settings.setPolicy { $0 = policy }
            // The companion chooser with Spark chosen, then the robot in coral with a scarf.
            settings.update { $0.choose(.spark) }
            try await page("page-settings-companion-spark", SettingsTabContent(tab: .companion, model: settings), width: width)
            settings.update { $0.choose(.sidefolk); $0.setStyle(CompanionStyle(color: .coral, accessory: .scarf), for: .sidefolk) }
            try await page("page-settings-companion-coral", SettingsTabContent(tab: .companion, model: settings), width: width)
            settings.update { $0.choose(.mochi); $0.styles = [:] }
            // A companion from "Made by you" in use, when the home has one (D43): the stage and the
            // title show it, and no built-in card is picked.
            if let made = CompanionArt.made.lazy.compactMap(\.companion).first {
                settings.update { $0.choose(custom: made.id, name: made.name) }
                try await page("page-settings-companion-made", SettingsTabContent(tab: .companion, model: settings), width: width)
                settings.update { $0.choose(.mochi) }
            }
            // Settings › AI with each provider chosen, in the states that need different words.
            for (name, choice, setUp) in aiStates {
                setUp(fixtures, settings)
                settings.ai.choose(choice)
                await settings.ai.refresh()
                try await page("page-settings-ai-\(name)", AISettingsView(model: settings), width: width)
            }
            fixtures.detection = FixtureServices.sampleDetection
            settings.ai.choose(.codex)
            await settings.ai.refresh()
            await settings.ai.test()
            try await page("page-settings-ai-sent", AISettingsView(model: settings, showPayload: true), width: width)
            // Settings › Voice turned on, in the states that need different words (D34).
            for (name, setUp) in voiceStates {
                setUp(fixtures.voice, settings)
                await settings.voice.refresh()
                try await page("page-settings-voice-\(name)", VoiceSettingsView(model: settings), width: width)
            }
            settings.update { $0.voice = VoiceSettings() }
            // Settings › Privacy › Your location in each state that needs different words (D48).
            for (name, setUp) in locationStates {
                setUp(fixtures.location, settings)
                settings.location.refresh()
                if settings.settings.location.source == .chosen, settings.settings.location.place == nil {
                    settings.location.query = "Portland"
                    await settings.location.search()
                }
                try await page("page-settings-location-\(name)", SettingsPage { LocationGroup(model: settings.location) }, width: width)
            }
            settings.update { $0.location = LocationSettings() }

            // A Mac without git: the built-in Git extension says why it isn't there.
            fixtures.gitMissing = true
            await settings.loadExtensions()
            try await page("page-settings-extensions-no-git", ExtensionsSettingsView(model: settings), width: width)
            fixtures.gitMissing = false
            await settings.loadExtensions()
            // The list kept short (D39): one row open, only those switched off, a search that finds rows by their
            // permissions and tools, and one that finds nothing switched on.
            let listStates: [(String, ExtensionListQuery, Set<String>)] = [
                ("expanded", ExtensionListQuery(), ["dev.sidefolk.git", "mcp.github"]),
                ("off", ExtensionListQuery(show: .off), []),
                ("search", ExtensionListQuery(text: "internet"), []),
                ("search-tool", ExtensionListQuery(text: "pull"), []),
                ("no-match", ExtensionListQuery(text: "spreadsheet", show: .on), []),
            ]
            for (name, query, open) in listStates {
                try await page("page-settings-extensions-\(name)", ExtensionsSettingsView(model: settings, query: query, expanded: open),
                               width: width)
            }

            // Desktop surfaces: the Ask panel and the kinds of bubble.
            let portrait = CompanionArt.portrait(for: AppSettings(), side: 44)
            let actions = FixtureAskActions()
            let panels = [("desktop-ask", sampleAsk()), ("desktop-ask-apple-notes", sampleAskAppleNotes()),
                          ("desktop-ask-question", sampleAskQuestion()), ("desktop-ask-extensions", sampleAskExtensions()),
                          ("desktop-ask-internet", sampleAskInternet()),
                          ("desktop-ask-auto", awayAsk(.auto)), ("desktop-ask-full-access", awayAsk(.fullAccess)),
                          ("desktop-ask-no-ai", noAIAsk(ready: [])), ("desktop-ask-no-ai-found", noAIAsk(ready: [.claudeCode, .codex])),
                          ("desktop-ask-drop", dropAsk(actions)), ("desktop-ask-which-place", whichPlaceAsk())]
                + voiceAsks(actions).map { ("desktop-ask-\($0.0)", $0.1) }
            for (name, ask) in panels {
                try await page(name, AskView(model: ask, companionName: "Mochi", portrait: portrait, hotkey: "⇧⌘Space"), width: 380)
            }
            for (name, bubble) in sampleBubbles() {
                try await page("desktop-bubble-\(name)", BubbleView(model: bubble), width: 320)
            }
            try await page("desktop-readouts", ReadoutPills(model: sampleReadouts()), width: 200)

            // Sheets.
            try await page("sheet-new-collection", CollectionSheet(mode: .create, model: full.notebook) { _ in }, width: 400)
            try await page("sheet-install-extension", InstallPreviewSheet(preview: FixtureServices.samplePreview, model: settings), width: 480)
            try await page("sheet-install-draft", InstallPreviewSheet(preview: FixtureServices.draftPreview, model: settings), width: 480)
            try await page("sheet-add-mcp-server", AddServerSheet(model: settings), width: 500)
            try await page("sheet-delete-all", DeleteAllSheet(model: settings), width: 440)
            try await page("sheet-full-access", FullAccessSheet(model: settings), width: 460)
        }
        print("ui-snapshots: wrote \(dir.path) (\(Bundle.main.preferredLocalizations.first ?? "en"))")
    }

    // MARK: Fixtures

    /// A minute of an unanswered approval lasts a millisecond here, so sample steps can be skipped (D37).
    private static func runtime() async throws -> SidefolkRuntime {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-ui-\(UUID().uuidString)", isDirectory: true)
        let rt = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(),
                                       approvalMinute: 0.001)
        try await rt.notebook.inbox()
        return rt
    }

    private static func makeHome(empty: Bool) async throws -> (HomeModel, SampleData.Created?) {
        let rt = try await runtime()
        let model = HomeModel(services: FixtureServices(runtime: rt))
        let sample = empty ? nil : try await SampleData.fill(rt, notebook: model.notebook)
        if !empty { try await skipSteps(rt) }
        await model.reloadAll()
        return (model, sample)
    }

    /// Two steps Sidefolk's agent asked about while nobody was there, through the real path: a page
    /// to read (skipped, the run went on) and a command to run on a schedule (the task stopped).
    private static func skipSteps(_ rt: SidefolkRuntime) async throws {
        let policy = try await rt.permissions.policy()
        _ = await rt.executor.execute(name: "web.fetch", input: ["url": "https://example.com/pricing"], caller: .agent(runId: "sample"))
        var stopping = policy
        stopping.unanswered.action = .stop
        try await rt.permissions.setPolicy(stopping)
        _ = await rt.executor.execute(name: "watch.command", input: ["command": "npm run e2e", "exit_code": 0], caller: .agent(runId: "sample"))
        try await rt.permissions.setPolicy(policy)
    }

    private static func makeSettings() async throws -> (SettingsModel, FixtureServices) {
        let rt = try await runtime()
        let services = FixtureServices(runtime: rt, keys: [.anthropic])
        _ = try await SampleData.fill(rt, notebook: NotebookModel(services: services))
        let model = SettingsModel(services: services)
        await model.refresh()
        return (model, services)
    }

    /// Settings › AI pages: file name, the option chosen, and the fixture state it's shown in.
    private static let aiStates: [(String, AIChoice, @MainActor (FixtureServices, SettingsModel) -> Void)] = [
        // The founder's setup (D36): everyday gpt-6-luna at extra high, "Think harder" gpt-6.1-sol at high.
        ("codex-ready", .codex, { f, s in
            f.detection = FixtureServices.sampleDetection
            s.update { s in
                s.provider.switchProvider(to: .codex)
                (s.provider.model, s.provider.effort) = ("gpt-6-luna", ReasoningEffort.xhigh.rawValue)
                (s.provider.smartModel, s.provider.smartEffort) = ("gpt-6.1-sol", ReasoningEffort.high.rawValue)
            }
        }),
        ("codex-signed-out", .codex, { f, _ in f.detection.codex = .ready(path: "/usr/local/bin/codex", version: "0.160.0", login: .signedOut) }),
        ("codex-not-found", .codex, { f, _ in f.detection.codex = .notFound }),
        ("claude-code", .claudeCode, { f, _ in f.detection = FixtureServices.sampleDetection }),
        ("anthropic", .anthropic, { _, _ in }),
        ("groq-no-key", .preset(.groq), { _, _ in }),
        ("openai-key", .preset(.openAI), { f, _ in f.keys.insert(.preset(.openAI)) }),
        ("ollama-running", .preset(.ollama), { _, _ in }),
        ("ollama-not-running", .preset(.ollama), { f, _ in f.detection.ollama = .installedNotRunning }),
        ("lmstudio-not-installed", .preset(.lmStudio), { _, _ in }),
        ("custom", .preset(.custom), { _, s in s.update { $0.provider.baseURL = "https://llm.example.com/v1" } }),
        ("none", .none, { _, _ in }),
    ]

    /// Settings › Voice pages: file name and the fixture state each is shown in.
    private static let locationStates: [(String, @MainActor (FixtureLocationServices, SettingsModel) -> Void)] = [
        ("off", { f, s in f.macLocation = .notAsked; s.update { $0.location = LocationSettings() } }),
        ("mac", { f, s in
            f.macLocation = .allowed
            s.update { $0.location = LocationSettings(source: .mac, place: FixtureLocationServices.fukuoka) }
        }),
        ("mac-finding", { f, s in f.macLocation = .allowed; s.update { $0.location = LocationSettings(source: .mac) } }),
        ("mac-denied", { f, s in f.macLocation = .denied; s.update { $0.location = LocationSettings(source: .mac) } }),
        ("chosen", { f, s in
            f.macLocation = .notAsked
            s.update { $0.location = LocationSettings(source: .chosen, place: FixtureLocationServices.fukuoka) }
        }),
        ("chosen-search", { _, s in s.update { $0.location = LocationSettings(source: .chosen) } }),
    ]

    private static let voiceStates: [(String, @MainActor (FixtureVoiceServices, SettingsModel) -> Void)] = [
        ("on", { f, s in
            (f.microphone, f.status, f.hasElevenLabsKey) = (.allowed, .ready(.transcriber), false)
            s.update { $0.voice = VoiceSettings(); $0.voice.input = true }
        }),
        ("elevenlabs", { f, s in
            (f.microphone, f.status, f.hasElevenLabsKey) = (.allowed, .ready(.transcriber), true)
            s.update { $0.voice.input = true; $0.voice.engine = .elevenLabs; $0.voice.elevenLabsVoice = "v1"; $0.voice.elevenLabsVoiceName = "Juniper" }
        }),
        ("download", { f, s in
            (f.microphone, f.status, f.hasElevenLabsKey) = (.notAsked, .needsDownload(.transcriber), false)
            s.update { $0.voice = VoiceSettings(); $0.voice.input = true; $0.voice.talkKey = .ownShortcut; $0.voice.language = "fr-FR"; $0.voice.replies = .always }
        }),
        ("basic", { f, s in
            (f.microphone, f.status, f.hasElevenLabsKey) = (.denied, .ready(.basic), false)
            s.update { $0.voice = VoiceSettings(); $0.voice.input = true }
        }),
    ]

    /// The Ask panel while talking: listening with the words so far, the words not caught, and replies said aloud or muted.
    private static func voiceAsks(_ actions: FixtureAskActions) -> [(String, AskModel)] {
        let listening = AskModel()
        listening.actions = actions
        listening.voice = .listening(basic: false)
        listening.text = "Remind me at 5 to stretch"
        let starting = AskModel()
        starting.actions = actions
        starting.voice = .listening(basic: false)
        let missed = AskModel()
        missed.actions = actions
        missed.add(.info(String(localized: "I didn't catch that. Fix the words and press Return, or hold to talk again.")), caption: String(localized: "Talking"))
        missed.text = "uh"
        let spoken = AskModel()
        spoken.actions = actions
        spoken.add(.result(ResultCard(kind: .reminder, title: "Stretch", subtitle: "Today 17:00"), activityId: nil, undo: true),
                   caption: "Remind me at 5 to stretch.")
        spoken.add(.spoken("Stretch, Today 17:00", muted: nil))
        spoken.add(.answer("Next up is **Stretch** at 17:00. Scout is also watching example.com for changes.", canThinkHarder: false, tainted: false),
                   caption: "What's next?")
        spoken.add(.spoken("Next up is Stretch at 17:00.", muted: .quiet))
        return [("listening", listening), ("listening-empty", starting), ("missed", missed), ("spoken", spoken)]
    }

    /// A panel after a few requests: a result, an answer and a pending approval.
    private static func sampleAsk() -> AskModel {
        let ask = AskModel()
        ask.add(.result(ResultCard(kind: .reminder, title: "Stretch", subtitle: "Today 17:00"), activityId: nil, undo: true),
                caption: "remind me at 5 to stretch")
        ask.add(.answer("Next up is **Stretch** at 17:00, and Scout is watching example.com for changes.",
                        canThinkHarder: false, tainted: false), caption: "what's coming up?")
        ask.add(.approval(ApprovalRequest(tool: "files.move", title: "Move 3 files?", summary: "Move 3 items to ~/Downloads/Invoices",
                                          risk: .medium, caller: .agent(runId: "r"),
                                          details: .paths(["~/Downloads/a.pdf", "~/Downloads/b.pdf", "~/Downloads/c.pdf"]),
                                          canAlways: false)))
        return ask
    }

    /// An answer that ends with a question: Reply, then the input waits for it.
    private static func sampleAskQuestion() -> AskModel {
        let ask = AskModel()
        ask.add(.answer("I copied 42 notes. Five look like they hold passwords or tokens, so I left them in Notes. Should I copy those too?",
                        canThinkHarder: false, tainted: true), caption: "organize my Apple Notes into the notebook")
        ask.reply()
        return ask
    }

    /// No AI chosen yet: a question, then words with a time in them; `ready` are the plans found on this Mac.
    private static func noAIAsk(ready: [ProviderKind]) -> AskModel {
        let ask = AskModel()
        let call = "call the bank tomorrow at 9"
        let calendar = Calendar.autoupdatingCurrent
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86_400)) ?? Date()
        let guess = ReminderGuess(title: "Call the bank", when: nine, recurrence: nil,
                                  label: String(localized: "Remind me \(TimeFormat.when(nine, now: Date(), calendar: calendar))",
                                                comment: "A button: “Remind me Tomorrow 09:00”"))
        ask.add(.needsBrain(NoAIRequest(text: call, guess: guess, request: call, ready: ready)), caption: call)
        let question = "what time is it in Tokyo?"
        ask.add(.needsBrain(NoAIRequest(text: question, request: question, ready: ready)), caption: question)
        return ask
    }

    /// The weather with no place named while Sidefolk doesn't know where the person is (D48).
    private static func whichPlaceAsk() -> AskModel {
        let ask = AskModel()
        ask.add(.result(PlaceNeeded.card, activityId: nil, undo: false), caption: "every minute tell me the temperature")
        return ask
    }

    /// A link dropped on the companion, waiting for what to do with it, under a long answer with every button.
    private static func dropAsk(_ actions: FixtureAskActions) -> AskModel {
        let ask = AskModel()
        ask.actions = actions
        ask.attachment = Attachment(kind: .url(URL(string: "https://example.com/pricing")!), label: "example.com/pricing")
        ask.add(.answer("""
            The pricing page lists three plans. Free keeps five projects and a week of history. Pro is $15 a month (it was $12 \
            until Monday) and adds unlimited projects, a year of history and priority support. Team is $12 per person a month \
            with at least three people, and adds shared folders, single sign-on and an admin console. Annual billing takes 20% \
            off every paid plan. Do you want me to watch the page for the next change?
            """, canThinkHarder: true, tainted: true), caption: "what does example.com/pricing say?")
        return ask
    }

    /// The live values beside the companion: two running, one paused.
    private static func sampleReadouts() -> ReadoutPillsModel {
        let model = ReadoutPillsModel()
        model.items = [Readout(id: "1", label: String(localized: "CPU"), value: "23%"),
                       Readout(id: "2", label: "Fukuoka", value: "18.4 °C"),
                       Readout(id: "3", label: String(localized: "Network"), value: "↓ 1.2 MB/s ↑ 40 kB/s", paused: true)]
        return model
    }

    /// A panel in Auto or Full access after a request that went on while nobody answered: what was
    /// done without asking, and the step that was skipped (D37).
    private static func awayAsk(_ mode: GuardMode) -> AskModel {
        let ask = AskModel()
        ask.mode = mode
        let full = mode == .fullAccess
        ask.add(.result(ResultCard(kind: .file, title: "Renamed 3 invoices", subtitle: "~/Documents/Invoices"), activityId: nil, undo: true),
                caption: "tidy up my invoices and check the pricing page")
        ask.add(.doneWithoutAsking("Rename 3 files in ~/Documents/Invoices", fullAccess: full))
        if full {
            ask.add(.doneWithoutAsking("Move 2 files in ~/Downloads to the Trash", fullAccess: true))
        } else {
            // After a note was read, a step that keeps everything on the Mac can be allowed for the request.
            ask.add(.approval(ApprovalRequest(tool: "applenotes.copy", title: String(localized: "Copy Apple Notes to the notebook"),
                                              summary: "Copy 50 notes from Apple Notes into “Cooking”, “Travel”", risk: .medium,
                                              caller: .agent(runId: "r"), details: .none, canAlways: false, tainted: true,
                                              canAllowForRequest: true)))
        }
        ask.add(.skipped("Read https://example.com/pricing", why: "You didn't answer in time, so this step was skipped."))
        ask.add(.answer("I renamed the invoices. I didn't read the pricing page: you weren't there to say yes, so it's waiting in Now.",
                        canThinkHarder: false, tainted: false))
        return ask
    }

    /// Organizing Apple Notes (D38): a batch copied, macOS refusing Reminders, the next read waiting.
    private static func sampleAskAppleNotes() -> AskModel {
        let ask = AskModel()
        ask.add(.result(ResultCard(kind: .note, title: String(localized: "Copied 25 notes from Apple Notes"), subtitle: "Cooking, Travel, Work",
                                   detail: String(localized: "\(75) of \(214) copied so far"), itemKind: .note), activityId: nil, undo: true),
                caption: "check my Apple Notes and move them, well organized, into our notebook")
        ask.add(.result(MacApp.reminders.permissionCard, activityId: nil, undo: false), caption: "what's on my Apple Reminders?")
        ask.add(.approval(ApprovalRequest(tool: "applenotes.list", title: String(localized: "List Apple Notes"),
                                          summary: "Read the titles, folders and dates of up to 50 notes in “Recipes” in Apple Notes",
                                          risk: .medium, caller: .agent(runId: "r"), details: .none, canAlways: true, effect: .readsPrivateData)))
        ask.add(.approval(ApprovalRequest(tool: "applenotes.remove", title: String(localized: "Remove notes from Apple Notes"),
                                          summary: "Move 2 notes in Apple Notes to Recently Deleted", risk: .high, caller: .agent(runId: "r"),
                                          details: .text("“Pasta carbonara” (iCloud › Recipes)\n“Sourdough” (iCloud › Recipes)\n\n"
                                                         + "Their copies stay in your notebook. Notes keeps deleted notes in Recently Deleted for 30 days."),
                                          canAlways: false, tainted: true)))
        return ask
    }

    /// The founder's case (D39): cloning into ~/git with the built-in Git extension, after a World Clock answer.
    private static func sampleAskExtensions() -> AskModel {
        let ask = AskModel()
        let git = FixtureServices.git
        ask.extensionLooks = [git.id: git.look,
                              "dev.sidefolk.world-clock": ExtensionLook(name: "World Clock", iconPath: FixtureServices.icon("world-clock"), folk: "tempo")]
        ask.add(.result(ResultCard(kind: .extensionResult, title: "Time around the world", subtitle: "World Clock",
                                   detail: "It is Tuesday 27 October, 09:12 in Tokyo (JST, UTC+9), 8 hours ahead of you.",
                                   refId: "dev.sidefolk.world-clock"), activityId: nil, undo: false),
                caption: "what time is it in Tokyo?")
        ask.add(.approval(ApprovalRequest(tool: "ext.git.clone", title: "Clone a repository",
                                          summary: "Clone https://github.com/octocat/Hello-World into ~/git/Hello-World",
                                          risk: .medium, caller: .agent(runId: "r"), details: .paths([NSHomeDirectory() + "/git/Hello-World"]),
                                          canAlways: true, extensionId: git.id)), caption: "please clone https://github.com/octocat/Hello-World under ~/git")
        return ask
    }

    /// Using the internet (D47): a page Sidefolk chose, a built-in service, and a new site after reading a page.
    private static func sampleAskInternet() -> AskModel {
        let ask = AskModel()
        ask.extensionLooks = ["dev.sidefolk.weather": ExtensionLook(name: "Weather", iconPath: FixtureServices.icon("weather"), folk: "scout")]
        ask.add(.approval(ApprovalRequest(tool: "web.fetch", title: String(localized: "Read a web page"),
                                          summary: "Read the web page https://forum.example.net/thread/42", risk: .medium,
                                          caller: .agent(runId: "r"), details: .url("https://forum.example.net/thread/42"), canAlways: false,
                                          tainted: true, effect: .usesInternet, site: "forum.example.net")),
                caption: "what do people say about it?")
        ask.add(.approval(ApprovalRequest(tool: "web.fetch", title: String(localized: "Read a web page"),
                                          summary: "Read the web page https://docs.swift.org/swift-book/", risk: .medium,
                                          caller: .agent(runId: "r"), details: .url("https://docs.swift.org/swift-book/"), canAlways: true,
                                          effect: .usesInternet, site: "docs.swift.org")),
                caption: "what's new in the Swift book?")
        ask.add(.approval(ApprovalRequest(tool: "ext.weather.forecast", title: "Forecast",
                                          summary: "Get the weather forecast for Fukuoka for the next 3 days", risk: .medium,
                                          caller: .agent(runId: "r"), details: .none, canAlways: true, effect: .usesInternet,
                                          extensionId: "dev.sidefolk.weather", service: "Open-Meteo")),
                caption: "and the weather there this weekend?")
        return ask
    }

    private static func sampleBubbles() -> [(String, BubbleModel)] {
        func bubble(_ item: AttentionItem, tail: BubbleModel.Tail = .init(onTop: false, x: 220)) -> BubbleModel {
            let model = BubbleModel()
            model.item = item
            model.tail = tail
            return model
        }
        return [
            ("reminder", bubble(AttentionItem(level: .attention, source: "reminder", title: "Stretch", body: "You asked at 16:40.",
                                              actions: [AttentionAction(id: "done", title: String(localized: "Done"), isPrimary: true),
                                                        AttentionAction(id: "snooze", title: String(localized: "10 min"))],
                                              refKind: "reminder", refId: "r1"))),
            ("reminder-repeating", bubble(AttentionItem(level: .attention, source: "reminder", title: "Drink some water",
                                                        body: "Every 30 minutes until 18:00",
                                                        actions: [AttentionAction(id: "done", title: String(localized: "Done"), isPrimary: true),
                                                                  AttentionAction(id: "snooze10", title: String(localized: "10 min")),
                                                                  AttentionAction(id: "stop", title: String(localized: "Stop repeating"))],
                                                        refKind: "reminder", refId: "r2"))),
            ("job-failed", bubble(AttentionItem(level: .attention, source: "job", title: "npm test failed (exit 1)",
                                                body: "FAIL src/app.test.ts\nExpected 2, received 3\nAfter 4m 12s in sidefolk",
                                                actions: [AttentionAction(id: "copy", title: String(localized: "Copy command"), isPrimary: true),
                                                          AttentionAction(id: "open", title: String(localized: "Open folder"))],
                                                refKind: "job", refId: "j1"))),
            ("question", bubble(AttentionItem(level: .attention, source: "external:codex", title: "Codex asks",
                                              body: "Deploy to staging now?",
                                              actions: [AttentionAction(id: "yes", title: "Yes", isPrimary: true),
                                                        AttentionAction(id: "no", title: "No")],
                                              refKind: "ask"),
                                tail: .init(onTop: true, x: 60))),
            ("done-without-asking", bubble(AttentionItem(level: .gentle, source: AppCoordinator.ownVoice,
                                                         title: String(localized: "Done without asking: \("Rename 3 files in ~/Documents/Invoices")",
                                                                       comment: "A bubble: what Sidefolk did on its own in Auto or Full access"),
                                                         body: GuardMode.auto.title, refKind: "unasked"))),
            ("intro", bubble(AttentionItem(level: .gentle, source: AppCoordinator.ownVoice, title: AppCoordinator.introduction(.scout).0,
                                           body: AppCoordinator.introduction(.scout).1, refKind: "intro"))),
            ("welcome", bubble(Onboarding.item(for: .hello, name: "Mochi", hotkey: "⇧⌘Space"))),
        ]
    }

    // MARK: Rendering
    //
    // AppKit draws the pictures (cacheDisplay): ImageRenderer can't draw AppKit-backed controls
    // such as switches, pop-up buttons, text fields and split views.

    /// A window that draws as if focused, so controls show their active look. Never shown on screen.
    private final class SnapshotWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
    }

    /// The whole window, titlebar and toolbar included.
    private static func capture(_ window: NSWindow, size: CGSize, dark: Bool, to url: URL) async throws {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        window.makeFirstResponder(nil) // no field focused, as when Settings opens
        guard let frame = window.contentView?.superview else { throw SnapshotError.render(url.lastPathComponent) }
        try write(frame, to: url)
    }

    /// A view at its full height in a borderless window.
    private static func capturePage(_ view: some View, width: CGFloat, dark: Bool, to url: URL) async throws {
        let host = NSHostingView(rootView: view
            .environment(\.rendersFullPage, true)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.surface))
        let window = SnapshotWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: 200),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(250))
        window.setContentSize(NSSize(width: width, height: max(host.fittingSize.height, 100)))
        try await Task.sleep(for: .milliseconds(250))
        try write(host, to: url)
        window.orderOut(nil)
    }

    private static func write(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw SnapshotError.render(url.lastPathComponent) }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.render(url.lastPathComponent) }
        try png.write(to: url)
    }

    enum SnapshotError: Error { case render(String) }
}
#endif
