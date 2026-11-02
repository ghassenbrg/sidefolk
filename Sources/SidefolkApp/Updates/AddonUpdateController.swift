import AppKit
import SidefolkCore

/// Gallery add-ons on this Mac keep up with the gallery (D55, D70): a look 90 s after launch, then every six hours,
/// and soon after Settings › Updates changes. With "Update add-ons automatically" on, companions, themes and
/// extensions whose update asks for nothing new install by themselves (`AddonUpdater`); an extension update that
/// would let it do more waits for the person, with one gentle heads-up per version. With it off, every update waits,
/// shown wherever add-ons appear, with Update all (D89), and after a day one whisper says so.
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
    /// Opens Home's Gallery, whose Updates section lists every update (D89).
    var openGallery: () -> Void = {}

    static let reviewKind = "addon-review"
    /// The whisper about updates that waited a day (D89).
    static let waitingKind = "addon-updates"
    /// The versions already brought up on the desktop, so a heads-up comes once per version.
    private static let mentionedKey = "addonUpdates.mentioned"
    private static let nudgeKey = "addonUpdates.nudge"

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
        await runtime.attention.onAction(kind: Self.waitingKind) { [weak self] _, action in
            await MainActor.run {
                if action == "updateAll" { self?.updateAddonsNow() }
                if action == "show" { self?.showAddonUpdates() }
            }
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
        Task { await updateAll() }
    }

    func update(_ entries: [AddonEntry]) {
        Task { await updateAll(entries, summarize: true) }
    }

    func update(_ entry: AddonEntry) {
        if model.addonNeedsReview(entry.id) { return review(entry) }
        Task {
            await updateAll([entry])
            // The person asked for this one: one that would do more goes straight to its sheet.
            if model.addonSteps[entry.id] == .needsReview { review(entry) }
        }
    }

    func showAddonUpdates() { openGallery() }

    func updateOutOfDate(_ id: String) {
        Task {
            model.addonNoneYet.remove(id)
            let have = await runtime.extensions.info(id: id)?.version
            guard let catalog = try? await runtime.addons.catalog(refresh: true), let entry = catalog.entry(id), entry.kind == .extension, entry.version != have else {
                model.addonNoneYet.insert(id)
                return
            }
            update(entry)
        }
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

    /// One look; `refresh` fetches the gallery's list again. Rows that Update all finished go: what's left is
    /// what still waits.
    private func look(refresh: Bool = false) async {
        guard !model.addonsBusy else { return }
        let s = runtime.settings.current.updates
        followed = (s.effectiveChannel, s.addons)
        model.addonsBusy = true
        let report = await updater.run(channel: s.effectiveChannel, automatic: s.addons, refresh: refresh)
        model.addonsBusy = false
        model.addonSteps = model.addonSteps.filter { $0.value != .updated }
        model.addonRecent = model.addonRecent.filter { model.addonSteps[$0.id] != nil }
        model.addonSummary = nil
        settle(report)
        model.addonWaiting = report.waiting
        model.addonReview = report.review
        await headsUp(report.review)
        await nudge(automatic: s.addons)
    }

    /// Update all (D89), or one add-on's Update: each in turn, its row following along, then a summary (for one add-on
    /// its row says it all). With nothing chosen, every waiting update that isn't known to ask for more, looked for first
    /// if none is known yet.
    private func updateAll(_ chosen: [AddonEntry]? = nil, summarize: Bool? = nil) async {
        if chosen == nil, model.addonInstallable.isEmpty { await look() }
        let entries = chosen ?? model.addonInstallable
        guard !model.addonsBusy, !entries.isEmpty else { return }
        model.addonsBusy = true
        model.addonSummary = nil
        for entry in entries { model.addonSteps[entry.id] = nil }
        model.addonRecent = entries + model.addonRecent.filter { old in !entries.contains { $0.id == old.id } }
        let report = await updater.updateAll(entries) { [weak self] entry, step in
            await MainActor.run { self?.model.addonSteps[entry.id] = step }
        }
        model.addonsBusy = false
        settle(report)
        let done = Set(report.companions.map(\.id) + report.themes.map(\.id) + report.extensions.map(\.id) + report.review.map(\.id))
        model.addonWaiting.removeAll { done.contains($0.id) }
        model.addonReview += report.review.filter { entry in !model.addonReview.contains { $0.id == entry.id } }
        if summarize ?? (chosen == nil) { model.addonSummary = report.summary }
    }

    /// What installed: companions and themes drawn again, the names for Settings › Updates.
    private func settle(_ report: AddonUpdateReport) {
        if !report.companions.isEmpty || !report.themes.isEmpty { onUpdated(report) }
        if report.installed > 0 {
            model.addonsUpdated = report.companions.map(\.name) + report.themes.map(\.tokens.name) + report.extensions.map(\.name)
            model.addonsUpdatedAt = Date()
        }
    }

    /// One whisper once updates have waited a day with the switch off (`AddonUpdateNudge`).
    private func nudge(automatic: Bool) async {
        var nudge = (try? await kv.get(Self.nudgeKey, as: AddonUpdateNudge.self)) ?? AddonUpdateNudge()
        nudge.note(automatic ? [] : model.addonPending, now: Date())
        let due = nudge.due(automatic: automatic, now: Date())
        try? await kv.set(Self.nudgeKey, nudge)
        if due { _ = await runtime.attention.post(Self.waitingNotice(model.addonPending, installable: !model.addonInstallable.isEmpty)) }
    }

    static func waitingNotice(_ entries: [AddonEntry], installable: Bool) -> AttentionRequest {
        AttentionRequest(
            level: .gentle, source: "addons",
            title: String(localized: "\(entries.count) add-ons have updates", comment: "A whisper after updates waited a day: “2 add-ons have updates”"),
            body: Wording.list(entries.map(\.shownName)),
            actions: (installable ? [AttentionAction(id: "updateAll", title: String(localized: "Update all"), isPrimary: true)] : [])
                + [AttentionAction(id: "show", title: String(localized: "Show", comment: "Opens the Gallery's Updates"), isPrimary: !installable)],
            refKind: waitingKind)
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
                ? String(localized: "\(names) has an update to look at", comment: "An extension's update waits for review: “Tea Timer has an update to look at”")
                : String(localized: "\(names) have updates to look at", comment: "Extensions' updates wait for review: “Tea Timer and Moss have updates to look at”"),
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
    /// `addons:review | waiting | updates | nudge | clear` from scripts/dev.swift: Settings › Updates and the heads-up with
    /// made-up gallery entries, without a gallery. With a gallery (`SIDEFOLK_ADDONS`, D89): `addons:auto:on|off` sets
    /// "Update add-ons automatically", `addons:get:<id>` installs that add-on from it as Get and the install sheet would,
    /// `addons:check` looks at it now, `addons:updateAll` is Update all, `addons:review:<id>` a waiting update's Review….
    func dev(_ command: String) {
        if command.hasPrefix("auto:") {
            let on = command == "auto:on"
            Task { await runtime.settings.update { $0.updates.addons = on } }
            return
        }
        if command == "updateAll" { return updateAddonsNow() }
        // The Gallery's Review… on a waiting update (one that would let an extension do more).
        if command.hasPrefix("review:"), let entry = model.addonPending.first(where: { $0.id == command.dropFirst(7) }) {
            return review(entry)
        }
        if command == "check" { return checkNow() }
        if command.hasPrefix("get:") {
            let id = String(command.dropFirst(4))
            Task {
                do {
                    guard let entry = try await runtime.addons.catalog(refresh: true).entry(id) else { return }
                    switch entry.kind {
                    case .companion: try await runtime.addons.install(companion: entry)
                    case .theme: break
                    case .extension:
                        try await runtime.extensions.install(from: try await runtime.addons.fetch(entry), origin: .official)
                        await runtime.addons.discard(entry)
                    }
                } catch {
                    Log.shared.warning("dev", "addons:get failed", ["id": id, "error": String(describing: error)])
                }
            }
            return
        }
        func entry(_ id: String, _ name: String, _ kind: AddonEntry.Kind) -> AddonEntry {
            let json = ["id": id, "kind": kind.rawValue, "name": name, "tagline": "", "description": "", "author": "Sidefolk",
                        "version": "1.0.0-snapshot.3", "file": "x.zip", "bytes": 1, "sha256": String(repeating: "0", count: 64)] as [String: Any]
            return try! JSONDecoder().decode(AddonEntry.self, from: JSONSerialization.data(withJSONObject: json))
        }
        switch command {
        case "review":
            model.addonReview = [entry(SampleAddons.repoPal, "Repo Pal", .extension)]
            Task { _ = await runtime.attention.post(Self.notice(model.addonReview)) }
        case "waiting":
            model.addonWaiting = [entry("dev.sidefolk.companions.kiko", "Kiko", .companion), entry(SampleAddons.newsstand, "Newsstand", .extension)]
        case "updates":
            // The Gallery's Updates mid-way through Update all, as the D89 snapshots show it.
            model.addonWaiting = [entry(SampleAddons.macPulsePlus, "Mac Pulse+", .extension), entry(SampleAddons.newsstand, "Newsstand", .extension),
                                  entry("dev.sidefolk.companions.kiko", "Kiko", .companion), entry("dev.sidefolk.theme.daylight", "Daylight", .theme)]
            model.addonReview = [entry(SampleAddons.castAlong, "Cast Along", .extension)]
            model.addonRecent = [entry(SampleAddons.repoPal, "Repo Pal", .extension)]
            model.addonSteps = [SampleAddons.repoPal: .updated, SampleAddons.newsstand: .updating]
        case "nudge":
            model.addonWaiting = [entry(SampleAddons.macPulsePlus, "Mac Pulse+", .extension), entry(SampleAddons.newsstand, "Newsstand", .extension)]
            Task { _ = await runtime.attention.post(Self.waitingNotice(model.addonPending, installable: true)) }
        case "clear":
            model.addonReview = []
            model.addonWaiting = []
            model.addonSteps = [:]
            model.addonRecent = []
            model.addonSummary = nil
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
            // Still waiting while another version is installed: a newer one, or the gallery's over a copy from
            // before its renumbering (D80), which is numbered higher.
            return have != entry.version
        }
        model.addonReview = model.addonReview.filter(waits)
        model.addonWaiting = model.addonWaiting.filter(waits)
        // One Update all left for review, then reviewed and installed: its row says Updated, not Review… again.
        for entry in model.addonRecent where model.addonSteps[entry.id] == .needsReview && installed[entry.id] == entry.version {
            model.addonSteps[entry.id] = .updated
        }
    }
}
