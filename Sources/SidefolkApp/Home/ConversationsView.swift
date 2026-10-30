import SidefolkCore
import SwiftUI

/// Home › Conversations (D45): the conversations with the AI on the left, the one picked on the right, to read again,
/// follow up in, or forget. Sidefolk isn't a chat app: the Ask panel stays the quick place; this is where you come back.
struct ConversationsView: View {
    @Bindable var model: ConversationsModel
    @State private var confirmingDeleteAll = false
    @State private var deleting: ConversationSummary?

    var body: some View {
        Group {
            if model.loaded, model.conversations.isEmpty, model.query.isEmpty {
                // Nothing to list or read: one calm page, not two empty columns.
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    PageTitle(title: "Conversations", subtitle: "What you asked the AI, to read again or follow up.")
                    Spacer()
                    EmptyState(title: "No conversations yet",
                               message: "When you ask the AI something, the conversation shows up here to read again or follow up. Reminders and notes made without AI don't start one.",
                               systemImage: "bubble.left.and.bubble.right", folk: "pip")
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.surfaceSunken)
            } else {
                HSplitView {
                    ConversationList(model: model, deleteAll: { confirmingDeleteAll = true }, delete: { deleting = $0 })
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
                    TranscriptPane(model: model, delete: { deleting = $0 })
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
                .background(Theme.surface)
            }
        }
        .alert("Delete all conversation history?", isPresented: $confirmingDeleteAll) {
            Button("Delete All History", role: .destructive) { Task { await model.deleteAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeleteHistoryWords.message)
        }
        .alert("Delete this conversation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { conversation in
            Button("Delete Conversation", role: .destructive) { Task { await model.delete(conversation) } }
            Button("Cancel", role: .cancel) {}
        } message: { conversation in
            Text("“\(conversation.title.clipped(60))” and its answers are deleted from this Mac. Activity keeps its record of what was done.")
        }
    }
}

/// Said wherever all history can be deleted (here and Settings › Privacy), so both promise the same thing.
enum DeleteHistoryWords {
    static let message: LocalizedStringKey =
        "Every conversation with the AI is deleted from this Mac. Your notes, reminders and Activity stay. This can't be undone."
}

// MARK: - The list

private struct ConversationList: View {
    @Bindable var model: ConversationsModel
    var deleteAll: () -> Void
    var delete: (ConversationSummary) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)
            list
        }
        .background(Theme.surfaceSunken)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversations").font(Theme.Font.title).foregroundStyle(Theme.ink).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text("Kept for \(model.keptDays) days", comment: "How long conversations with the AI are kept")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: Theme.Space.s)
                Menu {
                    Button("Delete All History…", role: .destructive, action: deleteAll)
                        .disabled(model.conversations.isEmpty && model.query.isEmpty)
                    Button("History Settings…") { model.services.openSettings(tab: .privacy) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                .accessibilityLabel("More")
            }
            searchBox
        }
        .padding(Theme.Space.l)
        // ⌘F, as everywhere on the Mac.
        .background {
            Button("Find") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Search", text: $model.query, prompt: Text("Search conversations"))
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .focused($searchFocused)
                .accessibilityLabel("Search conversations")
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 6)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
    }

    @ViewBuilder private var list: some View {
        if model.conversations.isEmpty {
            // With none at all the page shows its own empty state; here only a search can come up empty.
            VStack {
                Spacer()
                if model.loaded, !model.query.isEmpty {
                    EmptyState(title: "Nothing matches", message: "Try fewer or different words.", systemImage: "magnifyingglass", folk: "scout")
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.conversations) { conversation in
                            ConversationRow(conversation: conversation, selected: model.selectedId == conversation.id)
                                .id(conversation.id)
                                .onTapGesture { model.selectedId = conversation.id }
                                .accessibilityAction { model.selectedId = conversation.id }
                                .contextMenu {
                                    Button("Delete…") { delete(conversation) }
                                }
                        }
                    }
                    .padding(Theme.Space.s)
                }
                .focusable()
                .focusEffectDisabled()
                .onMoveCommand { direction in
                    move(direction)
                    if let id = model.selectedId { proxy.scrollTo(id) }
                }
                .onDeleteCommand { if let selected = model.selected { delete(selected) } }
            }
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        let ids = model.conversations.map(\.id)
        guard !ids.isEmpty else { return }
        let index = model.selectedId.flatMap { ids.firstIndex(of: $0) }
        switch direction {
        case .down: model.selectedId = ids[min((index ?? -1) + 1, ids.count - 1)]
        case .up: model.selectedId = ids[max((index ?? ids.count) - 1, 0)]
        default: break
        }
    }
}

