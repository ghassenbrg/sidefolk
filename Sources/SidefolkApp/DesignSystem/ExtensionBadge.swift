import AppKit
import SidefolkCore
import SwiftUI

/// How an extension looks wherever it is named: its name, its icon file (already checked by Sidefolk as
/// a square PNG or PDF), and its folk.
struct ExtensionLook: Hashable {
    var name: String
    var iconPath: String?
    var folk: String?
}

/// An extension's icon, everywhere one is drawn (the gallery, Settings, install previews, pages, Today's tiles, the
/// sidebar): a continuous rounded square like a Mac app's (corners at 22.5% of the side), a hairline edge so a pale
/// icon doesn't melt into a pale card, and a soft shadow once it's big enough to sit on the page (D67). Without an
/// icon of its own (MCP servers, drafts, extensions that don't ship one) it gets a tile in its folk's colour with
/// its page's symbol or its initial; extensions without a folk get a folk picked from their name, so two of them
/// rarely look alike.
struct ExtensionBadge: View {
    var look: ExtensionLook
    var size: CGFloat = 32
    /// Drawn instead of the initial when there's no icon file: a page's own symbol.
    var symbol: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let image = ExtensionIconCache.image(at: look.iconPath) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                let color = Theme.folkColor(Self.folk(for: look))
                ZStack {
                    LinearGradient(colors: [color.opacity(0.55), color], startPoint: .top, endPoint: .bottom)
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(Theme.navy)
                    } else {
                        Text(verbatim: Self.initial(look.name))
                            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.navy)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(size >= 24 ? 0.16 : 0), radius: size * 0.05, y: size * 0.025)
        .accessibilityHidden(true)
    }

    static let folks = ["byte", "tempo", "scout", "pip", "seed", "melody", "nova", "play", "brew", "guard"]

    static func folk(for look: ExtensionLook) -> String {
        if let folk = look.folk, folks.contains(folk) { return folk }
        // Stable across launches (String.hashValue isn't): the sum of the name's bytes.
        let sum = look.name.utf8.reduce(0) { $0 + Int($1) }
        return folks[sum % folks.count]
    }

    static func initial(_ name: String) -> String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }
}

/// Icons decoded once per file version. Paths come from Sidefolk's checked copies (or the folder being
/// previewed), and a file that changes on disk is read again.
@MainActor
enum ExtensionIconCache {
    private static var images: [String: (stamp: Date, image: NSImage?)] = [:]

    static func image(at path: String?) -> NSImage? {
        guard let path, let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int, size <= SidefolkCore.ExtensionIcon.maxBytes,
              let stamp = attributes[.modificationDate] as? Date else { return nil }
        if let cached = images[path], cached.stamp == stamp { return cached.image }
        let image = NSImage(contentsOfFile: path)
        images[path] = (stamp, image)
        return image
    }
}
