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

    /// The menu's room: the playroom with its table (Copy Me's), by day or at night.
    private var style: GameStyle { .of(.dance) }

    var body: some View {
        VStack(spacing: 10) {
            header
            HStack(alignment: .bottom, spacing: 4) {
                CompanionFigure(picture: menu.figure ?? menu.portrait, size: CGSize(width: 64, height: 64))
                SpeechBubble(text: String(localized: "Pick a game! Can you beat me?", comment: "The companion on the Play panel's menu"),
                             clock: nil, tail: .leading)
            }
            .padding(.horizontal, PlayView.pad)
            stats.padding(.horizontal, PlayView.pad)
            cards
            HintRow(text: String(localized: "Arrows to choose · Return to play · Esc to close", comment: "Keys on the Play panel's menu"))
                .padding(.horizontal, PlayView.pad)
        }
        .padding(.top, 7).padding(.bottom, 10)
        .frame(width: PlayView.width)
        .background(GameSceneBackground(style: style))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: menu.title))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(style.bottom).brightness(-0.12).offset(y: 2.5)
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(style.gradient)
                Image(systemName: "gamecontroller.fill").font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: menu.title).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                Text(String(localized: "Quick games against \(menu.companionName)", comment: "Under the title of the Play panel's menu"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            HeaderButton(symbol: "xmark", label: String(localized: "Close", comment: "Closes the Play panel")) { menu.onClose?() }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .gameCard(corner: 20, opacity: 0.97)
        .padding(.horizontal, 7)
    }

    /// Wins, the current run of wins, and games played, on one card.
    private var stats: some View {
        HStack(spacing: 0) {
            stat(Toss.number(menu.stats.wins), String(localized: "Wins", comment: "Play panel's menu: games the person won"), "trophy.fill", Theme.sun)
            Rectangle().fill(GamePaint.edge).frame(width: 1, height: 30)
            stat(Toss.number(menu.stats.streak), String(localized: "Streak", comment: "Play panel's menu: wins in a row now"), "flame.fill",
                 GameColors.color(.win))
            Rectangle().fill(GamePaint.edge).frame(width: 1, height: 30)
            stat(Toss.number(menu.stats.played), String(localized: "Played", comment: "Play panel's menu: games played to the end"),
                 "gamecontroller.fill", Theme.accent)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .gameCard(corner: 18)
    }

    private func stat(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
                .frame(width: 32, height: 32).background(Circle().fill(color.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: value).font(.system(size: 20, weight: .black, design: .rounded)).monospacedDigit().foregroundStyle(Theme.ink)
                Text(verbatim: label).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The games against the companion, then the puzzles played alone (`GameLook.solo`), each a grid of cards.
    private var groups: [(title: String, solo: Bool, games: [(Int, GameInfo)])] {
        let all = Array(menu.games.enumerated())
        let versus = all.filter { !($0.element.look?.solo ?? false) }, solo = all.filter { $0.element.look?.solo ?? false }
        var out: [(String, Bool, [(Int, GameInfo)])] = []
        if !versus.isEmpty {
            out.append((String(localized: "Play against \(menu.companionName)", comment: "Play panel's menu: the games played against the companion"), false, versus))
        }
        if !solo.isEmpty { out.append((String(localized: "Puzzles", comment: "Play panel's menu: the games played alone"), true, solo)) }
        return out
    }

    private var cards: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.title) { group in
                    GameSectionHeader(title: group.title, solo: group.solo, portrait: menu.portrait)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(group.games, id: \.1.id) { i, game in
                            GameCard(info: game, selected: menu.selected == i, resume: menu.kept == game) { menu.onOpen?(game) }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, PlayView.pad).padding(.vertical, 2).padding(.bottom, 4)
        }
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
