import AppKit
import SidefolkCharacter
import SidefolkCore

/// Maps the settings onto the character module (D30), and keeps the still pictures Settings shows.
enum CompanionArt {
    private static var previews: [String: NSImage] = [:]

    /// The companions Settings offers: only those whose rigs are finished, and the 3D-only ones once
    /// they are installed from the add-on gallery (D55).
    static var offered: [CompanionChoice] {
        CharacterSpecies.available.filter { !$0.only3D || Companion3DStage.has($0) }
            .compactMap { CompanionChoice(rawValue: $0.rawValue) }.filter { !$0.isRetired }
    }

    /// Whether `choice` is shown in 3D: as the settings say, when this copy can draw it so (D51).
    static func threeD(_ choice: CompanionChoice, in settings: AppSettings) -> Bool {
        settings.dimension(for: choice) == .threeD && Companion3DStage.folder != nil
    }

    static func look(_ choice: CompanionChoice, style: CompanionStyle, threeD: Bool = false) -> CharacterLook {
        CharacterLook(species(choice), style: CharacterStyle(color: CharacterAccent(style.color),
                                                             accessory: CharacterAccessory(style.accessory)), threeD: threeD)
    }

    /// What the settings say; a companion that isn't offered (yet) shows as Mochi. A custom one
    /// that loads is worn in the chosen companion's style; one added from a folder stands on the rig its body borrows.
    static func look(for settings: AppSettings) -> CharacterLook {
        if let local = local(settings.localCompanion) {
            var look = CharacterLook(standIn(local.body), threeD: true)
            look.character3D = local.companion
            return look
        }
        let choice = offered.contains(settings.companion) ? settings.companion : .mochi
        let built = look(choice, style: settings.style(for: choice), threeD: threeD(choice, in: settings))
        guard let custom = custom(settings.customCompanion) else { return built }
        return CharacterLook(custom: custom, style: built.style)
    }

    /// Drops the pictures drawn so far (a companion was installed or removed).
    static func forgetPictures() { previews = [:] }

    static func liveliness(_ level: CompanionLiveliness) -> Liveliness {
        Liveliness(rawValue: level.rawValue) ?? .balanced
    }

    // MARK: Made by you

    /// Companions made from data in `<home>/companions/` (and installed extensions), as last read.
    private(set) static var made: [CompanionReport] = CustomCompanions.loadAll(home: SidefolkPaths.standard().home)

    /// Reads them again (at launch and when Settings › Companion opens): data only, never run.
    static func reloadMade() {
        made = CustomCompanions.loadAll(home: SidefolkPaths.standard().home)
        locals = loadLocals()
        previews = previews.filter { !$0.key.hasPrefix("custom:") }
    }

    static func custom(_ id: String?) -> CustomCompanion? {
        guard let id else { return nil }
        return made.lazy.compactMap(\.companion).first { $0.id == id }
    }

    /// 3D companions added from a folder (D60), as last read: those whose files are all here.
    private(set) static var locals: [InstalledCompanion] = loadLocals()

    private static func loadLocals() -> [InstalledCompanion] {
        AddonStore.installedCompanions(in: CompanionAddons.folder).filter { $0.addedFromFolder && Companion3DStage.has($0.companion) }
    }

    static func local(_ name: String?) -> InstalledCompanion? {
        guard let name else { return nil }
        return locals.first { $0.companion == name }
    }

    /// The rig a companion added from a folder stands on, undrawn: a gallery companion's of the same build.
    static func standIn(_ body: CompanionBody?) -> CharacterSpecies {
        switch body ?? .biped {
        case .biped: .kiko
        case .floating: .nimbo
        case .card: .folio
        }
    }

    static func species(_ choice: CompanionChoice) -> CharacterSpecies {
        CharacterSpecies(rawValue: choice.rawValue) ?? .mochi
    }

    /// One line about who it is, under its name.
    static func role(_ choice: CompanionChoice) -> String {
        switch choice {
        case .mochi: String(localized: "Your AI companion")
        case .spark: String(localized: "A little robot helper")
        case .ember: String(localized: "A curious little fox")
        case .kiko: String(localized: "A young space explorer")
        case .nimbo: String(localized: "A dreamy little cloud")
        case .folio: String(localized: "A folded little wish")
        default: ""   // folks and the robot aren't offered (D54, D56)
        }
    }

