import SidefolkCore
import SwiftUI

/// Settings › Attention › What may interrupt you (D88): one row per source, each with how far it may go. A notice gets
/// the lower of its own level and its row's, then Focus or Quiet; questions and approvals are never turned down.
struct InterruptionsGroup: View {
    var model: SettingsModel

    var body: some View {
        let levels = model.settings.interruptions
        SettingsGroup(title: Text(verbatim: SettingKey.interruptions.section),
                      footer: Text("Card: may step forward and wait for you. Whisper: comes gently; if it needs an answer it waits in the stack. Only in Today: never on the desktop, in Today until you look. Off: in History only.",
                                   comment: "Settings › Attention: under What may interrupt you, what each choice means"),
                      anchor: .interruptions) {
            row(.reminders)
            row(.watches)
            ForEach(watchOverrides(levels), id: \.id) { watch in
                WatchOverrideRow(model: model, id: watch.id, title: watch.title)
            }
            row(.commands)
            ForEach(model.noticeAgents, id: \.self) { row(.agent($0)) }
            ForEach(model.extensions.filter { !$0.watcherNames.isEmpty }) { ext in
                row(.extension(ext.id), look: ext.look)
            }
            row(.games)
            row(.companion)
        }
    }

    private func row(_ source: InterruptSource, look: ExtensionLook? = nil) -> some View {
        InterruptionRow(model: model, source: source, look: look)
    }

    /// The watches set apart, by title, for the watches that still exist.
    private func watchOverrides(_ levels: Interruptions) -> [(id: String, title: String)] {
        levels.watchOverrides.keys.compactMap { id in model.watchTitles[id].map { (id, $0) } }.sorted { $0.title < $1.title }
    }
}

/// One source: its icon, its name, what it covers, and how far it may go.
private struct InterruptionRow: View {
    var model: SettingsModel
    var source: InterruptSource
    var look: ExtensionLook?

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: source.name(companion: model.settings.companionName, extensions: [:], look: look))
                    .font(Theme.Font.body).foregroundStyle(Theme.ink)
                source.detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            InterruptLevelMenu(source: source, label: source.name(companion: model.settings.companionName, extensions: [:], look: look),
                               selection: Binding(get: { model.settings.interruptions.level(for: source) },
                                                  set: { level in model.update { $0.interruptions.set(level, for: source) } }))
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m - 1)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var icon: some View {
        if let look {
            ExtensionBadge(look: look, size: 28)
        } else {
            IconTile(symbol: source.symbol, folk: source.folk, size: 28, logo: source.logo)
        }
    }
}

/// A watch set apart from the rest (from a card's "Fewer like this"): its level, or back to the others'.
private struct WatchOverrideRow: View {
    var model: SettingsModel
    var id: String
    var title: String

    var body: some View {
        let source = InterruptSource.watch(id)
        HStack(alignment: .center, spacing: Theme.Space.m) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                .flipsForRightToLeftLayoutDirection(true)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                Text("Set apart from your other watches", comment: "Settings › Attention: under one watch with a level of its own")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.update { $0.interruptions.set(nil, for: source) } } label: {
                Text("Like the others", comment: "Settings › Attention: one watch goes back to the level all watches have")
            }
            .buttonStyle(.sf(.quiet))
            .fixedSize()
            InterruptLevelMenu(source: source, label: title,
                               selection: Binding(get: { model.settings.interruptions.level(for: source) },
                                                  set: { level in model.update { $0.interruptions.set(level, for: source) } }))
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m - 1)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }
}

/// The choices a source offers, as a menu: four words never fit a segmented control in German.
struct InterruptLevelMenu: View {
    var source: InterruptSource
    var label: String
    @Binding var selection: InterruptLevel

    var body: some View {
        Picker(selection: $selection) {
            ForEach(source.choices, id: \.self) { level in Text(verbatim: level.word).tag(level) }
        } label: { Text(verbatim: label) }
        .labelsHidden()
        .fixedSize()
    }
}

extension InterruptLevel {
    var word: String {
        switch self {
        case .card: String(localized: "Card", comment: "Settings › Attention: a source may step forward with a card")
        case .whisper: String(localized: "Whisper", comment: "Settings › Attention: a source comes as a gentle whisper")
        case .today: String(localized: "Only in Today", comment: "Settings › Attention: a source never shows on the desktop, only in Home › Today")
        case .off: String(localized: "interrupt.off", defaultValue: "Off", comment: "Settings › Attention: a source's notices are kept in History only")
        }
    }
}

extension InterruptSource {
    /// What the table and the Sidecard call it. `look` names an extension; without it, its id.
    func name(companion: String, extensions: [String: String] = [:], look: ExtensionLook? = nil) -> String {
        switch self {
        case .reminders: String(localized: "Reminders")
        case .watches: String(localized: "Watches")
        case .watch: String(localized: "This watch", comment: "The Sidecard: one watch set apart, “This watch: whispers from now on”")
        case .commands: String(localized: "Commands", comment: "Settings › Attention: commands started with `sidefolk run`")
        case .agent(let name): AgentFacingTools.displayName(name)
        case .extension(let id): look?.name ?? extensions[id] ?? id
        case .games: String(localized: "Games")
        case .companion: companion
        }
    }

    /// One line of what the row covers; an agent's says what can't be turned down.
    var detail: Text {
        switch self {
        case .reminders: Text("At the time you chose. They may come quieter, never not at all.", comment: "Settings › Attention › Reminders")
        case .watches: Text("Pages, sites, files and programs you watch.", comment: "Settings › Attention › Watches")
        case .watch: Text("Set apart from your other watches", comment: "Settings › Attention: under one watch with a level of its own")
        case .commands: Text("When `sidefolk run` finishes or fails.", comment: "Settings › Attention › Commands; keep `sidefolk run` as it is")
        case .agent: Text("Its notices and what it saves. Its questions and approvals always come as a card.",
                          comment: "Settings › Attention: under an agent such as Claude Code")
        case .extension: Text("What its watches notice.", comment: "Settings › Attention: under an extension")
        case .games: Text("The companion's lines while you play.", comment: "Settings › Attention › Games")
        case .companion: Text("Its AI's notices, routines and its own remarks. Its questions always come.",
                              comment: "Settings › Attention: under the companion's name")
        }
    }

    var symbol: String {
        switch self {
        case .reminders: "alarm"
        case .watches, .watch: "binoculars"
        case .commands: "terminal"
        case .agent: "sparkles"
        case .extension: "puzzlepiece.extension"
        case .games: "gamecontroller"
        case .companion: "face.smiling"
        }
    }

    var folk: String {
        switch self {
        case .reminders: "tempo"
        case .watches, .watch: "scout"
        case .commands, .agent, .extension: "byte"
        case .games: "play"
        case .companion: "sidefolk"
        }
    }

    var logo: ProviderLogo? {
        guard case .agent(let name) = self else { return nil }
        return switch name {
        case "claude-code": .claude
        case "codex": .codex
        default: nil
        }
    }
}
