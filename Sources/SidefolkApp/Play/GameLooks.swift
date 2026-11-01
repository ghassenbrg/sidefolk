import AppKit
import SidefolkCore
import SwiftUI

/// How Sidefolk dresses a game (`GameLook`, D79 amended): its colour for its icon tile and the menu card, the chip that
/// names a level, the scene behind the board by day and by night, and its icon. The colour is the game's identity only,
/// never a verdict (D78): red or coral may dress a game's icon, but a level chip is never red, a win stays the theme's
/// green and a loss the calm sand tone.
struct GameStyle {
    /// The game's colour, top and bottom of its tiles.
    var top: Color
    var bottom: Color
    /// Words and icons on that colour, and on the level chip.
    var onColor: Color
    /// The scene behind the board, and whether its bottom is a table the props stand on.
    var scene: GameArt?
    /// The menu card's picture.
    var icon: GameArt?
    /// The scene is dark in both appearances (the arcade): no night version, light words on it.
    var night = false
    /// The level chip ("Fair"): the game's colour, or a neighbour of it where that colour is red or pink, which would
    /// read as a mistake beside a round's number (D78).
    var chip: Color? = nil

    static func of(_ look: GameLook?) -> GameStyle {
        switch look {
        case .quiz: GameStyle(top: Color(hex: 0x6B7BFF), bottom: Color(hex: 0x4A55D9), onColor: .white, scene: .sceneQuiz, icon: .iconQuiz)
        case .grid: GameStyle(top: Color(hex: 0x22C2B0), bottom: Color(hex: 0x0E9384), onColor: .white, scene: .sceneGrid, icon: .iconGrid)
        case .dance: GameStyle(top: Color(hex: 0x3FCB74), bottom: Color(hex: 0x1F9E52), onColor: .white, scene: .sceneDance, icon: .iconDance)
        case .arcade: GameStyle(top: Color(hex: 0x3A2380), bottom: Color(hex: 0x1D1450), onColor: .white, scene: .sceneArcade, icon: .iconArcade,
                                night: true, chip: Color(hex: 0x3E6FE8))
        case .cups: GameStyle(top: Color(hex: 0xF4626A), bottom: Color(hex: 0xD6404B), onColor: .white, scene: .sceneCups, icon: .iconCups,
                              chip: Color(hex: 0x3E6FE8))
        case .numbers: GameStyle(top: Color(hex: 0xFF9447), bottom: Color(hex: 0xE8691C), onColor: .white, scene: .sceneNumbers, icon: .iconNumbers,
                                 chip: Color(hex: 0x2C8BD6))
        case .animals: GameStyle(top: Color(hex: 0x7DBD45), bottom: Color(hex: 0x4F9128), onColor: .white, scene: .sceneAnimals, icon: .iconAnimals)
        case .balloons: GameStyle(top: Color(hex: 0x45B4F5), bottom: Color(hex: 0x1D8AD8), onColor: .white, scene: .sceneBalloons, icon: .iconBalloons)
        case .sticks: GameStyle(top: Color(hex: 0x9B6BFA), bottom: Color(hex: 0x7342E0), onColor: .white, scene: .sceneSticks, icon: .iconSticks)
        case .cards: GameStyle(top: Color(hex: 0xF0619D), bottom: Color(hex: 0xCC3A7A), onColor: .white, scene: .sceneCards, icon: .iconCards,
                               chip: Color(hex: 0x7A55D6))
        case .words: GameStyle(top: Color(hex: 0xFFD25C), bottom: Color(hex: 0xF2B21B), onColor: Color(hex: 0x3B2A05), scene: .sceneWords, icon: .iconWords)
        case .plots: GameStyle(top: Color(hex: 0xB98455), bottom: Color(hex: 0x92603A), onColor: .white, scene: .scenePlots, icon: .iconPlots)
        case .seesaw: GameStyle(top: Color(hex: 0xB06AB3), bottom: Color(hex: 0x8A4590), onColor: .white, scene: .sceneSeesaw, icon: .iconSeesaw)
        case .sudoku: GameStyle(top: Color(hex: 0x6F8BAB), bottom: Color(hex: 0x4A6585), onColor: .white, scene: .sceneSudoku, icon: .iconSudoku)
        case .blossoms: GameStyle(top: Color(hex: 0xFF9580), bottom: Color(hex: 0xEC6A55), onColor: .white, scene: .sceneBlossoms, icon: .iconBlossoms,
                                  chip: Color(hex: 0x3E9A5A))
        case .hands: GameStyle(top: Color(hex: 0xFFAE48), bottom: Color(hex: 0xEE8A1E), onColor: .white, scene: .sceneCups, icon: .iconHands)
        case nil: GameStyle(top: Theme.accent.opacity(0.85), bottom: Theme.accent, onColor: Theme.onAccent, scene: .sceneDance, icon: nil)
        }
    }

