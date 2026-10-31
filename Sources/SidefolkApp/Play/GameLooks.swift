import AppKit
import SidefolkCore
import SwiftUI

/// How Sidefolk dresses a game (`GameLook`, D79 amended): its colour for the header, the menu card and its buttons, the
/// scene behind the board, and its icon. The colour is the game's identity only, never a verdict (D78): red or coral
/// may dress a game, a win stays the theme's green and a loss the calm sand tone.
struct GameStyle {
    /// The header's colour, top and bottom.
    var top: Color
    var bottom: Color
    /// Words and icons on that colour.
    var onColor: Color
    /// The scene behind the board, and whether its bottom is a table the props stand on.
    var scene: GameArt?
    /// The menu card's picture.
    var icon: GameArt?
    /// The scene is dark in both appearances (the arcade): no dimming in dark mode, light words on it.
    var night = false

    static func of(_ look: GameLook?) -> GameStyle {
        switch look {
        case .quiz: GameStyle(top: Color(hex: 0x6B7BFF), bottom: Color(hex: 0x4A55D9), onColor: .white, scene: .sceneQuiz, icon: .iconQuiz)
        case .grid: GameStyle(top: Color(hex: 0x22C2B0), bottom: Color(hex: 0x0E9384), onColor: .white, scene: .sceneGrid, icon: .iconGrid)
        case .dance: GameStyle(top: Color(hex: 0x3FCB74), bottom: Color(hex: 0x1F9E52), onColor: .white, scene: .sceneDance, icon: .iconDance)
        case .arcade: GameStyle(top: Color(hex: 0x3A2380), bottom: Color(hex: 0x1D1450), onColor: .white, scene: .sceneArcade, icon: .iconArcade,
                                night: true)
        case .cups: GameStyle(top: Color(hex: 0xF4626A), bottom: Color(hex: 0xD6404B), onColor: .white, scene: .sceneCups, icon: .iconCups)
        case .numbers: GameStyle(top: Color(hex: 0xFF9447), bottom: Color(hex: 0xE8691C), onColor: .white, scene: .sceneNumbers, icon: .iconNumbers)
        case .animals: GameStyle(top: Color(hex: 0x7DBD45), bottom: Color(hex: 0x4F9128), onColor: .white, scene: .sceneAnimals, icon: .iconAnimals)
        case .balloons: GameStyle(top: Color(hex: 0x45B4F5), bottom: Color(hex: 0x1D8AD8), onColor: .white, scene: .sceneBalloons, icon: .iconBalloons)
        case .sticks: GameStyle(top: Color(hex: 0x9B6BFA), bottom: Color(hex: 0x7342E0), onColor: .white, scene: .sceneSticks, icon: .iconSticks)
        case .cards: GameStyle(top: Color(hex: 0xF0619D), bottom: Color(hex: 0xCC3A7A), onColor: .white, scene: .sceneCards, icon: .iconCards)
        case .words: GameStyle(top: Color(hex: 0xFFD25C), bottom: Color(hex: 0xF2B21B), onColor: Color(hex: 0x3B2A05), scene: .sceneWords, icon: .iconWords)
        case .plots: GameStyle(top: Color(hex: 0xB98455), bottom: Color(hex: 0x92603A), onColor: .white, scene: .scenePlots, icon: .iconPlots)
        case .seesaw: GameStyle(top: Color(hex: 0xB06AB3), bottom: Color(hex: 0x8A4590), onColor: .white, scene: .sceneSeesaw, icon: .iconSeesaw)
        case .sudoku: GameStyle(top: Color(hex: 0x6F8BAB), bottom: Color(hex: 0x4A6585), onColor: .white, scene: .sceneSudoku, icon: .iconSudoku)
        case .blossoms: GameStyle(top: Color(hex: 0xFF9580), bottom: Color(hex: 0xEC6A55), onColor: .white, scene: .sceneBlossoms, icon: .iconBlossoms)
        case .hands: GameStyle(top: Color(hex: 0xFFAE48), bottom: Color(hex: 0xEE8A1E), onColor: .white, scene: .sceneCups, icon: .iconHands)
        case nil: GameStyle(top: Theme.accent.opacity(0.85), bottom: Theme.accent, onColor: Theme.onAccent, scene: .sceneDance, icon: nil)
        }
    }

    /// The colour as one fill, for a tile or a chip.
    var color: Color { bottom }
    var gradient: LinearGradient { LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom) }
}

/// The scene behind a board: the game's illustration filling the panel's body, its top fading into the panel, dimmed
/// in dark mode so the cards on it keep their contrast. Never anything a game sent.
struct GameSceneBackground: View {
    var style: GameStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.surface
                if let image = style.scene?.image {
                    Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                        .clipped()
                }
                // Dark mode: the room in the evening, its own colour kept faintly.
                if scheme == .dark && !style.night {
                    LinearGradient(colors: [Color.black.opacity(0.62), Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    style.bottom.opacity(0.08)
                }
                // The header's colour runs a little way down, so the band and the scene read as one.
                LinearGradient(colors: [style.bottom.opacity(0.55), style.bottom.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The wooden table at the bottom of a game's scene, as a strip a prop stands on (cups, pads, sticks): the same
/// picture's last third, so the table in front of the companion is the room's own.
struct GameTableStrip: View {
    var style: GameStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if let table = style.scene?.table {
                Image(nsImage: table).resizable().interpolation(.medium)
            } else {
                LinearGradient(colors: [Color(hex: 0xD9955A), Color(hex: 0xB0703C)], startPoint: .top, endPoint: .bottom)
            }
            if scheme == .dark && !style.night { Color.black.opacity(0.42) }
            // Its back edge softened, so the companion behind it sinks into the table rather than being cut.
            LinearGradient(colors: [.black.opacity(0.12), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
        }
        .accessibilityHidden(true)
    }
}
