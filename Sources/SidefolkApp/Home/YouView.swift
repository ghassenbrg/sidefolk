import SidefolkCore
import SwiftUI

/// Notebook › You (D84): what Sidefolk keeps in mind about the person, as a profile. Their facts with where each came
/// from, Edit and Forget; what another agent suggested waits at the top, out of answers, with Keep and Forget; and one
/// honest line about how the facts are used. When each fact was last used isn't kept, so it isn't shown (D84 rule 9).
struct YouView: View {
    @Bindable var model: YouModel
    @State private var draft = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        HomePage {
            header
            if let problem = model.problem { InlineError(error: problem) }
            if model.adding { addField }
            ForEach(model.suggestions) { item in SuggestionCard(item: item, model: model) }
            if empty {
                EmptyState(title: Text("\(model.companionName) doesn't know you yet"),
                           message: Text("Tell it something worth keeping in mind, like “I prefer short answers” or “I work in Swift”. Say it in the Say bar (“remember that…”) or add it here."),
                           systemImage: "person.crop.circle", folk: "pip", actionTitle: Text("Add a fact")) {
                    model.adding = true
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Space.xl)
            } else if !model.facts.isEmpty {
                RowsCard {
                    ForEach(model.facts) { item in FactRow(item: item, model: model) }
                }
            }
            HowItIsUsed(companion: model.companionName)
        }
        .onChange(of: model.adding) { if model.adding { addFocused = true } }
    }

    private var empty: Bool { model.loaded && model.facts.isEmpty && model.suggestions.isEmpty && !model.adding }

    private var header: some View {
        WrapRow(minimum: 380, spacing: Theme.Space.l, alignment: .top) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                PersonAvatar(size: 72)
                    .overlay(Circle().strokeBorder(Theme.surfaceRaised, lineWidth: 3))
                    .elevation(.e1, radius: 36)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(verbatim: NSFullUserName().isEmpty ? String(localized: "You") : NSFullUserName().split(separator: " ").first.map(String.init) ?? "")
                        .font(Theme.Font.display).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                        .homePageTitle()
                    summary.font(.system(size: 15 * ThemeStore.shared.style.tokens.type.scale)).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Empty, the page's one primary is the empty state's own.
            if !empty {
                Button { model.adding = true } label: { Label("Add a fact", systemImage: "plus") }
                    .buttonStyle(.sf(.primary, size: .large))
                    .fixedSize()
            }
        }
    }

    private var summary: Text {
        switch model.count {
        case 0: Text("\(model.companionName) keeps nothing in mind about you yet.")
        case 1: Text("\(model.companionName) keeps one thing in mind about you. It shapes its answers, and never leaves this Mac unless an answer needs the AI.")
        default: Text("\(model.companionName) keeps \(model.count) things in mind about you. They shape its answers, and never leave this Mac unless an answer needs the AI.")
        }
    }

    private var addField: some View {
        HStack(spacing: Theme.Space.s) {
            TextField("New fact", text: $draft, prompt: Text(verbatim: "")).fieldHint(Text("Something to keep in mind, like “I prefer short answers”"), showing: draft.isEmpty)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .focused($addFocused)
                .onSubmit(add)
                .onExitCommand { cancelAdd() }
                .padding(.horizontal, Theme.Space.m)
                .frame(height: Theme.Size.field + 4)
                .fieldChrome(focused: addFocused)
            Button("Cancel", action: cancelAdd).buttonStyle(.sf(.secondary))
            Button("Keep in mind", action: add).buttonStyle(.sf(.primary))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func add() {
        let words = draft
        Task { if await model.save(words) { draft = "" } }
    }

    private func cancelAdd() {
        draft = ""
        model.adding = false
    }
}

/// A fact: its words, then where it came from and when; Edit and Forget on hover (and for VoiceOver), editing in place.
private struct FactRow: View {
    var item: NotebookItem
    var model: YouModel
    @State private var text = ""
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        if model.editing == item.id {
            HStack(spacing: Theme.Space.s) {
                TextField("Fact", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit(save)
                    .onExitCommand { model.editing = nil }
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
                    .fieldChrome(focused: focused)
                Button("Cancel") { model.editing = nil }.buttonStyle(.sf(.secondary))
                Button("Save", action: save).buttonStyle(.sf(.primary))
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .onAppear {
                text = ProfileFacts.text(item)
                focused = true
            }
        } else {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: item.title).font(Theme.Font.headline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    if !item.body.isEmpty, !item.title.hasSuffix("…") {
                        Text(verbatim: item.body).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).lineLimit(3)
                    }
                    Label {
                        Text(verbatim: "\(model.origin(item)) · \(item.createdAt.formatted(.dateTime.day().month(.abbreviated)))")
                    } icon: {
                        Image(systemName: model.originSymbol(item))
                    }
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Theme.Space.xs) {
                    Button { model.editing = item.id } label: { Image(systemName: "pencil") }
                        .help("Edit").accessibilityLabel("Edit")
                    Button { Task { await model.forget(item) } } label: { Image(systemName: "trash") }
                        .help("Forget").accessibilityLabel("Forget")
                }
                .buttonStyle(.sf(.quiet))
                .opacity(hovered ? 1 : 0)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .background(hovered ? Theme.ink.opacity(0.03) : .clear)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text("Edit")) { model.editing = item.id }
            .accessibilityAction(named: Text("Forget")) { Task { await model.forget(item) } }
            .contextMenu {
                Button("Edit") { model.editing = item.id }
                Button("Forget", role: .destructive) { Task { await model.forget(item) } }
            }
        }
    }

    private func save() {
        let words = text
        Task { await model.save(words, editing: item) }
    }
}

/// What another agent suggested about the person (A7): who and when, that it isn't used until kept, Forget and Keep.
private struct SuggestionCard: View {
    var item: NotebookItem
    var model: YouModel

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            FolkAvatar(name: "byte", size: Theme.Size.avatar + 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(model.origin(item)) · \(TimeText.short(item.createdAt)) · ")
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                    + Text("not used until you keep it", comment: "A fact another agent suggested").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                Text(verbatim: ProfileFacts.text(item)).font(Theme.Font.headline).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Forget") { Task { await model.forget(item) } }.buttonStyle(.sf(.quiet))
            Button("Keep") { Task { await model.keep(item) } }.buttonStyle(.sf(.secondary))
        }
        .padding(Theme.Space.l)
        .background(Theme.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
    }
}

/// How the facts are used, in one place and plain words.
private struct HowItIsUsed: View {
    var companion: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: "checkmark.shield").font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text("How \(companion) uses this").font(Theme.Font.headline).foregroundStyle(Theme.ink)
                Text("Only facts you said or kept go into answers. What agents suggest waits above until you keep it. Forgotten facts sit in the Trash for 30 days.")
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