    /// The companion standing idle in its style, as the Settings gallery shows it (in 3D when
    /// that is how it would come or has been chosen).
    static func preview(_ choice: CompanionChoice, style: CompanionStyle, threeD: Bool = false, side: CGFloat) -> NSImage {
        picture(choice, style: style, state: .idle, threeD: threeD, side: side)
    }

    /// The companion the settings choose, still in `state`, as Home and the Ask panel show it.
    static func portrait(for settings: AppSettings, state: CharacterState = .idle, side: CGFloat) -> NSImage {
        if let local = local(settings.localCompanion), let still = localPicture(local, side: side) { return still }
        let choice = offered.contains(settings.companion) ? settings.companion : .mochi
        if let custom = custom(settings.customCompanion) {
            let look = look(for: settings), size = CGSize(width: side, height: side)
            let key = "custom:\(custom.id).\(look.style.color.rawValue).\(look.style.accessory.rawValue).\(state.name).\(side)"
            if let cached = previews[key] { return cached }
            let image = NSImage(cgImage: CharacterRenderer.image(state: state, size: size, scale: 2, look: look), size: size)
            previews[key] = image
            return image
        }
        return picture(choice, style: settings.style(for: choice), state: state, threeD: threeD(choice, in: settings), side: side)
    }

    /// Who is talking, as a round picture `side` across (the Ask panel): a 3D companion's profile picture, or else
    /// the drawn companion's face on a soft disc (its canvas has room around the body, so the middle is cut out).
    static func avatar(for settings: AppSettings, side: CGFloat) -> NSImage {
        let choice = offered.contains(settings.companion) ? settings.companion : .mochi
        let local = local(settings.localCompanion)
        if settings.customCompanion == nil, local != nil || threeD(choice, in: settings) || species(choice).only3D {
            let name = local?.companion ?? choice.rawValue
            let key = "avatar.\(name).\(side)"
            if let cached = previews[key] { return cached }
            if let image = Companion3DStage.avatar(name) {
                image.size = CGSize(width: side, height: side)
                previews[key] = image
                return image
            }
        }
        let drawn = portrait(for: settings, side: side * 2)
        let disc = NSColor(Theme.accentSoft)
        // Drawn when shown, so the disc follows light and dark.
        return NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            disc.setFill()
            rect.fill()
            drawn.draw(in: NSRect(x: -side / 2, y: -side / 2 + 1, width: side * 2, height: side * 2))
            return true
        }
    }

    /// A companion added from a folder as it stands at rest: its own still, `side` across.
    static func localPicture(_ local: InstalledCompanion, side: CGFloat) -> NSImage? {
        let key = "local.\(local.companion).\(side)"
        if let cached = previews[key] { return cached }
        guard let still = Companion3DStage.portrait(local.companion) else { return nil }
        still.size = CGSize(width: side, height: side)
        previews[key] = still
        return still
    }

    private static func picture(_ choice: CompanionChoice, style: CompanionStyle, state: CharacterState, threeD: Bool,
                                side: CGFloat) -> NSImage {
        let key = "\(choice.rawValue).\(style.color.rawValue).\(style.accessory.rawValue).\(state.name).\(threeD).\(side)"
        if let cached = previews[key] { return cached }
        let size = CGSize(width: side, height: side)
        // A 3D companion's still is a render of it (one pose: the 3D one has no 2D states to draw).
        if threeD || species(choice).only3D, let still = Companion3DStage.portrait(choice.rawValue) {
            still.size = size
            previews[key] = still
            return still
        }
        let image = NSImage(cgImage: CharacterRenderer.image(state: state, size: size, scale: 2, look: look(choice, style: style)),
                            size: size)
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

extension CharacterAccessory {
    init(_ accessory: CompanionAccessory) {
        switch accessory {
        case .none: self = .none
        case .scarf: self = .scarf
        }
    }
}
