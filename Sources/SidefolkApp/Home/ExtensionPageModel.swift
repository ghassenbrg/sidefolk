import Foundation
import Observation
import SidefolkCore

/// Extensions' pages in Home (D62): which there are, how the person arranged them (D67), what each said last, and one
/// model per page while it is shown.
@MainActor @Observable
final class ExtensionPagesModel {
    /// All Extensions (D67), every extension's page and tile in one place: `.page(hub)`. A page's own id is
    /// `<extension id>/<page>`, never a slash alone, so this one can't be taken; it is `hubInfo`'s id.
    static let hub = "/"
    /// All Extensions standing in a list of pages, where a navigation shows pages by their title and symbol.
    static var hubInfo: ExtensionPageInfo {
        ExtensionPageInfo(extensionId: "", extensionName: "", page: "", title: String(localized: "All Extensions",
                          comment: "Home's sidebar: the page listing every extension's page and tile"), symbol: "square.grid.2x2")
    }

    let services: AppServices
    private(set) var list: [ExtensionPageInfo] = []
    /// What each page said last, by page, for pages Sidefolk reads in the background (`widget`, `history`).
    private(set) var summaries: [String: ExtensionPage.Summary] = [:]
    private(set) var layout = HomePages()
    /// A switch flipped from the sidebar or a tile, until the page confirms it.
    private(set) var switching: [String: Bool] = [:]
    var problem: String?
    /// Today's tiles follow what changed here; set by Home.
    var changed: (() -> Void)?
    private var models: [String: ExtensionPageModel] = [:]

    init(services: AppServices) {
        self.services = services
    }

    /// The pages the sidebar lists, in the person's order.
    var shown: [ExtensionPageInfo] {
        let byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return layout.shown(list.map(\.id)).compactMap { byId[$0] }
    }

    /// Every page, in the person's order, the hidden ones too.
    var all: [ExtensionPageInfo] {
        let byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return layout.sorted(list.map(\.id)).compactMap { byId[$0] }
    }

    func reload() async {
        list = await services.runtime.extensions.pages()
        layout = services.runtime.settings.current.homePages
        let ids = Set(list.map(\.id))
        models = models.filter { ids.contains($0.key) }
        await refreshSummaries()
    }

    func info(_ id: String) -> ExtensionPageInfo? { list.first { $0.id == id } }

    /// The page's model, kept while Home is open so its charts and window choice survive switching away.
    func model(_ info: ExtensionPageInfo) -> ExtensionPageModel {
        if let m = models[info.id] { return m }
        let m = ExtensionPageModel(info: info, services: services)
        m.onControl = { [weak self] in
            Task {
                await self?.refreshSummaries()
                self?.changed?()
            }
        }
        models[info.id] = m
        return m
    }

    /// While Home is open: the background readings (once a minute, D62) reach the sidebar's switches and Today's tiles,
    /// so "25 min left" counts down without a click.
    func follow() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30), tolerance: .seconds(5))
            guard !Task.isCancelled else { return }
            await refreshSummaries()
            changed?()
        }
    }

    // MARK: What each page says

    /// The last reading of the pages Sidefolk reads anyway (D62): their summary and main switch for the sidebar and
    /// the Extensions page. Nothing is read here that wouldn't be read in the background.
    func refreshSummaries() async {
        let host = services.runtime.extensions
        var out: [String: ExtensionPage.Summary] = [:]
        for info in list where info.widget || info.history {
            if let latest = await host.latestPage(extensionId: info.extensionId, page: info.page), let summary = latest.page.summary {
                out[info.id] = summary
            }
        }
        if out != summaries { summaries = out }
    }

    /// The page's main switch (or button, `on` nil), from where it was flipped: the extension's own tool, run as the person through Guard
    /// (D63), then the page read again so every place showing it agrees.
    func flip(_ info: ExtensionPageInfo, _ control: ExtensionPage.Control, on: Bool?) async {
        switching[info.id] = on ?? isOn(info.id) ?? false
        problem = await ExtensionControl.run(control, on: on, extensionId: info.extensionId, services: services)
        if let page = try? await services.runtime.extensions.renderPage(extensionId: info.extensionId, page: info.page,
                                                                      language: ExtensionPageModel.language),
           let summary = page.summary {
            summaries[info.id] = summary
        }
        switching[info.id] = nil
        await models[info.id]?.refresh()
        changed?()
    }

    /// Where the switch stands: the flip under way, else what the page said.
    func isOn(_ id: String) -> Bool? {
        if let pending = switching[id] { return pending }
        guard case .toggle(let on)? = summaries[id]?.control?.kind else { return nil }
        return on
    }

    // MARK: Arranging

    func setInSidebar(_ id: String, _ on: Bool) { arrange { $0.setInSidebar(id, on) } }
    func setTile(_ id: String, _ on: Bool) { arrange { $0.setTile(id, on) } }
    func setCollapsed(_ collapsed: Bool) { arrange { $0.collapsed = collapsed } }
    func step(_ id: String, by delta: Int) { arrange { [ids = list.map(\.id)] in $0.step(id, by: delta, among: ids) } }
    func move(_ id: String, before: String?) { arrange { [ids = list.map(\.id)] in $0.move(id, before: before, among: ids) } }

    /// Changes the arrangement at once on screen, saves it, and tells Today (a tile may have come or gone).
    private func arrange(_ change: @escaping @Sendable (inout HomePages) -> Void) {
        change(&layout)
        Task {
            await services.runtime.settings.update { change(&$0.homePages) }
            changed?()
        }
    }
}

