import SidefolkCore
import SwiftUI

/// A game's picture on a tile in its colour: the Play menu's art for its look (`GameStyle`, `GameArt`), its symbol
/// when the look has no icon. Never a picture from the game (D75).
struct GameArtTile: View {
    var info: GameInfo
    var side: CGFloat

    var body: some View {
        let style = GameStyle.of(info.look)
        ZStack {
            style.gradient
            LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)
            if let icon = style.icon, icon.image != nil {
                icon.view(fitting: side * 0.82).shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            } else {
                Image(systemName: info.symbol ?? "gamecontroller.fill").font(.system(size: side * 0.4, weight: .bold)).foregroundStyle(style.onColor)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Wins, puzzles solved, the best run of wins and games played, as the Play menu's strip.
struct GameStatsStrip: View {
    var totals: GameCenter.Totals
    var hasPuzzles: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            stat(totals.wins, Text("Wins", comment: "Game Center: games won against the companion"), "trophy.fill", Theme.sun)
            if hasPuzzles { stat(totals.solved, Text("Solved", comment: "Game Center: puzzles solved"), "checkmark.seal.fill", GameColors.color(.win)) }
            stat(totals.bestStreak, Text("Best streak", comment: "Game Center: the longest run of wins"), "flame.fill", GameStyle.of(.numbers).bottom)
            stat(totals.played, Text("Played", comment: "Game Center: games played to the end"), "gamecontroller.fill", Theme.accent)
        }
        .padding(Theme.Space.s)
        .cardSurface(radius: Theme.Radius.panel)
    }

    private func stat(_ value: Int, _ label: Text, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(value.formatted()).font(Theme.Font.number).monospacedDigit().foregroundStyle(Theme.ink)
                label.font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.well))
        .accessibilityElement(children: .combine)
    }
}

/// A game's board or word of the day: its art, what the game says of today, the days in a row, and Play (a tick once
/// today's is done, in the good-outcome green with its symbol, D78).
struct DailyCard: View {
    var entry: GameCenter.Entry
    var play: () -> Void

    var body: some View {
        let today = entry.record.today
        Button(action: play) {
            HStack(spacing: Theme.Space.m) {
                GameArtTile(info: entry.info, side: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: entry.info.title).font(Theme.Font.headline).foregroundStyle(Theme.ink).lineLimit(1)
                    if let today { Text(ext: today.text).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(2) }
                    if let streak = today?.streak, streak > 1 {
                        Label { Text("\(streak) days in a row", comment: "Game Center: a daily's streak") } icon: { Image(systemName: "flame.fill") }
                            .font(Theme.Font.caption).foregroundStyle(GameStyle.of(.numbers).bottom)
                    }
                }
                Spacer(minLength: 0)
                if today?.done == true {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(GameColors.color(.win))
                        .accessibilityLabel(Text("Done today", comment: "Game Center: today's daily is done"))
                } else {
                    Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.accent)
                        .accessibilityLabel(Text("Play", comment: "Game Center: play this game"))
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Theme.Radius.panel)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .buttonStyle(GamePressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// A game as a card: its art, title and tagline, its best and record, when it was last played, Play (with a level
/// from the menu beside it), and Resume when it was put away.
struct GameCenterCard: View {
    var entry: GameCenter.Entry
    var kept: Bool
    var companionName: String
    /// The level it opens at, when the person chose one.
    var level: String?
    var play: (String?) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Button { play(nil) } label: { GameArtTile(info: entry.info, side: 84) }
                .buttonStyle(GamePressStyle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Space.xs) {
                    Text(verbatim: entry.info.title).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                    if let level { Chip(text: Text(verbatim: GameLevels.name(level))) }
                }
                if let tagline = entry.info.tagline {
                    Text(verbatim: tagline).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                record.font(Theme.Font.caption).foregroundStyle(Theme.ink).lineLimit(2)
                if let last = entry.last {
                    Text("Played \(last.formatted(.relative(presentation: .named)))", comment: "Game Center: when a game was last played")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: Theme.Space.xs) {
                Button { play(nil) } label: {
                    if kept {
                        Label { Text("Resume", comment: "Play panel's menu: a game put away, opened where it was") } icon: { Image(systemName: "play.fill") }
                    } else {
                        Label { Text("Play", comment: "Game Center: play this game") } icon: { Image(systemName: "play.fill") }
                    }
                }
                .buttonStyle(.sf(kept ? .primary : .secondary, size: .regular))
                if entry.info.levels.count > 1 {
                    Menu {
                        ForEach(entry.info.levels, id: \.self) { l in
                            Button { play(l) } label: { Text(verbatim: GameLevels.name(l)) }
                        }
                    } label: {
                        Text("Level", comment: "Game Center: a menu to play a game at a level")
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .font(Theme.Font.caption)
                    .help(Text("Play at a level", comment: "Game Center: the level menu's tooltip"))
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).fill(Theme.surfaceRaised)
            .shadow(color: GameStyle.of(entry.info.look).bottom.opacity(0.3), radius: 0, y: 3))
        .elevation(hovered ? .e2 : .e1, radius: Theme.Radius.panel)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.micro, value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: [entry.info.title, entry.info.tagline].compactMap { $0 }.joined(separator: ", ")))
    }

    /// Its record in plain words: the game's own best, then wins of games played (a puzzle's solves), or not yet played.
    private var record: Text {
        let r = entry.record
        guard r.played > 0 else { return Text("Not played yet", comment: "Game Center: a game never played") }
        var parts: [String] = []
        if let best = r.best { parts.append(best) }
        if entry.solo {
            parts.append(String(localized: "\(r.won) solved", comment: "Game Center: puzzles solved"))
        } else {
            parts.append(String(localized: "Won \(r.won) of \(r.played)", comment: "Game Center: games won of games played"))
        }
        if r.streak > 1 { parts.append(String(localized: "\(r.streak) wins in a row", comment: "Game Center: the run of wins going now")) }
        return Text(ext: parts.joined(separator: " · "))
    }
}
