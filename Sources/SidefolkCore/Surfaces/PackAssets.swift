import AVFoundation
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An extension's own pictures and sounds (D99): files in the `assets` folder of its pack, addressed by a path relative
/// to that folder, checked here twice: by the validator at install, against these limits, and again when one is loaded,
/// against the install's pin as well. Nothing comes from outside the pack, and nothing in a file is followed, run or fetched.
public enum PackAssets {
    public static let imageTypes = ["png", "jpg", "jpeg", "webp", "heic"]
    public static let soundTypes = ["wav", "aif", "aiff", "caf", "m4a"]

    public static let maxImageBytes = 4 * 1024 * 1024
    /// On each side; large enough for a panel's backdrop at twice its size, with room.
    public static let maxImageSide = 3000
    public static let maxImagePixels = 6_000_000
    public static let maxSoundBytes = 2 * 1024 * 1024
    public static let maxSoundSeconds = 10.0
    public static let maxSoundRate = 96_000.0
    public static let maxFiles = 512
    /// All of a pack's assets together, so an add-on stays small to fetch and to keep.
    public static let maxTotalBytes = 48 * 1024 * 1024
    /// What one surface may hold decoded in memory, as the panel's cache evicts down to.
    public static let maxDecodedBytes = 96 * 1024 * 1024

    public enum Kind: Sendable, Hashable { case image, sound }

    public static func kind(of path: String) -> Kind? {
        let type = (path as NSString).pathExtension.lowercased()
        if imageTypes.contains(type) { return .image }
        if soundTypes.contains(type) { return .sound }
        return nil
    }

    /// A safe relative path inside the assets folder: plain names, no `..`, no leading `/`, no hidden parts, nothing
    /// that could read as a URL. Nil for anything else.
    public static func clean(_ path: String) -> String? {
        guard !path.isEmpty, path.utf8.count <= 200, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 8, parts.allSatisfy({ part in
            !part.isEmpty && !part.hasPrefix(".") && part.range(of: #"^[\p{L}\p{N}._ -]+$"#, options: .regularExpression) != nil
        }) else { return nil }
        return path
    }

    // MARK: Checking one file

    /// Nil when `data` is an image Sidefolk will draw, else what is wrong: its real type must match its name, one frame,
    /// within the caps. It reads the header alone, so a bomb is refused before any pixel is decoded.
    public static func imageProblem(_ data: Data, fileName: String) -> String? {
        guard data.count <= maxImageBytes else { return "is \(data.count / 1024) KiB; a picture can be at most \(maxImageBytes / 1024 / 1024) MiB." }
        let name = (fileName as NSString).pathExtension.lowercased()
        guard imageTypes.contains(name) else { return "must be a \(imageTypes.joined(separator: ", ")) file." }
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), let type = CGImageSourceGetType(source) as String? else {
            return "isn't a picture Sidefolk can read."
        }
        guard contentMatches(type: type, name: name) else { return "says .\(name), but it is really \(type)." }
        guard CGImageSourceGetCount(source) == 1 else { return "must be one still picture, not an animation." }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return "has no size Sidefolk can read." }
        guard width <= maxImageSide, height <= maxImageSide, width * height <= maxImagePixels else {
            return "is \(width)×\(height) pixels; at most \(maxImageSide) on a side and \(maxImagePixels / 1_000_000) million in all."
        }
        return nil
    }

    private static func contentMatches(type: String, name: String) -> Bool {
        switch name {
        case "png": type == UTType.png.identifier
        case "jpg", "jpeg": type == UTType.jpeg.identifier
        case "webp": type == UTType.webP.identifier
        case "heic": type == UTType.heic.identifier
        default: false
        }
    }

    /// Decodes a checked picture at most `maxSide` pixels on its long side, or nil: a truncated or corrupt file draws
    /// nothing and never stops the panel. A thumbnail keeps the decoded size within what was asked, whatever the header said.
    public static func decodeImage(_ data: Data, fileName: String, maxSide: Int) -> CGImage? {
        guard imageProblem(data, fileName: fileName) == nil else { return nil }
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumb = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                     kCGImageSourceShouldCacheImmediately: true, kCGImageSourceShouldAllowFloat: false,
                     kCGImageSourceThumbnailMaxPixelSize: min(max(maxSide, 1), maxImageSide)] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumb)
    }

    /// Nil when `url` is a short sound Sidefolk will play, else what is wrong. The sound is opened, never played here.
    public static func soundProblem(_ url: URL) -> String? {
        let name = url.pathExtension.lowercased()
        guard soundTypes.contains(name) else { return "must be a \(soundTypes.joined(separator: ", ")) file." }
        guard let size = ExtensionFS.lstat(url.path)?.st_size, Int(size) <= maxSoundBytes else {
            return "can be at most \(maxSoundBytes / 1024 / 1024) MiB."
        }
        guard let file = try? AVAudioFile(forReading: url) else { return "isn't a sound Sidefolk can read." }
        let format = file.fileFormat
        guard format.sampleRate > 0, format.sampleRate <= maxSoundRate, (1...2).contains(format.channelCount) else {
            return "must be mono or stereo at up to \(Int(maxSoundRate / 1000)) kHz."
        }
        let seconds = Double(file.length) / format.sampleRate
        guard seconds > 0, seconds <= maxSoundSeconds else { return "lasts \(Int(seconds)) s; a sound can last at most \(Int(maxSoundSeconds)) s." }
        return nil
    }

    // MARK: Checking the folder

    public struct Report: Sendable {
        public var files: [String] = []
        public var bytes = 0
        public var problems: [(path: String, message: String)] = []
    }

    /// Every file under `assets` of a pack: the validator's check. A link, a hidden file, a type off the lists or a bad
    /// picture is a problem, as is too many or too much.
    public static func check(folder: String) -> Report {
        var report = Report()
        let entries: [ExtensionFiles.Entry]
        do {
            entries = try ExtensionFiles.walk(folder)
        } catch {
            report.problems.append(("", (error as? UserFacingError)?.message ?? "couldn't be read."))
            return report
        }
        for entry in entries where !entry.isDirectory {
            guard clean(entry.path) != nil else {
                report.problems.append((entry.path, "isn't a plain relative path (letters, digits, spaces, . _ -; nothing hidden)."))
                continue
            }
            let url = URL(fileURLWithPath: folder + "/" + entry.path)
            report.files.append(entry.path)
            report.bytes += Int(entry.st.st_size)
            switch kind(of: entry.path) {
            case .image:
                if Int(entry.st.st_size) > maxImageBytes {
                    report.problems.append((entry.path, "can be at most \(maxImageBytes / 1024 / 1024) MiB."))
                } else if let data = try? Data(contentsOf: url) {
                    if let problem = imageProblem(data, fileName: entry.path) {
                        report.problems.append((entry.path, problem))
                    } else if decodeImage(data, fileName: entry.path, maxSide: 64) == nil {
                        report.problems.append((entry.path, "couldn't be decoded."))
                    }
                } else {
                    report.problems.append((entry.path, "couldn't be read."))
                }
            case .sound:
                if let problem = soundProblem(url) { report.problems.append((entry.path, problem)) }
            case nil:
                report.problems.append((entry.path, "isn't a picture (\(imageTypes.joined(separator: ", "))) or a sound (\(soundTypes.joined(separator: ", ")))."))
            }
        }
        if report.files.count > maxFiles { report.problems.append(("", "holds \(report.files.count) files; a pack can hold at most \(maxFiles) assets.")) }
        if report.bytes > maxTotalBytes { report.problems.append(("", "holds \(report.bytes / 1024 / 1024) MiB; a pack's assets can take at most \(maxTotalBytes / 1024 / 1024) MiB.")) }
        return report
    }
}

