import SidefolkCore
import SwiftUI

/// The one bar (D58): one place to type, in Home's toolbar (⌘K) and in the Ask panel. What it does with the words
/// is the Ask panel's own path; what it adds is a search across everything, shown as you type.

/// How typed words are sent on: done without AI when understood (Return), asked of the AI even when understood
/// (⌘Return), or kept as a note in Inbox (⌥Return).
enum AskHow {
    case auto, ai, note
}

/// Something a search found, to open where it lives.
enum Found: Identifiable {
    case note(NotebookItem)
    case conversation(ConversationSummary)
    case reminder(Reminder)
    case watch(Watcher)
    case activity(ActivityEntry)

    var id: String {
        switch self {
        case .note(let n): "n" + n.id
        case .conversation(let c): "c" + c.id
        case .reminder(let r): "r" + r.id
        case .watch(let w): "w" + w.id
        case .activity(let a): "a" + (a.id.map(String.init) ?? "\(a.at.timeIntervalSince1970)")
        }
    }
}

/// Searches as the words change, a moment after typing pauses, and drops answers to words already gone.
@MainActor @Observable
final class FindModel {
    var query = "" {
        didSet { if query != oldValue { schedule() } }
    }
    private(set) var results = SearchResults()

    /// Where it searches: the runtime's `find`, through whoever owns this.
    @ObservationIgnored var find: @MainActor (String) async -> SearchResults
    @ObservationIgnored private var task: Task<Void, Never>?

    init(find: @escaping @MainActor (String) async -> SearchResults = { _ in SearchResults() }) {
        self.find = find
    }

    var searching: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).count >= SidefolkRuntime.shortestSearch }

    /// Searches now, without the pause (the dev channel and snapshots).
    func searchNow() async {
        task?.cancel()
        results = searching ? await find(query) : SearchResults()
    }

    private func schedule() {
        task?.cancel()
        guard searching else {
            results = SearchResults()
            return
        }
        let words = query
        task = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let found = await find(words)
            guard !Task.isCancelled, words == query else { return }
            results = found
        }
    }
}

/// What a search found, grouped by kind: a few of each, newest or best first, each a click from where it lives.
struct FoundList: View {
    var results: SearchResults
    /// How many of each kind: the Ask panel shows fewer than Home.
    var each = 5
    var open: (Found) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            group("Notes", results.notes.prefix(each).map(Found.note))
            group("Conversations", results.conversations.prefix(each).map(Found.conversation))
            group("Reminders", results.reminders.prefix(each).map(Found.reminder))
            group("Watching", results.watches.prefix(each).map(Found.watch))
            group("Activity", results.activity.prefix(each).map(Found.activity))
        }
    }

    @ViewBuilder private func group(_ title: LocalizedStringKey, _ found: [Found]) -> some View {
        if !found.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(Text(title))
                ForEach(found) { item in
                    Button { open(item) } label: { FoundRow(found: item) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct FoundRow: View {
    var found: Found

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 18)
            Text(verbatim: title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
            if let detail {
                Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch found {
        case .note(let n): ItemKindStyle.symbol(n.kind)
        case .conversation: "bubble.left.and.bubble.right"
        case .reminder: "alarm"
        case .watch: "binoculars"
        case .activity: "list.bullet.rectangle"
        }
    }

    private var title: String {
        switch found {
        case .note(let n): n.title
        case .conversation(let c): c.title
        case .reminder(let r): r.title
        case .watch(let w): w.title
        case .activity(let a): a.summary
        }
    }

    private var detail: String? {
        switch found {
        case .note(let n): TimeText.short(n.updatedAt)
        case .conversation(let c): TimeText.short(c.updatedAt)
        case .reminder(let r): ReminderBadge.when(r)
        case .watch: nil
        case .activity(let a): TimeText.short(a.at)
        }
    }
}

/// Home while the one bar has words: what Return will do, the other two ways to send them, and what was found.
struct SearchPage: View {
    var find: FindModel
    var services: AppServices
    var send: (AskHow) -> Void

    var body: some View {
        PageScroll {
            WillDo(text: find.query, services: services, send: send)
            if find.results.isEmpty {
                if find.searching {
                    Text("Nothing found for “\(find.query)”.").font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                        .padding(.leading, Theme.Space.xs)
                }
            } else {
                FoundList(results: find.results) { services.open($0) }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            }
        }
    }
}

/// What Return will do with the words (D64), before anything happens: the action and its parts, the tool that runs it
/// and its risk, whether a model is used; then the other two ways to send them.
struct WillDo: View {
    var text: String
    var services: AppServices
    var send: (AskHow) -> Void

    var body: some View {
        let name = services.runtime.settings.current.companionName
        let plan = services.understands(text) ? services.plan(for: text) : nil
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(Text("Will do")).padding(.horizontal, Theme.Space.l).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.xs)
            Button { send(.auto) } label: {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: plan == nil ? "sparkles" : "return").foregroundStyle(Theme.link).frame(width: 18)
                    if let plan, !plan.title.isEmpty {
                        (Text(verbatim: plan.kind).fontWeight(.semibold) + Text(verbatim: " · \(plan.title)"))
                            .lineLimit(1).truncationMode(.tail)
                    } else {
                        Text(verbatim: plan?.kind ?? services.hint(for: text) ?? String(localized: "Ask \(name)")).fontWeight(.semibold).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                    ForEach(plan?.chips ?? [], id: \.self) { chip in
                        Text(verbatim: chip).font(Theme.Font.captionStrong).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Theme.surfaceRaised, in: Capsule()).overlay(Capsule().strokeBorder(Theme.line))
                    }
                    KeyCap("⏎")
                }
                .font(Theme.Font.body).foregroundStyle(Theme.ink)
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                .background(Theme.accentSoft.opacity(0.7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(verbatim: toolLine(plan, name: name))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
            Divider()
            if plan != nil {
                choice("bubble.left", Text("Ask \(name) instead"), key: "⌘⏎") { send(.ai) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            choice("note.text", Text("Save as a note in Inbox"), key: "⌥⏎") { send(.note) }
                .keyboardShortcut(.return, modifiers: .option)
            HStack {
                Text("Esc clears")
                Spacer()
                Text("Nothing happens until you press ⏎")
            }
            .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
            .background(Theme.surfaceSunken)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .cardSurface()
    }

    /// "reminders.create · low risk · understood on this Mac, no model call", or which AI will be asked.
    private func toolLine(_ plan: IntentPlan?, name: String) -> String {
        guard let plan else {
            return String(localized: "goes to \(name) and your AI · whatever it does still asks you first, as always",
                          comment: "The one bar: words not understood on the Mac go to the AI")
        }
        guard let tool = plan.tool else { return String(localized: "understood on this Mac, no model call") }
        let risk = services.runtime.registry.tool(named: tool)?.spec.risk
        let word = switch risk {
        case .high: String(localized: "high risk")
        case .medium: String(localized: "medium risk")
        default: String(localized: "low risk")
        }
        return "\(tool) · \(word) · \(String(localized: "understood on this Mac, no model call"))"
    }

    private func choice(_ symbol: String, _ title: Text, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 18)
                title.foregroundStyle(Theme.ink)
                Spacer()
                KeyCap(key)
            }
            .font(Theme.Font.body)
            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A key as printed on a keycap.
struct KeyCap: View {
    var key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(verbatim: key).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line))
            .accessibilityHidden(true)
    }
}
