import SidefolkCore
import SwiftUI

/// The Settings window's eight tabs (D84), in the sidebar's order. AI and Voice became Brain; Privacy, Location and
/// what other agents may do became Trust; agents' connections are Connections; Extensions are Add-ons; how Sidefolk
/// looks is Appearance; quiet, focus and how things reach you are Attention.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, companion, attention, brain, trust, connections, addons, appearance
    var id: Self { self }

    // The names before D84, so every "Open Settings" elsewhere still lands where it meant.
    static let ai = SettingsTab.brain
    static let voice = SettingsTab.brain
    static let agents = SettingsTab.connections
    static let privacy = SettingsTab.trust
    static let extensions = SettingsTab.addons

    /// A tab by its name, old names included (the debug app's `settings:<tab>`).
    init?(named name: String) {
        let old: [String: SettingsTab] = ["ai": .brain, "voice": .brain, "agents": .connections, "privacy": .trust,
                                          "extensions": .addons]
        guard let tab = SettingsTab(rawValue: name) ?? old[name] else { return nil }
        self = tab
    }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .companion: String(localized: "Companion")
        case .attention: String(localized: "Attention", comment: "A Settings tab: Focus, Quiet and how things reach you")
        case .brain: String(localized: "Brain", comment: "A Settings tab: the AI that answers, and voice")
        case .trust: String(localized: "Trust", comment: "A Settings tab: what Sidefolk may do without asking, folders, privacy, data")
        case .connections: String(localized: "Connections", comment: "A Settings tab: Claude Code, Codex and other apps that reach Sidefolk")
        case .addons: String(localized: "Add-ons", comment: "A Settings tab: installed extensions, tool servers and skills")
        case .appearance: String(localized: "Appearance", comment: "A Settings tab: theme, light or dark, density, icons")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .companion: "face.smiling.inverse"
        case .attention: Theme.Symbol.quiet
        case .brain: "sparkles"
        case .trust: "checkmark.shield.fill"
        case .connections: "powerplug.fill"
        case .addons: "puzzlepiece.extension.fill"
        case .appearance: "paintpalette.fill"
        }
    }

    /// The tile behind the tab's symbol, as in System Settings: identity, never status.
    var tint: Color {
        switch self {
        case .general: Color(hex: 0x8A94A6)
        case .companion: Color(hex: 0x2FBFC8)
        case .attention: Theme.folkColor("nova")
        case .brain: Theme.folkColor("byte")
        case .trust: Theme.folkColor("guard")
        case .connections: Theme.folkColor("tempo")
        case .addons: Color(hex: 0xF08C4A)
        case .appearance: Color(hex: 0x1B7F86)
        }
    }
}
