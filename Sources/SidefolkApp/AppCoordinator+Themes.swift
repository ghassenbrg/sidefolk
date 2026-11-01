import Foundation
import SidefolkCore

/// Themes (D58): every window draws with the chosen one, and while a theme is being made in a folder, Sidefolk
/// follows that folder and repaints each time it is saved.
extension AppCoordinator {
    var themes: ThemeLibrary { .app(runtime.paths) }

    func applyTheme() {
        let s = runtime.settings.current
        ThemeStore.shared.apply(themes.theme(id: s.theme), density: s.density)
        ThemeStore.shared.setIcons(s.sidebarIcons)
        let folder = s.themeFolder.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if folder == nil { ThemeStore.shared.setFolderReport(nil) }
        // Edits made while Sidefolk was closed count too, so a folder newly followed is read at once.
        if themeFollower.follow(folder, changed: { [weak self] in self?.reloadThemeFolder($0) }), let folder {
            reloadThemeFolder(folder)
        }
    }

    static let themeSuccessor = "themeSuccessor"
    static let useSuccessor = "theme.useSuccessor"

    /// A theme that left Sidefolk (D92): a retired built-in becomes its successor before the first paint; a theme that
    /// left the gallery stays, and its successor is offered once (`announceSuccession`).
    func succeedRetiredTheme() async -> ThemeSuccession.Step? {
        let installed = Set(themes.all().map(\.id))
        var next = runtime.settings.current
        guard let step = ThemeSuccession.step(&next, installed: installed.contains) else { return nil }
        let changed = next
        await runtime.settings.update {
            $0.theme = changed.theme
            $0.density = changed.density
            $0.themeSuccessorsOffered = changed.themeSuccessorsOffered
        }
        return step
    }

    /// Says what happened to the theme, once, as a whisper.
    func announceSuccession(_ step: ThemeSuccession.Step) {
        let successor = switch step {
        case .moved(_, let to): to
        case .offer(let old, _): old.successor
        }
        sidecard.present(Self.successionItem(step, successorName: themes.theme(id: successor).tokens.name),
                         .gentle(autoDismiss: AttentionPolicy.gentleSeconds))
    }

    /// The whisper's words: moved needs nothing more; an offer carries "Use …" (`useSuccessor`).
    static func successionItem(_ step: ThemeSuccession.Step, successorName name: String) -> AttentionItem {
        switch step {
        case .moved(let old, _):
            AttentionItem(level: .gentle, source: ownVoice,
                          title: String(localized: "\(old.name) is now \(name), its successor.",
                                        comment: "A whisper at launch after a retired theme was replaced: “Field Notes is now Paper Garden, its successor.”"),
                          refKind: themeSuccessor)
        case .offer(let old, _):
            AttentionItem(level: .gentle, source: ownVoice,
                          title: String(localized: "\(old.name) left the gallery and stays yours. \(name) took its place.",
                                        comment: "A whisper at launch about a theme no longer in the gallery: “Daylight left the gallery and stays yours. Harbor took its place.”"),
                          actions: [AttentionAction(id: useSuccessor,
                                                    title: String(localized: "Use \(name)", comment: "Wears a retired theme's successor: “Use Harbor”"))],
                          refKind: themeSuccessor, refId: old.successor)
        }
    }

    /// "Use Harbor" on that whisper.
    func useTheme(_ id: String) {
        Task {
            await runtime.settings.update {
                $0.theme = id
                $0.themeFolder = nil
            }
            settingsChanged()
        }
    }

    /// Checks the followed folder again and uses it when it can be used. A theme with an error leaves the last good
    /// one on screen, and Settings says what's wrong.
    func reloadThemeFolder(_ folder: URL) {
        do {
            let (theme, report) = try themes.install(from: folder)
            ThemeStore.shared.setFolderReport(report)
            ThemeStore.shared.apply(theme, density: runtime.settings.current.density)
            if runtime.settings.current.theme != theme.id {
                Task { await runtime.settings.update { $0.theme = theme.id } }
            }
        } catch {
            ThemeStore.shared.setFolderReport(ThemeCheck.check(folder: folder))
        }
    }
}

extension ThemeLibrary {
    /// The library with the built-ins this copy of Sidefolk ships in its Resources.
    static func app(_ paths: SidefolkPaths) -> ThemeLibrary {
        ThemeLibrary(paths: paths, bundled: ResourceLocator.resources?.appendingPathComponent("Themes", isDirectory: true))
    }
}

/// Notices when the files in a theme folder change. Once a second is quick enough for someone saving in an editor,
/// and a look at every file's date sees atomic saves and images in subfolders alike, which a folder event doesn't.
@MainActor
final class ThemeFollower {
    private var folder: URL?
    private var task: Task<Void, Never>?

    /// Follows `folder` (nil: nothing). True when that is a change.
    func follow(_ folder: URL?, changed: @escaping @MainActor (URL) -> Void) -> Bool {
        guard folder?.standardizedFileURL != self.folder?.standardizedFileURL else { return false }
        task?.cancel()
        self.folder = folder
        guard let folder else { return true }
        task = Task {
            var last = await Task.detached { Self.fingerprint(folder) }.value
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let now = await Task.detached { Self.fingerprint(folder) }.value
                if now != last, !Task.isCancelled {
                    last = now
                    changed(folder)
                }
            }
        }
        return true
    }

    /// Each file's date and size; a theme folder holds a handful, and anything past 200 is not a theme's.
    nonisolated private static func fingerprint(_ folder: URL) -> [String: [Double]] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [:] }
        var seen: [String: [Double]] = [:]
        for case let url as URL in files where seen.count < 200 {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            seen[url.path] = [values.contentModificationDate?.timeIntervalSince1970 ?? 0, Double(values.fileSize ?? 0)]
        }
        return seen
    }
}
