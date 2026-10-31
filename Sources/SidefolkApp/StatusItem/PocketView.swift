import SidefolkCore
import SwiftUI

/// The menu bar's Pocket (D84): a glance, then an answer. The companion and its state, Open, Focus or Quiet in one
/// click, Full access with its way out, an update, what needs you, what's next, the agents at work, and an Ask field.
/// Everything else (Settings, updates, About, Quit) is in the ⋯ menu.
@MainActor @Observable
final class PocketModel {
    var content = PocketContent()
    var palettes: [ExtensionPaletteInfo] = []
    @ObservationIgnored var actions = PocketActions()
}

struct PocketView: View {
    var model: PocketModel
    @State private var question = ""
    @FocusState private var asking: Bool

    private var content: PocketContent { model.content }
    private var actions: PocketActions { model.actions }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            header
            if content.fullAccess { fullAccess }
            if !content.companionVisible { hidden }
            dial
            if let update = content.update { updateCard(update) }
            section(Text("Needs you · \(content.needsYou.count)", comment: "The Pocket: a section, “Needs you · 3”"), rows: content.needsYou,
                    trailing: content.companionVisible ? nil : (Text("Open Today", comment: "The Pocket: opens Home › Today"), actions.openToday))
            section(Text("Next up", comment: "The Pocket: a section of reminders coming"), rows: content.nextUp)
            section(Text("Agents", comment: "The Pocket: a section of agents at work"), rows: content.agents)
            if content.needsYou.isEmpty, content.nextUp.isEmpty, content.agents.isEmpty {
                Text("Nothing waiting, nothing due soon.", comment: "The Pocket: nothing to show")
                    .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.Space.s)
            }
            askField
        }
        .padding(Theme.Space.m)
        .frame(width: 340)
        .background(Theme.surface)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            avatar(size: 36)
            VStack(alignment: .leading, spacing: 1) {
                (content.companionVisible ? Text(verbatim: content.name)
                     : Text("\(content.name) is tucked away", comment: "The Pocket: the companion is hidden"))
                    .font(Theme.Font.headline).foregroundStyle(Theme.ink).lineLimit(1)
                Text(verbatim: content.companionVisible ? content.stateLine
                     : String(localized: "Reminders arrive as notifications", comment: "The Pocket, while the companion is hidden"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            moreMenu
        }
    }

    private func avatar(size: CGFloat) -> some View {
        Group {
            if let image = content.avatar {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "face.smiling").resizable().foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.well, in: Circle())
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            ShoulderBadge(state: content.attention == .focus ? .focus : content.attention == .quiet ? .quiet
                          : content.needsYou.isEmpty ? .idle : .waiting(content.needsYou.count), count: content.held)
                .scaleEffect(0.7).offset(x: 8, y: 6)
        }
        .accessibilityHidden(true)
    }

    private var moreMenu: some View {
        Menu {
            Button("Open Sidefolk", action: actions.openHome).keyboardShortcut("o")
            Button("Settings…", action: actions.openSettings).keyboardShortcut(",")
            if !model.palettes.isEmpty {
                Divider()
                ForEach(model.palettes, id: \.id) { info in
                    Button { actions.openPalette(info.id) } label: { Text(verbatim: "\(info.title)…") }
                }
            }
            Divider()
            Button(content.companionVisible ? "Hide Companion" : "Show Companion", action: actions.toggleCompanion)
            Button(content.update.map { String(localized: "Update to Sidefolk \($0)…", comment: "Menu bar: a newer version waits") }
                   ?? String(localized: "Check for Updates…"), action: actions.checkForUpdates)
            Button("About Sidefolk", action: actions.about)
            Divider()
            Button("Quit Sidefolk", action: actions.quit).keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                .frame(width: 28, height: 28)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("More", comment: "The Pocket's ⋯ menu: Settings, updates, About, Quit"))
    }

    private var fullAccess: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: GuardMode.fullAccess.symbol).foregroundStyle(Theme.warning).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Full access is on").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Text(verbatim: content.fullAccessEnds.map { String(localized: "Ends \(TimeText.clock($0))", comment: "Full access: “Ends 22:00”") }
                     ?? String(localized: "On until you turn it off", comment: "Full access without an end"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: Theme.Space.s)
            Button("Turn Off", action: actions.turnOffFullAccess).buttonStyle(.sf(.secondary))
        }
        .padding(Theme.Space.s + 2)
        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var hidden: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "eye").foregroundStyle(Theme.inkMuted).accessibilityHidden(true)
            Text("It still watches, reminds and listens to agents.", comment: "The Pocket, while the companion is hidden")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            Button("Show \(content.name)", action: actions.showCompanion).buttonStyle(.sf(.primary))
        }
        .padding(Theme.Space.s + 2)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var dial: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SegmentedPicker(Text("Open, Focus or Quiet", comment: "Settings › Attention: the three ways things reach you"),
                            selection: Binding(get: { content.attention }, set: { mode in
                                actions.setAttention(mode, mode == .open ? nil : Date().addingTimeInterval(3600))
                            }),
                            segments: AttentionMode.allCases.map { .init($0, $0.word, symbol: $0 == .open ? nil : $0.symbol) },
                            equalWidths: true)
                .frame(maxWidth: .infinity)
            if content.attention != .open {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "clock").font(.system(size: 10)).accessibilityHidden(true)
                    Menu {
                        ForEach(content.spans, id: \.title) { span in
                            Button(span.title) { actions.setAttention(content.attention, span.until) }
                        }
                    } label: {
                        Text(verbatim: content.attentionEnds.map { String(localized: "Until \(TimeText.clock($0))", comment: "When Focus or Quiet ends: “Until 17:00”") }
                             ?? String(localized: "Until I turn it off", comment: "When Focus or Quiet ends"))
                    }
                    .menuStyle(.borderlessButton)
                    .font(Theme.Font.caption)
                    .fixedSize()
                    Spacer()
                    Button { actions.openAttentionSettings() } label: { Text("Attention Settings…", comment: "The Pocket: opens Settings › Attention") }
                        .buttonStyle(.plain).foregroundStyle(Theme.link)
                }
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            } else if let hours = content.quietHours {
                Label {
                    Text("Quiet hours, every night \(Self.clock(hours.start))–\(Self.clock(hours.end))", comment: "The Pocket: “Quiet hours, every night 22:00–08:00”")
                } icon: { Image(systemName: Theme.Symbol.quiet) }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    static func clock(_ minutes: Int) -> String { "\u{2066}" + String(format: "%02d:%02d", minutes / 60, minutes % 60) + "\u{2069}" }

    private func updateCard(_ version: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(version) is ready", comment: "Settings › General: a new version, “0.1.0 snapshot 560 is ready”")
                    .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                (content.updateReady ? Text("Downloaded and checked", comment: "The Pocket: an update ready to restart into")
                     : Text("Sidefolk asks before installing", comment: "The Pocket: an update found"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: Theme.Space.s)
            Button(content.updateReady ? "Restart Now" : "Update…", action: actions.update).buttonStyle(.sf(.primary))
        }
        .padding(Theme.Space.s + 2)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func section(_ title: Text, rows: [PocketContent.Row], trailing: (Text, () -> Void)? = nil) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    title.font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    if let trailing {
                        Button(action: trailing.1) { trailing.0.font(Theme.Font.captionStrong) }.buttonStyle(.plain).foregroundStyle(Theme.link)
                    }
                }
                .padding(.horizontal, Theme.Space.xs)
                ForEach(rows.prefix(3)) { row in PocketRow(row: row) }
            }
        }
    }

    private var askField: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: Theme.Symbol.say).foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Ask", text: $question,
                      prompt: Text("Ask \(content.name), or type a reminder…", comment: "The Pocket's Ask field"))
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .focused($asking)
                .onSubmit {
                    let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    question = ""
                    actions.ask(text)
                }
            if !content.hotkey.isEmpty { KeyHint(content.hotkey) }
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(minHeight: 34)
        .fieldChrome(focused: asking)
    }
}

private struct PocketRow: View {
    var row: PocketContent.Row
    @State private var hovering = false

    var body: some View {
        Button(action: row.open) {
            HStack(spacing: Theme.Space.s) {
                Group {
                    if let folk = row.folk {
                        FolkAvatar(name: folk, size: 28, live: row.live)
                    } else {
                        Image(systemName: row.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkMuted)
                            .frame(width: 28, height: 28)
                            .background(Theme.well, in: Circle())
                    }
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: row.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                    if let detail = row.detail {
                        Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                if let trailing = row.trailing {
                    HStack(spacing: 4) {
                        if row.live { Circle().fill(Theme.glow).frame(width: 7, height: 7) }
                        Text(verbatim: trailing).font(Theme.Font.caption.monospacedDigit())
                            .foregroundStyle(row.live ? Theme.link : Theme.inkMuted)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, 5)
            .background(hovering ? Theme.well : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}
