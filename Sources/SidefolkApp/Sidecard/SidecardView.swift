import SidefolkCore
import SwiftUI

/// The Sidecard above the companion (D84): a whisper, a card, or the stack fanned out. One glass, one tail toward the
/// head; the size says how much it matters.
struct SidecardView: View {
    var model: SidecardModel

    /// Room around the glass for its shadow (e3 falls 18 pt with a 24 pt blur), so the window doesn't cut it.
    static let margin = EdgeInsets(top: 12, leading: 24, bottom: 34, trailing: 24)

    var body: some View {
        Group {
            switch model.shape {
            case .whisper: if let item = model.item { whisper(item).fixedSize() }
            // As wide as the card allows (320–400), so long words and buttons wrap inside it rather than run off.
            case .card: if let item = model.item { SidecardItemCard(item: item, model: model, tail: tail).fixedSize(horizontal: false, vertical: true) }
            case .stack: stack.fixedSize()
            }
        }
        .padding(Self.margin)
        .onHover { model.hovering = $0 }
    }

    private var tail: SidecardTail? { model.tailAt.map { SidecardTail(edge: .bottom, at: $0) } }

    private func whisper(_ item: AttentionItem) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: model.pausedLeft != nil)) { context in
            let undo = item.actions.first { $0.id == SidecardItemCard.undo }
            Whisper(text: Text(verbatim: item.title), folk: SidecardItemCard.folk(item), face: SidecardItemCard.speaksItself(item) ? model.face : nil,
                    timeLeft: model.timeLeft(at: context.date), paused: model.pausedLeft != nil, tail: tail) {
                if let undo {
                    Button { model.respond?(item, undo.id) } label: {
                        Label { Text(verbatim: undo.title) } icon: { Image(systemName: "arrow.uturn.backward") }
                    }
                    .help(Text("Undo (⌘Z)", comment: "A whisper's Undo button, with its shortcut"))
                }
            }
        }
        .contentShape(Rectangle())
        // Clicked, it grows into a card on the same anchor, never replaced (b02).
        .onTapGesture { model.grow?() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Shows more", comment: "VoiceOver: clicking a whisper beside the companion grows it into a card"))
    }

    /// A held card as the stack shows it: who it's from, its title, and when.
    static func stackItem(_ item: AttentionItem, companion: String, sessions: [String: AgentSession]) -> SidecardStack.Item {
        SidecardStack.Item(id: item.id, folk: SidecardItemCard.folk(item), title: Text(verbatim: item.title),
                           meta: SidecardItemCard.source(item, companion: companion, sessions: sessions)
                               + Text(verbatim: " · \(TimeFormat.clock(item.shownAt ?? item.createdAt, calendar: .autoupdatingCurrent))"))
    }

    /// Three held cards at most: the newest, or the three around the one the keyboard is on.
    static func shown(_ stack: [AttentionItem], around focus: String?) -> [AttentionItem] {
        guard let focus, let at = stack.firstIndex(where: { $0.id == focus }), stack.count > 3 else { return Array(stack.suffix(3)) }
        let start = min(max(0, at - 1), stack.count - 3)
        return Array(stack[start..<start + 3])
    }

    private func keyPair(_ key: String, _ words: Text) -> some View {
        HStack(spacing: 4) {
            KeyHint(key)
            words.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    /// What waits, fanned out from the shoulder: the newest in front, a click opens Ask on top of them.
    private var stack: some View {
        VStack(alignment: .trailing, spacing: Theme.Space.s) {
            SidecardStack(items: Self.shown(model.stack, around: model.stackFocus).map {
                Self.stackItem($0, companion: model.companionName, sessions: model.sessions)
            }, selected: model.stackFocus, out: model.stackOut, from: model.fanFrom)
            HStack(spacing: Theme.Space.s) {
                if model.stackFocus != nil {
                    // From the shortcut: the keys that move through the held cards (D84).
                    ButtonRow(spacing: Theme.Space.s) {
                        keyPair("↑↓", Text("choose", comment: "Under the held cards fanned from the keyboard: ↑↓ picks one"))
                        keyPair("↩", Text("open", comment: "Under the held cards fanned from the keyboard: ↩ brings the chosen one out"))
                    }
                } else if model.waiting > 3 {
                    Text("+\(model.waiting - 3) more", comment: "Under the held cards beside the companion: how many more wait")
                        .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                }
                Button { model.openStack?() } label: { Text("Answer", comment: "Under the held cards: opens Ask on top of them") }
                    .buttonStyle(.sf(.quiet, size: .small))
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.xxs)
            .lanternGlass(radius: 16)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openStack?() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(model.waiting) waiting", comment: "A count of things waiting on the person, read by VoiceOver"))
    }
}

/// One notice as a card: who it is from, what it is, and at most three answers with the main one last; the rest wait
/// in a ⋯ menu (b03). Lists (the morning brief, what waited) show as rows, not a paragraph.
struct SidecardItemCard: View {
    var item: AttentionItem
    var model: SidecardModel
    var tail: SidecardTail?

    static let undo = "undo"

    var body: some View {
        let lines = Self.listLines(item)
        let (menu, buttons) = Self.arrange(item.actions)
        SidecardCard(folk: Self.folk(item), face: Self.speaksItself(item) ? model.face : nil,
                     source: Self.source(item, companion: model.companionName, sessions: model.sessions), title: Text(verbatim: item.title),
                     message: lines == nil ? item.body.map { Text(verbatim: $0) } : nil, tail: tail,
                     close: { model.respond?(item, nil) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                // The very first hello introduces the whole family, not just the one on the desktop.
                if item.refKind == Onboarding.welcome, let family = BrandAsset.familyColor.image {
                    Image(nsImage: family).resizable().scaledToFit().frame(height: 84).frame(maxWidth: .infinity).accessibilityHidden(true)
                }
                if let lines { ListLines(lines: lines) }
                if let keys = model.keys {
                    SidecardKeysLine(keys: keys, nudge: model.keysNudge, closes: !(item.level >= .attention && SidecardController.folds(item)))
                }
            }
        } actions: {
            if !menu.isEmpty {
                Menu {
                    ForEach(menu, id: \.id) { action in
                        Button { model.respond?(item, action.id) } label: { Text(verbatim: action.title) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.sf(.secondary, size: .sidecard))
                .fixedSize()
                .keyFocusRing(focused(SidecardController.moreAnswers))
                .accessibilityLabel(Text("More choices", comment: "A ⋯ menu on a card beside the companion"))
            }
            ForEach(buttons, id: \.id) { action in
                Button { model.respond?(item, action.id) } label: { Text(verbatim: action.title) }
                    .buttonStyle(.sf(action.isPrimary ? .primary : .secondary, size: .sidecard))
                    .keyFocusRing(focused(action.id))
            }
        }
        .accessibilityLabel(Text(verbatim: item.title))
    }

    /// The answer the keyboard is on, while the card has it (D84).
    private func focused(_ id: String) -> Bool { model.keys?.focusedAnswer == id }

    /// Three in sight at most, the main one last (macOS order): the likeliest other answer beside it, and the rest in a
    /// ⋯ menu first in the row, in the order they came (b03). Long languages keep one row that way.
    static func arrange(_ actions: [AttentionAction]) -> (menu: [AttentionAction], buttons: [AttentionAction]) {
        let shown = actions.filter { $0.id != undo }
        guard let primary = shown.first(where: \.isPrimary) ?? shown.first else { return ([], []) }
        let others = shown.filter { $0.id != primary.id }
        return (Array(others.dropFirst()), others.prefix(1) + [primary])
    }

    /// A body made of lines (the brief's day, what waited while away or quiet) reads as rows.
    static func listLines(_ item: AttentionItem) -> [String]? {
        guard item.refKind == "brief" || item.source == "summary", let body = item.body else { return nil }
        let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.count > 1 ? lines.map { $0.hasPrefix("• ") ? String($0.dropFirst(2)) : $0 } : nil
    }

    /// The folk who signs it (D73): Tempo for time, Scout for watching, Byte for agents, commands and extensions.
    static func folk(_ item: AttentionItem) -> String? {
        switch item.refKind ?? item.source {
        case "reminder", "brief": return "tempo"
        case "watcher": return "scout"
        case "job", "session", "credit": return "byte"
        default:
            return ["external:", "session:", "extension:"].contains { item.source.hasPrefix($0) } ? "byte" : nil
        }
    }

    /// The companion itself speaks: introductions, onboarding, what waited, updates.
    static func speaksItself(_ item: AttentionItem) -> Bool { folk(item) == nil }

    /// "Tempo · reminder", "Scout · watch", "Codex · question", "Claude Code · sidefolk": who it is from, then what kind
    /// of moment. An agent session's notice names the agent and its project, from the session it is about.
    static func source(_ item: AttentionItem, companion: String, sessions: [String: AgentSession] = [:]) -> Text {
        if item.refKind == "session", let session = item.refId.flatMap({ sessions[$0] }) {
            return Text(verbatim: ([AgentFacingTools.displayName(session.agent), session.projectName].compactMap { $0 }).joined(separator: " · "))
        }
        let kind: Text? = switch item.refKind ?? item.source {
        case "reminder": Text("reminder", comment: "A card's source line: “Tempo · reminder”")
        case "brief": Text("today", comment: "A card's source line: the morning brief, “Tempo · today”")
        case "watcher": Text("watch", comment: "A card's source line: “Scout · watch”")
        case "job": Text("command", comment: "A card's source line: a command started with `sidefolk run`")
        case "session": Text("agent session", comment: "A card's source line: a Claude Code or Codex session")
        case "ask": Text("question", comment: "A card's source line: “Codex · question”")
        case "quiet": Text("Quiet ended", comment: "A card's source line when quiet mode ended: “Mochi · Quiet ended”")
        case "focus": Text("Focus ended", comment: "A card's source line when Focus ended: “Mochi · Focus ended”")
        case "summary": Text("while you were away", comment: "A card's source line: what waited")
        default: nil
        }
        let who: String = switch folk(item) {
        case "tempo": "Tempo"
        case "scout": "Scout"
        case "byte":
            item.source.hasPrefix("external:") ? AgentFacingTools.displayName(String(item.source.dropFirst("external:".count))) : "Byte"
        default: companion
        }
        guard let kind else { return Text(verbatim: who) }
        return Text(verbatim: "\(who) · ") + kind
    }
}

/// Rows of a list inside a card: the brief's day, what waited.
private struct ListLines: View {
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.prefix(6).enumerated()), id: \.offset) { index, line in
                if index > 0 { Divider().overlay(Theme.line) }
                Text(verbatim: line).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.xxs)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}