private struct ConversationRow: View {
    var conversation: ConversationSummary
    var selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: conversation.title)
                .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(TimeText.short(conversation.updatedAt))
                Text("\(conversation.requests) requests", comment: "How many requests a conversation with the AI has")
                if conversation.spoken {
                    Image(systemName: "waveform").accessibilityLabel("Spoken")
                }
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.inkFaint)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.s + 2)
        .padding(.vertical, Theme.Space.s + 1)
        .background(selected ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - The conversation

private struct TranscriptPane: View {
    @Bindable var model: ConversationsModel
    var delete: (ConversationSummary) -> Void
    @FocusState private var replyFocused: Bool

    var body: some View {
        if let conversation = model.selected {
            VStack(spacing: 0) {
                header(conversation)
                Rectangle().fill(Theme.line).frame(height: 1)
                transcript
                composer
            }
            .background(Theme.surface)
        } else {
            Theme.surface
        }
    }

    private func header(_ conversation: ConversationSummary) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: conversation.title).font(Theme.Font.heading).foregroundStyle(Theme.ink).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text("Started \(TimeText.short(conversation.startedAt))", comment: "When a conversation with the AI began")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: Theme.Space.s)
            Button { delete(conversation) } label: { Image(systemName: "trash") }
                .buttonStyle(.sf(.secondary))
                .disabled(model.busy)
                .help("Delete this conversation")
                .accessibilityLabel("Delete this conversation")
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(model.lines) { line in
                        LineView(line: line, avatar: model.companionAvatar, name: model.companionName).id(line.id)
                    }
                    if let sending = model.sending, model.lines.last(where: \.isRequest)?.text != sending {
                        LineView(line: ConversationLine(id: "sending", kind: .request(spoken: false, attachment: nil), text: sending, at: Date()))
                    }
                    if let phase = model.phase {
                        HStack(spacing: 6) {
                            ReplyAvatar(image: model.companionAvatar)
                            ProgressView().controlSize(.small)
                            Text(verbatim: phase)
                        }
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                    if let error = model.error { InlineError(error: error) }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.l)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // The newest is at the bottom, as in any conversation.
            .onChange(of: model.lines) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: model.sending) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onAppear { proxy.scrollTo(Self.bottom, anchor: .bottom) }
        }
    }

    private static let bottom = "bottom"

    @ViewBuilder private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            if model.hasAI {
                HStack(alignment: .bottom, spacing: Theme.Space.s) {
                    TextField("Reply", text: $model.draft, prompt: Text("Reply in this conversation…"), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .lineLimit(1...6)
                        .focused($replyFocused)
                        .onSubmit { model.send() }
                        .disabled(model.busy)
                        .accessibilityLabel("Reply in this conversation")
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, Theme.Space.s)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
                    if model.runId != nil {
                        Button("Stop") { Task { await model.stop() } }
                            .buttonStyle(.sf(.secondary))
                            .keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button("Send") { model.send() }
                            .buttonStyle(.sf(.primary))
                            .disabled(model.busy || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.m)
            } else {
                HStack(spacing: Theme.Space.m) {
                    Text("Following up needs AI, which isn't set up yet.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: Theme.Space.s)
                    Button("AI Settings…") { model.services.openSettings(tab: .ai) }.buttonStyle(.sf(.secondary))
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.m)
            }
        }
        .background(Theme.surface)
    }
}

/// One line of a conversation: the person's words on the trailing side, the answers as text to read, the steps in
/// between as quiet lines.
private struct LineView: View {
    var line: ConversationLine
    var avatar: NSImage? = nil
    var name = ""

    var body: some View {
        switch line.kind {
        case .request(let spoken, let attachment):
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(verbatim: line.text).font(Theme.Font.body).foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, Theme.Space.s)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    HStack(spacing: 4) {
                        if let attachment { Label { Text(verbatim: attachment.clipped(40)) } icon: { Image(systemName: "paperclip") } }
                        if spoken { Image(systemName: "waveform").accessibilityLabel("Spoken") }
                        Text(TimeText.short(line.at))
                    }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
            }
            .accessibilityElement(children: .combine)
        case .reply:
            HStack(alignment: .top, spacing: Theme.Space.s + 2) {
                ReplyAvatar(image: avatar)
                VStack(alignment: .leading, spacing: 4) {
                    if !name.isEmpty { Text(verbatim: name).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted) }
                    AnswerText(text: line.text)
                    HStack(spacing: 4) {
                        Text(TimeText.short(line.at)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                        CopyButton(text: line.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .step(let done):
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: line.text).fixedSize(horizontal: false, vertical: true)
                    if let detail = line.detail {
                        Text(verbatim: detail).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } icon: {
                Image(systemName: done ? "checkmark.circle" : "xmark.circle")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.inkMuted)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(done ? Text("Done: \(line.text)") : Text("Not done: \(line.text). \(line.detail ?? "")"))
        case .note:
            Label {
                Text(verbatim: line.text).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.coral)
            }
            .font(Theme.Font.caption)
        }
    }
}

/// The companion's round profile picture beside what it said (CompanionArt.avatar).
private struct ReplyAvatar: View {
    var image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image).resizable().frame(width: 30, height: 30).accessibilityHidden(true)
        }
    }
}
