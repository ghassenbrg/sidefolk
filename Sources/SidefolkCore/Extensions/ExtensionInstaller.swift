import Darwin
import Foundation

/// Moves extension folders into `Extensions/<id>/` and back out (SECURITY T14). A new version is staged
/// in a hidden folder (copied, locked read-only, pinned), then swapped in with `rename`; the previous
/// version waits in `.previous-<id>` until the install is confirmed, so a failure can roll back.
struct ExtensionInstaller: Sendable {
    let paths: SidefolkPaths

    struct Staged {
        var id: String
        var folder: String
        var pins: [ExtensionFilePin]
    }

    struct Committed {
        var id: String
        var folder: String
        var backup: String?
    }

    private func base() throws -> String {
        try ExtensionFS.makePrivateDirectory(paths.extensions)
        guard let real = ExtensionFS.realpath(paths.extensions.path) else {
            throw ExtensionError.io("The Extensions folder is missing.")
        }
        return real
    }

    func installedFolder(_ id: String) -> String {
        (ExtensionFS.realpath(paths.extensions.path) ?? paths.extensions.path) + "/" + id
    }

    func backupFolder(_ id: String) -> String {
        (ExtensionFS.realpath(paths.extensions.path) ?? paths.extensions.path) + "/.previous-" + id
    }

    /// Copies `source` (without links, special files or `.git`), locks it read-only and pins every file.
    func stage(source: URL, id: String) throws -> Staged {
        guard let src = ExtensionFS.realpath(source.path) else { throw UserFacingError("The extension folder is missing.") }
        let staging = try base() + "/.staging-" + Identifier.make()
        do {
            try ExtensionFiles.copy(from: src, to: staging)
            try ExtensionFiles.lock(staging)
            return Staged(id: id, folder: staging, pins: try ExtensionFiles.pin(staging))
        } catch {
            ExtensionFiles.removeTree(staging)
            throw error
        }
    }

    func commit(_ staged: Staged) throws -> Committed {
        let final = installedFolder(staged.id)
        var backup: String?
        if ExtensionFS.lstat(final) != nil {
            let b = backupFolder(staged.id)
            ExtensionFiles.removeTree(b)
            guard rename(final, b) == 0 else {
                ExtensionFiles.removeTree(staged.folder)
                throw ExtensionError.io("Couldn't move the previous version aside: \(String(cString: strerror(errno)))")
            }
            backup = b
        }
        guard rename(staged.folder, final) == 0 else {
            let why = String(cString: strerror(errno))
            ExtensionFiles.removeTree(staged.folder)
            if let backup { _ = rename(backup, final) }
            throw ExtensionError.io("Couldn't put the extension in place: \(why)")
        }
        return Committed(id: staged.id, folder: final, backup: backup)
    }

    /// Removes the new version and puts the previous one back.
    func rollback(_ c: Committed) {
        ExtensionFiles.removeTree(c.folder)
        if let backup = c.backup { _ = rename(backup, c.folder) }
    }

    func finish(_ c: Committed) {
        if let backup = c.backup { ExtensionFiles.removeTree(backup) }
    }

    func remove(id: String) {
        ExtensionFiles.removeTree(installedFolder(id))
        ExtensionFiles.removeTree(backupFolder(id))
        ExtensionFiles.removeTree(dataFolder(id).path)
        try? FileManager.default.removeItem(at: profileFile(id))
    }

    /// Staging folders left by an interrupted install.
    func removeStaleStaging() {
        guard let base = try? base() else { return }
        for name in (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? [] where name.hasPrefix(".staging-") {
            ExtensionFiles.removeTree(base + "/" + name)
        }
    }

    func dataFolder(_ id: String) -> URL { paths.extensionData.appendingPathComponent(id, isDirectory: true) }

    /// Profiles live outside the data folder, which the extension can write.
    func profileFile(_ id: String) -> URL {
        paths.home.appendingPathComponent("Sandbox", isDirectory: true).appendingPathComponent("\(id).sb")
    }

    /// The extension's private folder (with `tmp/`), created 0700; returns its real path.
    func prepareDataFolder(_ id: String) throws -> String {
        let dir = dataFolder(id)
        try ExtensionFS.makePrivateDirectory(dir.appendingPathComponent("tmp", isDirectory: true))
        guard let real = ExtensionFS.realpath(dir.path), let st = ExtensionFS.lstat(real), ExtensionFS.isDirectory(st) else {
            throw ExtensionError.io("The extension's data folder is missing.")
        }
        return real
    }

    func writeProfile(_ text: String, id: String) throws -> String {
        let url = profileFile(id)
        try ExtensionFS.makePrivateDirectory(url.deletingLastPathComponent())
        try Data(text.utf8).write(to: url, options: .atomic)
        _ = chmod(url.path, 0o600)
        return url.path
    }
}
