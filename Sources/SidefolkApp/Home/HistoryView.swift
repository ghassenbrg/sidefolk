import SidefolkCore
import SwiftUI

/// Home › History (D84): what happened, who did it, and Undo where an undo still exists. One timeline grouped by the
/// hour, one plain sentence per row with a chip for how it ended; said no and skipped rows are calm, never red. The
/// exact record (the tool's own name and arguments) shows only when a row is opened; a conversation opens in place
/// with its reply field; another agent's session is a receipt of its calls.
struct HistoryView: View {
    @Bindable var model: HistoryModel
    var home: HomeModel
    @FocusState private var focus: HistoryFocus?

    enum HistoryFocus: Hashable { case search }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if model.loaded && model.events.isEmpty {
                EmptyState(title: Text("Nothing has happened yet"),
                           message: Text("What \(model.companionName) and your agents do, the conversations you have and what was noticed for you show up here, with Undo where it can be undone."),
                           systemImage: "clock.arrow.circlepath", folk: "guard",
                           actionTitle: Text("Ask \(model.companionName) something")) { home.services.openAsk(prefill: "") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                timeline
            }
        }
        .background(Theme.surfaceSunken)
        .background {
            Button("Find") { focus = .search }.keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    // MARK: Filters and search

    private var bar: some View {
        WrapRow(minimum: 420, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                SegmentedPicker("Show", selection: $model.filter, segments: [
                    .init(HistoryFilter.all, Text("All", comment: "History's filter: everything")),
                    .init(HistoryFilter.conversations, Text("Conversations")),
                    .init(HistoryFilter.actions, Text("Actions", comment: "History's filter: what Sidefolk and the person did")),
                    .init(HistoryFilter.agents, Text("Agents", comment: "History's filter: other agents' sessions and calls")),
                    .init(HistoryFilter.alerts, Text("Alerts", comment: "History's filter: what Sidefolk told the person")),
                ])
                Menu {
                    Picker("Span", selection: $model.span) {
                        Text("Today").tag(HistoryModel.Span.today)
                        Text("Last 7 days").tag(HistoryModel.Span.week)
                        Text("Everything kept").tag(HistoryModel.Span.all)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label { Text(spanTitle) } icon: { Image(systemName: "calendar") }
                }
                .menuStyle(.button)
                .buttonStyle(.sf(.secondary))
                .fixedSize()
            }
            SearchBox(text: $model.query, prompt: Text("Search history"), focus: $focus, focusValue: .search)
                .frame(maxWidth: 300)
        }
        .padding(.horizontal, Theme.Size.contentPadding)
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: Theme.Size.contentMaxWidth + 2 * Theme.Size.contentPadding)
        .frame(maxWidth: .infinity)
    }

    private var spanTitle: String {
        switch model.span {
        case .today: String(localized: "Today")
        case .week: String(localized: "Last 7 days")
        case .all: String(localized: "Everything kept")
        }
    }

    // MARK: The timeline

