import SidefolkCore
import SwiftUI

/// The panel beside the companion: one input, a hint line, and the results, newest first. Each can be swiped
/// away with two fingers like a notification, "Clear all" empties them, and notices that need nothing fade.
struct AskView: View {
    @Bindable var model: AskModel
    var companionName: String
    /// The companion as drawn on the desktop, so the panel says who you're talking to.
    var portrait: NSImage?
    var hotkey: String
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How tall the results are, so the scroll area is as tall as them until it reaches its limit.
    @State private var resultsHeight: CGFloat = 0

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
        .onHover { model.hovering = $0 }
        // ⌘N, as for a new note: the next request starts a new conversation (D45).
        .background {
            Button("New conversation") { startFresh() }.keyboardShortcut("n", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }

    private func startFresh() {
        guard !model.busy else { return }
        model.actions?.startFresh(in: model, announce: true)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.xs) {
            if let portrait {
                // The face in a soft disc: the rig's canvas has room around the body.
                Image(nsImage: portrait).resizable().frame(width: 52, height: 52).offset(y: -1)
                    .frame(width: 26, height: 26)
                    .background(Theme.accentSoft)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                    .padding(.trailing, Theme.Space.xs)
            }
            Text(companionName).font(Theme.Font.captionStrong).foregroundStyle(Theme.ink).lineLimit(1)
                .layoutPriority(1)
            ModeChip(mode: model.mode) { model.actions?.openSettings(tab: .privacy) }
                .padding(.leading, Theme.Space.xs)
            Spacer(minLength: Theme.Space.xs)
            // The mode chip needs the room: the shortcut shows while there is nothing to clear.
            let clearable = model.hasResults && !model.busy
            if clearable {
                Button { model.clearResults() } label: {
                    Text("Clear all").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.line.opacity(0.7)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Remove every result below and start a new conversation")
                .padding(.trailing, Theme.Space.xs)
            }
            headerButton("house", help: "Open Sidefolk") { model.actions?.openHome() }
            headerButton("gearshape", help: "Settings") { model.actions?.openSettings(tab: nil) }
            if !clearable {
                Text(verbatim: hotkey).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                    .fixedSize()
                    .padding(.leading, Theme.Space.xs)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.m)
    }

    private func headerButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).imageScale(.small) }
            .buttonStyle(.sf(.plain))
            .help(help)
            .accessibilityLabel(help)
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                if model.voice != nil {
                    // The microphone is on (or the words are settling): the words below are what was heard.
                    Image(systemName: "waveform")
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.variableColor.iterative, isActive: isListening)
                        .accessibilityLabel("Listening")
                }
                TextField(placeholder, text: $model.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.input)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { model.submit() }
                    .disabled((model.busy && model.pendingQuestion == nil) || model.voice != nil)
                    .accessibilityLabel("Ask \(companionName)")
                if model.busy {
                    Button("Stop") { model.actions?.stop() }
                        .buttonStyle(.sf(.secondary))
                        .keyboardShortcut(".", modifiers: .command)
                }
            }
            if let attachment = model.attachment {
                HStack(spacing: 6) {
                    Chip(verbatim: attachment.label, tone: .accent, systemImage: icon(for: attachment))
                    Button { model.attachment = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkFaint)
                        .accessibilityLabel("Remove attachment")
                }
                if model.text.isEmpty, !model.busy {
                    // Drops work without AI: the common things are one click away.
                    ButtonRow {
                        Button("Save") { model.actions?.perform(.save, with: attachment, in: model) }.buttonStyle(.sf(.primary))
                        Button("Remind me…") { model.actions?.perform(.remind, with: attachment, in: model) }.buttonStyle(.sf(.secondary))
                        if canWatch(attachment) {
                            Button("Watch") { model.actions?.perform(.watch, with: attachment, in: model) }.buttonStyle(.sf(.secondary))
                        }
                        Button("Ask about it…") { model.actions?.perform(.ask, with: attachment, in: model) }.buttonStyle(.sf(.secondary))
                    }
                }
            }
            if let target = model.replyingTo {
                HStack(spacing: 6) {
                    Chip(verbatim: replyLabel(target), tone: .accent, systemImage: "arrowshape.turn.up.left")
                    Button { model.replyingTo = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkFaint)
                        .help("Don't reply")
                        .accessibilityLabel("Don't reply")
                }
            }
            if model.pendingReminderTitle != nil, !model.busy, let actions = model.actions {
                // Typing a time works in English; tapping works in every language.
                WhenChips(times: actions.reminderTimes()) { date in actions.remindPending(at: date, in: model) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: model.voice == nil ? "return" : "mic").imageScale(.small)
                    // Two lines at most: the hint stays short in English, and other languages run longer.
                    Text(verbatim: hintLine)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(model.hint == nil && !model.busy ? Theme.inkFaint : Theme.inkMuted)
                .accessibilityElement(children: .combine)
                if offersFresh {
                    Spacer(minLength: Theme.Space.s)
                    // Here rather than in the header: it says what continues, and the header has no room in longer languages.
                    Button(action: startFresh) { Label("New conversation", systemImage: "square.and.pencil") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .fixedSize()
                        .help(Text("\(String(localized: "New conversation")) (⌘N)", comment: "A button's name, then its shortcut"))
                }
            }
            .font(Theme.Font.hint)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }

    private var results: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(model.pinnedEntries) { entry in
                        EntryView(entry: entry, model: model)
                            .transition(arrival)
                    }
                    ForEach(model.visibleRequests) { request in
                        RequestView(request: request, model: model)
                            .transition(arrival)
                    }
                }
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3), value: model.entries)
                .padding(Theme.Space.m)
                .id(Self.top)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resultsHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(resultsHeight, 1), model.resultsMaxHeight))
            // Something new arrives at the top: show it, even when the older ones were scrolled to.
            .onChange(of: model.latestCaption) { withAnimation { scroller.scrollTo(Self.top, anchor: .top) } }
        }
    }

    private static let top = "top"

    /// New cards slide in from the input; with Reduce Motion they only fade in, like the companion's states.
    private var arrival: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity)
    }

    private var placeholder: LocalizedStringKey {
        if model.voice != nil { return "Listening…" }
        if model.pendingQuestion != nil { return "Type your answer…" }
        return model.replyingTo != nil ? "Type your reply…" : "Ask, remind, note, watch…"
    }

    /// Which answer the reply follows up, by the words it answered.
    private func replyLabel(_ target: ReplyTarget) -> String {
        guard let request = target.request else { return String(localized: "Reply to the answer") }
        return String(localized: "Reply about “\(request.clipped(36))”", comment: "Shown while typing a follow-up to an answer; the words are the request it answered")
    }

    private var isListening: Bool {
        if case .listening? = model.voice { return true }
        return false
    }

    /// While talking: what releasing will do, and whether it uses AI (D34).
    private func voiceHint(_ voice: VoiceInput) -> String {
        switch voice {
        case .starting:
            return String(localized: "Getting ready to listen…")
        case .preparing(let progress):
            return String(localized: "Downloading the speech model… \(Int(progress * 100))%", comment: "The number is a percentage")
        case .finishing:
            return String(localized: "Getting your last words…")
        case .listening(let basic):
            let words = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty, let hint = model.actions?.hint(for: words) else {
                return basic ? String(localized: "Listening (basic recognition)… Release to send, Esc to cancel")
                    : String(localized: "Listening… Release to send, Esc to cancel")
            }
            return String(localized: "Release: \(hint)", comment: "While talking: what releasing the talk key will do, e.g. “Release: Reminder · Today 17:00 · no AI”")
        }
    }

    /// A conversation with the AI is open and the input is free: the next request would continue it.
    private var offersFresh: Bool {
        model.thread != nil && !model.busy && model.voice == nil && model.text.isEmpty && model.replyingTo == nil
            && model.pendingQuestion == nil && model.pendingReminderTitle == nil && model.pendingWatch == nil && model.attachment == nil
    }

    private var hintLine: String {
        if let voice = model.voice { return voiceHint(voice) }
        if let question = model.pendingQuestion { return String(localized: "Your answer goes to: \(question.title)") }
        if model.busy { return model.phase ?? String(localized: "Working…") }
        if let hint = model.hint { return hint }
        if model.replyingTo != nil { return String(localized: "Your reply continues that conversation") }
        if model.pendingReminderTitle != nil { return String(localized: "When? Try “tomorrow 9am” or “in 2 hours”") }
        if model.pendingWatch != nil { return String(localized: "Which address? e.g. localhost:3000 or example.com/status") }
        if model.attachment != nil { return String(localized: "Pick what to do, or type what you want") }
        if offersFresh { return String(localized: "Your next request continues this conversation") }
        return String(localized: "Type something, or drop a file or link on me")
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

/// One request: its words, with a way to remove it, then what came of it. Two fingers sideways slide it away.
private struct RequestView: View {
    var request: AskModel.Request
    var model: AskModel
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: 4) {
                Text(verbatim: request.caption ?? "").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
                Spacer(minLength: 0)
                // A target the size of a fingertip, not of the glyph.
                Button { model.dismiss(request.id, toward: 1) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.line.opacity(hovering ? 0.8 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).foregroundStyle(Theme.inkMuted)
                .opacity(hovering ? 1 : 0)
                .help("Remove")
                .accessibilityLabel(request.caption.map { Text("Remove “\($0)”") } ?? Text("Remove this result"))
            }
            .frame(minHeight: 22)
            ForEach(request.entries) { entry in
                EntryView(entry: entry, model: model, request: request.caption, retry: request.caption == nil ? nil : { model.retry(request) })
            }
        }
        .contentShape(Rectangle())
        .offset(x: offset)
        .opacity(1 - min(abs(offset) / 360, 0.8))
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: offset)
        .onHover { inside in
            hovering = inside
            if inside { model.hoveredRequest = request.id } else if model.hoveredRequest == request.id { model.hoveredRequest = nil }
        }
    }

    private var offset: CGFloat { model.swipe?.id == request.id ? model.swipe!.offset : 0 }
}

