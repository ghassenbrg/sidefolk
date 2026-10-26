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
            let width = SettingsWindowController.width
            for tab in SettingsTab.allCases {
                try await page("page-settings-\(tab.rawValue)", SettingsTabContent(tab: tab, model: settings), width: width)
            }
            // The companion chooser with Spark chosen, then the robot in coral with a scarf.
            settings.update { $0.choose(.spark) }
            try await page("page-settings-companion-spark", SettingsTabContent(tab: .companion, model: settings), width: width)
            settings.update { $0.choose(.sidefolk); $0.setStyle(CompanionStyle(color: .coral, accessory: .scarf), for: .sidefolk) }
            try await page("page-settings-companion-coral", SettingsTabContent(tab: .companion, model: settings), width: width)
            settings.update { $0.choose(.mochi); $0.styles = [:] }
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

            // Desktop surfaces: the Ask panel and the kinds of bubble.
            try await page("desktop-ask", AskView(model: sampleAsk(), companionName: "Mochi",
                                                      portrait: CompanionArt.portrait(for: AppSettings(), side: 44), hotkey: "⇧⌘Space"), width: 380)
            try await page("desktop-ask-apple-notes", AskView(model: sampleAskAppleNotes(), companionName: "Mochi",
                                                                  portrait: CompanionArt.portrait(for: AppSettings(), side: 44), hotkey: "⇧⌘Space"),
                           width: 380)
            for (name, bubble) in sampleBubbles() {
                try await page("desktop-bubble-\(name)", BubbleView(model: bubble), width: 320)
            }

            // Sheets.
            try await page("sheet-new-collection", CollectionSheet(mode: .create, model: full.notebook) { _ in }, width: 400)
            try await page("sheet-install-extension", InstallPreviewSheet(preview: FixtureServices.samplePreview, model: settings), width: 480)
            try await page("sheet-add-mcp-server", AddServerSheet(model: settings), width: 500)
            try await page("sheet-delete-all", DeleteAllSheet(model: settings), width: 440)
        }
        print("ui-snapshots: wrote \(dir.path) (\(Bundle.main.preferredLocalizations.first ?? "en"))")
    }

    // MARK: Fixtures

    private static func runtime() async throws -> SidefolkRuntime {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-ui-\(UUID().uuidString)", isDirectory: true)
        let rt = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform())
        try await rt.notebook.inbox()
        return rt
    }

    private static func makeHome(empty: Bool) async throws -> (HomeModel, SampleData.Created?) {
        let rt = try await runtime()
        let model = HomeModel(services: FixtureServices(runtime: rt))
        let sample = empty ? nil : try await SampleData.fill(rt, notebook: model.notebook)
        await model.reloadAll()
        return (model, sample)
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

    /// Organizing Apple Notes (D38): a batch copied, macOS refusing Reminders, the next read waiting.
    private static func sampleAskAppleNotes() -> AskModel {
        let ask = AskModel()
        ask.add(.result(ResultCard(kind: .note, title: String(localized: "Copied 25 notes from Apple Notes"), subtitle: "Cooking, Travel, Work",
                                   detail: String(localized: "\(75) of \(214) copied so far"), itemKind: .note), activityId: nil, undo: true),
                caption: "check my Apple Notes and move them, well organized, into our notebook")
        ask.add(.result(MacApp.reminders.permissionCard, activityId: nil, undo: false), caption: "what's on my Apple Reminders?")
        ask.add(.approval(ApprovalRequest(tool: "applenotes.list", title: String(localized: "List Apple Notes"),
                                          summary: "Read the titles, folders and dates of up to 50 notes in “Recipes” in Apple Notes",
                                          risk: .medium, caller: .agent(runId: "r"), details: .none, canAlways: true, readsOnly: true)))
        ask.add(.approval(ApprovalRequest(tool: "applenotes.remove", title: String(localized: "Remove notes from Apple Notes"),
                                          summary: "Move 2 notes in Apple Notes to Recently Deleted", risk: .high, caller: .agent(runId: "r"),
                                          details: .text("“Pasta carbonara” (iCloud › Recipes)\n“Sourdough” (iCloud › Recipes)\n\n"
                                                         + "Their copies stay in your notebook. Notes keeps deleted notes in Recently Deleted for 30 days."),
                                          canAlways: false, tainted: true)))
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
