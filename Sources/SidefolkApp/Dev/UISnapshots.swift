#if DEBUG
import AppKit
import SidefolkCore
import SwiftUI

/// Renders the Home and Settings windows, the Ask panel and the Sidecard with sample data to PNGs, in light
/// and dark, then exits:
/// `SidefolkApp --ui-snapshots <dir> [--language fr] [--theme <folder>] [--only now,calendar]`. Lets agents (who can't see the screen) review
/// the UI, in any language (SnapshotLanguage) and in any theme (D58), read straight from its folder. Uses an in-memory database, a temp home and fixture services:
/// no real data is read or touched. The sample notes, reminders and activity are content, so they stay
/// English in every language.
///
/// - `window-*`: the real windows, titlebar and toolbar included, as the controllers build them.
/// - `page-*`: a page at its full height, to review everything below the fold.
/// - `sheet-*`: sheets on their own.
/// - `desktop-*`: the Ask panel, the Sidecard and the companion's floor (on a plain wallpaper, without the desktop behind them).
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

            // Home, as a real window (D84): every place, at the mockups' 1280 × 800, in a wide and a narrow window, and empty.
            let home = SnapshotWindow()
            HomeWindowController.configure(home, model: full)
            func homeShot(_ name: String, size: CGSize = CGSize(width: 1280, height: 800)) async throws {
                try await capture(home, size: size, dark: dark, to: file("window-home-\(name)"))
            }
            full.selection = .now
            try await homeShot("today")
            try await homeShot("today-wide", size: CGSize(width: 1600, height: 1000))
            try await homeShot("today-narrow", size: CGSize(width: 900, height: 720))
            // On duty in the same state as Today, so their counts can be read side by side.
            full.selection = .onDuty
            try await homeShot("onduty")
            full.selection = .now
            // The Say bar (⌘K) with words in it: what Return does, in plain words, with or without AI, and what they find.
            for (name, words) in [("say", "remind me tomorrow at 9 to send the deck to Acme"), ("say-ai", "plan my afternoon around the design review"),
                                  ("say-search", "invoice")] {
                full.find.query = words
                await full.find.searchNow()
                try await homeShot(name)
            }
            full.find.query = ""
            // Extensions' pages in the sidebar with Keep Awake's switch, their tiles on Today (D67), and On duty with them.
            SampleExtensionPage.showPages(in: full.pages)
            full.now.widgets = [SampleExtensionPage.widget(), SampleExtensionPage.awakeWidget()]
            try await homeShot("today-extensions", size: CGSize(width: 1280, height: 1000))
            full.selection = .onDuty
            try await homeShot("onduty-extensions")
            ThemeStore.shared.setIcons(.colorful)
            full.selection = .now
            try await homeShot("today-colorful")
            ThemeStore.shared.setIcons(nil)
            full.pages.showSample([], summaries: [:])
            full.now.widgets = []
            // Quiet on: the queue held in one card, the moon at the sidebar's foot.
            await full.services.runtime.settings.update { $0.quietUntil = Date().addingTimeInterval(3 * 3600) }
            await full.now.reload()
            try await homeShot("today-quiet")
            await full.services.runtime.settings.update { $0.quietUntil = nil }
            await full.now.reload()
            // The Calendar (D66, D84): Agenda first, then the week and the month.
            full.selection = .calendar
            for mode in CalendarModel.Mode.allCases {
                full.calendar.mode = mode
                await full.calendar.reload()
                try await homeShot("calendar-\(mode.rawValue)")
            }
            full.calendar.mode = .agenda
            await full.calendar.reload()
            await full.reveal(sample.selectedItem)
            try await homeShot("notebook")
            await full.reveal(sample.remindedTask)
            try await homeShot("notebook-reminder")
            await full.reveal(sample.savedInConversation)
            try await homeShot("notebook-connected")
            full.selection = .you
            await full.you.reload()
            try await homeShot("you")
            full.you.editing = full.you.facts.first?.id
            try await homeShot("you-editing")
            full.you.editing = nil
            full.selection = .trash
            try await homeShot("trash")
            full.selection = .onDuty
            try await homeShot("onduty-wide", size: CGSize(width: 1600, height: 1000))
            // History (D84): everything kept, an action's record open, a conversation open in place, the agents' receipts.
            full.selection = .history
            full.history.span = .all
            await full.history.reload()
            try await homeShot("history")
            let allowedBefore = full.history.events.lazy.compactMap { event -> Int64? in
                if case .action(let e) = event.kind, e.decision == .always { return e.id }
                return nil
            }.first
            full.history.open(activityRow: allowedBefore)
            try await homeShot("history-record")
            full.history.openId = nil
            full.history.open(conversation: "c-plan")
            await full.history.conversation.loadTranscript()
            try await homeShot("history-conversation")
            full.history.conversation.selectedId = nil
            full.history.filter = .agents
            try await homeShot("history-agents")
            full.history.filter = .all
            // The Gallery in Home (D84), with Settings' sample catalog.
            full.selection = .gallery
            full.settingsHost.gallery.showSample(catalog: try SampleCompanions.catalog(), companions: SampleCompanions.installed)
            try await homeShot("gallery")
            try await homeShot("gallery-wide", size: CGSize(width: 1600, height: 1000))
            // Add-on updates (D89): the Gallery's Updates halfway through Update all, then Today's one row and the sidebar's marks.
            if let catalog = full.settingsHost.gallery.catalog {
                SampleAddonUpdates.show(in: full.services.updates, catalog: catalog)
                try await homeShot("gallery-updates")
                full.services.updates.addonSummary = "3 updated, 1 needs your review"
                SampleExtensionPage.showPages(in: full.pages)
                full.selection = .now
                try await homeShot("today-updates")
                full.pages.showSample([], summaries: [:])
                SampleAddonUpdates.clear(full.services.updates)
            }
            // The smallest window Home allows, to catch clipping and overflow.
            let small = CGSize(width: 860, height: 560)
            full.selection = .now
            try await homeShot("today-small", size: small)
            full.selection = .history
            try await homeShot("history-small", size: small)
            full.selection = .onDuty
            try await homeShot("onduty-small", size: small)
            full.selection = .calendar
            for mode in CalendarModel.Mode.allCases {
                full.calendar.mode = mode
                await full.calendar.reload()
                try await homeShot("calendar-\(mode.rawValue)-small", size: small)
            }
            full.calendar.mode = .agenda
            await full.reveal(sample.selectedItem)
            try await homeShot("notebook-small", size: small)
            home.orderOut(nil)

            // Every place empty: what fills it, with its one action.
            let blank = SnapshotWindow()
            HomeWindowController.configure(blank, model: empty)
            func emptyShot(_ name: String) async throws {
                try await capture(blank, size: CGSize(width: 1280, height: 800), dark: dark, to: file("window-home-\(name)-empty"))
            }
            empty.selection = .now
            try await emptyShot("today")
            if let inbox = empty.notebook.inboxId {
                empty.selection = .collection(inbox)
                await empty.notebook.show(collectionId: inbox)
            }
            try await emptyShot("notebook")
            empty.selection = .calendar
            await empty.calendar.reload()
            try await emptyShot("calendar")
            empty.selection = .onDuty
            try await emptyShot("onduty")
            empty.selection = .history
            await empty.history.reload()
            try await emptyShot("history")
            empty.selection = .you
            await empty.you.reload()
            try await emptyShot("you")
            empty.selection = .trash
            try await emptyShot("trash")
            blank.orderOut(nil)

            // Settings, as a real window, one picture per tab, then a search (D84).
            let settingsWindow = SnapshotWindow()
            SettingsWindowController.configure(settingsWindow, model: settings)
            let settingsSize = CGSize(width: SettingsWindowController.size.width, height: SettingsWindowController.size.height)
            for tab in SettingsTab.allCases {
                settings.navigation.tab = tab
                try await capture(settingsWindow, size: settingsSize, dark: dark, to: file("window-settings-\(tab.rawValue)"))
            }
            settings.navigation.query = String(localized: "quiet", comment: "UI snapshots only: a word searched in Settings")
            settings.navigation.highlighted = settings.navigation.results.first
            try await capture(settingsWindow, size: settingsSize, dark: dark, to: file("window-settings-search"))
            settings.navigation.query = "zzzz"
            try await capture(settingsWindow, size: settingsSize, dark: dark, to: file("window-settings-search-none"))
            settings.navigation.query = ""
            settings.navigation.tab = .general
            // The narrowest Settings allows, to catch clipping.
            try await capture(settingsWindow, size: CGSize(width: 760, height: 520), dark: dark, to: file("window-settings-general-small"))
            settingsWindow.orderOut(nil)

            let aboutWindow = SnapshotWindow()
            let aboutUpdates = UpdateModel()
            aboutUpdates.phase = .upToDate
            AboutWindowController.configure(aboutWindow, updates: aboutUpdates)
            try await capture(aboutWindow, size: CGSize(width: 420, height: 520), dark: dark, to: file("window-about"))
            aboutWindow.orderOut(nil)

            // The update window in each state it has words for (D46).
            for (name, phase, plan) in updatePhases {
                let model = UpdateModel()
                (model.running, model.lastCheck, model.phase, model.plan) = ("0.1.0 snapshot 411", Date().addingTimeInterval(-120), phase, plan)
                let window = SnapshotWindow()
                UpdateWindowController.configure(window, model: model)
                try await capture(window, size: CGSize(width: 560, height: 460), dark: dark, to: file("window-update-\(name)"))
                window.orderOut(nil)
            }

            // Full pages.
            func page(_ name: String, _ view: some View, width: CGFloat) async throws {
                try await capturePage(view, width: width, dark: dark, to: file(name))
            }
            full.selection = .now
            try await page("page-today", TodayView(model: full), width: 1100)
            try await page("page-today-empty", TodayView(model: empty), width: 1100)
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
            // Its update waiting (D89): the page's strip, and Settings › Add-ons' rows with their new versions.
            SampleAddonUpdates.show(in: fixtures.updates, catalog: try SampleCompanions.catalog(), halfway: false)
            let clipboardUpdate = SampleExtensionPage.clipboard()
            clipboardUpdate.updates = fixtures.updates
            try await page("page-extension-clipboard-update", ExtensionPageView(model: clipboardUpdate), width: 980)
            try await page("page-extension-clipboard-update-narrow", ExtensionPageView(model: clipboardUpdate), width: 640)
            try await page("page-settings-addons-updates", SettingsTabContent(tab: .addons, model: settings), width: 690)
            SampleAddonUpdates.clear(fixtures.updates)
            // Miraya in each of its states (D74): a hero with the one thing to do, TVs beside, pictures to pick from.
            for state in ["notv", "ready", "window", "area", "norecord", "pairing", "authorizing", "sharing", "paused", "playing", "problem"] {
                try await page("page-extension-miraya-\(state)", ExtensionPageView(model: SampleExtensionPage.miraya(state)), width: 1180)
            }
            try await page("page-extension-miraya-ready-narrow", ExtensionPageView(model: SampleExtensionPage.miraya("ready")), width: 640)
            try await page("page-extension-miraya-ready-wide", ExtensionPageView(model: SampleExtensionPage.miraya("ready")), width: 1560)
            for state in ["sharing", "paused", "pairing", "area", "window"] {
                try await page("page-extension-miraya-\(state)-narrow", ExtensionPageView(model: SampleExtensionPage.miraya(state)), width: 640)
            }
            let audioPage = SampleExtensionPage.miraya("ready")
            audioPage.toggleOpen("Picture & sound")
            try await page("page-extension-miraya-audio-narrow", ExtensionPageView(model: audioPage), width: 640)
            // With Full access on, Today leads with it (D37).
            let homePolicy = try await full.services.runtime.permissions.policy()
            try await full.services.runtime.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
            await full.now.reload()
            try await page("page-today-full-access", TodayView(model: full), width: 1100)
            try await full.services.runtime.permissions.setPolicy(homePolicy)
            await full.now.reload()
            let width: CGFloat = 690
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
            let fullAccessEnds = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
            await settings.setPolicy { $0.choose(.fullAccess, fullAccessEnds: fullAccessEnds); $0.unanswered = UnansweredRule(action: .stop, minutes: 30) }
            try await page("page-settings-trust-full-access", SettingsTabContent(tab: .trust, model: settings), width: width)
            await settings.setPolicy { $0 = policy }
            // What Full access means, and when it ends (D84).
            try await page("sheet-full-access", FullAccessSheet(model: settings), width: Theme.Size.sheet + 40)
            // The menu bar's Pocket in the states that read differently (D84).
            for (name, content) in SamplePocket.states(name: settings.settings.companionName) {
                let pocket = PocketModel()
                pocket.content = content
                try await page("panel-pocket-\(name)", PocketView(model: pocket), width: 340)
            }
            // Attention in Focus until five, with two things held, then Quiet for good with quiet hours on (D84).
            let five = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
            settings.setAttention(.focus, until: max(five, Date().addingTimeInterval(3500)))
            await settings.services.runtime.attention.update { $0.focus = true }
            for title in ["Codex finished in pockito", "Pricing page changed"] {
                _ = await settings.services.runtime.attention.post(AttentionRequest(level: .gentle, source: "watcher", title: title))
            }
            await settings.refreshHeld()
            try await page("page-settings-attention-focus", SettingsTabContent(tab: .attention, model: settings), width: width)
            settings.update { $0.quietHours.on = true }
            settings.setAttention(.quiet, until: nil)
            await settings.services.runtime.attention.update { $0.focus = false; $0.quiet = true }
            try await page("page-settings-attention-quiet", SettingsTabContent(tab: .attention, model: settings), width: width)
            settings.update { $0.quietHours.on = false }
            settings.setAttention(.open, until: nil)
            await settings.services.runtime.attention.update { $0.quiet = false }
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
            if let catalog = settings.gallery.catalog {
                settings.gallery.showSample(catalog: catalog, companions: SampleCompanions.installed + localCompanions,
                                            progress: ["dev.sidefolk.companions.nori": 0.45, "dev.sidefolk.companions.acorn": 0.8])
                try await page("page-home-gallery-downloading", HomeGalleryView(settings: settings), width: 1100)
                for (name, id) in [("get", "dev.sidefolk.companions.rune"), ("owned", "io.github.lenak.pebble"),
                                   ("downloading", "dev.sidefolk.companions.nori"), ("update", "dev.sidefolk.companions.ember")] {
                    if let entry = catalog.entry(id) {
                        try await page("sheet-companion-detail-\(name)", CompanionGalleryDetail(entry: entry, model: settings), width: 520)
                    }
                }
                settings.gallery.showSample(catalog: catalog, companions: SampleCompanions.installed + localCompanions)
            }
            try await page("sheet-companion-add", AddCompanionOptions(model: settings).background(Theme.surfaceRaised), width: 380)
            // The menus can't be drawn open; their items for each kind of companion, as a list.
            try await page("sheet-companion-menus", SampleCompanions.menus(chooser), width: 600)
            try await page("sheet-companion-remove", SampleCompanions.removals(chooser, settings: settings.settings), width: 480)
            // Settings › AI with each provider chosen, in the states that need different words.
            for (name, choice, setUp) in aiStates {
                setUp(fixtures, settings)
                settings.ai.choose(choice)
                await settings.ai.refresh()
                try await page("page-settings-ai-\(name)", SettingsPage { AISettingsSections(model: settings) }, width: width)
            }
            fixtures.detection = FixtureServices.sampleDetection
            settings.ai.choose(.codex)
            await settings.ai.refresh()
            await settings.ai.test()
            try await page("page-settings-ai-sent", SettingsPage { AISettingsSections(model: settings, showPayload: true) }, width: width)
            // Settings › Voice turned on, in the states that need different words (D34).
            for (name, setUp) in voiceStates {
                setUp(fixtures.voice, settings)
                await settings.voice.refresh()
                try await page("page-settings-voice-\(name)", SettingsPage { VoiceSettingsSections(model: settings) }, width: width)
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
                ask.companionName = "Mochi"
                ask.tail = SidecardTail(edge: .trailing, at: 0.85)
                try await page(name, AskView(model: ask, companionName: "Mochi", portrait: portrait, hotkey: "⇧⌘Space").background(Wallpaper()),
                               width: Theme.Size.sidecardAsk + 48)
            }
            // Permission slips alone above the companion (D84): calm from your own words, firm from another app or
            // after outside content, with the exact request unfolded.
            for (name, request, exact) in DesktopScenes.slips() {
                let slip = PermissionSlip(request: request, look: request.extensionId.map { ExtensionLook(name: $0.hasSuffix("miraya") ? "Miraya" : $0) },
                                          companionName: "Mochi", tail: SidecardTail(edge: .bottom, at: 0.8), standalone: true, exactOpen: exact,
                                          decide: { _ in }, changeMode: {})
                try await page("desktop-slip-\(name)", slip.padding(AskView.margin).frame(maxWidth: .infinity).background(Wallpaper()),
                               width: Theme.Size.sidecardMax + 48)
            }
            // The desktop of D84: the Sidecard's moments, every state of the light, and the companion on its floor.
            let face = CompanionArt.avatar(for: AppSettings(), side: 48)
            let still = CompanionArt.portrait(for: AppSettings(), side: 300)
            for (name, moment) in DesktopScenes.sidecards(face: face) {
                try await page("desktop-sidecard-\(name)", SidecardView(model: moment).frame(maxWidth: .infinity).background(Wallpaper()), width: 470)
            }
            try await page("desktop-states", DesktopScenes.statesBoard(portrait: still), width: 1100)
            for (name, floor, measure) in DesktopScenes.scenes(portrait: still, face: face) {
                try await page("desktop-floor-\(name)", FloorScene(portrait: still, floor: floor, height: floor.sidecard == nil ? 300 : 520,
                                                                   measure: measure), width: 760)
            }
            for (name, caption) in sampleTosses(face: portrait) {
                try await page("desktop-toss-\(name)", CaptionView(model: caption), width: 300)
            }
            // The Play panel in each state, and the moment a clash is halfway (D75).
            for (name, model, at) in await SamplePlayBoards.models(portrait: portrait) where wantedName("game-\(name)") {
                try await page("game-\(name)", PlayView(model: model).environment(\.revealProgress, at), width: PlayView.width)
            }
            // The panel's menu of games, its home (D79 amended).
            if wantedName("game-menu") {
                try await page("game-menu", PlayMenuView(menu: SamplePlayBoards.menu(from: gameBoards, portrait: portrait)), width: PlayView.width)
            }
            // Playtime's real boards, every game and moment, when a folder of them is given (`--game-boards`).
            if let boards = gameBoards {
                for (name, model) in await SamplePlayBoards.real(from: boards, portrait: portrait) where wantedName("play-\(name)") {
                    try await page("play-\(name)", PlayView(model: model).environment(\.revealProgress, 1), width: PlayView.width)
                }
            }

            // Lantern's design-system sheet (D84): tokens and shared components, the reference for every screen.
            for sheet in DesignSystemSheet.Page.allCases {
                try await page("design-system-\(sheet.rawValue)", DesignSystemSheet(page: sheet), width: 1600)
            }
            // Reduce Transparency with Increase Contrast (D84 phase 5): solid surfaces and edges at a control's strength.
            func accessible(_ name: String, _ view: some View, width: CGFloat) async throws {
                // A view can't turn the system settings on; these stand in for them (the hairline colour itself follows
                // the high-contrast appearance, which a snapshot window can't take).
                try await capturePage(view.environment(\.solidSurfaces, true).environment(\._colorSchemeContrast, .increased),
                                      width: width, dark: dark, to: file("a11y-\(name)"))
            }
            try await accessible("design-system-sidecard", DesignSystemSheet(page: .sidecard), width: 1600)
            try await accessible("page-today", TodayView(model: full), width: 1100)
            if let (_, content) = SamplePocket.states(name: full.companionName).first {
                let pocket = PocketModel()
                pocket.content = content
                try await accessible("panel-pocket", PocketView(model: pocket), width: 340)
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
            try await page("sheet-install-extension", InstallPreviewSheet(preview: FixtureServices.samplePreview, model: settings), width: 600)
            try await page("sheet-install-draft", InstallPreviewSheet(preview: FixtureServices.draftPreview, model: settings), width: 600)
            // One per source (D71): Sidefolk's own from the gallery, the same permissions from a folder, an update asking for more.
            try await page("sheet-install-gallery", InstallPreviewSheet(preview: FixtureServices.galleryPreview, model: settings), width: 600)
            try await page("sheet-install-unknown", InstallPreviewSheet(preview: FixtureServices.unknownMirrorPreview, model: settings), width: 600)
            try await page("sheet-install-update", InstallPreviewSheet(preview: FixtureServices.updatePreview, model: settings), width: 600)
            // The passport's second step: what it can touch (D84).
            for (name, preview) in [("extension", FixtureServices.samplePreview), ("draft", FixtureServices.draftPreview),
                                    ("gallery", FixtureServices.galleryPreview), ("unknown", FixtureServices.unknownMirrorPreview),
                                    ("update", FixtureServices.updatePreview)] {
                try await page("sheet-install-\(name)-touch", InstallPreviewSheet(preview: preview, model: settings, step: .touch), width: 600)
            }
            try await page("sheet-add-mcp-server", AddServerSheet(model: settings), width: 500)
            try await page("sheet-delete-all", DeleteAllSheet(model: settings), width: 440)
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
