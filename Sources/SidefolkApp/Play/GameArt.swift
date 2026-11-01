import AppKit
import SidefolkCore
import SwiftUI

/// Sidefolk's own pictures for the games (Play/Art, made for the panel in one warm, glossy, toy-like style, D79
/// amended): each game look's scene, the menu's icons, Copy Me's moves, the memory cards' faces, trivia's topics and
/// the props (cup, gem, balloon, trophy, the Boop button, a card back). Drawn where a part's own data asks for that
/// thing (a cup, a pad's `art`, a card's symbol), never a file from a game (D75). A missing picture falls back to the
/// part's drawing in code. About 1.5 MB in all: scenes (by day and at night) are HEIC, the rest WebP with transparency.
enum GameArt: String, CaseIterable {
    case cup = "game-cup", gem = "game-gem", balloon = "game-balloon", trophy = "game-trophy"
    case boop = "game-boop", bulb = "game-bulb", cardBack = "game-card-back", magnifier = "game-magnifier"

    case sceneQuiz = "game-bg-quiz", sceneGrid = "game-bg-grid", sceneDance = "game-bg-dance", sceneArcade = "game-bg-arcade"
    case sceneCups = "game-bg-cups", sceneNumbers = "game-bg-numbers", sceneAnimals = "game-bg-animals"
    case sceneBalloons = "game-bg-balloons", sceneSticks = "game-bg-sticks", sceneCards = "game-bg-cards", sceneWords = "game-bg-words"
    case scenePlots = "game-bg-plots", sceneSeesaw = "game-bg-seesaw", sceneSudoku = "game-bg-sudoku", sceneBlossoms = "game-bg-blossoms"

    // The same places at night, for dark mode (the arcade is night already).
    case sceneQuizNight = "game-bg-quiz-night", sceneGridNight = "game-bg-grid-night", sceneDanceNight = "game-bg-dance-night"
    case sceneCupsNight = "game-bg-cups-night", sceneNumbersNight = "game-bg-numbers-night", sceneAnimalsNight = "game-bg-animals-night"
    case sceneBalloonsNight = "game-bg-balloons-night", sceneSticksNight = "game-bg-sticks-night", sceneCardsNight = "game-bg-cards-night"
    case sceneWordsNight = "game-bg-words-night", scenePlotsNight = "game-bg-plots-night", sceneSeesawNight = "game-bg-seesaw-night"
    case sceneSudokuNight = "game-bg-sudoku-night", sceneBlossomsNight = "game-bg-blossoms-night"

    case iconQuiz = "game-icon-quiz", iconGrid = "game-icon-grid", iconDance = "game-icon-dance", iconArcade = "game-icon-arcade"
    case iconCups = "game-icon-cups", iconNumbers = "game-icon-numbers", iconAnimals = "game-icon-animals"
    case iconBalloons = "game-icon-balloons", iconSticks = "game-icon-sticks", iconCards = "game-icon-cards", iconWords = "game-icon-words"
    case iconHands = "game-icon-hands"
    case iconPlots = "game-icon-plots", iconSeesaw = "game-icon-seesaw", iconSudoku = "game-icon-sudoku", iconBlossoms = "game-icon-blossoms"

    case padWave = "game-pad-wave", padHop = "game-pad-hop", padSpin = "game-pad-spin", padBow = "game-pad-bow"
    case padWaveBoth = "game-pad-wave-both"

    case faceMoon = "game-face-moon", faceLeaf = "game-face-leaf", faceAnchor = "game-face-anchor", faceStar = "game-face-star"
    case faceHeart = "game-face-heart", faceSun = "game-face-sun", faceCloud = "game-face-cloud", faceFlower = "game-face-flower"
    case faceFish = "game-face-fish", faceBell = "game-face-bell", faceKey = "game-face-key", faceDrop = "game-face-drop"

