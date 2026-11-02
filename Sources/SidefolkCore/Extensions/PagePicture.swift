import CoreGraphics
import Darwin
import Foundation
import ImageIO

/// Reads a picture from an extension's own pack for its page (D100): the installed copy's `assets` folder (D99), its path checked,
/// not a link, within the limits, its bytes what was installed. Anything off comes back nil and the part draws without it.
///
/// Reconciling with team/ext-scene: D99's `PackAssetReader` does this for scenes with the same addressing (a path relative to the
/// manifest's `assets`). When both are in, this type's body is that reader's `image(_:maxSide:)`.
public struct PagePictureReader: Sendable {
    public static let maxBytes = 4 * 1024 * 1024
    public static let types: Set<String> = ["png", "jpg", "jpeg", "webp", "heic"]

    let root: String
    let prefix: String
    let pins: [String: String]

    /// A plain relative path of a picture: no `..`, no leading `/`, nothing hidden, nothing that could read as an address.
    static func clean(_ path: String) -> String? {
        guard !path.isEmpty, path.utf8.count <= 200, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              types.contains((path as NSString).pathExtension.lowercased()) else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 8, parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && $0.range(of: #"^[\p{L}\p{N}._ -]+$"#, options: .regularExpression) != nil }) else { return nil }
        return path
    }

    /// The picture, at most `maxSide` pixels on its long side, whatever its header says.
    public func image(_ path: String, maxSide: Int) -> CGImage? {
        guard let path = Self.clean(path) else { return nil }
        var walked = root
        for part in path.split(separator: "/") {
            walked += "/" + part
            guard let st = ExtensionFS.lstat(walked), st.st_mode & S_IFMT != S_IFLNK else { return nil }
        }
        guard let st = ExtensionFS.lstat(walked), ExtensionFS.isRegular(st), Int(st.st_size) <= Self.maxBytes,
              let data = FileManager.default.contents(atPath: walked), let pin = pins[prefix + "/" + path], ExtensionHash.sha256(data) == pin else { return nil }
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) == 1 else { return nil }
        let thumb = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                     kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: max(1, maxSide)] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumb)
    }
}
