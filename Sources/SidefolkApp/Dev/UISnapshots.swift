import AppKit
import SidefolkCore
import SwiftUI

/// Renders the Home and Settings windows with sample data to PNGs, in light and dark, then exits:
/// `SidefolkApp --ui-snapshots <dir>`. Lets agents (who can't see the screen) review the UI.
/// Uses an in-memory database, a temp home and fixture services: no real data is read or touched.
enum UISnapshots {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--ui-snapshots"), flag + 1 < args.count else { return }
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

    private static let homeSize = CGSize(width: 1100, height: 740)

    private static func render(into dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (full, filled) = try await makeHome(empty: false)
        let (empty, _) = try await makeHome(empty: true)
        guard let sample = filled else { return }
        let settings = try await makeSettings()

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            func shot(_ name: String, _ view: some View, size: CGSize = homeSize, fullHeight: Bool = false) async throws {
                try await snapshot(view, size: size, dark: dark, fullHeight: fullHeight, to: dir.appendingPathComponent("\(name)-\(suffix).png"))
            }

            // Home
            full.selection = .now
            try await shot("home-now", HomeView(model: full, flatLayout: true))
            try await shot("home-now-page", NowView(model: full.now), size: CGSize(width: 870, height: 0), fullHeight: true)
            await full.reveal(sample.selectedItem)
            try await shot("home-notebook", HomeView(model: full, flatLayout: true))
            await full.reveal(sample.profileItem)
            try await shot("home-about-you", HomeView(model: full, flatLayout: true))
            full.selection = .trash
            await full.notebook.reloadTrash()
            try await shot("home-trash", HomeView(model: full, flatLayout: true))
            full.selection = .activity
            await full.activity.reload()
            try await shot("home-activity", HomeView(model: full, flatLayout: true))

            // The smallest window Home allows, to catch clipping and overflow.
            let small = CGSize(width: 860, height: 560)
            try await shot("home-activity-small", HomeView(model: full, flatLayout: true), size: small)
            full.selection = .now
            try await shot("home-now-small", HomeView(model: full, flatLayout: true), size: small)
            await full.reveal(sample.selectedItem)
            try await shot("home-notebook-small", HomeView(model: full, flatLayout: true), size: small)

            empty.selection = .now
            try await shot("home-now-empty", HomeView(model: empty, flatLayout: true))
            if let inbox = empty.notebook.inboxId {
                empty.selection = .collection(inbox)
                await empty.notebook.show(collectionId: inbox)
            }
            try await shot("home-notebook-empty", HomeView(model: empty, flatLayout: true))
            empty.selection = .activity
            try await shot("home-activity-empty", HomeView(model: empty, flatLayout: true))
            try await shot("sheet-new-collection", CollectionSheet(mode: .create, model: full.notebook) { _ in },
                           size: CGSize(width: 400, height: 0), fullHeight: true)

            // Settings
            let width = SettingsWindowController.width
            for tab in SettingsTab.allCases {
                try await shot("settings-\(tab.rawValue)", SettingsTabContent(tab: tab, model: settings),
                               size: CGSize(width: width, height: 0), fullHeight: true)
            }
            for kind in [ProviderKind.anthropic, .openAICompatible, .none] {
                settings.setProvider(kind)
                try await Task.sleep(for: .milliseconds(50))
                try await shot("settings-ai-\(kind.rawValue)", SettingsTabContent(tab: .ai, model: settings),
                               size: CGSize(width: width, height: 0), fullHeight: true)
            }
            settings.setProvider(.claudeCode)
            await settings.checkProvider()
            try await shot("settings-ai-sent", AISettingsView(model: settings, showPayload: true),
                           size: CGSize(width: width, height: 0), fullHeight: true)
            try await shot("sheet-install-extension", InstallPreviewSheet(preview: FixtureServices.samplePreview, model: settings),
                           size: CGSize(width: 480, height: 0), fullHeight: true)
            try await shot("sheet-add-mcp-server", AddServerSheet(model: settings), size: CGSize(width: 500, height: 0), fullHeight: true)
            try await shot("sheet-delete-all", DeleteAllSheet(model: settings), size: CGSize(width: 440, height: 0), fullHeight: true)
        }
        print("ui-snapshots: wrote \(dir.path)")
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

    private static func makeSettings() async throws -> SettingsModel {
        let rt = try await runtime()
        let services = FixtureServices(runtime: rt, keys: [.anthropic])
        _ = try await SampleData.fill(rt, notebook: NotebookModel(services: services))
        let model = SettingsModel(services: services)
        await model.refresh()
        return model
    }

    // MARK: Rendering

    /// Window that draws as if focused, so controls render in their active colors.
    private final class SnapshotWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
    }

    /// Draws `view` offscreen with AppKit (ImageRenderer can't draw AppKit-backed controls such as
    /// switches, pop-up buttons, text fields and tables).
    private static func snapshot(_ view: some View, size: CGSize, dark: Bool, fullHeight: Bool, to url: URL) async throws {
        let content = view
            .environment(\.rendersFullPage, fullHeight)
            .frame(width: size.width, height: fullHeight ? nil : size.height)
            .fixedSize(horizontal: false, vertical: fullHeight)
            .background(Theme.surface)
        let host = NSHostingView(rootView: content)
        let window = SnapshotWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: max(size.height, 200)),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(250))
        if fullHeight {
            let height = max(host.fittingSize.height, 100)
            window.setContentSize(NSSize(width: size.width, height: height))
            try await Task.sleep(for: .milliseconds(250))
        }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SnapshotError.render(url.lastPathComponent) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.render(url.lastPathComponent) }
        try png.write(to: url)
        window.orderOut(nil)
    }

    enum SnapshotError: Error { case render(String) }
}
