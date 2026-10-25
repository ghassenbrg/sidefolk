import SidefolkCore
import SwiftUI

/// Home › a collection: its items on the left, the selected one in the editor on the right.
struct NotebookView: View {
    @Bindable var model: NotebookModel
    var collection: NotebookCollection

    var body: some View {
        HSplitView {
            ItemList(model: model, collection: collection)
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 440)
            NotebookEditor(model: model)
                .frame(minWidth: 340, maxWidth: .infinity)
        }
        .background(Theme.surface)
    }
}

/// What kind of item it is, as an icon and a word.
enum ItemKindStyle {
    static func symbol(_ kind: NotebookItem.Kind) -> String {
        switch kind {
        case .note: "note.text"
        case .idea: "lightbulb"
        case .task: "checkmark.circle"
        case .link: "link"
        }
    }

    static func title(_ kind: NotebookItem.Kind) -> String {
        switch kind {
        case .note: "Note"
        case .idea: "Idea"
        case .task: "Task"
        case .link: "Link"
        }
    }
}

// MARK: - Item list

private struct ItemList: View {
    @Bindable var model: NotebookModel
    var collection: NotebookCollection
    @FocusState private var listFocused: Bool

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
                    Text(collection.name).font(Theme.Font.title).foregroundStyle(Theme.ink).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(countLine).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: Theme.Space.s)
                Button {
                    Task { await model.newItem() }
                } label: {
                    Label("New \(ItemKindStyle.title(model.filter.kind ?? .note).lowercased())", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.sf(.secondary))
                .keyboardShortcut("n", modifiers: .command)
                .help("New \(ItemKindStyle.title(model.filter.kind ?? .note).lowercased()) (⌘N)")
            }
            if collection.kind == .profile {
                Label("Sidefolk keeps these in mind in every conversation. Change or delete anything.",
                      systemImage: "person.crop.circle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Space.s + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            if collection.kind != .profile {
                Picker("Show", selection: $model.filter) {
                    ForEach(NotebookModel.KindFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            searchField
        }
        .padding(Theme.Space.l)
    }

    private var countLine: String {
        let n = model.counts[collection.id] ?? 0
        return n == 0 ? "Empty" : Describe.count(n, "item")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Search", text: $model.query, prompt: Text("Search \(collection.name)"))
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .accessibilityLabel("Search \(collection.name)")
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
        if model.items.isEmpty {
            VStack(spacing: 0) {
                Spacer()
                EmptyState(title: emptyTitle, message: emptyMessage, systemImage: emptySymbol)
                if !searching {
                    Button("Write a \(ItemKindStyle.title(newKind).lowercased())") { Task { await model.newItem() } }
                        .buttonStyle(.sfPrimary)
                        .padding(.top, -Theme.Space.l)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.items) { item in
                            ItemRow(item: item, selected: model.selectedId == item.id, model: model)
                                .id(item.id)
                        }
                    }
                    .padding(Theme.Space.s)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onMoveCommand { direction in
                    moveSelection(direction)
                    if let id = model.selectedId { proxy.scrollTo(id) }
                }
                .onDeleteCommand {
                    if let item = model.items.first(where: { $0.id == model.selectedId }) {
                        Task { await model.moveToTrash(item) }
                    }
                }
            }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let ids = model.items.map(\.id)
        guard !ids.isEmpty else { return }
        let index = model.selectedId.flatMap { ids.firstIndex(of: $0) }
        switch direction {
        case .down: model.select(ids[min((index ?? -1) + 1, ids.count - 1)])
        case .up: model.select(ids[max((index ?? ids.count) - 1, 0)])
        default: break
        }
    }

    private var searching: Bool { !model.query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var newKind: NotebookItem.Kind { model.filter.kind ?? .note }

    private var emptyTitle: String {
        if searching { return "Nothing matches" }
        if collection.kind == .profile { return "Nothing about you yet" }
        return model.filter == .all ? "Nothing here yet" : "No \(model.filter.title.lowercased()) here"
    }

    private var emptyMessage: String {
        if searching { return "Try fewer words, or look in another collection." }
        if collection.kind == .profile { return "Tell me things like “I prefer short answers” and I'll keep them here." }
        if collection.kind == .inbox { return "Anything you save without saying where lands here." }
        return "Write one here, or ask me to save something to \(collection.name)."
    }

    private var emptySymbol: String {
        if searching { return "magnifyingglass" }
        return collection.kind == .profile ? "person.crop.circle" : "tray"
    }
}

private struct ItemRow: View {
    var item: NotebookItem
    var selected: Bool
    var model: NotebookModel

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s + 2) {
            if item.kind == .task {
                CheckCircle(checked: item.status == .done, label: item.status == .done ? "Mark “\(displayTitle)” not done" : "Mark “\(displayTitle)” done") {
                    Task { await model.toggleDone(item) }
                }
                .padding(.top, 1)
            } else {
                Image(systemName: ItemKindStyle.symbol(item.kind))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 18)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(item.status == .done ? Theme.inkMuted : (item.title.isEmpty ? Theme.inkFaint : Theme.ink))
                    .strikethrough(item.status == .done, color: Theme.inkFaint)
                    .lineLimit(2)
                if let snippet {
                    Text(snippet).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .lineLimit(item.kind == .link ? 1 : 2)
                        .truncationMode(item.kind == .link ? .middle : .tail)
                }
                HStack(spacing: 6) {
                    Text(TimeText.short(item.updatedAt))
                    ForEach(item.tagList.prefix(3), id: \.self) { Text("#" + $0) }
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
                if let who = Describe.source(item.source) {
                    Chip("from \(who)", tone: .accent, systemImage: "sparkles")
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.s + 2)
        .padding(.vertical, Theme.Space.s + 1)
        .background(selected ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { model.select(item.id) }
        .contextMenu {
            if item.kind == .task {
                Button(item.status == .done ? "Mark not done" : "Mark done") { Task { await model.toggleDone(item) } }
            }
            Button("Move to Trash") { Task { await model.moveToTrash(item) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.select(item.id) }
    }

    private var displayTitle: String { item.title.isEmpty ? "Untitled" : item.title }

    private var snippet: String? {
        if item.kind == .link, let url = item.url {
            return url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        }
        let line = item.body.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return line?.isEmpty == false ? line : nil
    }
}

// MARK: - Editor

private struct NotebookEditor: View {
    @Bindable var model: NotebookModel
    @FocusState private var focus: Field?
    private enum Field { case title, body }

    var body: some View {
        if let draft = Binding($model.draft) {
            VStack(alignment: .leading, spacing: 0) {
                topBar(draft)
                Rectangle().fill(Theme.line).frame(height: 1)
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    TextField("Title", text: draft.title, prompt: Text("Untitled"), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1...3)
                        .focused($focus, equals: .title)
                        .onSubmit { focus = .body }
                        .accessibilityLabel("Title")
                    meta(draft.wrappedValue)
                    if draft.wrappedValue.kind == .link { linkField(draft) }
                    tagsField(draft)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    TextEditor(text: draft.body)
                        .font(Theme.Font.body)
                        .lineSpacing(3)
                        .foregroundStyle(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .focused($focus, equals: .body)
                        .frame(maxHeight: .infinity)
                        // The text view insets its text by 5 points; pull it back in line with the title.
                        .padding(.horizontal, -5)
                        .accessibilityLabel("Text")
                        .overlay(alignment: .topLeading) {
                            if draft.wrappedValue.body.isEmpty {
                                Text("Write anything…").font(Theme.Font.body).foregroundStyle(Theme.inkFaint)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                }
                .padding(.horizontal, Theme.Space.xl + 4)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.l)
            }
            .background(Theme.surface)
            .id(draft.wrappedValue.id)
            .onAppear { if draft.wrappedValue.title.isEmpty { focus = .title } }
        } else {
            VStack {
                Spacer()
                EmptyState(title: "Nothing selected", message: "Pick something on the left, or press ⌘N to write something new.",
                           systemImage: "note.text")
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
        }
    }

    private func topBar(_ draft: Binding<NotebookItem>) -> some View {
        HStack(spacing: Theme.Space.s) {
            Picker("Kind", selection: draft.kind) {
                ForEach(NotebookItem.Kind.allCases, id: \.self) { kind in
                    Label(ItemKindStyle.title(kind), systemImage: ItemKindStyle.symbol(kind)).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Kind")
            Picker("Collection", selection: draft.collectionId) {
                ForEach(model.collections) { c in Text(c.name).tag(c.id) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Collection")
            if draft.wrappedValue.kind == .task {
                Toggle("Done", isOn: Binding(
                    get: { draft.wrappedValue.status == .done },
                    set: { draft.wrappedValue.status = $0 ? .done : .open }
                ))
                .toggleStyle(.checkbox)
                .font(Theme.Font.body)
                .padding(.leading, Theme.Space.xs)
            }
            Spacer(minLength: Theme.Space.s)
            Button {
                Task { await model.moveToTrash(draft.wrappedValue) }
            } label: {
                Label("Move to Trash", systemImage: "trash").labelStyle(.iconOnly)
            }
            .buttonStyle(.sf(.secondary))
            .keyboardShortcut(.delete, modifiers: .command)
            .help("Move to Trash (⌘⌫)")
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private func meta(_ item: NotebookItem) -> some View {
        var parts = ["Created \(TimeText.short(item.createdAt))"]
        if item.updatedAt.timeIntervalSince(item.createdAt) > 1 { parts.append("Edited \(TimeText.relative(item.updatedAt))") }
        if let who = Describe.source(item.source) { parts.append("Saved by \(who)") }
        return Text(parts.joined(separator: " · ")).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
    }

    private func linkField(_ draft: Binding<NotebookItem>) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "link").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Link", text: Binding(
                get: { draft.wrappedValue.url ?? "" },
                set: { draft.wrappedValue.url = $0.isEmpty ? nil : $0 }
            ), prompt: Text("https://…"))
            .textFieldStyle(.plain)
            .font(Theme.Font.body)
            .accessibilityLabel("Link")
            if let url = webURL(draft.wrappedValue.url) {
                Button("Open link") { NSWorkspace.shared.open(url) }.buttonStyle(.sf(.secondary))
            }
        }
    }

    private func tagsField(_ draft: Binding<NotebookItem>) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "number").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Tags", text: Binding(
                get: { draft.wrappedValue.tags },
                set: { draft.wrappedValue.tags = $0.replacingOccurrences(of: ",", with: " ") }
            ), prompt: Text("Tags, separated by spaces"))
            .textFieldStyle(.plain)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.inkMuted)
            .accessibilityLabel("Tags")
        }
    }

    /// Only web links open from here; anything else stays text.
    private func webURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}