private struct EntryView: View {
    var entry: AskEntry
    var model: AskModel
    /// The words of the request this came from, if any.
    var request: String? = nil
    /// Sends the request again, replacing these cards (failed requests only).
    var retry: (() -> Void)? = nil

    var body: some View {
        switch entry.content {
        case .result(let card, let activityId, let undo):
            ResultCardView(card: card, look: card.kind == .extensionResult ? card.refId.flatMap { model.extensionLooks[$0] } : nil, actions: {
                if undo, let activityId {
                    Button("Undo") { model.actions?.undo(activityId: activityId, in: model) }.buttonStyle(.sf(.secondary))
                }
                if PrivacyPane.isKnown(card.url) {
                    Button("Open System Settings") { model.actions?.open(card: card) }.buttonStyle(.sf(.primary))
                } else if SettingsLink.isKnown(card.url) {
                    Button("Set Your Location…") { model.actions?.open(card: card) }.buttonStyle(.sf(.primary))
                } else if card.kind != .extensionResult, card.refId != nil || card.url != nil {
                    Button("Open") { model.actions?.open(card: card) }.buttonStyle(.sf(.secondary))
                }
            })
        case .list(let title, let cards):
            SFCard(accent: Theme.folkColor("pip")) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(Text(verbatim: title))
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
        case .answer(let text, let canThinkHarder, let tainted, let thread):
            AnswerCard(entry: entry.id, text: text, canThinkHarder: canThinkHarder, tainted: tainted, thread: thread, request: request, model: model)
        case .approval(let request):
            ApprovalCard(request: request, look: request.extensionId.flatMap { model.extensionLooks[$0] }) { decision in
                model.actions?.answer(approval: request, decision: decision)
            }
        case .error(let error, let retryable):
            SFCard(accent: Theme.coral) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.message).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let r = error.recovery {
                        Text(r).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    if retryable, let retry {
                        HStack(spacing: 6) {
                            Button("Try again", action: retry).buttonStyle(.sf(.secondary))
                            Button("AI settings…") { model.actions?.openSettings(tab: .ai) }.buttonStyle(.sf(.plain))
                        }
                    }
                }
            }
        case .needsBrain(let request):
            NoAICard(request: request, entry: entry.id, model: model)
        case .question(let item):
            QuestionCard(item: item) { actionId in model.actions?.answer(question: item, actionId: actionId) }
        case .info(let text):
            Text(text).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
        case .spoken(let line, let muted):
            SpokenLineView(line: line, muted: muted)
        case .doneWithoutAsking(let summary, let fullAccess):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: fullAccess ? GuardMode.fullAccess.symbol : GuardMode.auto.symbol)
                    .foregroundStyle(fullAccess ? Theme.danger : Theme.aqua)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(fullAccess ? GuardMode.fullAccess.title : GuardMode.auto.title)
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        + Text(verbatim: " · ").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        + Text("done without asking").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
            }
            .accessibilityElement(children: .combine)
        case .skipped(let summary, let why):
            SFCard(accent: Theme.sun) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "clock.badge.xmark").foregroundStyle(Theme.inkMuted).accessibilityHidden(true)
                        Text(summary).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(why).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    Button("Open Now") { model.actions?.openNow() }.buttonStyle(.sf(.secondary))
                }
            }
        }
    }
}

