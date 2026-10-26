import AppKit
import SidefolkCharacter
import SidefolkCore

/// Maps the settings onto the character module (D30), and keeps the still pictures Settings shows.
enum CompanionArt {
    private static var previews: [String: NSImage] = [:]

    /// The companions Settings offers: only those whose rigs are finished.
    static var offered: [CompanionChoice] {
        CharacterSpecies.available.compactMap { CompanionChoice(rawValue: $0.rawValue) }
    }

    static func look(_ choice: CompanionChoice, style: CompanionStyle) -> CharacterLook {
        CharacterLook(species(choice), style: CharacterStyle(color: CharacterAccent(style.color),
                                                             accessory: CharacterAccessory(style.accessory)))
    }

    /// What the settings say; a companion that isn't offered (yet) shows as Mochi.
    static func look(for settings: AppSettings) -> CharacterLook {
        let choice = offered.contains(settings.companion) ? settings.companion : .mochi
        return look(choice, style: settings.style(for: choice))
    }

    static func species(_ choice: CompanionChoice) -> CharacterSpecies {
        CharacterSpecies(rawValue: choice.rawValue) ?? .mochi
    }

    /// One line about who it is, under its name.
    static func role(_ choice: CompanionChoice) -> String {
        switch choice {
        case .mochi: "Your AI companion"
        case .sidefolk: "The original robot"
        case .spark: "A little robot helper"
        default: species(choice).folk?.role ?? ""
        }
    }

    /// The companion standing idle in its style, as the Settings gallery shows it.
    static func preview(_ choice: CompanionChoice, style: CompanionStyle, side: CGFloat) -> NSImage {
        picture(choice, style: style, state: .idle, side: side)
    }

    /// The companion the settings choose, still in `state`, as Home and the Ask panel show it.
    static func portrait(for settings: AppSettings, state: CharacterState = .idle, side: CGFloat) -> NSImage {
        let choice = offered.contains(settings.companion) ? settings.companion : .mochi
        return picture(choice, style: settings.style(for: choice), state: state, side: side)
    }

    private static func picture(_ choice: CompanionChoice, style: CompanionStyle, state: CharacterState, side: CGFloat) -> NSImage {
        let key = "\(choice.rawValue).\(style.color.rawValue).\(style.accessory.rawValue).\(state.name).\(side)"
        if let cached = previews[key] { return cached }
        let size = CGSize(width: side, height: side)
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
