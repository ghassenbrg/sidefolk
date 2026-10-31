import Darwin
import Foundation

/// Putting a checked new copy where the running one is (D46). The new copy is staged beside the old one, on the
/// same volume, under a hidden name; one atomic rename then exchanges the two, so the app's path always holds a
/// whole, signed Sidefolk, and a failure before that leaves the old one untouched.
public enum BundleSwap {
    /// Staged copies and the swapped-out old one carry this prefix, so leftovers are known and nothing else is removed.
    static let prefix = ".Sidefolk-update-"

    /// Where the new version waits beside `bundle`.
    public static func stagingURL(beside bundle: URL, version: ReleaseVersion) -> URL {
        bundle.deletingLastPathComponent().appendingPathComponent("\(prefix)\(version).app", isDirectory: true)
    }

    static func isStaging(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(prefix) && url.pathExtension == "app"
    }

    /// Copies an app bundle as it is: signature, symlinks, extended attributes and all.
    static func copy(_ source: URL, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        let out = try await SystemTool.run("/usr/bin/ditto", [source.path, destination.path], timeout: 300)
        guard out.status == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw UserFacingError("Sidefolk couldn't copy the new version beside itself.", detail: "ditto exited \(out.status)")
        }
    }

    /// Removes the download mark from every file of a copy that was already checked. Sidefolk marks what it writes
    /// (LSFileQuarantineEnabled, D39), and a marked copy would stop at Gatekeeper's "downloaded from the internet"
    /// question on its first launch, after Sidefolk itself had quit.
    static func clearQuarantine(_ bundle: URL) {
        let fm = FileManager.default
        var paths = [bundle.path]
        if let walk = fm.enumerator(at: bundle, includingPropertiesForKeys: nil, options: []) {
            for case let url as URL in walk { paths.append(url.path) }
        }
        for path in paths { removexattr(path, ExtensionFiles.quarantine, XATTR_NOFOLLOW) }
    }

    /// Exchanges two folders on the same volume in one step (`renamex_np` with `RENAME_SWAP`).
    public static func swap(_ a: URL, _ b: URL) throws {
        guard renamex_np(a.path, b.path, UInt32(RENAME_SWAP)) == 0 else {
            let code = errno
            throw UserFacingError("Sidefolk couldn't put the new version in place, so nothing changed.",
                                  detail: String(cString: strerror(code)))
        }
    }

    /// Once process `pid` has quit, opens `app` and removes `leftover` (the old copy, now under the staging name).
    /// With no `app` it only removes: an update put in place as Sidefolk quits (D70) waits for the next launch.
    /// The waiting shell gets only its arguments: no paths are pasted into the script.
    public static func relaunch(after pid: Int32, open app: URL?, removing leftover: URL, environment: [String: String] = [:]) throws {
        let env = environment.sorted { $0.key < $1.key }.flatMap { ["--env", "\($0.key)=\($0.value)"] }
        let script = """
            pid=$1; app=$2; old=$3; shift 3
            while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
            [ -n "$app" ] && /usr/bin/open "$@" "$app"
            case "$old" in */\(prefix)*.app) /bin/rm -rf "$old" ;; esac
            """
        _ = try PosixSpawn.run("/bin/sh", arguments: ["-c", script, "sh", String(pid), app?.path ?? "", leftover.path] + env,
                               environment: nil, searchPath: false,
                               options: PosixSpawn.Options(newProcessGroup: true, closeOtherDescriptors: true))
    }

    /// Removes staged or swapped-out copies an earlier update left beside `bundle` (a quit during the download,
    /// a shell that couldn't remove the old copy). Never the running copy, never anything without the prefix.
    public static func removeLeftovers(beside bundle: URL) {
        let fm = FileManager.default
        let folder = bundle.deletingLastPathComponent()
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".app") {
            let url = folder.appendingPathComponent(name)
            guard url.standardizedFileURL != bundle.standardizedFileURL else { continue }
            try? fm.removeItem(at: url)
        }
    }
}
