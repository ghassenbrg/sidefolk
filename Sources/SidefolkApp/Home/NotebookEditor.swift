import SidefolkCore
import SwiftUI

/// The right side of a collection: the selected item, edited in place. Changes land in the model's
/// draft, which saves itself when editing pauses.
struct NotebookEditor: View {
    @Bindable var model: NotebookModel
    @FocusState private var focus: Field?
    @State private var formatting = NoteEditorController()
    private enum Field { case title, body }

    /// The theme's editor (D64): formatted as you write, or Markdown as written with tabs and an outline.
    private var markdown: Bool { ThemeStore.shared.style.tokens.layout.editor == .markdown }

    var body: some View {
        if markdown, let item = model.draft {
            markdownEditor(item)
        } else if let item = model.draft {
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
                        .onSubmit { formatting.focus() }
                        .accessibilityLabel("Title")
                    meta(item)
                    connected
                    if item.kind == .link { linkField(item) }
                    tagsField(item)
                    FormatBar(controller: formatting)
                    NoteBodyEditor(text: field(item, \.body, ""), controller: formatting)
                        .frame(maxHeight: .infinity)
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
                // Lines a reader can follow in a wide window: the page keeps a book's measure, centred (D67).
                .frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Theme.surface)
            .id(item.id)
            .onAppear { if item.title.isEmpty { focus = .title } }
        } else {
            VStack {
                Spacer()
                // Just the symbol: the list beside it already has someone saying hello. An empty list
                // speaks for both sides (its own empty state and button), so this side stays blank.
                if !model.items.isEmpty {
                    EmptyState(title: "Nothing selected", message: "Pick something from the list, or press ⌘N to write something new.",
                               systemImage: "note.text")
                }
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
                    Label { Text(ItemKindStyle.title(kind)) } icon: { Image(systemName: ItemKindStyle.symbol(kind)) }.tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Kind")
            Picker("Collection", selection: field(item, \.collectionId, item.collectionId)) {
                ForEach(model.collections) { c in Text(NotebookCollections.shownName(c)).tag(c.id) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Collection")
            if item.kind == .task {
                Toggle(String(localized: "state.done", defaultValue: "Done", comment: "Checkbox and status: the task or reminder is finished"), isOn: Binding(
                    get: { field(item, \.status, item.status).wrappedValue == .done },
                    set: { field(item, \.status, item.status).wrappedValue = $0 ? .done : .open }
                ))
                .toggleStyle(.checkbox)
                .font(Theme.Font.body)
                .padding(.leading, Theme.Space.xs)
            }
            Spacer(minLength: Theme.Space.s)
            Button {
                Task { await model.togglePin(item) }
            } label: {
                Label(item.pinnedAt == nil ? "Pin" : "Unpin", systemImage: item.pinnedAt == nil ? "pin" : "pin.fill").labelStyle(.iconOnly)
            }
            .buttonStyle(.sf(.secondary))
            .help(item.pinnedAt == nil ? "Pin to the top" : "Unpin")
            RemindButton(item: item, model: model)
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

    // MARK: Markdown (D64)

    private func markdownEditor(_ item: NotebookItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tabStrip(item)
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "#").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
                        TextField("Title", text: field(item, \.title, ""), prompt: Text("Untitled"))
                            .textFieldStyle(.plain)
                            .focused($focus, equals: .title)
                            .onSubmit { formatting.focus() }
                            .accessibilityLabel("Title")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.link)
                    Text(verbatim: markdownMeta(item)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.inkFaint)
                    NoteBodyEditor(text: field(item, \.body, ""), controller: formatting, showsMarks: true)
                        .frame(maxHeight: .infinity)
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Rectangle().fill(Theme.line).frame(width: 1)
                references(item).frame(width: 200)
            }
        }
        .background(Theme.surface)
        .id(item.id)
        .onAppear { if item.title.isEmpty { focus = .title } }
    }

