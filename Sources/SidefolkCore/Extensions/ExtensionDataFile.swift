import Darwin
import Foundation

/// A picture an extension shows on its palette or page (D68): a file it wrote in its own data folder, named relative to
/// it (`thumbs/ab12.png`). The sandbox lets the extension write only there, so this opens nothing new for it; what keeps
/// Sidefolk from reading anything else is here: a plain name, the file opened without following a link, and the path
/// of what was opened checked to be inside the folder, with one link and a size cap. What is read is only drawn, for
/// the person: it never goes back to the extension or to a model.
public enum ExtensionDataFile {
    /// Up to four folders deep, no part starting with a dot (so no `..`), a picture's extension.
    static let pattern = #"^([A-Za-z0-9_-][A-Za-z0-9._-]{0,99}/){0,3}[A-Za-z0-9_-][A-Za-z0-9._-]{0,99}\.(png|jpg|jpeg)$"#
    /// A row's picture; a list asks for up to 200 of them.
    public static let thumbnailLimit = 4 * 1024 * 1024
    /// A preview's picture: a screenshot of a big display, as copied.
    public static let previewLimit = 25 * 1024 * 1024

    public static func isValidName(_ name: String) -> Bool {
        name.count <= 200 && name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The file's bytes, or nil when it isn't a regular file of one link inside `folder` and at most `limit` bytes.
    public static func read(_ name: String, in folder: URL, limit: Int) -> Data? {
        guard isValidName(name), let root = FolderAccess.canonical(folder.path) else { return nil }
        let fd = open(folder.appendingPathComponent(name).path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        // Where the opened file really is, after any folder on the way that was a link: checked on the open file, so
        // swapping the path afterwards changes nothing.
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
        let real = String(cString: buffer)
        var info = stat()
        guard real.hasPrefix(root + "/"), fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1,
              info.st_size > 0, info.st_size <= limit else { return nil }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: false).readData(ofLength: Int(info.st_size))
    }
}
