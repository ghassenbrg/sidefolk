import Foundation
import Observation
import SidefolkCore

/// Extensions' pages in Home (D62): which there are, and one model per page while it is shown.
@MainActor @Observable
final class ExtensionPagesModel {
    let services: AppServices
    private(set) var list: [ExtensionPageInfo] = []
    private var models: [String: ExtensionPageModel] = [:]

    init(services: AppServices) {
        self.services = services
    }

    func reload() async {
        list = await services.runtime.extensions.pages()
        let ids = Set(list.map(\.id))
        models = models.filter { ids.contains($0.key) }
    }

    func info(_ id: String) -> ExtensionPageInfo? { list.first { $0.id == id } }

    /// The page's model, kept while Home is open so its charts and window choice survive switching away.
    func model(_ info: ExtensionPageInfo) -> ExtensionPageModel {
        if let m = models[info.id] { return m }
        let m = ExtensionPageModel(info: info, services: services)
        models[info.id] = m
        return m
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
        await run(tool: control.tool, input: control.input(switchedTo: on))
    }

    /// A switch, button, choice, field or list row's tool (D63, D68): whether it ran without a problem.
    @discardableResult
    func run(tool: String, input: JSONValue) async -> Bool {
        guard let services else { return false }
        let short = String(info.extensionId.split(separator: ".").last ?? "")
        let outcome = await services.runtime.executor.execute(name: ExtensionTool.registryName(short: short, tool: tool), input: input, caller: .user)
        await refresh()
        // After the read, which clears any earlier problem: what went wrong with this click stays in sight.
        if let why = outcome.problem?.message { problem = why }
        return outcome.problem == nil
    }

    /// Where the extension's pictures are (`ExtensionDataFile`); nil in UI snapshots.
    var folder: URL? { services?.runtime.extensions.dataFolder(extensionId: info.extensionId) }

    static var language: String { Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en" }
}
