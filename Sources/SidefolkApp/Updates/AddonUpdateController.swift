import AppKit
import SidefolkCore

/// Gallery add-ons on this Mac keep up with the gallery (D55, D70): a look 90 s after launch, then every six hours,
/// and soon after Settings › Updates changes. With "Update add-ons automatically" on, companions, themes and
/// extensions whose update asks for nothing new install by themselves (`AddonUpdater`); an extension update that
/// would let it do more waits for the person, with one gentle heads-up per version. With it off, every update waits
/// and Settings › Updates says so, with Update All.
@MainActor
final class AddonUpdateController: AddonUpdateActions {
    private let runtime: SidefolkRuntime
    private let model: UpdateModel
    private let updater: AddonUpdater
    private let kv: KVStore
    private var loop: Task<Void, Never>?
    private var events: Task<Void, Never>?
    private var soon: Task<Void, Never>?
    /// What the last look followed, so a change in Settings looks again.
    private var followed: (UpdateChannel, Bool)?
    /// Companions or themes changed on disk: the coordinator draws them again.
    var onUpdated: (AddonUpdateReport) -> Void = { _ in }
    /// Opens the install sheet for a checked folder.
    var openReview: (URL) -> Void = { _ in }
    /// Opens Settings › General, where every update waiting for a look is listed.
    var openSettings: () -> Void = {}

    static let reviewKind = "addon-review"
    /// The versions already brought up on the desktop, so a heads-up comes once per version.
    private static let mentionedKey = "addonUpdates.mentioned"

    init(runtime: SidefolkRuntime, model: UpdateModel, themes: ThemeLibrary) {
        self.runtime = runtime
        self.model = model
        updater = AddonUpdater(store: runtime.addons, extensions: runtime.extensions, themes: themes)
        kv = KVStore(runtime.db)
    }

