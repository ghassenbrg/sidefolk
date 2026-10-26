import AppKit
import SidefolkCharacter

/// The Folk Family as pictures for the windows, drawn by the same rig as the desktop folks and
/// cached per folk and size (a few dozen small bitmaps at most).
enum FolkArt {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String, size: CGFloat) -> NSImage? {
        guard let folk = Folk(rawValue: name) else { return nil }
        let key = "\(name)-\(Int(size))"
        if let cached = cache[key] { return cached }
        let pixels = CharacterRenderer.folkImage(folk, size: CGSize(width: size, height: size), scale: 2)
        let image = NSImage(cgImage: pixels, size: NSSize(width: size, height: size))
        cache[key] = image
        return image
    }
}
