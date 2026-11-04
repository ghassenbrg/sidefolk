import AppKit
import SidefolkCore

extension AppCoordinator {
    func installSelfTools() {
        runtime.registry.register(SelfTools.make(app: SelfService(app: self)))
    }
}

/// The app's answers about itself, for the companion (D120). Updates and windows live here, not in the core.
@MainActor
final class SelfService: SelfReporting {
    private unowned let app: AppCoordinator
    private var runtime: SidefolkRuntime { app.runtime }
    private var updater: UpdateController { app.updater }

    init(app: AppCoordinator) { self.app = app }

    func about() async -> SelfAbout {
        let s = runtime.settings.current
        let installed = await runtime.extensions.extensions()
        let theme = ThemeLibrary.app(runtime.paths).all().first { $0.id == s.theme }?.tokens.name ?? s.theme
        return SelfAbout(version: SidefolkVersion.running, published: updater.isPublished, companion: s.companionName,
                         ai: s.provider.kind == .none ? nil : s.provider.kind.displayName, theme: theme, appearance: s.appearance.rawValue,
                         language: Locale.preferredLanguages.first ?? "en",
                         extensions: installed.filter(\.enabled).map(\.name), extensionsOff: installed.filter { !$0.enabled }.map(\.name))
    }

    func lookForUpdates() async throws -> SelfUpdates {
        // A copy nobody published doesn't update itself, whatever is out there.
        let found = updater.isPublished ? try await updater.lookNow() : (newest: nil, ready: false)
        let addons = await app.addonUpdater.lookNow()
        return SelfUpdates(running: SidefolkVersion.running, published: updater.isPublished, newest: found.newest?.version.shown,
                           ready: found.ready, addons: addons)
    }

    func installUpdate() async -> SelfInstall {
        guard updater.isPublished else { return .nothingNewer }
        if updater.model.busy {
            updater.showUpdates()
            return .underWay
        }
        guard let found = try? await updater.lookNow(), let offer = found.newest else { return .nothingNewer }
        // Downloaded already, `install` would restart at once, in the middle of this answer: that's the person's click.
        if found.ready {
            updater.showUpdates()
            return .readyToRestart(offer.version.shown)
        }
        updater.install(offer)
        return .downloading(offer.version.shown)
    }

    func open(_ place: SelfPlace) async {
        switch place {
        case .updates: updater.showUpdates()
        case .general: app.openSettings(tab: .general)
        case .companion: app.openSettings(tab: .companion)
        case .attention: app.openSettings(tab: .attention)
        case .brain: app.openSettings(tab: .brain)
        case .trust: app.openSettings(tab: .trust)
        case .connections: app.openSettings(tab: .connections)
        case .addons: app.openSettings(tab: .addons)
        case .appearance: app.openSettings(tab: .appearance)
        case .today: app.home.show(section: .now)
        case .calendar: app.home.show(section: .calendar)
        case .notebook: app.home.show(section: .notebook)
        case .onDuty: app.home.show(section: .onDuty)
        case .history: app.home.show(section: .history)
        case .gallery: app.home.show(section: .gallery)
        }
    }

    func setAppearance(_ appearance: AppAppearance) async -> AppAppearance {
        let was = runtime.settings.current.appearance
        await runtime.settings.update { $0.appearance = appearance }
        app.settingsChanged()
        return was
    }

    func setShowsOverFullScreen(_ shows: Bool) async -> Bool {
        let was = !runtime.settings.current.hideOverFullScreen
        await runtime.settings.update { $0.hideOverFullScreen = !shows }
        app.settingsChanged()
        return was
    }

    func setFullScreenNotice(_ notice: FullScreenNotice) async -> FullScreenNotice {
        let was = runtime.settings.current.fullScreenNotice
        await runtime.settings.update { $0.fullScreenNotice = notice }
        app.settingsChanged()
        return was
    }

    func setTheme(_ name: String) async -> (name: String, was: String)? {
        let installed = ThemeLibrary.app(runtime.paths).all().map { (id: $0.id, name: $0.tokens.name) }
        guard let theme = ThemeSuccession.named(name, among: installed) else { return nil }
        let was = runtime.settings.current.theme
        await runtime.settings.update {
            $0.theme = theme.id
            $0.themeFolder = nil
        }
        app.settingsChanged()
        // A theme that moved to the gallery and isn't here yet (an Undo back to it) is fetched, as at launch.
        if !installed.contains(where: { $0.id == theme.id }) { Task { await app.fetchThemeThatMoved() } }
        return (theme.name, was)
    }
}