/// Reads one extension's assets at the moment they are drawn or played: the installed copy, its path checked, not a
/// link, its bytes matching the install's pin. Anything off comes back nil, so a node simply draws nothing.
public struct PackAssetReader: Sendable {
    /// The real path of `<installed>/<assets folder>`.
    public let root: String
    /// Path in the pack (assets folder included) → its sha256 at install.
    public let pins: [String: String]
    /// The assets folder's name inside the pack.
    public let prefix: String

    public init(root: String, prefix: String, pins: [String: String]) {
        self.root = root
        self.prefix = prefix
        self.pins = pins
    }

    /// The bytes of an asset, or nil when the path isn't clean, leaves the pack, is a link or a special file, is over the
    /// caps, or isn't what was installed.
    public func data(_ path: String) -> Data? {
        guard let path = PackAssets.clean(path), let kind = PackAssets.kind(of: path) else { return nil }
        let full = root + "/" + path
        // Each part in turn, so a link anywhere on the way is seen; an installed pack has none (T14), so this guards a change made after it.
        var walked = root
        for part in path.split(separator: "/") {
            walked += "/" + part
            guard let st = ExtensionFS.lstat(walked), st.st_mode & S_IFMT != S_IFLNK else { return nil }
        }
        guard let st = ExtensionFS.lstat(full), ExtensionFS.isRegular(st) else { return nil }
        let cap = kind == .image ? PackAssets.maxImageBytes : PackAssets.maxSoundBytes
        guard Int(st.st_size) <= cap, let data = try? Data(contentsOf: URL(fileURLWithPath: full)), data.count <= cap else { return nil }
        guard let pin = pins[prefix + "/" + path], ExtensionHash.sha256(data) == pin else { return nil }
        return data
    }

    public func image(_ path: String, maxSide: Int) -> CGImage? {
        data(path).flatMap { PackAssets.decodeImage($0, fileName: path, maxSide: maxSide) }
    }

    /// A checked sound, for AVFoundation to open: its pin matched and its limits held a moment ago.
    public func soundURL(_ path: String) -> URL? {
        guard PackAssets.kind(of: path) == .sound, data(path) != nil else { return nil }
        let url = URL(fileURLWithPath: root + "/" + path)
        return PackAssets.soundProblem(url) == nil ? url : nil
    }

    public func has(_ path: String) -> Bool { PackAssets.clean(path).map { pins[prefix + "/" + $0] != nil } ?? false }
}