/// A switch or button an extension put on its page (D63, D67): its own tool, run as the person through Guard, never a
/// side door. Returns what went wrong, if anything.
enum ExtensionControl {
    @MainActor
    static func run(_ control: ExtensionPage.Control, on: Bool?, extensionId: String, services: AppServices) async -> String? {
        let short = String(extensionId.split(separator: ".").last ?? "")
        let outcome = await services.runtime.executor.execute(name: ExtensionTool.registryName(short: short, tool: control.tool),
                                                              input: control.input(switchedTo: on), caller: .user)
        return outcome.problem?.message
    }
}

/// One extension page while it is open: what the extension says now, refreshed as often as its manifest asks, the
/// past of its charts from Sidefolk's history, and its heads-ups (the extension's watchers) to switch on or off.
@MainActor @Observable
final class ExtensionPageModel {
    enum Window: Int, CaseIterable, Identifiable {
        case tenMinutes = 600, hour = 3600, day = 86_400
        var id: Int { rawValue }
        var seconds: TimeInterval { TimeInterval(rawValue) }
    }

    /// A watcher the extension offers, and the one running for it if any.
    struct Alert: Identifiable, Equatable {
        var kind: ExtensionWatcherKind
        var watcherId: String?
        var id: String { kind.watcher }
    }

    let info: ExtensionPageInfo
    private let services: AppServices?
    private(set) var page: ExtensionPage?
    var problem: String?
    private(set) var updated: Date?
    private(set) var history: [String: [ExtensionPageHistory.Point]] = [:]
    private(set) var alerts: [Alert] = []
    private(set) var alertProblem: String?
    /// The extension's palettes, with their shortcuts (D63).
    private(set) var palettes: [ExtensionPaletteInfo] = []
    /// Home hears when a switch on the page ran, so the sidebar and Today's tile show the new state.
    var onControl: (() -> Void)?
    var window: Window = .tenMinutes {
        didSet { if window != oldValue { Task { await loadHistory() } } }
    }

    init(info: ExtensionPageInfo, services: AppServices) {
        self.info = info
        self.services = services
    }

    /// A page with nothing behind it, for UI snapshots.
    init(info: ExtensionPageInfo, page: ExtensionPage, history: [String: [ExtensionPageHistory.Point]], alerts: [Alert], updated: Date) {
        self.info = info
        services = nil
        self.page = page
        self.history = history
        self.alerts = alerts
        self.updated = updated
    }

    /// Refreshes while the page is shown: the view runs it in its `.task`, which ends it when the page goes away.
    func run() async {
        guard let services else { return }
        palettes = await services.runtime.extensions.palettes().filter { $0.extensionId == info.extensionId }
        await loadAlerts()
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(info.refresh), tolerance: .seconds(Double(info.refresh) / 10))
        }
    }

    func refresh() async {
        guard let host = services?.runtime.extensions else { return }
        do {
            page = try await host.renderPage(extensionId: info.extensionId, page: info.page, language: Self.language)
            problem = nil
            updated = Date()
        } catch {
            problem = (error as? UserFacingError)?.message ?? String(localized: "The page couldn't be read.")
        }
        await loadHistory()
    }

    func loadHistory() async {
        guard let host = services?.runtime.extensions, let page else { return }
        var out: [String: [ExtensionPageHistory.Point]] = [:]
        let now = Date()
        for key in page.samples.keys {
            out[key] = await host.pageHistory.points(extensionId: info.extensionId, page: info.page, key: key, window: window.seconds, now: now)
        }
        history = out
    }

    func points(chart: String, series: String) -> [ExtensionPageHistory.Point] { history["\(chart)/\(series)"] ?? [] }

    // MARK: Heads-ups

    func loadAlerts() async {
        guard let runtime = services?.runtime else { return }
        let kinds = await runtime.extensions.watcherKinds().filter { $0.extensionId == info.extensionId }
        let running = await runtime.watchers.list().filter { $0.kind == "extension" && $0.state != .expired && $0.state != .triggered }
        alerts = kinds.map { kind in
            let w = running.first { $0.config.string("extension") == info.extensionId && $0.config.string("watcher") == kind.watcher }
            return Alert(kind: kind, watcherId: w?.id)
        }
    }

    /// Starts the watcher with its default settings, checking every five minutes and telling again after things
    /// went back to normal; or stops it. Starting goes through Guard like any tool the person runs.
    func setAlert(_ alert: Alert, on: Bool) async {
        guard let services else { return }
        alertProblem = nil
        if on {
            let input: JSONValue = ["extension": .string(info.extensionId), "watcher": .string(alert.kind.watcher),
                                    "title": .string(alert.kind.title), "interval_minutes": 5, "mode": "repeat"]
            let outcome = await services.runtime.executor.execute(name: "watch.extension", input: input, caller: .user)
            if let problem = outcome.problem { alertProblem = problem.message }
        } else if let id = alert.watcherId {
            await services.stopWatcher(id)
        }
        await loadAlerts()
    }

    func ask(_ text: String) { services?.ask(text, how: .auto) }

    /// A switch or button: the extension's own tool, run as the person through Guard (D63), then the page again.
    func run(_ control: ExtensionPage.Control, on: Bool?) async {
        guard let services else { return }
        let why = await ExtensionControl.run(control, on: on, extensionId: info.extensionId, services: services)
        await refresh()
        // After the read, which clears any earlier problem: what went wrong with this click stays in sight.
        if let why { problem = why }
        onControl?()
    }

    static var language: String { Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en" }
}
