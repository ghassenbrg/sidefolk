import AppKit
import Foundation
import Observation
import SidefolkCore
import UniformTypeIdentifiers

/// Extensions' pages in Home (D62): which there are, how the person arranged them (D67), what each said last, and one
/// model per page while it is shown.
@MainActor @Observable
final class ExtensionPagesModel {
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
    /// A heads-up switched off stops its watch, which Home asks about first, as for every watch (`WatchStopAsk`).
    var askToStop: ((_ id: String, _ title: String) -> Void)?
    private var models: [String: ExtensionPageModel] = [:]

    init(services: AppServices) {
        self.services = services
    }

    /// The pages the sidebar lists, in the person's order.
    var shown: [ExtensionPageInfo] {
        let byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return layout.shown(list.map(\.id)).compactMap { byId[$0] }
    }

    /// Pages the person put out of the sidebar (D67): one menu row lists them, with the way back.
    var hidden: [ExtensionPageInfo] { all.filter { !layout.inSidebar($0.id) } }

    /// Extensions working in the background now: a page whose main switch is on, for On duty (D84).
    var background: [ExtensionPageInfo] { all.filter { isOn($0.id) == true } }
    var backgroundCount: Int { background.count }

    /// Every page, in the person's order, the hidden ones too.
    var all: [ExtensionPageInfo] {
        let byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return layout.sorted(list.map(\.id)).compactMap { byId[$0] }
    }

    func reload() async {
        list = await services.runtime.extensions.pages()
        Describe.learnExtensionNames(Dictionary(list.map { ($0.extensionId, $0.extensionName) }, uniquingKeysWith: { a, _ in a }))
        layout = services.runtime.settings.current.homePages
        let ids = Set(list.map(\.id))
        models = models.filter { ids.contains($0.key) }
        await refreshSummaries()
    }

    func info(_ id: String) -> ExtensionPageInfo? { list.first { $0.id == id } }

    #if DEBUG
    /// Pages and what they said, without extensions behind them: the UI snapshots' sidebar and All Extensions.
    func showSample(_ pages: [ExtensionPageInfo], summaries: [String: ExtensionPage.Summary]) {
        list = pages
        self.summaries = summaries
    }
    #endif

    /// The page's model, kept while Home is open so its charts and window choice survive switching away.
    func model(_ info: ExtensionPageInfo) -> ExtensionPageModel {
        if let m = models[info.id] { return m }
        let m = ExtensionPageModel(info: info, services: services)
        m.askToStop = { [weak self] id, title in self?.askToStop?(id, title) }
        m.onControl = { [weak self] in
            Task {
                await self?.refreshSummaries()
                self?.changed?()
            }
        }
        models[info.id] = m
        return m
    }

    /// A watch was stopped from Home's question: the switches of the pages open now stop showing it on.
    func alertsChanged() async {
        for model in models.values { await model.loadAlerts() }
    }

    /// The page was asked to show something else (D105), and may be open already.
    func moved(_ id: String) async { await models[id]?.refresh() }

    #if DEBUG
    func asks(_ id: String, _ consent: PageConsent) { models[id]?.asking = consent }

    /// The debug app's stand-in for a press of a page's `share`, then for the person's yes.
    func asksToShare(_ id: String, path: String) async { await models[id]?.perform(.share(PageShareAsk(path: path))) }
    func answersShare(_ id: String) async {
        guard let model = models[id], let question = model.sharing else { return }
        model.sharing = nil
        await model.share(question)
    }

    /// The debug app's stand-in for a press of a button that does this.
    func acts(_ id: String, _ act: PageAct) async { await models[id]?.perform(act) }

    func pressInlay(_ id: String, label: String) async -> Bool {
        guard let model = models[id], let page = model.page else { return false }
        for section in page.sections {
            for block in section.blocks {
                guard case .scene(let scene) = block else { continue }
                for inlay in scene.inlays {
                    guard case .control(let control) = inlay.part, control.label == label else { continue }
                    if case .toggle(let on) = control.kind { await model.run(control, on: !on) } else { await model.run(control, on: nil) }
                    return true
                }
            }
        }
        return false
    }
    #endif

