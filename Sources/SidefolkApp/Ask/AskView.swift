import SidefolkCore
import SwiftUI

/// The panel beside the companion: one input, a hint line, and up to three result cards.
struct AskView: View {
    @Bindable var model: AskModel
    var companionName: String
    var hotkey: String
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            input
            if !model.entries.isEmpty || model.busy {
                Divider().overlay(Theme.line)
                results
            }
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .background(Theme.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.line.opacity(0.8)))
        .onAppear { inputFocused = true }
        .onChange(of: model.focusRequest) { inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Text(companionName).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
            Spacer()
            Button { model.actions?.openHome() } label: {
                Image(systemName: "house").imageScale(.small)
            }
            .buttonStyle(.sfPlain)
            .help("Open Sidefolk")
            .accessibilityLabel("Open Sidefolk")
            Text(hotkey).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.m)
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                TextField(model.pendingQuestion == nil ? "Ask, remind, note, watch…" : "Type your answer…", text: $model.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.input)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { model.submit() }
                    .disabled(model.busy && model.pendingQuestion == nil)
                    .accessibilityLabel("Ask \(companionName)")
                if model.busy {
                    Button("Stop") { model.actions?.stop() }
                        .buttonStyle(.sf(.secondary))
                        .keyboardShortcut(".", modifiers: .command)
                }
            }
            if let attachment = model.attachment {
                HStack(spacing: 6) {
                    Chip(text: attachment.label, systemImage: icon(for: attachment))
                    Button { model.attachment = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkFaint)
                        .accessibilityLabel("Remove attachment")
                }
                if model.text.isEmpty, !model.busy {
                    // Drops work without AI: the common things are one click away.
                    HStack(spacing: 6) {
                        Button("Save") { model.actions?.perform(.save, with: attachment, in: model) }.buttonStyle(.sf(.primary))
                        Button("Remind me…") { model.actions?.perform(.remind, with: attachment, in: model) }.buttonStyle(.sf(.secondary))
                        if canWatch(attachment) {
                            Button("Watch") { model.actions?.perform(.watch, with: attachment, in: model) }.buttonStyle(.sf(.secondary))
                        }
                        Button("Ask…") { model.actions?.perform(.ask, with: attachment, in: model) }.buttonStyle(.sf(.secondary))
                    }
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "return").imageScale(.small)
                Text(hintLine)
                    .lineLimit(1)
            }
            .font(Theme.Font.hint)
            .foregroundStyle(model.hint == nil && !model.busy ? Theme.inkFaint : Theme.inkMuted)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(model.visibleEntries) { entry in
                if let caption = entry.caption {
                    Text(caption).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
                }
                EntryView(entry: entry, model: model)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.entries)
        .padding(Theme.Space.m)
    }

    private var hintLine: String {
        if let question = model.pendingQuestion { return "Your answer goes to: \(question.title)" }
        if model.busy { return model.phase ?? "Working…" }
        if let hint = model.hint { return hint }
        if model.pendingReminderTitle != nil { return "When? Try “tomorrow 9am” or “in 2 hours”" }
        if model.pendingWatch != nil { return "Which address? e.g. localhost:3000 or example.com/status" }
        if model.attachment != nil { return "Pick what to do, or type what you want" }
        return "Type something, or drop a file or link on me"
    }

    private func canWatch(_ a: Attachment) -> Bool {
        switch a.kind {
        case .url, .file: true
        case .text: false
        }
    }

    private func icon(for a: Attachment) -> String {
        switch a.kind {
        case .file: "doc"
        case .url: "link"
        case .text: "text.quote"
        }
    }
}

private struct EntryView: View {
    var entry: AskEntry
    var model: AskModel

