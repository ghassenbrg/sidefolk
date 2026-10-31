#if DEBUG
import AppKit
import SidefolkCore
import SwiftUI

/// Renders the Home and Settings windows, the Ask panel and bubbles with sample data to PNGs, in light
/// and dark, then exits:
/// `SidefolkApp --ui-snapshots <dir> [--language fr] [--theme <folder>] [--only now,calendar]`. Lets agents (who can't see the screen) review
/// the UI, in any language (SnapshotLanguage) and in any theme (D58), read straight from its folder. Uses an in-memory database, a temp home and fixture services:
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
        if let i = args.firstIndex(of: "--theme"), i + 1 < args.count {
            let folder = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            let report = ThemeCheck.check(folder: folder)
            guard report.isUsable else {
                FileHandle.standardError.write(Data("ui-snapshots: \(report.text)\n".utf8))
                exit(1)
            }
            ThemeStore.shared.apply(InstalledTheme(tokens: report.tokens, images: report.images, folder: folder))
        }
        // Boards a game wrote (Playtime's `writeSampleBoards`), drawn as `play-<game>-<moment>`.
        if let i = args.firstIndex(of: "--game-boards"), i + 1 < args.count {
            gameBoards = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        // Only the shots whose names contain one of these words: a page under review in seconds, not minutes.
        if let i = args.firstIndex(of: "--only"), i + 1 < args.count {
            only = args[i + 1].split(separator: ",").map(String.init)
        }
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
            // The one bar with words in it: what Return does, and what they match (D58).
            full.find.query = "invoice"
            await full.find.searchNow()
            try await homeShot("search")
            // Words Sidefolk does without AI: Return does them, ⌘Return asks instead.
            full.find.query = "remind me at 5 to stretch"
            await full.find.searchNow()
            try await homeShot("search-command")
            full.find.query = ""
            await full.reveal(sample.selectedItem)
            try await homeShot("notebook")
            await full.reveal(sample.remindedTask)
            try await homeShot("notebook-reminder")
            await full.reveal(sample.savedInConversation)
            try await homeShot("notebook-connected")
            await full.reveal(sample.profileItem)
            try await homeShot("about-you")
            full.selection = .trash
            try await homeShot("trash")
            await full.showConversation("c-plan")
            try await homeShot("conversations")
            await full.showConversation("c-rename")
            try await homeShot("conversations-stopped")
            full.selection = .activity
            try await homeShot("activity")
            // A row opened in place: the rule that allowed it and what it was called with.
            full.activity.openId = full.activity.entries.first { $0.decision == .always }?.id
            try await homeShot("activity-open")
            full.activity.openId = nil
            // The Calendar (D66): the month, the week and the list, with the sample's reminders and events.
            full.selection = .calendar
            for mode in CalendarModel.Mode.allCases {
                full.calendar.mode = mode
                await full.calendar.reload()
                try await homeShot("calendar-\(mode.rawValue)")
            }
            full.calendar.mode = .month
            await full.calendar.reload()
            // A wide window, to catch pages left on one side (D67).
            let wide = CGSize(width: 1600, height: 900)
            try await homeShot("activity-wide", size: wide)
            await full.showConversation("c-plan")
            try await homeShot("conversations-wide", size: wide)
            await full.reveal(sample.selectedItem)
            try await homeShot("notebook-wide", size: wide)
            full.selection = .trash
            try await homeShot("trash-wide", size: wide)
            full.selection = .now
            try await homeShot("now-wide", size: wide)
            // Extensions' pages in the sidebar with Keep Awake's switch, their tiles, and All Extensions, in simple and
            // colorful icons (D67).
            SampleExtensionPage.showPages(in: full.pages)
            full.now.widgets = [SampleExtensionPage.widget(), SampleExtensionPage.awakeWidget()]
            try await homeShot("now-extensions")
            full.selection = .page(ExtensionPagesModel.hub)
            try await homeShot("extensions-hub")
            ThemeStore.shared.setIcons(.colorful)
            try await homeShot("extensions-hub-colorful")
            full.selection = .now
            try await homeShot("now-extensions-colorful")
            ThemeStore.shared.setIcons(nil)
            full.pages.showSample([], summaries: [:])
            full.now.widgets = []
            full.selection = .activity
            // The smallest window Home allows, to catch clipping and overflow.
            let small = CGSize(width: 860, height: 560)
            try await homeShot("activity-small", size: small)
            await full.showConversation("c-plan")
            try await homeShot("conversations-small", size: small)
            full.selection = .now
            try await homeShot("now-small", size: small)
            full.selection = .calendar
            for mode in CalendarModel.Mode.allCases {
                full.calendar.mode = mode
                await full.calendar.reload()
                try await homeShot("calendar-\(mode.rawValue)-small", size: small)
            }
            full.calendar.mode = .month
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
            empty.selection = .calendar
            await empty.calendar.reload()
            try await capture(blank, size: CGSize(width: 1100, height: 720), dark: dark, to: file("window-home-calendar-empty"))
            empty.selection = .activity
            try await capture(blank, size: CGSize(width: 1100, height: 720), dark: dark, to: file("window-home-activity-empty"))
            await empty.showConversation(nil)
            try await capture(blank, size: CGSize(width: 1100, height: 720), dark: dark, to: file("window-home-conversations-empty"))
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

            // The update window in each state it has words for (D46).
            for (name, phase, plan) in updatePhases {
                let model = UpdateModel()
                (model.running, model.lastCheck, model.phase, model.plan) = ("0.1.0 snapshot 411", Date().addingTimeInterval(-120), phase, plan)
                let window = SnapshotWindow()
                UpdateWindowController.configure(window, model: model)
                try await capture(window, size: CGSize(width: 460, height: 380), dark: dark, to: file("window-update-\(name)"))
                window.orderOut(nil)
            }

            // Full pages.
            func page(_ name: String, _ view: some View, width: CGFloat) async throws {
                try await capturePage(view, width: width, dark: dark, to: file(name))
            }
            try await page("page-now", NowView(model: full.now), width: 870)
            // The narrowest page that keeps the theme's Today columns side by side (D64), with and without anything in them.
            try await page("page-now-tight", NowView(model: full.now), width: tightTodayWidth)
            try await page("page-now-tight-empty", NowView(model: empty.now), width: tightTodayWidth)
            // An extension's page, and its tile on Today (D62).
            try await page("page-extension-mac", ExtensionPageView(model: SampleExtensionPage.model()), width: 980)
            // A wide window and a narrow one: the page fills the width it has, centred (D67).
            try await page("page-extension-mac-wide", ExtensionPageView(model: SampleExtensionPage.model()), width: 1560)
            try await page("page-extension-mac-narrow", ExtensionPageView(model: SampleExtensionPage.model()), width: 640)
            // Switches and buttons on a page, and a palette (D63).
            try await page("page-extension-awake", ExtensionPageView(model: SampleExtensionPage.keepAwake()), width: 980)
            try await page("panel-extension-palette", PaletteView(model: SampleExtensionPage.palette(host: full.services.runtime.extensions)), width: 880)
            // Choices, fields and lists with pictures on a page (D68).
            try await page("page-extension-clipboard", ExtensionPageView(model: SampleExtensionPage.clipboard()), width: 980)
            // Miraya in each of its states (D74): a hero with the one thing to do, TVs beside, pictures to pick from.
            for state in ["notv", "ready", "window", "norecord", "pairing", "authorizing", "sharing", "paused", "playing", "problem"] {
                try await page("page-extension-miraya-\(state)", ExtensionPageView(model: SampleExtensionPage.miraya(state)), width: 1180)
            }
            try await page("page-extension-miraya-ready-narrow", ExtensionPageView(model: SampleExtensionPage.miraya("ready")), width: 640)
            try await page("page-extension-miraya-ready-wide", ExtensionPageView(model: SampleExtensionPage.miraya("ready")), width: 1560)
            full.now.widgets = [SampleExtensionPage.widget(), SampleExtensionPage.awakeWidget()]
            try await page("page-now-extension-tile", NowView(model: full.now), width: 870)
            full.now.widgets = []
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
            // Settings › General with a version waiting (D46).
            fixtures.updates.phase = .available(UpdateController.sampleOffer)
            try await page("page-settings-general-update", SettingsTabContent(tab: .general, model: settings), width: width)
            // Installing by itself, a version ready, an extension update to look at, and add-ons waiting (D70).
            settings.update { $0.updates.app = .install }
            fixtures.updates.phase = .ready(UpdateController.sampleOffer)
            fixtures.updates.addonReview = Self.sampleAddons.filter { $0.kind == .extension }.prefix(1).map { $0 }
            fixtures.updates.addonWaiting = Self.sampleAddons
            try await page("page-settings-general-auto-update", SettingsTabContent(tab: .general, model: settings), width: width)
            settings.update { $0.updates = UpdateSettings() }
            (fixtures.updates.addonReview, fixtures.updates.addonWaiting) = ([], [])
            fixtures.updates.phase = .upToDate
            // How much Sidefolk asks, set to Full access and to stopping after 30 minutes (D37).
            let policy = settings.policy
            await settings.setPolicy { $0.mode = .fullAccess; $0.unanswered = UnansweredRule(action: .stop, minutes: 30) }
            try await page("page-settings-privacy-full-access", SettingsTabContent(tab: .privacy, model: settings), width: width)
            await settings.setPolicy { $0 = policy }
            // The companion chooser with Spark chosen, then Spark in 2D, coral with a scarf.
            settings.update { $0.choose(.spark) }
            try await page("page-settings-companion-spark", SettingsTabContent(tab: .companion, model: settings), width: width)
            settings.update { $0.setDimension(.twoD, for: .spark); $0.setStyle(CompanionStyle(color: .coral, accessory: .scarf), for: .spark) }
            try await page("page-settings-companion-coral", SettingsTabContent(tab: .companion, model: settings), width: width)
            settings.update { $0.choose(.mochi); $0.styles = [:]; $0.dimensions = [:] }
            // A companion from "Made by you" in use, when the home has one (D43): the stage and the
            // title show it, and no built-in card is picked.
            if let made = CompanionArt.made.lazy.compactMap(\.companion).first {
                settings.update { $0.choose(custom: made.id, name: made.name) }
                try await page("page-settings-companion-made", SettingsTabContent(tab: .companion, model: settings), width: width)
                settings.update { $0.choose(.mochi) }
            }
            // The chooser (D77): every companion here in one grid (the made-by-you and folder ones
            // when SIDEFOLK_HOME has them), the gallery of sixty with filters, a download under way, and the details.
            let chooser = settings.chooser
            // Worn: the one added from a folder, when SIDEFOLK_HOME has it (its files are real), else Spark.
            if let local = CompanionArt.locals.first {
                settings.update { $0.choose(local: local.companion, name: local.name) }
            } else {
                settings.update { $0.choose(.spark) }
            }
            try await page("page-settings-companion-yours", SettingsTabContent(tab: .companion, model: settings), width: width)
            settings.update { $0.choose(.mochi) }
            chooser.page = .gallery
            try await page("page-settings-companion-gallery", SettingsTabContent(tab: .companion, model: settings), width: width)
            chooser.browse = CompanionBrowse(text: "cat", look: .twoD)
            try await page("page-settings-companion-gallery-search", SettingsTabContent(tab: .companion, model: settings), width: width)
            chooser.browse = CompanionBrowse(look: .threeD, maker: .others, hideOwned: true, sort: .newest)
            try await page("page-settings-companion-gallery-filters", SettingsTabContent(tab: .companion, model: settings), width: width)
            chooser.browse = CompanionBrowse(text: "spreadsheet")
            try await page("page-settings-companion-gallery-none", SettingsTabContent(tab: .companion, model: settings), width: width)
            chooser.browse = CompanionBrowse()
            if let catalog = settings.gallery.catalog {
                settings.gallery.showSample(catalog: catalog, companions: SampleCompanions.installed + localCompanions,
                                            progress: ["dev.sidefolk.companions.nori": 0.45, "dev.sidefolk.companions.acorn": 0.8])
                try await page("page-settings-companion-gallery-downloading", SettingsTabContent(tab: .companion, model: settings), width: width)
                for (name, id) in [("get", "dev.sidefolk.companions.rune"), ("owned", "io.github.lenak.pebble"),
                                   ("downloading", "dev.sidefolk.companions.nori"), ("update", "dev.sidefolk.companions.ember")] {
                    if let entry = catalog.entry(id) {
                        try await page("sheet-companion-detail-\(name)", CompanionGalleryDetail(entry: entry, model: settings), width: 520)
                    }
                }
                settings.gallery.showSample(catalog: catalog, companions: SampleCompanions.installed + localCompanions)
            }
            chooser.page = .yours
            try await page("sheet-companion-add", AddCompanionOptions(model: settings).background(Theme.surfaceRaised), width: 380)
            // The menus can't be drawn open; their items for each kind of companion, as a list.
            try await page("sheet-companion-menus", SampleCompanions.menus(chooser), width: 600)
            try await page("sheet-companion-remove", SampleCompanions.removals(chooser, settings: settings.settings), width: 480)
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

            await settings.loadExtensions()
            // The list kept short (D39): one row open, only those switched off, a search that finds rows by their
            // permissions and tools, and one that finds nothing switched on.
            let listStates: [(String, ExtensionListQuery, Set<String>)] = [
                ("expanded", ExtensionListQuery(), ["dev.sidefolk.git", "mcp.github"]),
                ("off", ExtensionListQuery(show: .off), []),
                ("search", ExtensionListQuery(text: "internet"), []),
                ("search-tool", ExtensionListQuery(text: "pull"), []),
                ("no-match", ExtensionListQuery(text: "spreadsheet", show: .on), []),
                // The sentences an extension answers without the AI (D50).
                ("commands", ExtensionListQuery(text: "what time"), ["dev.sidefolk.world-clock"]),
            ]
            for (name, query, open) in listStates {
                try await page("page-settings-extensions-\(name)", ExtensionsSettingsView(model: settings, query: query, expanded: open),
                               width: width)
            }

            // Desktop surfaces: the Ask panel and the kinds of bubble.
            let portrait = CompanionArt.avatar(for: AppSettings(), side: 26)
            let actions = FixtureAskActions()
            // The words typed so far, and what they match across Sidefolk (D58).
            let finding = AskModel()
            finding.actions = actions
            finding.found.find = { query in (try? await full.services.runtime.find(query)) ?? SearchResults() }
            finding.text = "invoice"
            await finding.found.searchNow()
            // Nothing typed: Today at a glance (D58).
            let glancing = AskModel()
            glancing.actions = actions
            glancing.glance = Glance(
                decisions: [AttentionItem(level: .attention, source: "watcher", title: "Pricing changed: Pro went from $12 to $15.",
                                          actions: [AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true)])],
                sessions: [AgentSession(id: "cc-1", agent: "claude-code", cwd: NSHomeDirectory() + "/git/sidefolk", state: .needsYou)],
                next: [Glance.Next(title: "Stretch", at: Date().addingTimeInterval(25 * 60), event: false),
                       Glance.Next(title: "Call with mom", at: Date().addingTimeInterval(70 * 60), event: true)],
                working: ["Codex in pockito"])
            let panels = [("desktop-ask-found", finding), ("desktop-ask-glance", glancing), ("desktop-ask", sampleAsk()), ("desktop-ask-apple-notes", sampleAskAppleNotes()),
                          ("desktop-ask-question", sampleAskQuestion()), ("desktop-ask-long", longAnswerAsk()),
                          ("desktop-ask-fresh", freshAsk()), ("desktop-ask-extensions", sampleAskExtensions()),
                          ("desktop-ask-internet", sampleAskInternet()), ("desktop-ask-outside", sampleAskOutside()),
                          ("desktop-ask-auto", awayAsk(.auto)), ("desktop-ask-full-access", awayAsk(.fullAccess)),
                          ("desktop-ask-no-ai", noAIAsk(ready: [])), ("desktop-ask-no-ai-found", noAIAsk(ready: [.claudeCode, .codex])),
                          ("desktop-ask-drop", dropAsk(actions)), ("desktop-ask-which-place", whichPlaceAsk()),
                          ("desktop-ask-now", sampleAskNow())]
                + voiceAsks(actions).map { ("desktop-ask-\($0.0)", $0.1) }
            for (name, ask) in panels {
                try await page(name, AskView(model: ask, companionName: "Mochi", portrait: portrait, hotkey: "⇧⌘Space"), width: 380)
            }
            for (name, bubble) in sampleBubbles() {
                try await page("desktop-bubble-\(name)", BubbleView(model: bubble), width: 320)
            }
            try await page("desktop-readouts", ReadoutPills(model: sampleReadouts()), width: 200)
            for (name, caption) in sampleTosses(face: portrait) {
                try await page("desktop-toss-\(name)", CaptionView(model: caption), width: 300)
            }
            // The Play panel in each state, and the moment a clash is halfway (D75).
            for (name, model, at) in await SamplePlayBoards.models(portrait: portrait) where wantedName("game-\(name)") {
                try await page("game-\(name)", PlayView(model: model).environment(\.revealProgress, at), width: PlayView.width)
            }
            // Playtime's real boards, every game and moment, when a folder of them is given (`--game-boards`).
            if let boards = gameBoards {
                for (name, model) in await SamplePlayBoards.real(from: boards, portrait: portrait) where wantedName("play-\(name)") {
                    try await page("play-\(name)", PlayView(model: model).environment(\.revealProgress, 1), width: PlayView.width)
                }
            }

            // Sheets.
            // Where a time is set (WhenField): typed, read back, picked; and the sheets that use it.
            try await page("panel-when-field", WhenFieldSamples(parser: full.now.whenParser), width: 380)
            try await page("panel-when-picker", WhenPicker(start: nil, parser: full.now.whenParser) { _ in }, width: 300)
            if let reminder = full.now.reminders.first(where: { $0.recurrence != nil }) {
                try await page("sheet-edit-reminder", EditReminderSheet(reminder: reminder, model: full.now), width: 420)
            }
            try await page("sheet-remind-at", PickReminderTimeSheet(item: sample.remindedTask, model: full.notebook), width: 360)
            try await page("sheet-calendar-new-reminder", NewReminderSheet(at: WhenPicker.nextHour(.autoupdatingCurrent), model: full.calendar),
                           width: 400)
            try await page("sheet-new-collection", CollectionSheet(mode: .create, model: full.notebook) { _ in }, width: 420)
            if let edited = full.notebook.collections.first(where: { $0.symbol != nil }) {
                try await page("sheet-edit-collection", CollectionSheet(mode: .edit(edited), model: full.notebook) { _ in }, width: 420)
            }
            try await page("sheet-install-extension", InstallPreviewSheet(preview: FixtureServices.samplePreview, model: settings), width: 480)
            try await page("sheet-install-draft", InstallPreviewSheet(preview: FixtureServices.draftPreview, model: settings), width: 480)
            // One per source (D71): Sidefolk's own from the gallery, the same permissions from a folder, an update asking for more.
            try await page("sheet-install-gallery", InstallPreviewSheet(preview: FixtureServices.galleryPreview, model: settings), width: 480)
            try await page("sheet-install-unknown", InstallPreviewSheet(preview: FixtureServices.unknownMirrorPreview, model: settings), width: 480)
            try await page("sheet-install-update", InstallPreviewSheet(preview: FixtureServices.updatePreview, model: settings), width: 480)
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
        let rt = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: SamplePlatform(),
                                       approvalMinute: 0.001)
        try await rt.notebook.inbox()
        return rt
    }

    private static func makeHome(empty: Bool) async throws -> (HomeModel, SampleData.Created?) {
        let rt = try await runtime()
        let model = HomeModel(services: FixtureServices(runtime: rt))
        let sample = empty ? nil : try await SampleData.fill(rt, notebook: model.notebook)
        if !empty {
            try await skipSteps(rt)
            await askWaiting(rt)
        }
        await model.reloadAll()
        return (model, sample)
    }

    /// Two of Guard's questions still waiting (D58), through the broker as a real request is: Sidefolk's own, which
    /// the keyboard may answer, and another app's, which only a click approves. They wait until the snapshots end.
    private static func askWaiting(_ rt: SidefolkRuntime) async {
        let home = NSHomeDirectory()
        let questions = [
            ApprovalRequest(tool: "files.move", title: "Move 12 PDFs to Invoices", summary: "Move 12 files from Downloads to Documents › Invoices",
                            risk: .medium, caller: .agent(runId: "sample-move"),
                            details: .paths([home + "/Downloads/Scan 0412.pdf", home + "/Downloads/Scan 0413.pdf"]), canAlways: true,
                            effect: .changesFiles),
            ApprovalRequest(tool: "clipboard.read", title: "Read the clipboard", summary: "Read what you copied last",
                            risk: .medium, caller: .external(client: "codex"), details: .none, canAlways: false, effect: .readsPrivateData),
        ]
        for question in questions {
            Task { _ = await rt.broker.request(question, timeout: 600) }
        }
        while await rt.broker.pending().count < questions.count { try? await Task.sleep(for: .milliseconds(10)) }
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
        // A gallery of sixty companions (D77), and those added from a folder in SIDEFOLK_HOME, read only.
        model.gallery.showSample(catalog: try SampleCompanions.catalog(), companions: SampleCompanions.installed + localCompanions)
        return (model, services)
    }

    private static var localCompanions: [InstalledCompanion] {
        AddonStore.installedCompanions(in: CompanionAddons.folder).filter(\.addedFromFolder)
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
        let request = "organize my Apple Notes into the notebook"
        ask.add(.answer("I copied 42 notes. Five look like they hold passwords or tokens, so I left them in Notes. Should I copy those too?",
                        canThinkHarder: false, tainted: true, thread: "sample"), caption: request)
        ask.thread = "sample"
        if let answer = ask.entries.last { ask.reply(to: answer.id, thread: "sample", request: request) }
        return ask
    }

    /// A long answer opens on its first lines, with Show all; the conversation is open, so New conversation shows (D45).
    private static func longAnswerAsk() -> AskModel {
        let ask = AskModel()
        ask.add(.answer(SampleData.plan, canThinkHarder: true, tainted: false, thread: "sample"),
                caption: "Plan my afternoon around the invoices and a run")
        ask.thread = "sample"
        return ask
    }

    /// "new conversation": the notice that the next request starts fresh, above the answer it leaves on screen (D45).
    private static func freshAsk() -> AskModel {
        let ask = AskModel()
        ask.add(.answer("Light rain is likely tomorrow morning in Fukuoka (70%), clearing after noon.", canThinkHarder: false,
                        tainted: false, thread: "sample"), caption: "Will it rain in Fukuoka tomorrow?")
        ask.add(.info(String(localized: "Your next request starts a new conversation. Earlier ones stay in Conversations.")),
                caption: "new conversation", fades: true)
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

    /// The founder's case (D39): cloning into ~/git with the Git extension, after a World Clock answer.
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

    /// A value read now and a hand played, answered without AI (D35 and D44, amended).
    private static func sampleAskNow() -> AskModel {
        let ask = AskModel()
        ask.add(.result(ResultCard(kind: .reading, title: "CPU: 23%"), activityId: nil, undo: false), caption: "what's my cpu usage?")
        ask.add(.result(ResultCard(kind: .reading, title: "Temperature in Fukuoka: 18 °C", subtitle: "Fukuoka, Japan"), activityId: nil, undo: false),
                caption: "temperature in Fukuoka")
        ask.add(.result(ResultCard(kind: .chance, title: Toss.hands(person: .rock, companion: .paper).result, subtitle: "You 2 · Me 3 · Draws 1"),
                        activityId: nil, undo: false), caption: "rock")
        return ask
    }

    /// What the companion flipped, rolled and played (D44, amended; D75): landed with the result under it and Again, one coin
    /// halfway up, a called coin, a natural 20 and the shapes of dice, and two hands meeting.
    private static func sampleTosses(face: NSImage?) -> [(String, CaptionModel)] {
        func caption(_ toss: Toss, landed: Bool = true, text: String? = nil, at: Double = 0.5, again: Bool = true) -> CaptionModel {
            let model = CaptionModel()
            model.text = text ?? ""
            model.companionName = "Mochi"
            model.face = face
            let flight = 1.2
            model.stage = TossShow(toss: toss, start: Date().addingTimeInterval(landed ? -3 : -at * flight - 0.3), flight: flight, still: false, landed: landed)
            if landed, again, !{ if case .hands = toss { true } else { false } }() { model.again = {} }
            return model
        }
        return [
            ("coin-flying", caption(.coins([false]), landed: false, text: String(localized: "Heads or tails…"), at: 0.45)),
            ("coin-heads", caption(.coins([true]))),
            ("coin-called", caption(.coins([false], call: false), text: String(localized: "You called it!", comment: "The companion: the person called the coin right"))),
            ("coins", caption(.coins([true, false, true]))),
            ("dice-rolling", caption(.dice(sides: 6, rolls: [5, 3], modifier: 0), landed: false, text: String(localized: "Rolling…"), at: 0.4)),
            ("dice", caption(.dice(sides: 6, rolls: [5, 3], modifier: 1))),
            ("doubles", caption(.dice(sides: 6, rolls: [4, 4], modifier: 0), text: String(localized: "Doubles!", comment: "The companion: two dice landed on the same face"))),
            ("d20", caption(.dice(sides: 20, rolls: [20], modifier: 0), text: String(localized: "Natural 20!", comment: "The companion: a d20 landed on 20"))),
            ("polyhedra", caption(.dice(sides: 8, rolls: [3, 7], modifier: 0))),
            ("d12", caption(.dice(sides: 12, rolls: [11, 4, 9], modifier: 2))),
            ("many-dice", caption(.dice(sides: 6, rolls: [1, 2, 3, 4, 5, 6, 6], modifier: 0))),
            ("hands-clash", caption(.hands(person: .scissors, companion: .paper), landed: false, at: 1.25)),
            ("hands-you-win", caption(.hands(person: .rock, companion: .scissors))),
            ("hands-i-win", caption(.hands(person: .rock, companion: .paper))),
            ("hands-draw", caption(.hands(person: .scissors, companion: .scissors))),
        ]
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

    /// Cards after outside content (D71): the founder's "mirror my screen to the living room TV" in Full access, after
    /// Miraya's own list of TVs (calm), and someone else's extension after a web page (strong). Arguments in words.
    private static func sampleAskOutside() -> AskModel {
        let ask = AskModel()
        ask.extensionLooks = ["dev.sidefolk.miraya": ExtensionLook(name: "Miraya", iconPath: nil, folk: "byte"),
                              "com.example.uploader": ExtensionLook(name: "Uploader", iconPath: nil, folk: nil)]
        var mirror = ApprovalRequest(tool: "ext.miraya.share_screen", title: "Share screen to TV",
                                     summary: "Share screen to TV (Miraya) · " + ArgumentWords.line(["tv": "living room"], schema: .object([:])),
                                     risk: .medium, caller: .agent(runId: "r"), details: .none, canAlways: false, tainted: true,
                                     effect: .usesInternet, extensionId: "dev.sidefolk.miraya")
        mirror.input = JSONValue.object(["tv": "living room"]).prettyString
        mirror.taintedBy = .extension(name: "Miraya", official: true)
        mirror.mode = .fullAccess
        ask.add(.approval(mirror), caption: "mirror my screen to the living room TV")
        let input: JSONValue = ["file": .string(NSHomeDirectory() + "/Documents/Taxes 2025.pdf"), "public": true]
        var upload = ApprovalRequest(tool: "ext.uploader.send", title: "Send a file",
                                     summary: "Send a file (Uploader) · " + ArgumentWords.line(input, schema: .object([:])),
                                     risk: .medium, caller: .agent(runId: "r"), details: .paths([NSHomeDirectory() + "/Documents/Taxes 2025.pdf"]),
                                     canAlways: false, tainted: true, effect: .usesInternet, extensionId: "com.example.uploader")
        upload.input = input.prettyString
        upload.taintedBy = .web
        upload.firstParty = false
        upload.mode = .askOncePerKind
        ask.add(.approval(upload), caption: "summarize that page and share my notes")
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
            ("update", bubble({
                let n = UpdateController.notice(UpdateController.sampleOffer)
                return AttentionItem(level: n.level, source: n.source, title: n.title, body: n.body, actions: n.actions,
                                     refKind: n.refKind, refId: n.refId)
            }())),
        ]
    }

    /// The update window's states (D46): file name, phase, and how this copy would install it.
    /// Gallery entries for Settings › Updates' add-on rows (D70).
    private static var sampleAddons: [AddonEntry] {
        [("dev.sidefolk.git", "Git", "extension"), ("dev.sidefolk.companions.kiko", "Kiko", "companion")].compactMap { id, name, kind in
            let json: [String: Any] = ["id": id, "kind": kind, "name": name, "tagline": "", "description": "", "author": "Sidefolk",
                                       "version": "1.0.0-snapshot.3", "file": "x.zip", "bytes": 1, "sha256": String(repeating: "0", count: 64)]
            return (try? JSONSerialization.data(withJSONObject: json)).flatMap { try? JSONDecoder().decode(AddonEntry.self, from: $0) }
        }
    }

    private static var updatePhases: [(String, UpdateModel.Phase, InstallPlan)] {
        let offer = UpdateController.sampleOffer
        return [
            ("available", .available(offer), .replace),
            ("available-download", .available(offer), .download(.notWritable)),
            ("ready", .ready(offer), .replace),
            ("downloading", .downloading(offer, received: 9_400_000, total: offer.image.size), .replace),
            ("verifying", .verifying(offer), .replace),
            ("downloaded", .downloaded(offer, URL(fileURLWithPath: "/Users/you/Downloads/Sidefolk-0.1.0-snapshot.430.dmg"), .translocated), .replace),
            ("up-to-date", .upToDate, .replace),
            ("failed", .failed(offer, UserFacingError("The download doesn't match the release's checksum, so it wasn't installed.",
                                                      recovery: "Try again; if it happens again, download it from the release page.")), .replace),
            ("failed-look", .failed(nil, UserFacingError("Sidefolk couldn't reach GitHub to look for updates.",
                                                         recovery: "Check the connection and try again.")), .replace),
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
        guard wanted(url) else { return }
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
        guard wanted(url) else { return }
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

    private static var only: [String] = []
    private static var gameBoards: URL?

    /// The narrowest page where every row of the theme's Today stays side by side (ColumnsLayout's rule, with
    /// NowView's least widths): where its columns are at their slimmest.
    private static var tightTodayWidth: CGFloat {
        let content = ThemeStore.shared.style.tokens.layout.today.map { row -> CGFloat in
            guard row.count > 1 else { return 0 }
            let total = row.map(\.width).reduce(0, +)
            let least = row.map { NowView.leastWidth($0) * CGFloat(total / $0.width) }.max() ?? 0
            return least + Theme.Space.l * CGFloat(row.count - 1)
        }.max() ?? 0
        return (max(content, 420) + 2 * Theme.Space.xxl + 2).rounded(.up)
    }

    private static func wantedName(_ name: String) -> Bool { only.isEmpty || only.contains { name.contains($0) } }

    private static func wanted(_ url: URL) -> Bool {
        only.isEmpty || only.contains { url.lastPathComponent.contains($0) }
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
