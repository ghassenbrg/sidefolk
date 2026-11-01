import SidefolkCore
import SwiftUI

/// The Game Center (D93): a game extension's page in Home, drawn by Sidefolk in the Play panel's own art and colours.
/// A hero with the companion and the one big action (continue the game put away, today's daily, or a surprise), the
/// day's boards, every game as a card in its group, the person's numbers, last games and badges, and the games'
/// settings in one place. Data-driven: a new game in the manifest is a new card in its group, nothing else.
struct GameCenterView: View {
    var model: GameCenterModel

    var body: some View {
        let center = model.center
        PageScroll(maxWidth: 1180) {
            if let updates = model.page.updates, let entry = updates.addonUpdate(for: model.page.info.extensionId) {
                AddonUpdateStrip(entry: entry, updates: updates)
            }
            GameCenterHero(model: model, center: center)
            GameStatsStrip(totals: center.totals, hasPuzzles: !center.group(.puzzles).isEmpty)
            if !center.dailies.isEmpty { today(center) }
            ForEach(GameCenter.Group.allCases, id: \.self) { group in
                let entries = center.group(group)
                if !entries.isEmpty { games(group, entries) }
            }
            GameRecordsSection(model: model, center: center)
            GameSettingsSection(model: model)
            if let page = model.page.page, !page.sections.isEmpty {
                // Anything else the extension says, in the usual parts (D62), under the center.
                ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in SectionView(section: section, model: model.page) }
            }
            if let problem = model.page.problem {
                Label { Text(ext: problem) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
            }
        }
        .task(id: model.page.info.id) { await model.run() }
    }

    private func today(_ center: GameCenter) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            GameBand(title: Text("Today", comment: "Game Center: today's boards and words"), symbol: "sun.max.fill", tint: Theme.sun,
                     line: Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide))))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                ForEach(center.dailies) { entry in DailyCard(entry: entry) { model.play(entry.info) } }
            }
        }
    }

    private func games(_ group: GameCenter.Group, _ entries: [GameCenter.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            switch group {
            case .versus:
                GameBand(title: Text("Play against \(model.companionName)", comment: "Game Center: the games played against the companion"),
                         symbol: "person.2.fill", tint: GameStyle.of(.dance).bottom,
                         line: Text("Face off in these games", comment: "Game Center: under the games against the companion"))
            case .puzzles:
                GameBand(title: Text("Puzzles", comment: "Game Center: the games played alone"), symbol: "puzzlepiece.fill",
                         tint: GameStyle.of(.sudoku).bottom, line: Text("Relax and challenge your brain", comment: "Game Center: under the puzzles"))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                ForEach(entries) { entry in
                    GameCenterCard(entry: entry, kept: model.kept == entry.info, companionName: model.companionName, level: model.level(of: entry.info),
                                   play: { model.play(entry.info, level: $0) })
                }
            }
        }
    }
}

/// The center's top: the playroom scene with the companion inviting the person, the page's title (the toolbar shows
/// it only once this has scrolled away), and the one big action.
struct GameCenterHero: View {
    var model: GameCenterModel
    var center: GameCenter
    @Environment(\.colorScheme) private var scheme

    private var style: GameStyle { .of(.dance) }

    /// Continue the game put away; else the first daily not done today; else a surprise.
    private var action: (title: Text, symbol: String, run: () -> Void) {
        if let kept = model.kept {
            return (Text("Continue \(kept.title)", comment: "Game Center: resume the game put away"), "play.fill", { model.play(kept) })
        }
        if let daily = center.dailies.first(where: { $0.record.today?.done != true }) {
            return (Text("Play today's \(daily.info.title)", comment: "Game Center: open a daily game"), "sun.max.fill", { model.play(daily.info) })
        }
        return (Text("Surprise me", comment: "Game Center: the companion picks a game"), "dice.fill", { model.surprise() })
    }

    var body: some View {
        let action = action
        ZStack(alignment: .bottomTrailing) {
            // The playroom at the trailing end at its own size (stretched across the page it blurs), fading into the
            // card under the words.
            Theme.surfaceRaised
            LinearGradient(colors: [style.top.opacity(0.10), style.bottom.opacity(scheme == .dark ? 0.22 : 0.16)], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let scene = style.scene?.image {
                    Image(nsImage: scene).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .frame(width: 420, height: 230, alignment: .bottom).clipped()
                        .overlay { if scheme == .dark { Color.black.opacity(0.45) } }
                        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing)
                            .environment(\.layoutDirection, .leftToRight).flipsForRightToLeftLayoutDirection(true))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            HStack(alignment: .bottom, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.m) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(style.gradient)
                            Image(systemName: "gamecontroller.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(style.onColor)
                        }
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ext: model.page.info.title)
                                .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                                .accessibilityAddTraits(.isHeader)
                                .homePageTitle()
                            Text("Games against \(model.companionName), and puzzles of your own", comment: "Game Center: under its title")
                                .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                        }
                    }
                    HStack(spacing: Theme.Space.s) {
                        Button(action: action.run) { Label { action.title } icon: { Image(systemName: action.symbol) } }
                            .buttonStyle(.sf(.primary, size: .large))
                        Button { model.showMenu() } label: {
                            Label { Text("All games", comment: "Game Center: open the Play panel's menu") } icon: { Image(systemName: "square.grid.2x2.fill") }
                        }
                        .buttonStyle(.sf(.secondary, size: .large))
                    }
                }
                .padding(Theme.Space.xl)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    SpeechBubble(text: bubble, chip: nil, clock: nil, tail: .bottom).frame(maxWidth: 220)
                    CompanionFigure(picture: model.figure, size: CGSize(width: 130, height: 120))
                }
                .padding(.trailing, Theme.Space.xl)
                .padding(.top, Theme.Space.m)
            }
        }
        .frame(minHeight: 230)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .elevation(.e1, radius: Theme.Radius.panel)
    }

    /// The companion's invitation: about the game put away, the day's boards, or a challenge.
    private var bubble: String {
        if model.kept != nil { return String(localized: "Ready when you are!", comment: "Game Center: the companion, a game put away") }
        if center.dailies.contains(where: { $0.record.today?.done != true }) {
            return String(localized: "Today's boards are waiting!", comment: "Game Center: the companion, dailies not done")
        }
        return String(localized: "Pick a game! Can you beat me?", comment: "The companion on the Play panel's menu")
    }
}

/// A group's band: its symbol on a tinted tile, its title and one line, as the Play menu's sections.
struct GameBand: View {
    var title: Text
    var symbol: String
    var tint: Color
    var line: Text

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint))
                .accessibilityHidden(true)
            title.font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.s)
            line.font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(tint.opacity(0.12)))
    }
}