/// The words said aloud, always on screen too (D34); a muted speaker when they stayed text.
private struct SpokenLineView: View {
    var line: String
    var muted: VoicePolicy.Silence?

    var body: some View {
        Label {
            Text(verbatim: line).italic().fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: muted == nil ? "speaker.wave.2" : "speaker.slash")
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.inkMuted)
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(muted == nil ? Text("Said aloud: \(line)") : Text("Not said aloud: \(line)"))
    }

    private var help: Text {
        switch muted {
        case nil: Text("Said aloud")
        case .quiet?: Text("Not said aloud: quiet mode is on")
        case .micInUse?: Text("Not said aloud: another app is using the microphone")
        case .typing?: Text("Not said aloud: you were typing")
        }
    }
}

struct ResultCardView<Actions: View>: View {
    var card: ResultCard
    /// The extension that answered, drawn by its icon instead of the generic symbol.
    var look: ExtensionLook? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        SFCard(accent: Self.accent(for: card.kind)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let look {
                        ExtensionBadge(look: look, size: 18)
                    } else {
                        Image(systemName: card.itemKind.map(ItemKindStyle.symbol) ?? Self.symbol(for: card.kind))
                            .foregroundStyle(Self.accent(for: card.kind))
                    }
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
                ButtonRow { actions }
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

/// An AI answer. A long one opens on its first lines and unfolds in place; every answer can be replied to, in its
/// own conversation, and opened in Conversations (D45).
private struct AnswerCard: View {
    var entry: AskEntry.ID
    var text: String
    var canThinkHarder: Bool
    var tainted: Bool
    var thread: String?
    var request: String?
    var model: AskModel
    @State private var expanded = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    static let collapsedLines = 8

    var body: some View {
        SFCard(accent: Theme.aqua) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                AnswerText(text: text)
                    .lineLimit(expanded ? nil : Self.collapsedLines)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                    .background(alignment: .top) {
                        // The whole answer, unseen, so the card knows whether its first lines cut it short.
                        if !expanded {
                            AnswerText(text: text).lineLimit(nil).hidden()
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                                .accessibilityHidden(true)
                        }
                    }
                if expanded || fullHeight > shownHeight + 1 {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Label(expanded ? "Show less" : "Show all", systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(Theme.Font.caption)
                    }
                    .buttonStyle(.sf(.plain))
                }
                HStack(alignment: .top, spacing: Theme.Space.xs) {
                    ButtonRow {
                        Button("Reply") { model.reply(to: entry, thread: thread, request: request) }
                            .buttonStyle(.sf(asks || replying ? .primary : .secondary))
                            .accessibilityAddTraits(replying ? .isSelected : [])
                        Button("Save") { model.actions?.saveAnswer(text, tainted: tainted, in: model) }.buttonStyle(.sf(.secondary))
                        if canThinkHarder {
                            Button("Think harder") { model.submitThinkHarder(about: text) }.buttonStyle(.sf(.secondary))
                        }
                    }
                    Spacer(minLength: 0)
                    CopyButton(text: text)
                    if let thread {
                        Button { model.actions?.openConversation(thread) } label: {
                            Image(systemName: "bubble.left.and.text.bubble.right").imageScale(.small)
                        }
                        .buttonStyle(.sf(.plain))
                        .help("Open in Conversations")
                        .accessibilityLabel("Open in Conversations")
                    }
                }
            }
        }
    }