    private var timeline: some View {
        let hours = HistoryTimeline.hours(model.visible)
        return ScrollViewReader { proxy in ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.l) {
                if let message = model.undoMessage {
                    HStack {
                        Label { Text(verbatim: message) } icon: { Image(systemName: "arrow.uturn.backward") }
                            .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                        Spacer()
                        Button("OK") { model.clearUndoMessage() }.buttonStyle(.sf(.quiet))
                    }
                }
                if hours.isEmpty {
                    (model.query.isEmpty ? Text("Nothing here for this span. Try “Last 7 days”.")
                     : Text("Nothing in History matches “\(model.query)”."))
                        .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                        .padding(.top, Theme.Space.xl)
                }
                ForEach(hours, id: \.start) { hour in
                    HStack(alignment: .top, spacing: Theme.Space.l) {
                        Text(verbatim: hourTitle(hour.start)).font(Theme.Font.headline.monospacedDigit()).foregroundStyle(Theme.ink)
                            .frame(width: 64, alignment: .trailing)
                            .padding(.top, Theme.Space.l)
                        RowsCard {
                            ForEach(hour.events) { event in
                                HistoryRow(event: event, model: model, home: home).id(event.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Size.contentPadding)
            .padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: Theme.Size.contentMaxWidth + 2 * Theme.Size.contentPadding)
            .frame(maxWidth: .infinity)
        }
        // What was opened from elsewhere (a conversation, an Activity row) comes into view.
        .onChange(of: model.conversation.selectedId, initial: true) { if let id = model.conversation.selectedId { proxy.scrollTo("c" + id, anchor: .top) } }
        .onChange(of: model.openId, initial: true) { if let id = model.openId { proxy.scrollTo(id, anchor: .top) } }
        }
    }

    /// "15:00" today; "Yesterday 15:00", "Tue 15:00" further back.
    private func hourTitle(_ start: Date) -> String {
        let clock = TimeFormat.clock(start, calendar: .current)
        if Calendar.current.isDateInToday(start) { return clock }
        return TimeFormat.day(start, now: Date(), calendar: .current) + "\n" + clock
    }
}

/// One thing that happened, as a sentence: who (in bold) and what, then how it ended as a chip with one quiet line, and
/// Undo or the one thing to do at the trailing side. A click opens the exact record, the conversation or the receipt.
private struct HistoryRow: View {
    var event: HistoryEvent
    var model: HistoryModel
    var home: HomeModel
    @State private var hovered = false

    private var open: Bool {
        if case .conversation(let c) = event.kind { return model.conversation.selectedId == c.id }
        return model.openId == event.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Text(verbatim: TimeFormat.clock(event.at, calendar: .current)).font(Theme.Font.callout.monospacedDigit())
                    .foregroundStyle(Theme.inkFaint).frame(width: 40, alignment: .leading).padding(.top, 3)
                avatar
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    sentence.font(Theme.Font.body).foregroundStyle(muted ? Theme.inkMuted : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.Space.s) {
                        chip
                        if let meta {
                            Text(verbatim: meta).font(Theme.Font.callout).foregroundStyle(Theme.inkFaint).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .background(open || hovered ? Theme.ink.opacity(0.03) : .clear)
            .contentShape(Rectangle())
            .onTapGesture { model.toggle(event) }
            .onHover { hovered = $0 }
            if open { expanded }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: open ? Text("Close") : Text("Open")) { model.toggle(event) }
    }

    // MARK: Who and what

    private var companion: String { model.companionName }

    private var who: String {
        switch event.kind {
        case .action(let e): Describe.caller(e.caller, companion: companion)
        case .conversation: String(localized: "You and \(companion)", comment: "History: a conversation between the person and the companion")
        case .alert(let a): folkName(alertFolk(a))
        case .session(let s, _): Describe.agentName(s.agent)
        }
    }

    private var sentence: Text {
        let name = Text(verbatim: who).fontWeight(.semibold).foregroundStyle(Theme.ink)
        switch event.kind {
        case .action(let e):
            return name + Text(verbatim: "  ") + Text(verbatim: e.summary)
        case .conversation(let c):
            return Text("\(name) talked: “\(c.title.clipped(120))”", comment: "History: a conversation, “You and Mochi talked: “Plan my afternoon””")
        case .alert(let a):
            return Text("\(name) told you: \(a.title)", comment: "History: something Sidefolk told the person, “Scout told you: Pricing changed”")
        case .session(let s, _):
            if let project = s.projectName {
                return Text("\(name) worked in \(project)", comment: "History: another agent's session, “Codex worked in pockito”")
            }
            return Text("\(name) worked with Sidefolk", comment: "History: another agent's session without a project")
        }
    }

    /// Said no, blocked and skipped rows read calm (muted), never red.
    private var muted: Bool {
        if case .action(let e) = event.kind { return [.denied, .blocked, .skipped].contains(e.decision) }
        return false
    }

    // MARK: How it ended

    @ViewBuilder private var chip: some View {
        switch event.kind {
        case .action(let e):
            switch e.decision {
            case .denied: Chip("Not allowed", tone: .neutral)
            case .blocked: Chip("Not allowed", tone: .warning)
            case .skipped: Chip("Skipped", tone: .neutral)
            case .failed: Chip("Didn't work", tone: .danger)
            default: Chip(verbatim: String(localized: "state.done", defaultValue: "Done", comment: "Checkbox and status: the task or reminder is finished"), tone: .success)
            }
        case .conversation: Chip("Conversation", tone: .neutral, systemImage: "bubble.left")
        case .alert(let a):
            if a.state == .pending || a.state == .shown {
                Chip("Waiting for you", tone: .warning)
            } else {
                if a.level >= .attention { Chip("Alert", tone: .warning) } else { Chip("Told you", tone: .neutral) }
            }
        case .session(let s, _):
            switch s.state {
            case .needsYou: Chip("Waiting for you", tone: .warning)
            case .working: Chip("Working", tone: .accent)
            default: Chip("Receipt", tone: .neutral, systemImage: "doc.plaintext")
            }
        }
    }

    private var meta: String? {
        switch event.kind {
        case .action(let e):
            return e.error ?? e.outcome
        case .conversation(let c):
            return String(localized: "\(c.requests) requests", comment: "History: how many times the person asked in a conversation")
        case .alert(let a):
            return a.body.map { $0.clipped(120) }
        case .session(let s, let calls):
            let took = TimeText.span((s.endedAt ?? (s.state == .finished ? s.updatedAt : Date())).timeIntervalSince(s.startedAt))
            return String(localized: "^[\(calls.count) call](inflect: true) · \(took)", comment: "History: an agent's session, “9 calls · 14 min”")
        }
    }

    // MARK: Trailing

    @ViewBuilder private var trailing: some View {
        HStack(spacing: Theme.Space.s) {
            switch event.kind {
            case .action(let e) where model.canUndo(e):
                Button { Task { await model.undo(e) } } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.sf(.quiet))
            case .conversation:
                Button { model.toggle(event) } label: { open ? Text("Close") : Text("Open") }.buttonStyle(.sf(.quiet))
            case .alert(let a) where a.state == .pending || a.state == .shown:
                Button("Answer") { home.selection = .now }.buttonStyle(.sf(.quiet))
            case .session(let s, _) where s.state != .finished:
                Button("Open session") { home.services.openSession(s) }.buttonStyle(.sf(.quiet))
            default:
                Image(systemName: open ? "chevron.down" : "chevron.forward").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .fixedSize()
        .padding(.top, 2)
    }

    // MARK: Opened

    @ViewBuilder private var expanded: some View {
        switch event.kind {
        case .action(let e):
            ActivityDetails(entry: e, who: Describe.caller(e.caller, companion: companion),
                            askedIn: e.runId.flatMap { model.runConversations[$0] },
                            open: { model.open(conversation: $0) },
                            seeRule: e.decision == .always ? { home.services.openSettings(tab: .privacy) } : nil)
        case .conversation:
            InlineConversation(model: model.conversation)
        case .alert(let a):
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if let body = a.body { Text(verbatim: body).font(Theme.Font.body).foregroundStyle(Theme.ink) }
                Text(verbatim: a.source).font(Theme.Font.mono).foregroundStyle(Theme.inkFaint)
            }
            .padding(.leading, 40 + Theme.Size.avatar + 2 * Theme.Space.m + Theme.Space.l)
            .padding(.trailing, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceSunken)
        case .session(_, let calls):
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if calls.isEmpty {
                    Text("It didn't ask Sidefolk for anything.").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                }
                ForEach(calls) { call in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(verbatim: TimeFormat.clock(call.at, calendar: .current)).font(Theme.Font.callout.monospacedDigit())
                            .foregroundStyle(Theme.inkFaint)
                        Text(verbatim: call.summary).font(Theme.Font.callout).foregroundStyle(Theme.ink)
                        Spacer(minLength: Theme.Space.s)
                        Text(verbatim: call.tool).font(Theme.Font.mono).foregroundStyle(Theme.inkFaint)
                    }
                }
            }
            .padding(.leading, 40 + Theme.Size.avatar + 2 * Theme.Space.m + Theme.Space.l)
            .padding(.trailing, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceSunken)
        }
    }

    // MARK: Avatars

    @ViewBuilder private var avatar: some View {
        switch event.kind {
        case .action(let e):
            switch Describe.callerKind(e.caller) {
            case "user": PersonAvatar()
            case "agent": CompanionAvatar(settings: home.services.runtime.settings.current)
            case "external": FolkAvatar(name: "byte", size: Theme.Size.avatar)
            case "routine": FolkAvatar(name: "tempo", size: Theme.Size.avatar)
            default: FolkAvatar(name: "byte", size: Theme.Size.avatar)
            }
        case .conversation: CompanionAvatar(settings: home.services.runtime.settings.current)
        case .alert(let a): FolkAvatar(name: alertFolk(a), size: Theme.Size.avatar)
        case .session: FolkAvatar(name: "byte", size: Theme.Size.avatar)
        }
    }

    private func alertFolk(_ a: AttentionItem) -> String {
        switch a.refKind ?? String(a.source.split(separator: ":").first ?? "") {
        case "watcher": "scout"
        case "reminder", "brief": "tempo"
        case "job", "session", "external": "byte"
        default: "pip"
        }
    }

    private func folkName(_ folk: String) -> String {
        switch folk {
        case "scout": "Scout"
        case "tempo": "Tempo"
        case "byte": "Byte"
        default: companion
        }
    }
}

/// The person, as History shows who did something: the first letter of their name in a circle.
struct PersonAvatar: View {
    var size: CGFloat = Theme.Size.avatar