    var body: some View {
        switch entry.content {
        case .result(let card, let activityId, let undo):
            ResultCardView(card: card, actions: {
                if undo, let activityId {
                    Button("Undo") { model.actions?.undo(activityId: activityId, in: model) }.buttonStyle(.sf(.secondary))
                }
                if card.refId != nil || card.url != nil {
                    Button("Open") { model.actions?.open(card: card) }.buttonStyle(.sf(.secondary))
                }
            })
        case .list(let title, let cards):
            SFCard(accent: Theme.folkColor("pip")) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: title)
                    if cards.isEmpty {
                        Text("Nothing found.").font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    }
                    ForEach(Array(cards.prefix(6).enumerated()), id: \.offset) { _, card in
                        Button { model.actions?.open(card: card) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(card.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                                if let s = card.subtitle { Text(s).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .answer(let text, let canThinkHarder, let tainted):
            AnswerCard(text: text, canThinkHarder: canThinkHarder, tainted: tainted, model: model)
        case .approval(let request):
            ApprovalCard(request: request) { decision in model.actions?.answer(approval: request, decision: decision) }
        case .error(let error, let retryable):
            SFCard(accent: Theme.coral) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.message).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let r = error.recovery {
                        Text(r).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    if retryable, let caption = entry.caption {
                        HStack(spacing: 6) {
                            Button("Try again") { model.actions?.retry(caption, in: model) }.buttonStyle(.sf(.secondary))
                            Button("AI settings…") { model.actions?.openSettingsAI() }.buttonStyle(.sf(.plain))
                        }
                    }
                }
            }
        case .needsBrain(let text, let guess):
            SFCard(accent: Theme.folkColor("byte")) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(guess == nil ? "That needs AI, which isn't set up." : "That needs AI — or I can do this:")
                        .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    if let guess {
                        Button {
                            model.actions?.remind(guess, in: model)
                        } label: {
                            Label("\(guess.label): \(guess.title)", systemImage: "alarm").lineLimit(1)
                        }
                        .buttonStyle(.sf(.primary))
                    }
                    HStack(spacing: 6) {
                        Button("Save as task") { model.actions?.saveAsTask(text, in: model) }.buttonStyle(.sf(guess == nil ? .primary : .secondary))
                        Button("Save as note") { model.actions?.saveAnswer(text, tainted: false, in: model) }.buttonStyle(.sf(.secondary))
                        Spacer(minLength: 0)
                        Button("Set up AI…") { model.actions?.openSettingsAI() }.buttonStyle(.sf(.plain))
                    }
                }
            }
        case .question(let item):
            QuestionCard(item: item) { actionId in model.actions?.answer(question: item, actionId: actionId) }
        case .info(let text):
            Text(text).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
        }
    }
}

struct ResultCardView<Actions: View>: View {
    var card: ResultCard
    @ViewBuilder var actions: Actions

    var body: some View {
        SFCard(accent: Self.accent(for: card.kind)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: card.itemKind.map(ItemKindStyle.symbol) ?? Self.symbol(for: card.kind)).foregroundStyle(Self.accent(for: card.kind))
                    Text(card.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subtitle = card.subtitle {
                    Text(subtitle).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = card.detail {
                    Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) { actions }
            }
        }
        .accessibilityElement(children: .contain)
    }

    static func accent(for kind: ResultCard.Kind) -> Color {
        switch kind {
        case .note, .collection, .memory, .list: Theme.folkColor("pip")
        case .reminder: Theme.folkColor("tempo")
        case .watcher: Theme.folkColor("scout")
        case .file, .web, .info: Theme.aqua
        case .extensionResult: Theme.folkColor("byte")
        }
    }

    static func symbol(for kind: ResultCard.Kind) -> String {
        switch kind {
        case .note: "note.text"
        case .collection: "folder"
        case .memory: "person.text.rectangle"
        case .list: "list.bullet"
        case .reminder: "alarm"
        case .watcher: "binoculars"
        case .file: "doc"
        case .web: "globe"
        case .info: "info.circle"
        case .extensionResult: "puzzlepiece.extension"
        }
    }
}

private struct AnswerCard: View {
    var text: String
    var canThinkHarder: Bool
    var tainted: Bool
    var model: AskModel
    @State private var expanded = false

    var body: some View {
        SFCard(accent: Theme.aqua) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(markdown).font(Theme.Font.body).foregroundStyle(Theme.ink)
                    .lineLimit(expanded ? nil : 8).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    // Links in answers open only as web pages; anything else (file:, app schemes) is ignored.
                    .environment(\.openURL, OpenURLAction { url in
                        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil else { return .discarded }
                        return .systemAction
                    })
                HStack(spacing: 6) {
                    if text.count > 400 {
                        Button(expanded ? "Less" : "More") { expanded.toggle() }.buttonStyle(.sf(.secondary))
                    }
                    Button("Save") { model.actions?.saveAnswer(text, tainted: tainted, in: model) }.buttonStyle(.sf(.secondary))
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }.buttonStyle(.sf(.secondary))
                    if canThinkHarder {
                        Button("Think harder") { model.submitThinkHarder(about: text) }.buttonStyle(.sf(.secondary))
                    }
                }
            }
        }
    }

    /// Inline markdown only; links are shown, remote images are never loaded.
    private var markdown: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// A question from Sidefolk's own agent: buttons for its options, or type the answer in the input.
private struct QuestionCard: View {
    var item: AttentionItem
    var answer: (String) -> Void

    var body: some View {
        SFCard(accent: Theme.aqua) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "questionmark.bubble").foregroundStyle(Theme.aqua)
                    Text(item.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
                if let body = item.body {
                    Text(body).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
                if !item.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.actions, id: \.id) { action in
                            Button(action.title) { answer(action.id) }.buttonStyle(.sf(action.isPrimary ? .primary : .secondary))
                        }
                    }
                }
                Text(item.actions.isEmpty ? "Type your answer above and press Return." : "Or type a different answer above.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            }
        }
    }
}

extension AskModel {
    /// Re-asks the last request with the smart model.
    func submitThinkHarder(about _: String) {
        guard let lastPrompt = entries.last(where: { $0.caption != nil })?.caption else { return }
        text = lastPrompt
        submit(thinkHarder: true)
    }
}