    /// The colour as one fill, for a tile or a chip.
    var color: Color { bottom }
    var gradient: LinearGradient { LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom) }
    /// The level chip's fill.
    var levelChip: Color { chip ?? bottom }
}

/// The games' own surfaces (D79 amended, the games look v2): the theme's raised card with a soft blue hairline, a
/// cool inset for the halves of the score bar, and a lip under raised tiles, so a board reads as one set of toys over
/// its scene, by day and at night. Built on the theme's surfaces and ink, so a theme still dresses them.
enum GamePaint {
    static var card: Color { Theme.surfaceRaised }
    /// The hairline around a card, a bubble or a tile: pale blue by day, a moonlit navy at night.
    static let edge = Color(light: 0xD5E1F0, dark: 0x34476E)
    /// Under a raised tile or button, its thickness.
    static let lip = Color(light: 0xC6D5EA, dark: 0x0B1322)
    /// Inside a card: the score bar's halves, a track.
    static let inset = Color(light: 0xEEF3FA, dark: 0x111A2B)

    /// A card over a scene: the surface, its hairline and a soft shadow.
    struct Card: ViewModifier {
        var corner: CGFloat
        var opacity: Double = 0.96

        func body(content: Content) -> some View {
            content
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(GamePaint.card.opacity(opacity))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3))
                .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(GamePaint.edge, lineWidth: 1))
        }
    }
}

extension View {
    /// A game's card over its scene (`GamePaint.Card`).
    func gameCard(corner: CGFloat = 18, opacity: Double = 0.96) -> some View { modifier(GamePaint.Card(corner: corner, opacity: opacity)) }
}

/// The scene behind a game: its illustration filling the panel, by day in light mode and the same place at night in
/// dark mode (its own painting, not the day dimmed), the top softened into the header. Never anything a game sent.
struct GameSceneBackground: View {
    var style: GameStyle
    @Environment(\.colorScheme) private var scheme

    private var picture: NSImage? {
        if scheme == .dark, !style.night, let night = style.scene?.atNight?.image { return night }
        return style.scene?.image
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.surface
                if let picture {
                    Image(nsImage: picture).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                        .clipped()
                }
                // A night painting is already calm; a day one without a night version is dimmed into the evening.
                if scheme == .dark, !style.night {
                    Color.black.opacity(style.scene?.atNight?.image != nil ? 0.16 : 0.55)
                }
                // The header's card sits on a soft veil of the panel's own surface, so it never fights the picture.
                LinearGradient(colors: [Theme.surface.opacity(scheme == .dark ? 0.5 : 0.65), Theme.surface.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
        }
        // Only a picture: `clipped` hides the room where it overflows (above a short board, over the header) but would
        // still take its clicks there, and the header's back, speaker and ✕ went dead over a short board.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The wooden table at the bottom of a game's scene, as a strip a prop stands on (cups, pads, sticks): the same
/// picture's last part, by day or at night, so the table in front of the companion is the room's own.
struct GameTableStrip: View {
    var style: GameStyle
    @Environment(\.colorScheme) private var scheme

    private var table: NSImage? {
        if scheme == .dark, !style.night, let night = style.scene?.atNight?.table { return night }
        return style.scene?.table
    }

    var body: some View {
        ZStack {
            if let table {
                Image(nsImage: table).resizable().interpolation(.medium)
            } else {
                LinearGradient(colors: [Color(hex: 0xD9955A), Color(hex: 0xB0703C)], startPoint: .top, endPoint: .bottom)
            }
            if scheme == .dark, !style.night { Color.black.opacity(style.scene?.atNight?.image != nil ? 0.12 : 0.42) }
            // Its back edge softened, so the companion behind it sinks into the table rather than being cut.
            LinearGradient(colors: [.black.opacity(0.12), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