    #if DEBUG
    /// A sample page's model for the UI snapshots' window.
    func showSample(page: ExtensionPageModel) { models[page.info.id] = page }
    #endif

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
        // What a page said stays until it says something new (a flip may know sooner than the host's last reading).
        let ids = Set(list.map(\.id))
        var out = summaries.filter { ids.contains($0.key) }
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
        // A sidebar or a tile has no state to change: only a tool runs from there.
        if control.act == nil { problem = await ExtensionControl.run(control, on: on, extensionId: info.extensionId, services: services) }
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
        await run(tool: control.tool, input: control.input(switchedTo: on), extensionId: extensionId, services: services)
    }

    /// The extension's own tool, run as the person through Guard: what went wrong, if anything.
    @MainActor
    static func run(tool: String, input: JSONValue, extensionId: String, services: AppServices) async -> String? {
        let short = String(extensionId.split(separator: ".").last ?? "")
        // A control's input is the author's, not a file the person chose: only a `file` button may name one (D105, D141).
        let paths = await services.runtime.extensions.pathParameters(extensionId: extensionId, tool: tool)
        let outcome = await services.runtime.executor.execute(name: ExtensionTool.registryName(short: short, tool: tool),
                                                              input: input.removing(paths), caller: .user)
        return outcome.problem?.message
    }
}

/// Which folder a page's `share` is asking about: worked out by Sidefolk, whatever path the extension named.
struct PageFolderQuestion: Sendable, Hashable {
    var folder: String
    var write: Bool
}

