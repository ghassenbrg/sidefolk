import SidefolkCore
import SwiftUI

/// The right side of a collection: the selected item, edited in place. Changes land in the model's
/// draft, which saves itself when editing pauses.
struct NotebookEditor: View {
    @Bindable var model: NotebookModel
    @FocusState private var focus: Field?
    private enum Field { case title, body }

    var body: some View {
        if let item = model.draft {
            VStack(alignment: .leading, spacing: 0) {
                topBar(item)
                Rectangle().fill(Theme.line).frame(height: 1)
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    TextField("Title", text: field(item, \.title, ""), prompt: Text("Untitled"), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1...3)
                        .focused($focus, equals: .title)
                        .onSubmit { focus = .body }
                        .accessibilityLabel("Title")
                    meta(item)
                    if item.kind == .link { linkField(item) }
                    tagsField(item)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    TextEditor(text: field(item, \.body, ""))
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
                            if item.body.isEmpty {
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
            .id(item.id)
            .onAppear { if item.title.isEmpty { focus = .title } }
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

    /// A binding into the draft of `item`. When the selection moves on, it reads the fallback and
    /// drops writes, so a field that is going away can never write into the next item.
    private func field<T: Sendable>(_ item: NotebookItem, _ key: WritableKeyPath<NotebookItem, T> & Sendable, _ fallback: T) -> Binding<T> {
        let id = item.id
        return Binding(
            get: { model.draft?.id == id ? model.draft?[keyPath: key] ?? fallback : fallback },
            set: { value in if model.draft?.id == id { model.draft?[keyPath: key] = value } }
        )
    }

    private func topBar(_ item: NotebookItem) -> some View {
        HStack(spacing: Theme.Space.s) {
            Picker("Kind", selection: field(item, \.kind, item.kind)) {
                ForEach(NotebookItem.Kind.allCases, id: \.self) { kind in
                    Label(ItemKindStyle.title(kind), systemImage: ItemKindStyle.symbol(kind)).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Kind")
            Picker("Collection", selection: field(item, \.collectionId, item.collectionId)) {
                ForEach(model.collections) { c in Text(c.name).tag(c.id) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Collection")
            if item.kind == .task {
                Toggle("Done", isOn: Binding(
                    get: { field(item, \.status, item.status).wrappedValue == .done },
                    set: { field(item, \.status, item.status).wrappedValue = $0 ? .done : .open }
                ))
                .toggleStyle(.checkbox)
                .font(Theme.Font.body)
                .padding(.leading, Theme.Space.xs)
            }
            Spacer(minLength: Theme.Space.s)
            Button {
                Task { await model.moveToTrash(item) }
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

    private func linkField(_ item: NotebookItem) -> some View {
        let url = field(item, \.url, nil)
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: "link").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Link", text: Binding(
                get: { url.wrappedValue ?? "" },
                set: { url.wrappedValue = $0.isEmpty ? nil : $0 }
            ), prompt: Text("https://…"))
            .textFieldStyle(.plain)
            .font(Theme.Font.body)
            .accessibilityLabel("Link")
            if let link = webURL(item.url) {
                Button("Open link") { NSWorkspace.shared.open(link) }.buttonStyle(.sf(.secondary))
            }
        }
    }

    private func tagsField(_ item: NotebookItem) -> some View {
        let tags = field(item, \.tags, "")
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: "number").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Tags", text: Binding(
                get: { tags.wrappedValue },
                set: { tags.wrappedValue = $0.replacingOccurrences(of: ",", with: " ") }
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
