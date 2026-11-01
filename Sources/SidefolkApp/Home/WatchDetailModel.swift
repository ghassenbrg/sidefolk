import Foundation
import Observation
import SwiftUI
import SidefolkCore

/// The watch open on its detail page (D87): the watcher as the engine has it, its checks (runs, newest first) and the two
/// versions of the text it kept. Its buttons go the same way as On duty's (`AppServices`' watcher calls).
@MainActor @Observable
final class WatchDetailModel {
    let services: AppServices
    private(set) var id: String?
    private(set) var watcher: Watcher?
    private(set) var checks: [WatchCheck] = []
    private(set) var versions: [WatchVersion] = []
    /// The latest change line by line, worked out once per load (a page's text can be thousands of lines).
    private(set) var lines: [DiffLine] = []
    private(set) var rows: [DiffRow] = []
    /// False until the first load, so a page for a watch that is gone says so only once it knows.
    private(set) var loaded = false
    /// "What changed" in two columns rather than one.
    var sideBySide = false
    /// The button whose work is under way, for its spinner.
    private(set) var working: Action?

    enum Action { case check, pause, resume, stop }

    /// The timeline shows this many runs; the rest are a click away.
    static let shownRuns = 40

    init(services: AppServices) { self.services = services }

    func show(_ id: String) async {
        if id != self.id {
            self.id = id
            watcher = nil
            checks = []
            versions = []
            lines = []
            rows = []
            loaded = false
        }
        await reload()
    }

    func reload() async {
        guard let id else { return }
        let engine = services.runtime.watchers
        watcher = await engine.watcher(id: id)
        checks = await engine.checks(for: id)
        let kept = await engine.versions(for: id)
        if kept != versions || !loaded {
            versions = kept
            if let change {
                lines = LineDiff.inline(old: change.before.text, new: change.after.text)
                rows = LineDiff.sideBySide(old: change.before.text, new: change.after.text)
            } else if let page = watcher?.lastPageChange {
                // A page watch from before its history was kept (D87) has only the changed lines it kept for Today's tile.
                lines = page.removed.map(DiffLine.removed) + page.added.map(DiffLine.added)
                rows = []
            } else {
                lines = []
                rows = []
            }
        }
        loaded = true
    }

    func checkNow() async { await run(.check) }
    func pause() async { await run(.pause) }
    func resume() async { await run(.resume) }
    func stop() async { await run(.stop) }

    private func run(_ action: Action) async {
        guard let id, working == nil else { return }
        working = action
        switch action {
        case .check: await services.checkWatcherNow(id)
        case .pause: await services.pauseWatcher(id)
        case .resume: await services.resumeWatcher(id)
        case .stop: await services.stopWatcher(id)
        }
        await reload()
        working = nil
    }

    /// Which way the kept text reads: a page in Arabic right to left, a page in English left to right, whatever the app's
    /// language (the text is the page's or file's, not the app's).
    var textDirection: LayoutDirection {
        let text = versions.last?.text ?? lines.lazy.compactMap { line -> String? in
            if case .added(let t) = line { return t }
            if case .removed(let t) = line { return t }
            return nil
        }.first ?? ""
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return .rightToLeft
            default: return .leftToRight
            }
        }
        return .leftToRight
    }

    /// The newest version and the one before, when the watch kept both.
    var change: (before: WatchVersion, after: WatchVersion)? {
        guard versions.count >= 2 else { return nil }
        return (versions[versions.count - 2], versions[versions.count - 1])
    }
}
