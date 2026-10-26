import AppKit
import SidefolkCharacter
import SidefolkCore

/// The art for each companion choice (DECISIONS D27). Sprite sets load once from the bundled
/// resources and are shared, so the companion window and Settings draw the same images and
/// `CharacterLook` comparisons (by identity) stay cheap.
enum CompanionArt {
    /// A missing entry has not been tried yet; nil means the art could not be loaded.
    private static var sets: [CompanionChoice: SpriteSet?] = [:]
    private static var previews: [String: NSImage] = [:]

    /// How `choice` is drawn, or nil when its poses are not in this build (it is then not offered).
    static func look(_ choice: CompanionChoice, accent: CompanionAccent) -> CharacterLook? {
        guard choice != .sidefolk else { return .sidefolk(CharacterAccent(accent)) }
        if let tried = sets[choice] { return tried.map(CharacterLook.sprites) }
        let loaded = ResourceLocator.companions.flatMap { SpriteSet(folder: $0.appendingPathComponent(choice.rawValue)) }
        if loaded == nil {
            Log.shared.error("companion", "sprite art missing", ["companion": choice.rawValue])
        }
        sets[choice] = .some(loaded)
        return loaded.map(CharacterLook.sprites)
    }

    /// What the settings say, falling back to the robot when a sprite companion's art is missing.
    static func look(for settings: AppSettings) -> CharacterLook {
        look(settings.companion, accent: settings.accent) ?? .sidefolk(CharacterAccent(settings.accent))
    }

    /// The companion standing idle, as the Settings picker shows it.
    static func preview(_ choice: CompanionChoice, accent: CompanionAccent, side: CGFloat) -> NSImage? {
        let key = "\(choice.rawValue).\(accent.rawValue).\(side)"
        if let cached = previews[key] { return cached }
        guard let look = look(choice, accent: accent) else { return nil }
        let size = CGSize(width: side, height: side)
        let image = NSImage(cgImage: CharacterRenderer.image(state: .idle, size: size, scale: 2, look: look), size: size)
        previews[key] = image
        return image
    }
}

extension CharacterAccent {
    init(_ accent: CompanionAccent) {
        switch accent {
        case .aqua: self = .aqua
        case .coral: self = .coral
        case .mint: self = .mint
        case .lightBlue: self = .lightBlue
        }
    }
}
