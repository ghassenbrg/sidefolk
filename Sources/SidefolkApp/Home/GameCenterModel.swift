import AppKit
import Observation
import SidefolkCore

/// The Game Center (D93): Playtime's page in Home, drawn by Sidefolk for an extension that declares games. Its page is
/// still read through the page channel (`ExtensionPageModel`, so the summary, the Today tile and any sections keep
/// working); its records, every game on the shelf and Sidefolk's own Activity rows make the center (`GameCenter`).
/// Everything it starts goes through `games.open` as the person's own action, like the Play menu.
@MainActor @Observable
final class GameCenterModel {
    let page: ExtensionPageModel
    private let services: AppServices?
    private(set) var games: [GameInfo]
    private(set) var rows: [ActivityEntry] = []
    /// The game put away in the Play panel, to continue.
    private(set) var kept: GameInfo?
    private(set) var settings: GameSettings
    let companionName: String
    let figure: NSImage?
    /// Its face beside "Play against …", as on the Play menu.
    let avatar: NSImage?
    /// Whether the extension's records came (an older extension sends none: everything is counted from Activity).
    var center: GameCenter {
        GameCenter(games: games, extensionId: page.info.extensionId, records: page.page?.games, rows: rows)
    }

    init(page: ExtensionPageModel, services: AppServices) {
        self.page = page
        self.services = services
        let s = services.runtime.settings.current
        settings = s.games
        companionName = s.companionName
        figure = CompanionArt.portrait(for: s, state: .listening, side: 220)
        avatar = CompanionArt.avatar(for: s, side: 40)
        games = Self.games(for: page.info.extensionId, shelf: services.runtime.extensions.gameShelf.all)
    }

    /// A center with nothing behind it, for UI snapshots.
    init(page: ExtensionPageModel, games: [GameInfo], rows: [ActivityEntry], kept: GameInfo?, settings: GameSettings, companionName: String,
         figure: NSImage?, avatar: NSImage?) {
        self.page = page
        self.avatar = avatar
        services = nil
        self.games = games
        self.rows = rows
        self.kept = kept
        self.settings = settings
        self.companionName = companionName
        self.figure = figure
    }

    /// Sidefolk's own match, then the extension's games in the menu's order (the looks' order, games without one last).
    static func games(for extensionId: String, shelf: [GameInfo]) -> [GameInfo] {
        func rank(_ g: GameInfo) -> Int { g.look.flatMap { GameLook.allCases.firstIndex(of: $0) } ?? GameLook.allCases.count }
        let own = shelf.filter { $0.extensionId == extensionId }.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
        return [GameInfo.handsMatch] + own
    }

    /// While the page shows: the page's own reading (its refresh), then the games, Activity, the kept game and settings.
    func run() async {
        guard services != nil else { return }
        async let reading: Void = page.run()
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(5), tolerance: .seconds(1))
        }
        await reading
    }

    func refresh() async {
        guard let services else { return }
        games = Self.games(for: page.info.extensionId, shelf: services.runtime.extensions.gameShelf.all)
        rows = (try? await services.runtime.activity.recent(limit: 1000, tool: "games.play")) ?? rows
        kept = services.keptGame
        settings = services.runtime.settings.current.games
    }

    // MARK: Playing

    /// A game, at a level when one is given, as the person's own choice; the kept one resumes where it was.
    func play(_ game: GameInfo, level: String? = nil) {
        var input: [String: JSONValue] = ["extension": .string(game.extensionId), "game": .string(game.game)]
        if let level { input["level"] = .string(level) }
        open(.object(input))
    }

    func surprise() { open(["game": "random"]) }
    func showMenu() { services?.openPlayMenu() }

    private func open(_ input: JSONValue) {
        guard let services else { return }
        Task {
            _ = await services.runtime.executor.execute(name: "games.open", input: input, caller: .user)
            await refresh()
        }
    }

    // MARK: Settings, in one place

    /// Changes the games' settings at once on screen and saves them; an open game's sounds follow (the coordinator).
    func change(_ edit: @escaping @Sendable (inout GameSettings) -> Void) {
        edit(&settings)
        guard let services else { return }
        Task { await services.runtime.settings.update { edit(&$0.games) } }
    }

    func level(of game: GameInfo) -> String? { settings.levels[game.id].flatMap { game.levels.contains($0) ? $0 : nil } }
}
