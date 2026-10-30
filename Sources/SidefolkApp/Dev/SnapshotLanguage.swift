#if DEBUG
import Foundation

/// `--ui-snapshots <dir> --language fr [--catalog <file>]`: the pictures in another language, so each
/// page can be reviewed in each of them (D28). Without `--language` they're in English, from the compiled
/// catalog too, so plurals read as they do in the app ("1 request", not "1 requests"). macOS picks the
/// language once, at launch, from `AppleLanguages` and the bundle's `.lproj` folders, so this runs a second
/// copy with `-AppleLanguages (fr)` and waits for it. A plain `swift run` has no `.lproj` folders: the catalog
/// (or the copy `--catalog` names, such as scripts/pseudo-l10n.py's) is compiled next to the
/// executable for that run and removed after it. Inside an app bundle its own folders are used.
enum SnapshotLanguage {
    /// Nil when this copy should render; otherwise the exit status of the copy that rendered.
    static func relaunchIfNeeded(_ args: [String]) -> Int32? {
        guard !args.contains("-AppleLanguages") else { return nil }
        let language = value(after: "--language", in: args) ?? "en"
        var installed: [URL] = []
        defer { installed.forEach { try? FileManager.default.removeItem(at: $0) } }
        do {
            if Bundle.main.bundleURL.pathExtension != "app" {
                installed = try install(catalog: value(after: "--catalog", in: args).map { URL(fileURLWithPath: $0) } ?? repositoryCatalog)
            }
            let child = Process()
            child.executableURL = Bundle.main.executableURL
            child.arguments = Array(args.dropFirst()) + ["-AppleLanguages", "(\(language))"]
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

    /// Compiles `catalog` and moves its `<language>.lproj` folders beside the executable.
    private static func install(catalog: URL) throws -> [URL] {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("sidefolk-lproj-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        // The compiled table takes the file's name, and the app reads "Localizable".
        let source = work.appendingPathComponent("Localizable.xcstrings")
        try fm.copyItem(at: catalog, to: source)
        let compiled = work.appendingPathComponent("out", isDirectory: true)
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        tool.arguments = ["xcstringstool", "compile", source.path, "--output-directory", compiled.path]
        try tool.run()
        tool.waitUntilExit()
        guard tool.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: catalog.path]) }
        var installed: [URL] = []
        for folder in try fm.contentsOfDirectory(at: compiled, includingPropertiesForKeys: nil) where folder.pathExtension == "lproj" {
            let target = Bundle.main.bundleURL.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            try? fm.removeItem(at: target)
            try fm.moveItem(at: folder, to: target)
            installed.append(target)
        }
        return installed
    }
}
#endif