    private var replying: Bool { model.replyingTo?.entry == entry }

    /// The answer ends with a question (in any script), so the next thing to do is answer it.
    private var asks: Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return "?？؟".contains(last)
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
                    ButtonRow { options }
                }
                Text(item.actions.isEmpty ? "Type your answer above and press Return." : "Or type a different answer above.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private var options: some View {
        ForEach(item.actions, id: \.id) { action in
            Button { answer(action.id) } label: { Text(verbatim: action.title) }
                .buttonStyle(.sf(action.isPrimary ? .primary : .secondary))
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

/// One tap for the usual answers to "When?", and a date picker for any other moment.
private struct WhenChips: View {
    var times: [(label: String, date: Date)]
    var choose: (Date) -> Void
    @State private var picking = false
    @State private var custom = Date().addingTimeInterval(3600)

    var body: some View {
        // One row when it fits; longer languages get two.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips(times); pick }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { chips(Array(times.prefix(2))) }
                HStack(spacing: 6) { chips(Array(times.dropFirst(2))); pick }
            }
        }
    }

    private func chips(_ times: [(label: String, date: Date)]) -> some View {
        ForEach(times, id: \.label) { time in
            Button { choose(time.date) } label: { Text(verbatim: time.label) }.buttonStyle(.sf(.secondary)).fixedSize()
                .help(Text(verbatim: TimeText.short(time.date)))
        }
    }

    private var pick: some View {
        Button("Pick…") { picking = true }.buttonStyle(.sf(.secondary)).fixedSize()
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                VStack(alignment: .trailing, spacing: Theme.Space.s) {
                    DatePicker("When", selection: $custom, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    Button("Remind me") {
                        picking = false
                        choose(custom)
                    }
                    .buttonStyle(.sf(.primary))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(Theme.Space.m)
            }
    }
}
