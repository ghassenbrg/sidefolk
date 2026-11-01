#if DEBUG
import Foundation

/// `--ui-snapshots <dir> --language fr [--catalog <file>]`: the pictures in another language, so each
/// page can be reviewed in each of them (D28). Without `--language` they're in English, from the compiled
/// catalog too, so plurals read as they do in the app ("1 request", not "1 requests"). macOS picks the
/// language once, at launch, from `AppleLanguages` and the bundle's `.lproj` folders, so this runs a second
/// copy with `-AppleLanguages (fr)` and waits for it. A plain `swift run` has no `.lproj` folders: the catalog
/// (or the copy `--catalog` names, such as scripts/pseudo-l10n.py's) is compiled into a folder of the run's own,
/// beside a link to the executable and its resource bundles, and the copy runs from there; the folder goes after.
/// So runs in several languages at once never share or remove each other's folders (they used to: one run's
/// cleanup took another's `ar.lproj`, which then rendered left to right or not at all). Inside an app bundle its
/// own folders are used. The layout's direction is given the same way (`-AppleTextDirection`), never stored: every
/// run shares the `SidefolkApp` defaults, and an English run removing what an Arabic one stored mirrored it back.
enum SnapshotLanguage {
    /// Nil when this copy should render; otherwise the exit status of the copy that rendered.
    static func relaunchIfNeeded(_ args: [String]) -> Int32? {
        guard !args.contains("-AppleLanguages") else { return nil }
        let language = value(after: "--language", in: args) ?? "en"
        var stage: URL?
        defer { stage.map { try? FileManager.default.removeItem(at: $0) } }
        do {
            var executable = Bundle.main.executableURL
            if Bundle.main.bundleURL.pathExtension != "app" {
                let folder = try self.stage(catalog: value(after: "--catalog", in: args).map { URL(fileURLWithPath: $0) } ?? repositoryCatalog)
                stage = folder
                executable = folder.appendingPathComponent(Bundle.main.executableURL?.lastPathComponent ?? "SidefolkApp")
            }
            let child = Process()
            child.executableURL = executable
            // The direction goes on the command line too, in this run's own argument domain: stored in the defaults
            // every `SidefolkApp` run shares, a run in another language beside this one could change it under it.
            let rtl = Locale.Language(identifier: language).characterDirection == .rightToLeft
            child.arguments = Array(args.dropFirst()) + ["-AppleLanguages", "(\(language))", "-AppleTextDirection", rtl ? "YES" : "NO"]
            try child.run()
            child.waitUntilExit()
            return child.terminationStatus
        } catch {
            FileHandle.standardError.write(Data("ui-snapshots: couldn't render in \(language): \(error)\n".utf8))
            return 1
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Resources/Localization/Localizable.xcstrings, found from this file (Sources/SidefolkApp/Dev).
    private static var repositoryCatalog: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Localization/Localizable.xcstrings")
    }

    /// A folder for this run: `catalog` compiled into its `<language>.lproj` folders, the executable linked in (a copy
    /// if it can't be), and the resource bundles beside it linked, so the copy finds everything it reads.
    private static func stage(catalog: URL) throws -> URL {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("sidefolk-snapshots-\(UUID().uuidString)", isDirectory: true)
        let work = folder.appendingPathComponent(".catalog", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        // The compiled table takes the file's name, and the app reads "Localizable".
        let source = work.appendingPathComponent("Localizable.xcstrings")
        try fm.copyItem(at: catalog, to: source)
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        tool.arguments = ["xcstringstool", "compile", source.path, "--output-directory", folder.path]
        try tool.run()
        tool.waitUntilExit()
        guard tool.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: catalog.path]) }
        let home = Bundle.main.bundleURL
        if let executable = Bundle.main.executableURL {
            let target = folder.appendingPathComponent(executable.lastPathComponent)
            if (try? fm.linkItem(at: executable, to: target)) == nil { try fm.copyItem(at: executable, to: target) }
        }
        for bundle in try fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil) where bundle.pathExtension == "bundle" {
            try fm.createSymbolicLink(at: folder.appendingPathComponent(bundle.lastPathComponent), withDestinationURL: bundle)
        }
        return folder
    }
}
#endif