    case topicMix = "game-topic-mix", topicScience = "game-topic-science", topicSpace = "game-topic-space"
    case topicGeography = "game-topic-geography", topicHistory = "game-topic-history", topicNature = "game-topic-nature"
    case topicFood = "game-topic-food", topicArts = "game-topic-arts", topicTech = "game-topic-tech", topicSports = "game-topic-sports"

    private static var cache: [String: NSImage] = [:]

    var image: NSImage? {
        if let cached = Self.cache[rawValue] { return cached }
        for ext in ["png", "webp", "heic"] {
            if let url = Bundle.module.url(forResource: rawValue, withExtension: ext, subdirectory: "Art"), let image = NSImage(contentsOf: url) {
                Self.cache[rawValue] = image
                return image
            }
        }
        return nil
    }

    /// A scene's night version, if it has one.
    var atNight: GameArt? { GameArt(rawValue: rawValue + "-night") }

    /// A scene's table: its last part, where the props stand.
    var table: NSImage? {
        let key = rawValue + ".table"
        if let cached = Self.cache[key] { return cached }
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let top = Int(Double(cg.height) * 0.72)
        guard let strip = cg.cropping(to: CGRect(x: 0, y: top, width: cg.width, height: cg.height - top)) else { return nil }
        let out = NSImage(cgImage: strip, size: NSSize(width: strip.width, height: strip.height))
        Self.cache[key] = out
        return out
    }

    /// The picture of a pad's move (Copy Me): a waving hand, a hopping bunny…
    static func pad(_ art: GameBoard.Pads.Art?) -> GameArt? {
        switch art {
        case .wave: .padWave
        case .hop: .padHop
        case .spin: .padSpin
        case .bow: .padBow
        case .waveBoth: .padWaveBoth
        case nil: nil
        }
    }

    /// A card's face for the SF Symbol a board names (Memory Pairs' moon, leaf, anchor…): the object itself, in colour.
    static func face(_ symbol: String?) -> GameArt? {
        switch symbol {
        case "moon.fill", "moon": .faceMoon
        case "leaf.fill", "leaf": .faceLeaf
        case "anchor": .faceAnchor
        case "star.fill", "star": .faceStar
        case "heart.fill", "heart": .faceHeart
        case "sun.max.fill", "sun.max": .faceSun
        case "cloud.fill", "cloud": .faceCloud
        case "camera.macro": .faceFlower
        case "fish.fill", "fish": .faceFish
        case "bell.fill", "bell": .faceBell
        case "key.fill", "key": .faceKey
        case "drop.fill", "drop": .faceDrop
        default: nil
        }
    }

    /// A choice card's picture for its SF Symbol (trivia's topics, Higher or Lower's two ways).
    static func topic(_ symbol: String?) -> GameArt? {
        switch symbol {
        case "shuffle": .topicMix
        case "atom": .topicScience
        case "moon.stars.fill": .topicSpace
        case "globe.europe.africa.fill", "globe": .topicGeography
        case "building.columns.fill": .topicHistory
        case "leaf.fill": .topicNature
        case "fork.knife": .topicFood
        case "paintpalette.fill": .topicArts
        case "cpu": .topicTech
        case "figure.run", "sportscourt.fill": .topicSports
        case "sun.max.fill": .faceSun
        case "questionmark.square.fill", "questionmark": .iconQuiz
        case "brain.head.profile", "lightbulb", "lightbulb.fill": .bulb
        default: nil
        }
    }

    /// A white picture (the balloon) in `color`, its light and shade kept.
    @ViewBuilder func tinted(_ color: Color, height: CGFloat) -> some View {
        if let image {
            let picture = Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            picture.overlay(color.blendMode(.multiply).mask(picture)).frame(height: height).accessibilityHidden(true)
        }
    }

    /// The picture at `height` points, or nothing.
    @ViewBuilder func view(height: CGFloat) -> some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(height: height)
                .accessibilityHidden(true)
        }
    }

    /// The picture fitted in a square `side` across, or nothing.
    @ViewBuilder func view(fitting side: CGFloat) -> some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }
}
