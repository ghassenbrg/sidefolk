import Foundation
import SidefolkCharacter
import SidefolkCore

/// Companions installed from the add-on gallery (D55): `<home>/Addons/Companions/<name>/` holds a character's
/// `characters/<name>.js`, `assets/<name>.glb`, `portraits/<name>.png` and `avatars/<name>.png`, checked against
/// their signature when they were installed (`AddonStore`).
enum CompanionAddons {
    static var folder: URL { SidefolkPaths.standard().addons.appendingPathComponent("Companions", isDirectory: true) }

    /// The installed file for one of the page's paths, or nil. Only those four kinds of file, each named after the
    /// companion whose folder it is in: nothing else of the folder is ever served.
    static func file(_ path: String) -> URL? {
        guard let match = path.wholeMatch(of: #/(characters|assets|portraits|avatars)/([a-z][a-z0-9-]{0,30})\.(js|glb|png)/#) else {
            return nil
        }
        let kind = String(match.1), ext = String(match.3)
        let expected = ["characters": "js", "assets": "glb", "portraits": "png", "avatars": "png"]
        guard expected[kind] == ext else { return nil }
        let file = folder.appendingPathComponent(String(match.2), isDirectory: true).appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}