    private func tabStrip(_ item: NotebookItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.tabs) { tab in
                    let current = tab.id == item.id
                    HStack(spacing: 6) {
                        Image(systemName: "doc.plaintext").imageScale(.small).foregroundStyle(Theme.inkFaint)
                        Text(verbatim: Self.fileName(tab)).lineLimit(1)
                        Button { model.closeTab(tab.id) } label: { Image(systemName: "xmark").imageScale(.small) }
                            .buttonStyle(.plain).foregroundStyle(Theme.inkFaint)
                            .accessibilityLabel(Text("Close “\(tab.title)”"))
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(current ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, 7)
                    .background(current ? Theme.surfaceRaised : .clear)
                    .overlay(alignment: .bottom) { if current { Rectangle().fill(Theme.accent).frame(height: 2) } }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.items.contains(where: { $0.id == tab.id }) { model.select(tab.id) } else { model.services.open(item: tab) }
                    }
                    .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
                }
                Button { Task { await model.newItem() } } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkMuted).padding(.horizontal, Theme.Space.m)
                    .help("New (⌘N)")
            }
        }
        .background(Theme.surfaceSunken)
    }

    /// "extensions-folk.md": a note's title as a file name.
    static func fileName(_ item: NotebookItem) -> String {
        let words = item.title.lowercased().split { !$0.isLetter && !$0.isNumber }.prefix(4).joined(separator: "-")
        return (words.isEmpty ? String(localized: "untitled") : words) + ".md"
    }

    private func markdownMeta(_ item: NotebookItem) -> String {
        var parts = [String(localized: ItemKindStyle.title(item.kind)).lowercased()]
        if item.pinnedAt != nil { parts.insert(String(localized: "pinned"), at: 0) }
        parts += item.tags.split(separator: " ").map { "#\($0)" }
        return parts.joined(separator: " · ")
    }

    /// Where it came from and what it's linked to, then its outline: each heading with how many of its boxes are ticked.
    private func references(_ item: NotebookItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Eyebrow(Text("References"))
                if let who = Describe.source(item.source) {
                    Text("from \(who) at \(TimeText.short(item.createdAt))", comment: "Where a note came from: “from Claude Code at Oct 28 19:02”")
                }
                connected
                if let reminder = model.reminders[item.id] { ReminderBadge(reminder: reminder) }
                RemindButton(item: item, model: model)
                let outline = Self.outline(item.body)
                if !outline.isEmpty {
                    Eyebrow(Text("Outline")).padding(.top, Theme.Space.s)
                    ForEach(Array(outline.enumerated()), id: \.offset) { _, entry in
                        Text(verbatim: entry.boxes > 0 ? "\(entry.title) · \(entry.ticked)/\(entry.boxes)" : entry.title).lineLimit(2)
                    }
                }
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.inkMuted)
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The note's headings, each with its checklist's boxes and how many are ticked.
    static func outline(_ body: String) -> [(title: String, boxes: Int, ticked: Int)] {
        var out: [(title: String, boxes: Int, ticked: Int)] = []
        for raw in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                out.append((line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces), 0, 0))
            } else if !out.isEmpty, line.hasPrefix("- [") || line.hasPrefix("[") {
                out[out.count - 1].boxes += 1
                if line.lowercased().contains("[x]") { out[out.count - 1].ticked += 1 }
            }
        }
        return out
    }

    /// When it was made and changed, and its reminder (D49), if it has one.
    private func meta(_ item: NotebookItem) -> some View {
        HStack(spacing: Theme.Space.s) {
            if let reminder = model.reminders[item.id] { ReminderBadge(reminder: reminder) }
            Text(verbatim: metaText(item)).foregroundStyle(Theme.inkFaint)
        }
        .font(Theme.Font.caption)
    }

    /// The conversations it was saved and changed in (D58): only links that were recorded, newest change first.
    @ViewBuilder private var connected: some View {
        let links = model.conversations
        if links.madeIn != nil || !links.changedIn.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if let made = links.madeIn {
                    ConversationLink(conversation: made, label: Text("Saved in “\(made.title.clipped(60))”")) {
                        model.services.openConversation(made.id)
                    }
                }
                ForEach(links.changedIn.prefix(3)) { changed in
                    ConversationLink(conversation: changed, label: Text("Changed in “\(changed.title.clipped(60))”")) {
                        model.services.openConversation(changed.id)
                    }
                }
            }
        }
    }

    private func metaText(_ item: NotebookItem) -> String {
        var parts = [String(localized: "Created \(TimeText.short(item.createdAt))")]
        if item.updatedAt.timeIntervalSince(item.createdAt) > 1 {
            parts.append(String(localized: "Edited \(TimeText.relative(item.updatedAt))", comment: "“Edited 5 min ago”"))
        }
        if let who = Describe.source(item.source) { parts.append(String(localized: "Saved by \(who)")) }
        return parts.joined(separator: " · ")
    }

    private func linkField(_ item: NotebookItem) -> some View {
        let url = field(item, \.url, nil)
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: "link").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Link", text: Binding(
                get: { url.wrappedValue ?? "" },
                set: { url.wrappedValue = $0.isEmpty ? nil : $0 }
            ), prompt: Text(verbatim: "https://…"))
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

/// The formatting buttons over a note's text (D53); each also has its shortcut while the text has focus.
private struct FormatBar: View {
    var controller: NoteEditorController

    var body: some View {
        HStack(spacing: 2) {
            button("bold", Text("Bold (⌘B)")) { controller.toggle(.bold) }
            button("italic", Text("Italic (⌘I)")) { controller.toggle(.italic) }
            button("strikethrough", Text("Strikethrough (⇧⌘X)")) { controller.toggle(.strike) }
            button("chevron.left.forwardslash.chevron.right", Text("Code")) { controller.toggle(.code) }
            divider
            Menu {
                Button("Title") { controller.set(.heading(1)) }
                Button("Heading") { controller.set(.heading(2)) }
                Button("Subheading") { controller.set(.heading(3)) }
                Button("Body") { controller.set(.paragraph) }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 24)
            .help("Text style")
            divider
            button("checklist", Text("Checklist (⇧⌘L)")) { controller.set(.check(done: false)) }
            button("list.bullet", Text("Bulleted list (⇧⌘8)")) { controller.set(.bullet) }
            button("list.number", Text("Numbered list (⇧⌘7)")) { controller.set(.numbered(1)) }
            button("text.quote", Text("Quote")) { controller.set(.quote) }
            divider
            button("link", Text("Link (⌘K)")) { controller.link() }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.inkMuted)
        .padding(.vertical, 2)
        .padding(.horizontal, -4)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 14).padding(.horizontal, 4)
    }

    private func button(_ symbol: String, _ help: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12.5, weight: .medium)).frame(width: 28, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