    func start() async {
        model.addonActions = self
        await runtime.attention.onAction(kind: Self.reviewKind) { [weak self] item, action in
            guard action == "review" else { return }
            await MainActor.run { self?.reviewFromNotice(item.refId) }
        }
        // An update reviewed and installed (or the extension removed) no longer waits.
        let stream = runtime.events.stream()
        events = Task { [weak self] in
            for await event in stream {
                guard case .dataChanged(.extensions) = event else { continue }
                await self?.dropSettled()
            }
        }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            while !Task.isCancelled {
                await self?.look()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    /// Settings › Updates changed: a new channel or the switch turned on means a fresh look, a few seconds later
    /// (several changes in a row look once).
    func settingsChanged() {
        let s = runtime.settings.current.updates
        guard let followed, followed != (s.effectiveChannel, s.addons) else { return }
        soon?.cancel()
        soon = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.look()
        }
    }

    // MARK: AddonUpdateActions

    func updateAddonsNow() {
        Task { await look(installing: true) }
    }

    /// "Check for Updates…": the gallery's list fetched again now, not the one kept for half an hour, so an add-on
    /// published minutes ago is found without waiting for the next look.
    func checkNow() {
        Task { await look(refresh: true) }
    }

    func review(_ entry: AddonEntry) {
        Task {
            do {
                openReview(try await runtime.addons.fetch(entry))
            } catch {
                Log.shared.warning("addons", "update couldn't be fetched for review", ["id": entry.id, "error": String(describing: error)])
                openSettings()
            }
        }
    }

    // MARK: Looking

    /// One look. `installing` installs what the rule allows even with the switch off (Update All); `refresh` fetches
    /// the gallery's list again.
    private func look(installing: Bool = false, refresh: Bool = false) async {
        guard !model.addonsBusy else { return }
        let s = runtime.settings.current.updates
        followed = (s.effectiveChannel, s.addons)
        model.addonsBusy = true
        let report = await updater.run(channel: s.effectiveChannel, automatic: s.addons || installing, refresh: refresh)
        model.addonsBusy = false
        if !report.companions.isEmpty || !report.themes.isEmpty { onUpdated(report) }
        if report.installed > 0 {
            model.addonsUpdated = report.companions.map(\.name) + report.themes.map(\.tokens.name) + report.extensions.map(\.name)
            model.addonsUpdatedAt = Date()
        }
        model.addonWaiting = report.waiting
        model.addonReview = report.review
        await headsUp(report.review)
    }

    /// A gentle word about updates that wait for a look, once per version: they never install by themselves.
    private func headsUp(_ entries: [AddonEntry]) async {
        var mentioned = Set((try? await kv.get(Self.mentionedKey, as: [String].self)) ?? [])
        let new = entries.filter { !mentioned.contains(Self.mark($0)) }
        guard !new.isEmpty else { return }
        mentioned.formUnion(new.map(Self.mark))
        try? await kv.set(Self.mentionedKey, mentioned.sorted())
        _ = await runtime.attention.post(Self.notice(new))
    }

    static func notice(_ entries: [AddonEntry]) -> AttentionRequest {
        let names = Wording.list(entries.map(\.shownName))
        return AttentionRequest(
            level: .gentle, source: "addons",
            title: entries.count == 1
                ? String(localized: "\(names) has an update to look at", comment: "An extension's update waits for review: “Git has an update to look at”")
                : String(localized: "\(names) have updates to look at", comment: "Extensions' updates wait for review: “Git and Feeds have updates to look at”"),
            body: String(localized: "The new version would be allowed to do more, so it waits until you've seen what's new."),
            actions: [AttentionAction(id: "review", title: String(localized: "Review"), isPrimary: true),
                      AttentionAction(id: "later", title: String(localized: "Later"))],
            refKind: reviewKind, refId: entries.count == 1 ? entries[0].id : nil)
    }

    private static func mark(_ entry: AddonEntry) -> String { "\(entry.id)@\(entry.version)" }

    /// Review from the heads-up: the one extension's sheet, or Settings' list when there were several.
    private func reviewFromNotice(_ id: String?) {
        guard let id, let entry = model.addonReview.first(where: { $0.id == id }) else { return openSettings() }
        review(entry)
    }

    #if DEBUG
    /// `addons:review | waiting | clear` from scripts/dev.swift: Settings › Updates and the heads-up with made-up
    /// gallery entries, without a gallery.
    func dev(_ command: String) {
        func entry(_ id: String, _ name: String, _ kind: AddonEntry.Kind) -> AddonEntry {
            let json = ["id": id, "kind": kind.rawValue, "name": name, "tagline": "", "description": "", "author": "Sidefolk",
                        "version": "1.0.0-snapshot.3", "file": "x.zip", "bytes": 1, "sha256": String(repeating: "0", count: 64)] as [String: Any]
            return try! JSONDecoder().decode(AddonEntry.self, from: JSONSerialization.data(withJSONObject: json))
        }
        switch command {
        case "review":
            model.addonReview = [entry("dev.sidefolk.git", "Git", .extension)]
            Task { _ = await runtime.attention.post(Self.notice(model.addonReview)) }
        case "waiting":
            model.addonWaiting = [entry("dev.sidefolk.companions.kiko", "Kiko", .companion), entry("dev.sidefolk.feeds", "Feeds", .extension)]
        case "clear":
            model.addonReview = []
            model.addonWaiting = []
        default: break
        }
    }
    #endif

    /// Drops waiting updates that are now installed (reviewed and agreed to) or whose extension went.
    private func dropSettled() async {
        guard !model.addonReview.isEmpty || !model.addonWaiting.isEmpty else { return }
        let installed = Dictionary(await runtime.extensions.extensions().map { ($0.id, $0.version) }, uniquingKeysWith: { a, _ in a })
        func waits(_ entry: AddonEntry) -> Bool {
            guard entry.kind == .extension else { return true }
            guard let have = installed[entry.id] else { return false }
            return UpdateChannel.snapshots.offers(entry.version, over: have)
        }
        model.addonReview = model.addonReview.filter(waits)
        model.addonWaiting = model.addonWaiting.filter(waits)
    }
}