    var body: some View {
        Circle().fill(LinearGradient(colors: [Theme.link, Theme.accent], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Text(verbatim: String((NowModel.firstName ?? "").prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded)).foregroundStyle(Theme.onAccent)
            }
            .accessibilityHidden(true)
    }
}

/// The companion's portrait in a circle, as History and You show what it did.
struct CompanionAvatar: View {
    var settings: AppSettings
    var size: CGFloat = Theme.Size.avatar

    var body: some View {
        CompanionPortrait(settings: settings, side: size * 1.1)
            .frame(width: size, height: size)
            .background(Theme.accentSoft, in: Circle())
            .clipShape(Circle())
    }
}

/// A conversation opened in place in History (A10): the transcript, then a reply field that says it uses the AI.
private struct InlineConversation: View {
    @Bindable var model: ConversationsModel
    @FocusState private var replyFocused: Bool
    @State private var deleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(model.lines) { line in
                LineView(line: line, avatar: model.companionAvatar, name: model.companionName)
            }
            if let sending = model.sending, model.lines.last(where: \.isRequest)?.text != sending {
                LineView(line: ConversationLine(id: "sending", kind: .request(spoken: false, attachment: nil), text: sending, at: Date()))
            }
            if let phase = model.phase {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: phase)
                }
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            if let error = model.error { InlineError(error: error) }
            composer
        }
        .padding(.leading, 40 + Theme.Size.avatar + 2 * Theme.Space.m)
        .padding(.trailing, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSunken.opacity(0.6))
        .alert("Delete this conversation?", isPresented: $deleting, presenting: model.selected) { conversation in
            Button("Delete Conversation", role: .destructive) { Task { await model.delete(conversation) } }
            Button("Cancel", role: .cancel) {}
        } message: { conversation in
            Text("“\(conversation.title.clipped(60))” and its answers are deleted from this Mac. History keeps its record of what was done.")
        }
    }

    @ViewBuilder private var composer: some View {
        if model.hasAI {
            HStack(spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "bubble.left").foregroundStyle(Theme.inkFaint)
                    TextField("Reply", text: $model.draft, prompt: Text("Reply to \(model.companionName)…"), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .lineLimit(1...6)
                        .focused($replyFocused)
                        .onSubmit { model.send() }
                        .disabled(model.busy)
                        .accessibilityLabel("Reply in this conversation")
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .fieldChrome(focused: replyFocused)
                Chip("Uses AI", tone: .warning, systemImage: "sparkles")
                if model.runId != nil {
                    Button("Stop") { Task { await model.stop() } }
                        .buttonStyle(.sf(.secondary))
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button("Send") { model.send() }
                        .buttonStyle(.sf(.primary))
                        .disabled(model.busy || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button { deleting = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.sf(.quiet))
                    .disabled(model.busy)
                    .help("Delete this conversation")
                    .accessibilityLabel("Delete this conversation")
            }
        } else {
            HStack(spacing: Theme.Space.m) {
                Text("Following up needs AI, which isn't set up yet.").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: Theme.Space.s)
                Button("AI Settings…") { model.services.openSettings(tab: .ai) }.buttonStyle(.sf(.secondary))
            }
        }
    }
}
/// A row's details, opened in place: everything the columns cut, how it was allowed, and its arguments.
struct ActivityDetails: View {
    var entry: ActivityEntry
    var who: String
    /// The conversation whose run did it, while that conversation is kept.
    var askedIn: ConversationSummary?
    var open: (String) -> Void
    /// Opens the rule in Settings, for something an "Always allow" let through.
    var seeRule: (() -> Void)?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.s) {
            line("What") { Text(entry.summary).font(Theme.Font.bodyStrong) }
            line("Who") { Text(verbatim: who) }
            if let askedIn {
                line("Asked in") { ConversationLink(conversation: askedIn) { open(askedIn.id) } }
            }
            line("Decision") {
                HStack(spacing: Theme.Space.s) {
                    Text(verbatim: Describe.decision(entry.decision))
                    if let seeRule {
                        Button("See the rule in Settings…", action: seeRule).buttonStyle(.sf(.plain))
                    }
                }
            }
            if let error = entry.error {
                line("Outcome") { Text(error).foregroundStyle(entry.decision == .failed ? Theme.danger : Theme.ink) }
            } else if let outcome = entry.outcome {
                line("Outcome") { Text(outcome) }
            }
            ForEach(Describe.arguments(entry.args), id: \.name) { argument in
                GridRow {
                    Text(verbatim: argument.name).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.inkFaint)
                    Text(verbatim: argument.value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                Text(verbatim: entry.tool).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkFaint)
            }
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Theme.Space.l + 13)
        .padding(.trailing, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.surfaceSunken)
        .accessibilityElement(children: .contain)
    }

    private func line(_ label: LocalizedStringKey, @ViewBuilder _ value: () -> some View) -> some View {
        GridRow {
            Eyebrow(Text(label)).gridColumnAlignment(.trailing)
            value().fixedSize(horizontal: false, vertical: true)
        }
    }
}

