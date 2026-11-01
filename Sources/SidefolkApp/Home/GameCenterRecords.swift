import SidefolkCore
import SwiftUI

/// The person's last games and badges, side by side in a wide window (D93). Verdicts in GameVerdict's colours with
/// their symbol (D78): a win or a solve green, a loss the calm sand tone, a draw neutral ink.
struct GameRecordsSection: View {
    var model: GameCenterModel
    var center: GameCenter

    var body: some View {
        SectionColumns(minWidth: 380, maxColumns: 2, spacing: Theme.Space.xl) {
            recent
            badges
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: Text("Last games", comment: "Game Center: the games played lately")) { EmptyView() }
            RowsCard {
                if center.recent.isEmpty {
                    InlineEmpty(label: Text("Games you finish show here.", comment: "Game Center: no game played yet"), systemImage: "clock")
                } else {
                    ForEach(Array(center.recent.enumerated()), id: \.offset) { _, game in row(game) }
                }
            }
        }
    }

    private func row(_ game: GameCenterRecords.Recent) -> some View {
        let entry = center.entry(for: game)
        let verdict = game.outcome.verdict
        return HStack(spacing: Theme.Space.m) {
            if let entry { GameArtTile(look: entry.info.look, symbol: entry.info.symbol, corner: 6).frame(width: 28, height: 28) }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry?.info.title ?? game.game).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                Text(ext: [outcome(game), game.text].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Text(game.at.formatted(.relative(presentation: .named))).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            Image(systemName: verdict.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(GameColors.color(verdict))
                .frame(width: 18).accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Space.m).frame(minHeight: Theme.Size.row)
        .accessibilityElement(children: .combine)
    }

    private func outcome(_ game: GameCenterRecords.Recent) -> String {
        switch game.outcome {
        case .won: String(localized: "You won")
        case .lost: String(localized: "\(model.companionName) won", comment: "Game Center: the companion won a game")
        case .draw: String(localized: "A draw")
        case .solved: String(localized: "Solved", comment: "Game Center: puzzles solved")
        }
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            let all = center.badges
            SectionHeader(title: Text("Badges", comment: "Game Center: badges earned from the person's records"),
                          detail: Text("\(all.filter(\.earned).count) of \(all.count) earned", comment: "Game Center: badges earned of all")) { EmptyView() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                // Earned first; the rest show how far there is to go.
                ForEach(all.filter(\.earned) + all.filter { !$0.earned }) { BadgeTile(badge: $0) }
            }
        }
    }
}

/// A badge: its medal, its name and what earns it, faded with a count until earned.
struct BadgeTile: View {
    var badge: GameBadge

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle().fill(badge.earned ? AnyShapeStyle(LinearGradient(colors: [Theme.sun.opacity(0.95), Theme.sun.opacity(0.65)],
                                                                          startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.well))
                Image(systemName: GameBadgeWords.symbol(badge.kind)).font(.system(size: 20, weight: .bold))
                    .foregroundStyle(badge.earned ? Color.white : Theme.inkFaint)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
            Text(verbatim: GameBadgeWords.title(badge.kind)).font(Theme.Font.callout.weight(.semibold)).foregroundStyle(badge.earned ? Theme.ink : Theme.inkMuted)
                .multilineTextAlignment(.center).lineLimit(2)
            if badge.earned {
                Text(verbatim: GameBadgeWords.detail(badge.kind)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                ProgressView(value: Double(badge.value), total: Double(max(badge.goal, 1))).tint(Theme.accent).frame(width: 70)
                Text("\(badge.value) of \(badge.goal)", comment: "Game Center: a badge's progress").font(Theme.Font.caption).monospacedDigit()
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surfaceRaised))
        .opacity(badge.earned ? 1 : 0.85)
        .accessibilityElement(children: .combine)
        .accessibilityValue(badge.earned ? Text("Earned", comment: "Game Center: a badge earned")
            : Text("\(badge.value) of \(badge.goal)", comment: "Game Center: a badge's progress"))
    }
}

/// Each badge's name, what earns it and its symbol, in the person's language.
enum GameBadgeWords {
    static func title(_ kind: GameBadge.Kind) -> String {
        switch kind {
        case .firstWin: String(localized: "First win", comment: "A Game Center badge")
        case .tenWins: String(localized: "Ten wins", comment: "A Game Center badge")
        case .fiftyWins: String(localized: "Fifty wins", comment: "A Game Center badge")
        case .hatTrick: String(localized: "Hat trick", comment: "A Game Center badge: three wins in a row")
        case .fiveInARow: String(localized: "Unstoppable", comment: "A Game Center badge: five wins in a row")
        case .explorer: String(localized: "Explorer", comment: "A Game Center badge: every game played once")
        case .puzzler: String(localized: "Puzzler", comment: "A Game Center badge: ten puzzles solved")
        case .dailyWeek: String(localized: "A week of dailies", comment: "A Game Center badge: a daily seven days in a row")
        case .fullDay: String(localized: "Full house", comment: "A Game Center badge: every daily done today")
        }
    }

    static func detail(_ kind: GameBadge.Kind) -> String {
        switch kind {
        case .firstWin: String(localized: "Beat your companion once", comment: "What earns a Game Center badge")
        case .tenWins: String(localized: "Win ten games", comment: "What earns a Game Center badge")
        case .fiftyWins: String(localized: "Win fifty games", comment: "What earns a Game Center badge")
        case .hatTrick: String(localized: "Three wins in a row", comment: "What earns a Game Center badge")
        case .fiveInARow: String(localized: "Five wins in a row", comment: "What earns a Game Center badge")
        case .explorer: String(localized: "Play every game once", comment: "What earns a Game Center badge")
        case .puzzler: String(localized: "Solve ten puzzles", comment: "What earns a Game Center badge")
        case .dailyWeek: String(localized: "A daily seven days running", comment: "What earns a Game Center badge")
        case .fullDay: String(localized: "Every daily done today", comment: "What earns a Game Center badge")
        }
    }

    static func symbol(_ kind: GameBadge.Kind) -> String {
        switch kind {
        case .firstWin: "star.fill"
        case .tenWins: "trophy.fill"
        case .fiftyWins: "crown.fill"
        case .hatTrick: "flame.fill"
        case .fiveInARow: "bolt.fill"
        case .explorer: "map.fill"
        case .puzzler: "puzzlepiece.fill"
        case .dailyWeek: "calendar"
        case .fullDay: "sun.max.fill"
        }
    }
}