/// The system's open panel for a page's `file` (D105): the person chooses, and only then does the tool hear of a path.
enum PageFilePanel {
    @MainActor
    static func choose(_ ask: PageFileAsk) async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let types = ask.types.compactMap { UTType(filenameExtension: $0) }
        if !types.isEmpty { panel.allowedContentTypes = types }
        #if DEBUG
        if let chosen = choiceForTest { return chosen }
        #endif
        return await panel.begin() == .OK ? panel.url?.path : nil
    }

    /// The system's save panel: the place is the person's, and only Sidefolk ever knows it.
    @MainActor
    static func chooseWhere(_ ask: PageSaveAsk) async -> URL? {
        #if DEBUG
        if let chosen = choiceForTest { return URL(fileURLWithPath: chosen) }
        #endif
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ask.name
        if let note = ask.note { panel.message = note }
        if let type = UTType(filenameExtension: ask.type) { panel.allowedContentTypes = [type] }
        return await panel.begin() == .OK ? panel.url : nil
    }

    /// An ending outside the list of content kinds can still be one an app says it opens, and some of those run what's in them: only one nothing here opens is plain data.
    static func anAppWouldOpen(_ type: String) -> Bool {
        guard !ExtensionOutputs.allowedEndings.contains(type) else { return false }
        // Asked about a file, since that's how an app's claim on an ending is found: an empty one, of a name no one chose.
        let probe = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(type)")
        guard FileManager.default.createFile(atPath: probe.path, contents: Data()) else { return true }
        defer { try? FileManager.default.removeItem(at: probe) }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    #if DEBUG
    /// The debug app's stand-in for the person: there is no one to click in the panel.
    static var choiceForTest: String?
    #endif
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
    let services: AppServices?
    /// Where its extension's update, if one waits, is said (D89).
    var updates: UpdateModel?
    private(set) var page: ExtensionPage?
    var problem: String? { didSet { if problem != nil { saidAt = Date() } } }
    /// When a problem or a save was last said: a page's next read comes in seconds, and that's too soon to take it away.
    private var saidAt = Date.distantPast
    private var fieldRuns = 0
    private(set) var updated: Date?
    private(set) var history: [String: [ExtensionPageHistory.Point]] = [:]
    private(set) var alerts: [Alert] = []
    private(set) var alertProblem: String?
    /// The extension's palettes, with their shortcuts (D63).
    private(set) var palettes: [ExtensionPaletteInfo] = []
    /// Home hears when a switch on the page ran, so the sidebar and Today's tile show the new state.
    var onControl: (() -> Void)?
    /// Set by the pages model; a page with nobody to ask leaves its watch running.
    var askToStop: ((_ id: String, _ title: String) -> Void)?
    /// Folding sections the person opened or closed (D74), by title, while Home is open.
    private(set) var opened: Set<String> = []
    /// Which tab each set of tabs shows (D100), while Home is open.
    var tabChoices: [String: String] = [:]
    /// What the page was told to remember, and where Back goes (D105), while Home is open.
    private(set) var state = PageState()
    /// The page's column, as the program is told it (D105): what it draws to.
    private(set) var width: Int?
    /// One reading at a time; a change while one is out reads once more after it, so what shows is never older than the last click.
    private var reading = false
    private var readAgain = false
    private var widthWait: Task<Void, Never>?
    /// What a click just put on the clipboard, word for word: nobody should have to trust a button's label for that (SECURITY T12).
    private(set) var copied: String?
    private(set) var saved: String?
    /// Waiting for the person to answer Sidefolk's question (D106, D107).
    var asking: PageConsent?
    /// The folder Sidefolk is asking to share, for a page's `share`.
    var sharing: PageFolderQuestion?
    private var placePurpose: String?
    private var schedulePurpose: String?
    /// The extension's settings and its use of the AI, as the host keeps them (D100).
    var settingRows: [ExtensionSettingRow] = []
    var aiStatus: ExtensionAIStatus?
    /// Its own words for what Sidefolk's switch does are believed only then (D98).
    var signedBySidefolk = false
    /// Pictures from nothing behind them, for UI snapshots.
    var samplePicture: (@MainActor (PagePicture) -> NSImage?)?
    private var pictureCache: [String: NSImage] = [:]
    func toggleOpen(_ title: String) { if opened.contains(title) { opened.remove(title) } else { opened.insert(title) } }
    var window: Window = .tenMinutes {
        didSet { if window != oldValue { Task { await loadHistory() } } }
    }

    init(info: ExtensionPageInfo, services: AppServices) {
        self.info = info
        self.services = services
        updates = services.updates
    }

    /// A page with nothing behind it, for UI snapshots.
    init(info: ExtensionPageInfo, page: ExtensionPage, history: [String: [ExtensionPageHistory.Point]], alerts: [Alert], updated: Date,
         folder: URL? = nil) {
        self.info = info
        services = nil
        sampleFolder = folder
        self.page = page
        self.history = history
        self.alerts = alerts
        self.updated = updated
    }

    /// A page that couldn't be read, for UI snapshots: its extension's words, shown as they are (never as Markdown).
    init(info: ExtensionPageInfo, problem: String) {
        self.info = info
        services = nil
        self.problem = problem
    }

    /// Refreshes while the page is shown: the view runs it in its `.task`, which ends it when the page goes away.
    func run() async {
        guard let services else { return }
        palettes = await services.runtime.extensions.palettes().filter { $0.extensionId == info.extensionId }
        await loadAlerts()
        // The first reading already knows the column's width, so a page that draws to it doesn't draw twice.
        for _ in 0..<15 where width == nil { try? await Task.sleep(for: .milliseconds(20)) }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(info.refresh), tolerance: .seconds(Double(info.refresh) / 10))
        }
    }

    func refresh() async {
        guard let host = services?.runtime.extensions else { return }
        guard !reading else {
            readAgain = true
            return
        }
        reading = true
        defer { reading = false }
        repeat {
            readAgain = false
            for go in await host.takePageMoves(info.id) { state.apply(go) }
            do {
                page = try await host.renderPage(extensionId: info.extensionId, page: info.page, language: Self.language, state: state.json, width: width)
                if Date().timeIntervalSince(saidAt) > 12 {
                    problem = nil
                    saved = nil
                }
                updated = Date()
                await loadSettings()
            } catch {
                problem = (error as? UserFacingError)?.message ?? String(localized: "The page couldn't be read.")
                // It's about the read, so the next good read takes it away.
                saidAt = .distantPast
            }
        } while readAgain
        await loadHistory()
    }

    /// The column changed size: the page draws to it. Rounded and a moment late, so a window being dragged doesn't read the page at every point.
    func setWidth(_ points: CGFloat) {
        let rounded = Int(points / 10) * 10
        guard rounded > 0, rounded != width else { return }
        let first = width == nil
        width = rounded
        guard !first else { return }
        widthWait?.cancel()
        widthWait = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Changes the state and reads the page again (D105). No tool, so nothing in History.
    func go(_ go: PageGo) async {
        guard state.apply(go) else { return }
        await refresh()
    }

    /// What a control does that isn't a tool (D105).
    func perform(_ act: PageAct) async {
        saved = nil
        await handOverTyping()
        switch act {
        case .go(let move):
            await go(move)
        case .copy(let words):
            // Sidefolk's own tool, so the switch for the clipboard holds and History has the exact words.
            let outcome = await services?.runtime.executor.execute(name: "clipboard.write", input: ["text": .string(words)], caller: .user)
            if let why = outcome?.problem?.message { problem = why } else { copied = words }
        case .file(let ask):
            guard let services, let path = await PageFilePanel.choose(ask) else { return }
            // The file they chose, for this one call, and nothing beside it: not the folder it is in (SECURITY T12), not another parameter that names a path.
            let short = String(info.extensionId.split(separator: ".").last ?? "")
            let others = await services.runtime.extensions.pathParameters(extensionId: info.extensionId, tool: ask.tool)
            var input = ask.input.objectValue ?? [:]
            for key in others { input[key] = nil }
            input[ask.param] = .string(path)
            let outcome = await services.runtime.executor.execute(name: ExtensionTool.registryName(short: short, tool: ask.tool), input: .object(input), caller: .user, pickedFile: path)
            await refresh()
            if let why = outcome.problem?.message { problem = why }
            // Reported in its own words, since the call itself went through (D140).
            if case .ok(let result) = outcome.status, result.isError { problem = result.text.clipped(300) }
        case .save(let ask):
            guard let services else { return }
            guard !PageFilePanel.anAppWouldOpen(ask.type) else {
                problem = String(localized: "Sidefolk doesn't save this kind of file from a page.", comment: "An extension's page: it asked to save a kind of file an app on this Mac would open and could run")
                return
            }
            let short = String(info.extensionId.split(separator: ".").last ?? "")
            // A page's input is the author's, not a file the person chose, as for any control (D105, D141).
            let paths = await services.runtime.extensions.pathParameters(extensionId: info.extensionId, tool: ask.tool)
            let outcome = await services.runtime.executor.execute(name: ExtensionTool.registryName(short: short, tool: ask.tool), input: ask.input.removing(paths), caller: .user)
            if let why = outcome.problem?.message { problem = why; return }
            guard case .ok(let result) = outcome.status else { return }
            if result.isError { problem = result.text.clipped(300); return }
            // What a tool answers is cut for a model, so the file is handed over in its data folder. It stays for the program to tidy: a folder on the way there could be a link it made, so nothing is removed on its word.
            let name = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let folder, let bytes = ExtensionDataFile.readSaved(name, type: ask.type, in: folder, limit: PageSaveAsk.longest) else {
                problem = String(localized: "That couldn't be saved: the file is missing or too big.", comment: "An extension's page: the file it made to save can't be read or is over the limit")
                return
            }
            guard let place = await PageFilePanel.chooseWhere(ask) else { return }
            do {
                try bytes.write(to: place, options: .atomic)
                PageSaveAsk.markAsDownloaded(place)
                saved = place.lastPathComponent
                problem = nil
                saidAt = Date()
            } catch {
                problem = String(localized: "That couldn't be saved there.", comment: "An extension's page: the file couldn't be written where the person chose")
            }
        case .dropCard:
            services?.chooseFilesForCard()
        case .allow(let consent):
            asking = consent
        case .share(let ask):
            switch ask.folder() {
            case .success(let folder): sharing = PageFolderQuestion(folder: folder, write: ask.write)
            case .failure(let why): problem = why.message
            }
        case .palette(let name):
            services?.openPalette("\(info.extensionId)/\(name)")
        case .refresh:
            await refresh()
        case .settings(let pane):
            switch pane {
            case .attention: services?.openSettings(tab: .attention)
            case .place: services?.openSettings(tab: .privacy)
            case .addons: services?.openSettings(tab: .addons)
            case .notifications:
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
            }
        }
    }

    private func loadSettings() async {
        guard let details = await services?.runtime.extensions.info(id: info.extensionId) else { return }
        settingRows = details.settings
        aiStatus = details.ai
        placePurpose = await services?.runtime.extensions.consentPurpose(.place, extensionId: info.extensionId)
        schedulePurpose = await services?.runtime.extensions.consentPurpose(.schedule, extensionId: info.extensionId)
        signedBySidefolk = details.origin?.firstParty == true
    }

    /// A setting's row changed: through the same tool as any change to it, then the page again, which may depend on it.
    func set(_ row: ExtensionSettingRow, to value: JSONValue) async {
        guard let services else { return }
        let outcome = await services.runtime.executor.execute(name: ExtensionSettingRow.tool, input: ["extension": .string(row.extensionId), "key": .string(row.key), "value": value],
                                                              caller: .user)
        await refresh()
        if let why = outcome.problem?.message { problem = why }
    }

    func setAI(_ on: Bool) async {
        await services?.runtime.extensions.setAIAllowed(extensionId: info.extensionId, on)
        await refresh()
    }

    /// A picture the page names, decoded off the main thread, or nil: the part draws without it.
    func image(_ picture: PagePicture, dark: Bool, side: Int) async -> NSImage? {
        if let samplePicture { return samplePicture(picture) }
        let key = "\(picture)|\(dark)|\(side)"
        if let kept = pictureCache[key] { return kept }
        var made: NSImage?
        switch picture {
        case .pack(let path, let night):
            guard let reader = await services?.runtime.extensions.assetReader(extensionId: info.extensionId) else { return nil }
            let cg = await Task.detached { (dark ? night.flatMap { reader.image($0, maxSide: side) } : nil) ?? reader.image(path, maxSide: side) }.value
            made = cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        case .data(let name):
            guard let folder else { return nil }
            made = await ExtensionPictures.load(name, in: folder, pixels: side, limit: ExtensionDataFile.thumbnailLimit)
        case .companion(let figure):
            guard let s = services?.runtime.settings.current else { return nil }
            // Whole, cut to what is drawn: a figure's blank margins would make it stand small and off its ground.
            made = figure == .face ? CompanionArt.avatar(for: s, side: CGFloat(side)) : SceneFigures.trim(CompanionArt.portrait(for: s, state: .listening, side: CGFloat(side)))
        case .person:
            made = AccountPicture.current
        case .app(let path):
            // Off the main thread, and only a real app where apps are installed, after following any link: anything else draws nothing.
            let cg = await Task.detached { () -> CGImage? in
                let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                guard PagePicture.isAppPath(url.path), (try? url.resourceValues(forKeys: [.isApplicationKey]))?.isApplication == true else { return nil }
                var rect = CGRect(x: 0, y: 0, width: side, height: side)
                return NSWorkspace.shared.icon(forFile: url.path).cgImage(forProposedRect: &rect, context: nil, hints: nil)
            }.value
            made = cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        if let made { pictureCache[key] = made }
        return made
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
            // The switch stays on until the answer: Home's question stops it (`NowModel.confirmStop`) and `stopped` shows it off.
            askToStop?(id, alert.kind.title)
        }
        await loadAlerts()
    }

    func ask(_ text: String) { services?.ask(text, how: .auto) }

    /// A switch or button: the extension's own tool, run as the person through Guard (D63), then the page again.
    func run(_ control: ExtensionPage.Control, on: Bool?) async {
        await handOverTyping()
        if var act = control.act {
            // A switch says its new state in the page's own.
            if case .go(var move) = act, let key = control.key, let on {
                move.set[key] = .bool(on)
                act = .go(move)
            }
            await perform(act)
            onControl?()
            return
        }
        guard let services else { return }
        let why = await ExtensionControl.run(control, on: on, extensionId: info.extensionId, services: services)
        await refresh()
        // After the read, which clears any earlier problem: what went wrong with this click stays in sight.
        if let why { problem = why }
        onControl?()
    }

    /// The person's answer to Sidefolk's question (D106, D107), through the tool that records it.
    /// The person said yes to sharing the folder. Their click alone reaches this tool, and it's in History.
    func share(_ question: PageFolderQuestion) async {
        guard let services else { return }
        let outcome = await services.runtime.executor.execute(name: FolderShare.toolName, input: ["folder": .string(question.folder), "write": .bool(question.write)], caller: .user)
        await refresh()
        if let why = outcome.problem?.message { problem = why }
    }

    func answer(_ consent: PageConsent, allow: Bool) async {
        guard let services else { return }
        let what = consent == .place ? "place" : "schedule"
        let outcome = await services.runtime.executor.execute(name: "extensions.consent", input: ["extension": .string(info.extensionId), "what": .string(what), "on": .bool(allow)], caller: .user)
        await refresh()
        if let why = outcome.problem?.message { problem = why }
    }

    /// What Sidefolk says it means, the extension's purpose marked as its own words. Read before the question shows, so it never waits.
    func consentWords(_ consent: PageConsent) -> String {
        let purpose = consent == .place ? placePurpose : schedulePurpose
        let says = purpose.map { String(localized: "\(info.extensionName) says it wants this \($0).", comment: "Asked before an extension may have the person's place or schedule reminders: the extension's stated purpose") }
        let what = switch consent {
        case .place: String(localized: "It will get your town and region, its coordinates to about a kilometre and its time zone, and hear when they change. With internet access it could send them on. You can take this back in Settings › Add-ons.",
                            comment: "Asked before an extension may have the person's place")
        case .schedule: String(localized: "It can send you reminders at moments it plans, which follow your Focus, Quiet and Attention settings. It can't show them while Sidefolk is quit unless it asks macOS to. You can take this back in Settings › Add-ons.",
                               comment: "Asked before an extension may schedule reminders")
        }
        return [says, what].compactMap { $0 }.joined(separator: "\n\n")
    }

    /// A choice, field or list row's tool (D68): whether it ran without a problem.
    @discardableResult
    /// What's in the field being typed in counts: a press of anything else takes it first, and waits for it to arrive, or Save would keep what's there without it.
    func handOverTyping() async {
        guard let window = NSApp.keyWindow, window.firstResponder is NSTextView else { return }
        window.makeFirstResponder(nil)
        // Its commit starts on the next turn of the run loop.
        try? await Task.sleep(for: .milliseconds(30))
        for _ in 0..<100 where fieldRuns > 0 { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func run(tool: String, input: JSONValue) async -> Bool {
        guard let services else { return false }
        fieldRuns += 1
        defer { fieldRuns -= 1 }
        let why = await ExtensionControl.run(tool: tool, input: input, extensionId: info.extensionId, services: services)
        await refresh()
        if let why { problem = why } else { saidAt = .distantPast }
        return why == nil
    }

    /// Where the extension's pictures are (`ExtensionDataFile`); a sample folder in UI snapshots.
    var folder: URL? { services?.runtime.extensions.dataFolder(extensionId: info.extensionId) ?? sampleFolder }
    private var sampleFolder: URL?

    /// The language Sidefolk speaks (`pt-BR` and `zh-Hans` whole), which the extension answers in (D76).
    static var language: String { ExtensionStrings.current }
}
