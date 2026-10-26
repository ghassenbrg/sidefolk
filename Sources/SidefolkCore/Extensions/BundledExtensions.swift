import Foundation
import Synchronization

/// The extensions Sidefolk ships (D39). The app's `Extensions/catalog.json` lists them and whether each is
/// on by default; the rest of that folder are samples to try. A built-in extension is installed with the
/// app, can be switched off but not removed, and is replaced whenever the app brings a different copy.
///
/// There is no locked "core" tier: anything fundamental is a built-in tool (D38), and an extension the
/// person can't switch off would be one they can't refuse.
public final class BundledExtensions: Sendable {
    public static let catalogFile = "catalog.json"

    public struct Entry: Sendable, Hashable {
        public var id: String
        public var name: String
        public var folder: URL
        /// On for everyone unless they switch it off; otherwise shipped, but off until they switch it on.
        public var on: Bool
    }

    /// A built-in extension that couldn't be installed on this Mac, and why (git missing, for example).
    public struct Problem: Sendable, Hashable {
        public var id: String
        public var name: String
        public var message: String
    }

    /// `Resources/Extensions` in the app (or the repository's `extensions/` in development).
    public let directory: URL?
    private let problems = Mutex<[Problem]>([])

    public init(directory: URL?) { self.directory = directory }

    /// The catalog's entries whose folders hold a readable manifest, in catalog order.
    public func entries() -> [Entry] {
        guard let directory, let data = FileManager.default.contents(atPath: directory.appendingPathComponent(Self.catalogFile).path),
              let catalog = try? JSONValue.parse(String(decoding: data, as: UTF8.self)) else { return [] }
        return (catalog["extensions"]?.arrayValue ?? []).compactMap { item in
            guard let name = item.string("folder"), !name.contains("/"), !name.hasPrefix(".") else { return nil }
            let folder = directory.appendingPathComponent(name, isDirectory: true)
            guard let manifestData = FileManager.default.contents(atPath: folder.appendingPathComponent(ExtensionManifest.fileName).path),
                  let manifest = try? ExtensionManifest.decode(manifestData) else { return nil }
            return Entry(id: manifest.id, name: manifest.name, folder: folder, on: item["on"]?.boolValue ?? false)
        }
    }

    /// Folders in the directory that aren't in the catalog: samples the person may install themselves.
    public func samples() -> [URL] {
        guard let directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let bundled = Set(entries().map(\.folder.lastPathComponent))
        return names.sorted().filter { !bundled.contains($0) && !$0.hasPrefix(".") }
            .map { directory.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent(ExtensionManifest.fileName).path) }
    }

    /// Built-in extensions the last `install(into:)` couldn't install, for Settings.
    public var unavailable: [Problem] { problems.withLock { $0 } }

    /// Installs what is missing and replaces what the app brings a different copy of. Runs at every launch;
    /// when nothing changed it only hashes the shipped files.
    public func install(into host: ExtensionHost) async {
        var found: [Problem] = []
        for entry in entries() {
            if let problem = await reconcile(entry, host: host) {
                found.append(Problem(id: entry.id, name: entry.name, message: problem))
                Log.shared.warning("extensions", "built-in extension not installed", ["id": entry.id, "why": problem])
            }
        }
        problems.withLock { $0 = found }
        host.events.changed(.extensions)
    }

    /// Nil when the extension is in place; otherwise why it isn't.
    private func reconcile(_ entry: Entry, host: ExtensionHost) async -> String? {
        let preview = await host.preview(folder: entry.folder)
        guard preview.report.isValid, let manifest = preview.report.manifest, manifest.id == entry.id else {
            // The checks name the manifest field; people only need what is wrong ("git isn't installed …").
            return preview.report.errors.first?.message ?? String(localized: "It didn't pass Sidefolk's checks.")
        }
        guard let shipped = try? ExtensionFiles.pin(entry.folder.path, skipping: ExtensionFiles.skippedNames) else {
            return String(localized: "Its files couldn't be read.")
        }
        let installed = await host.info(id: entry.id)
        var enabled = entry.on
        var notice: String?
        if let installed {
            guard installed.kind == .sidefolk else { return preview.conflict }
            let state = await host.installedState(id: entry.id)
            switch installed.origin {
            case .bundled?:
                if state?.contentHash == ExtensionFiles.contentHash(shipped), state?.intact == true { return nil }
                // Damaged copies come back as the catalog has them; updates keep the person's choice.
                enabled = state?.intact == false ? entry.on : installed.enabled
            default:
                // A copy installed by hand stays unless the app brings a newer version of it.
                guard ExtensionVersion.compare(manifest.version, installed.version) == .orderedDescending else { return nil }
                enabled = installed.enabled
                notice = String(localized: "Sidefolk replaced your copy of \(installed.name) (\(installed.version)) with its built-in version \(manifest.version).")
            }
            // Something new it may do waits for the person to switch it back on.
            if let gained = preview.update?.addedPermissions, !gained.isEmpty, enabled {
                enabled = false
                notice = String(localized: "\(installed.name) was updated with Sidefolk and can now do more (\(Wording.list(gained))). I turned it off until you switch it on in Settings › Extensions.")
            }
        } else if preview.conflict != nil {
            return preview.conflict
        }
        do {
            try await host.install(from: entry.folder, origin: .bundled, enabled: enabled)
        } catch {
            return (error as? UserFacingError)?.message ?? String(describing: error)
        }
        if let notice { host.events.publish(.notice(notice)) }
        return nil
    }
}

/// Dotted extension versions (`1.2`, `1.2.3`, `1.2.3-beta.1`): numbers compared part by part, and a
/// pre-release before its release.
enum ExtensionVersion {
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ v: String) -> (numbers: [Int], pre: String?) {
            let split = v.split(separator: "-", maxSplits: 1).map(String.init)
            let core = split.first?.split(separator: "+").first.map(String.init) ?? v
            let numbers = core.split(separator: ".").map { Int($0) ?? 0 }
            return (numbers + Array(repeating: 0, count: max(0, 3 - numbers.count)), split.count > 1 ? split[1] : nil)
        }
        let (x, y) = (parts(a), parts(b))
        for (p, q) in zip(x.numbers, y.numbers) where p != q { return p < q ? .orderedAscending : .orderedDescending }
        switch (x.pre, y.pre) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (p?, q?): return p == q ? .orderedSame : (p < q ? .orderedAscending : .orderedDescending)
        }
    }
}
