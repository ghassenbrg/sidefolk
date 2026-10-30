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
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: 6) {
                    Image(systemName: "return").imageScale(.small)
                    Text(verbatim: services.hint(for: find.query) ?? "")
                }
                .font(Theme.Font.hint)
                .foregroundStyle(Theme.inkMuted)
                ButtonRow {
                    // Words Sidefolk doesn't do alone go to the AI on Return anyway: one button says so.
                    let name = services.runtime.settings.current.companionName
                    if services.understands(find.query) {
                        Button("Do it") { send(.auto) }.buttonStyle(.sf(.primary))
                            .help(Text(verbatim: "⏎"))
                        Button("Ask \(name) instead") { send(.ai) }.buttonStyle(.sf(.secondary))
                            .keyboardShortcut(.return, modifiers: .command)
                            .help(Text(verbatim: "⌘⏎"))
                    } else {
                        Button("Ask \(name)") { send(.auto) }.buttonStyle(.sf(.primary))
                            .help(Text(verbatim: "⏎"))
                    }
                    Button("Save as a note") { send(.note) }.buttonStyle(.sf(.secondary))
                        .keyboardShortcut(.return, modifiers: .option)
                        .help(Text(verbatim: "⌥⏎"))
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
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
