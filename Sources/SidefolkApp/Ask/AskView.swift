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
                Image(systemName: "square.grid.2x2").imageScale(.small)
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
                TextField("Ask, remind, note, watch…", text: $model.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.input)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { model.submit() }
                    .disabled(model.busy)
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
            }
            HStack(spacing: 4) {
                Image(systemName: "return").imageScale(.small)
                Text(model.busy ? (model.phase ?? "Working…") : (model.hint ?? (model.pendingReminderTitle != nil
                    ? "When? Try “tomorrow 9am” or “in 2 hours”" : "Type something, or drop a file or link on me")))
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
            if model.entries.count > AskModel.visibleLimit {
                Button("Earlier (\(model.entries.count - AskModel.visibleLimit)) ›") { model.actions?.openHome() }
                    .buttonStyle(.sfPlain).font(Theme.Font.caption)
            }
        }
        .animation(.spring(duration: 0.3), value: model.entries)
        .padding(Theme.Space.m)
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
        case .answer(let text, let canThinkHarder):
            AnswerCard(text: text, canThinkHarder: canThinkHarder, model: model)
        case .approval(let request):
            ApprovalCard(request: request) { decision in model.actions?.answer(approval: request, decision: decision) }
        case .error(let error, _):
            SFCard(accent: Theme.coral) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.message).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    if let r = error.recovery { Text(r).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted) }
                }
            }
        case .needsBrain(let text):
            SFCard(accent: Theme.folkColor("byte")) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("I need a brain for that.").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    Text("Notes, reminders and watches work without one. For questions, connect Claude Code, an API key or Ollama.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    HStack(spacing: 6) {
                        Button("Set up AI…") { model.actions?.openSettingsAI() }.buttonStyle(.sf(.primary))
                        Button("Keep as a note") { model.actions?.saveAnswer(text, in: model) }.buttonStyle(.sf(.secondary))
                    }
                }
            }
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
                    Image(systemName: Self.symbol(for: card.kind)).foregroundStyle(Self.accent(for: card.kind))
                    Text(card.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(2)
                }
                if let subtitle = card.subtitle {
                    Text(subtitle).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
                if let detail = card.detail {
                    Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(4)
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
    var model: AskModel
    @State private var expanded = false

    var body: some View {
        SFCard(accent: Theme.aqua) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(markdown).font(Theme.Font.body).foregroundStyle(Theme.ink)
                    .lineLimit(expanded ? nil : 8).textSelection(.enabled)
                HStack(spacing: 6) {
                    if text.count > 400 {
                        Button(expanded ? "Less" : "More") { expanded.toggle() }.buttonStyle(.sf(.secondary))
                    }
                    Button("Save") { model.actions?.saveAnswer(text, in: model) }.buttonStyle(.sf(.secondary))
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

extension AskModel {
    /// Re-asks the last request with the smart model.
    func submitThinkHarder(about _: String) {
        guard let lastPrompt = entries.last(where: { $0.caption != nil })?.caption else { return }
        text = lastPrompt
        submit(thinkHarder: true)
    }
}
