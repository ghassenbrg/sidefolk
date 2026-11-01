import SidefolkCore
import SwiftUI

/// The games' settings in one place (D93): how the companion takes a win, sounds, Sneaky, and the level each game
/// opens at. The same settings as Settings › Companion › Games and `games.settings`; saved at once.
struct GameSettingsSection: View {
    var model: GameCenterModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: Text("Game settings", comment: "Game Center: the games' settings")) { EmptyView() }
            RowsCard {
                row(Text("When it wins"), detail: Text("How \(model.companionName) takes a win", comment: "Game Center: the tone setting's line")) {
                    SegmentedPicker("When it wins", selection: Binding(get: { model.settings.tone }, set: { tone in model.change { $0.tone = tone } }),
                                    segments: GameTone.allCases.map { .init($0, Text(verbatim: $0.name)) })
                        .frame(maxWidth: 320)
                }
                row(Text("Game sounds"), detail: Text("Soft sounds in every game; a game's speaker button changes its own",
                                                      comment: "Game Center: the sounds setting's line")) {
                    Toggle("Game sounds", isOn: Binding(get: { model.settings.sounds },
                                                        set: { on in model.change { $0.sounds = on; $0.speakers = [:] } }))
                        .toggleStyle(.switch).labelsHidden()
                }
                row(Text("Sneaky", comment: "A game setting: the companion may cheat for fun"),
                    detail: Text("\(model.companionName) may cheat for fun where a game allows it, and owns up when caught",
                                 comment: "Game Center: the Sneaky setting's line")) {
                    Toggle(isOn: Binding(get: { model.settings.sneaky }, set: { on in model.change { $0.sneaky = on } })) {
                        Text("Sneaky", comment: "A game setting: the companion may cheat for fun")
                    }
                    .toggleStyle(.switch).labelsHidden()
                }
            }
            let leveled = model.games.filter { $0.levels.count > 1 }
            if !leveled.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Levels", comment: "Game Center: the level each game opens at").font(Theme.Font.headline).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                        ForEach(leveled) { game in level(game) }
                    }
                }
            }
        }
    }

    private func row(_ title: Text, detail: Text, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                title.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.m)
            control()
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s).frame(minHeight: Theme.Size.row)
    }

    /// A game's level: the game's own pick ("Default", a puzzle's last one) or one the person chose.
    private func level(_ game: GameInfo) -> some View {
        HStack(spacing: Theme.Space.m) {
            GameCenterTile(info: game, side: 30)
            Text(verbatim: game.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            Picker(selection: Binding(get: { model.level(of: game) ?? "" },
                                      set: { level in let id = game.id; model.change { $0.levels[id] = level.isEmpty ? nil : level } })) {
                Text("Default", comment: "Game Center: a game picks its own level").tag("")
                ForEach(game.levels, id: \.self) { Text(verbatim: GameLevels.name($0)).tag($0) }
            } label: {
                Text(verbatim: game.title)
            }
            .labelsHidden().fixedSize()
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.xs)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surfaceRaised))
    }
}
