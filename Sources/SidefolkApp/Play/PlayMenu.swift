import AppKit
import SidefolkCore
import SwiftUI

/// The Play panel's home when no game is open (D79 amended): every game as a card in its own colour and art, with
/// its tagline, the person's stats against the companion (counted from Sidefolk's own Activity rows, `GameStats`), and
/// the companion in the scene inviting them. A game put away shows "Resume". Arrow keys move, Return opens.
@MainActor @Observable
final class PlayMenuModel {
    var games: [GameInfo]
    var stats: GameStats
    let companionName: String
    let portrait: NSImage?
    /// The companion standing in the menu's scene.
    let figure: NSImage?
    /// The game kept from before, which opens where it was.
    var kept: GameInfo?
    var selected = 0
    var onOpen: ((GameInfo) -> Void)?
    var onClose: (() -> Void)?

    init(games: [GameInfo], stats: GameStats, companionName: String, portrait: NSImage?, figure: NSImage?, kept: GameInfo?) {
        // In the order the menu shows them, so the arrow keys follow the cards: the games against the companion, then
        // puzzles, each in the looks' order (games without a look last).
        func rank(_ g: GameInfo) -> Int { g.look.flatMap { GameLook.allCases.firstIndex(of: $0) } ?? GameLook.allCases.count }
        let ordered = games.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
        self.games = ordered.filter { !($0.look?.solo ?? false) } + ordered.filter { $0.look?.solo ?? false }
        self.stats = stats
        self.companionName = companionName
        self.portrait = portrait
        self.figure = figure
        self.kept = kept
        if let kept, let i = self.games.firstIndex(of: kept) { selected = i }
    }

    /// The panel's title: the extension that brings the games (Playtime, in the person's language), else "Games".
    var title: String {
        games.first { !$0.isSidefolk }?.extensionName ?? String(localized: "Games", comment: "The Play panel's menu when no extension brings games")
    }

    /// Arrows move through the two columns, Return or Space opens. True when the menu used the key.
    func press(_ key: String) -> Bool {
        guard !games.isEmpty else { return false }
        let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft
        switch key {
        case "left": selected = (selected + (rtl ? 1 : -1)).clamped(games.count)
        case "right": selected = (selected + (rtl ? -1 : 1)).clamped(games.count)
        case "up": selected = max(0, selected - 2)
        case "down": selected = min(games.count - 1, selected + 2)
        case "return", "space": onOpen?(games[selected])
        default: return false
        }
        return true
    }
}

private extension Int {
    func clamped(_ count: Int) -> Int { Swift.min(Swift.max(self, 0), count - 1) }
}

struct PlayMenuView: View {
    var menu: PlayMenuModel

    private var style: GameStyle { .of(.dance) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                GameSceneBackground(style: style)
                VStack(spacing: 12) {
                    HStack(alignment: .bottom, spacing: 4) {
                        CompanionFigure(picture: menu.figure ?? menu.portrait, size: CGSize(width: 58, height: 60))
                        SpeechBubble(text: String(localized: "Pick a game! Can you beat me?", comment: "The companion on the Play panel's menu"),
                                     clock: nil, tail: .leading)
                    }
                    stats
                    cards
                    HintRow(text: String(localized: "Arrows to choose · Return to play · Esc to close", comment: "Keys on the Play panel's menu"))
                }
                .padding(PlayView.pad)
            }
        }
        .frame(width: PlayView.width)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: menu.title))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                Image(systemName: "gamecontroller.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(style.bottom)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: menu.title).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                Text(String(localized: "Quick games against \(menu.companionName)", comment: "Under the title of the Play panel's menu"))
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            }
            Spacer(minLength: 4)
            HeaderButton(symbol: "xmark", label: String(localized: "Close", comment: "Closes the Play panel"), style: style) { menu.onClose?() }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(style.gradient)
    }

    /// Wins, the current run of wins, and games played.
    private var stats: some View {
        HStack(spacing: 8) {
            stat(Toss.number(menu.stats.wins), String(localized: "Wins", comment: "Play panel's menu: games the person won"), "trophy.fill", Theme.sun)
            stat(Toss.number(menu.stats.streak), String(localized: "Streak", comment: "Play panel's menu: wins in a row now"), "flame.fill",
                 GameColors.color(.win))
            stat(Toss.number(menu.stats.played), String(localized: "Played", comment: "Play panel's menu: games played to the end"),
                 "gamecontroller.fill", Theme.accent)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface.opacity(0.95)).shadow(color: .black.opacity(0.1), radius: 6, y: 3))
    }

    private func stat(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: value).font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Theme.ink)
                Text(verbatim: label).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surfaceSunken.opacity(0.7)))
        .accessibilityElement(children: .combine)
    }

    /// The games against the companion, then the puzzles played alone (`GameLook.solo`), each a grid of cards.
    private var groups: [(title: String, games: [(Int, GameInfo)])] {
        let all = Array(menu.games.enumerated())
        let versus = all.filter { !($0.element.look?.solo ?? false) }, solo = all.filter { $0.element.look?.solo ?? false }
        var out: [(String, [(Int, GameInfo)])] = []
        if !versus.isEmpty {
            out.append((String(localized: "Play against \(menu.companionName)", comment: "Play panel's menu: the games played against the companion"), versus))
        }
        if !solo.isEmpty { out.append((String(localized: "Puzzles", comment: "Play panel's menu: the games played alone"), solo)) }
        return out
    }

    private var cards: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.title) { group in
                    Text(verbatim: group.title).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.surface.opacity(0.92)))
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(group.games, id: \.1.id) { i, game in
                            GameCard(info: game, selected: menu.selected == i, resume: menu.kept == game) { menu.onOpen?(game) }
                        }
                    }
                }
            }
            .padding(.vertical, 2).padding(.bottom, 4)
        }
        .frame(maxHeight: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A game on the menu: its picture on a tile in its colour, its title and tagline, "Resume" when it was put away.
struct GameCard: View {
    var info: GameInfo
    var selected: Bool
    var resume: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        let style = GameStyle.of(info.look)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    style.gradient
                    LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)
                    if let icon = style.icon, icon.image != nil {
                        icon.view(fitting: 56).shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                            .scaleEffect(hovered ? 1.08 : 1).rotationEffect(.degrees(hovered ? -4 : 0))
                    } else {
                        Image(systemName: info.symbol ?? "gamecontroller.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(style.onColor)
                    }
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if resume {
                        Label(String(localized: "Resume", comment: "Play panel's menu: a game put away, opened where it was"), systemImage: "play.fill")
                            .font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.navy)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(.white)).padding(6)
                    }
                }
                Text(verbatim: info.title).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let tagline = info.tagline {
                    Text(verbatim: tagline).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkMuted)
                        .lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface)
                .shadow(color: style.bottom.opacity(0.35), radius: 0, y: 3)
                .shadow(color: .black.opacity(hovered ? 0.16 : 0.08), radius: hovered ? 8 : 4, y: 3))
            .overlay {
                // The keyboard's choice: the app's accent, as any selection.
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(GamePressStyle())
        .onHover { hovered = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.4), value: hovered)
        .accessibilityLabel(Text(verbatim: [info.title, info.tagline].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
