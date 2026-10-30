import SidefolkCore
import SwiftUI

/// The Home window: a sidebar (Now, Conversations, the Notebook's collections, Trash, Activity) and the selected page.
struct HomeView: View {
    @Bindable var model: HomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searching: Bool

    var body: some View {
        NavigationSplitView {
            HomeSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            Group {
                if model.find.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detail
                } else {
                    SearchPage(find: model.find, services: model.services) { model.send($0) }
                }
            }
            .overlay { ThemeGrain() }
        }
        // The one bar (D58): search everything, or type what to do. Return does it, as in the Ask panel.
        .searchable(text: Bindable(model.find).query, placement: .toolbar, prompt: Text("Search, or say what to do"))
        .searchFocused($searching)
        .onSubmit(of: .search) { model.send(.auto) }
        .background {
            Button("Search") { searching = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .frame(minWidth: 860, minHeight: 560)
        .overlay(alignment: .bottom) {
            if let toast = model.notebook.toast {
                Toast(message: toast.message, actionTitle: toast.actionTitle) {
                    toast.action?()
                    model.notebook.toast = nil
                }
                .padding(.bottom, Theme.Space.xl)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(Theme.Motion.spring(0.3), value: model.notebook.toast?.id)
    }

    @ViewBuilder private var detail: some View {
        switch model.selection ?? .now {
        case .now:
            NowView(model: model.now)
        case .conversations:
            ConversationsView(model: model.conversations)
        case .activity:
            ActivityView(model: model.activity)
        case .trash:
            TrashView(model: model.notebook)
        case .collection(let id):
            if let collection = model.notebook.collection(id: id) {
                NotebookView(model: model.notebook, collection: collection)
            } else {
                Theme.surfaceSunken
            }
        }
    }
}

// MARK: - Sidebar

private struct HomeSidebar: View {
    @Bindable var model: HomeModel
    @State private var sheet: CollectionSheet.Mode?
    @State private var deleting: NotebookCollection?

    private var notebook: NotebookModel { model.notebook }

    var body: some View {
        List(selection: $model.selection) {
            // The app's name at a size that reads as one; it opens About.
            Button { model.services.showAbout() } label: { Wordmark(height: 30) }
                .buttonStyle(.plain)
                .help("About Sidefolk")
                .selectionDisabled()
                .listRowSeparator(.hidden)
                .padding(.leading, Theme.Space.xs)
                .padding(.bottom, Theme.Space.s)
            // The companion's nook (D58): who keeps track of all this, and what it's on now. A click goes to Today.
            Button { model.selection = .now } label: {
                CompanionNook(settings: model.services.runtime.settings.current, line: model.now.nookLine)
            }
            .buttonStyle(.plain)
            .selectionDisabled()
            .listRowSeparator(.hidden)
            .padding(.bottom, Theme.Space.s)
            Section {
                Label { Text("Today") } icon: { icon("sun.max.fill", Theme.sun) }
                    .badge(model.now.needsYouCount)
                    .tag(HomeSelection.now)
                Label { Text("Conversations") } icon: { icon("bubble.left.and.bubble.right.fill", Theme.aqua) }
                    .tag(HomeSelection.conversations)
            }
            Section("Notebook") {
                ForEach(notebook.collections) { c in collectionRow(c) }
                Label { Text("Trash") } icon: { icon("trash", Theme.inkMuted) }
                    .badge(notebook.trashCount)
                    .tag(HomeSelection.trash)
            }
            Section {
                // The audit trail matters, but your notes come first.
                Label { Text("Activity") } icon: { icon("list.bullet.rectangle.fill", Theme.folkColor("guard")) }
                    .tag(HomeSelection.activity)
            }
            if !notebook.archived.isEmpty {
                Section("Archived") {
                    ForEach(notebook.archived) { c in
                        Label { Text(NotebookCollections.shownName(c)) } icon: { icon("archivebox", Theme.inkMuted) }
                            .badge(notebook.counts[c.id] ?? 0)
                            .tag(HomeSelection.collection(c.id))
                            .contextMenu {
                                Button("Unarchive") { Task { await notebook.setArchived(c, false) } }
                                Button("Delete…") { deleting = c }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // A translucent theme leaves the sidebar to the Mac's own material, the desktop showing faintly through.
        .background(ThemeStore.shared.style.tokens.material.sidebar == .solid ? Theme.surface : .clear)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button { sheet = .create } label: {
                    // Two lines rather than cut off, where a language needs the room.
                    Label("New collection", systemImage: "plus").lineLimit(2)
                }
                .buttonStyle(.sfPlain)
                Spacer()
                // Sidefolk lives in the menu bar, so the app menu (and ⌘,) is only there while a window
                // is in front; Settings is also one click from wherever Home is.
                Button { model.services.openSettings(tab: nil) } label: {
                    Image(systemName: "gearshape").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.sfPlain)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.s)
        }
        .sheet(item: $sheet) { mode in
            CollectionSheet(mode: mode, model: notebook) { created in
                if let created { model.selection = .collection(created.id) }
            }
        }
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { c in
            Button("Delete collection", role: .destructive) {
                if model.selection == .collection(c.id) { model.selection = .now }
                Task { await notebook.delete(c) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { c in
            let n = notebook.counts[c.id] ?? 0
            if n == 0 {
                Text("It's empty.")
            } else {
                Text("\(n) items in it move to the Trash for 30 days. Restored items go to the Inbox.")
            }
        }
    }

    private func collectionRow(_ c: NotebookCollection) -> some View {
        Label { Text(NotebookCollections.shownName(c)) } icon: { CollectionIcon(collection: c) }
            .badge(notebook.counts[c.id] ?? 0)
            .tag(HomeSelection.collection(c.id))
            .help(c.kind == .profile ? Text("Sidefolk keeps these in mind in every conversation.") : Text(verbatim: c.name))
            .contextMenu {
                if c.kind != .profile {
                    Button("Edit…") { sheet = .edit(c) }
                }
                if c.kind != .inbox && c.kind != .profile {
                    Button("Archive") {
                        if model.selection == .collection(c.id) { model.selection = .now }
                        Task { await notebook.setArchived(c, true) }
                    }
                    Divider()
                    Button("Delete…") { deleting = c }
                }
            }
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).foregroundStyle(color)
    }

}

// MARK: - New and edit collection

struct CollectionSheet: View {
    enum Mode: Identifiable {
        case create
        case edit(NotebookCollection)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let c): c.id
            }
        }
    }

    var mode: Mode
    var model: NotebookModel
    var done: (NotebookCollection?) -> Void
    @State private var name = ""
    @State private var kind: NotebookCollection.Kind = .project
    @State private var symbol: String?
    @State private var color: String?
    @State private var emoji = ""
    @State private var error: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    private static let kinds: [(NotebookCollection.Kind, LocalizedStringResource, LocalizedStringResource)] = [
        (.project, "Project", "Notes, ideas and tasks for something you're making."),
        (.topic, "Topic", "Things you're learning or thinking about."),
        (.list, "List", "Groceries, books to read, places to go."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(isCreate ? "New collection" : "Edit collection").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            if namable {
                TextField("Name", text: $name, prompt: Text("Name"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
            }
            if isCreate {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Kind", selection: $kind) {
                        ForEach(Self.kinds, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if let detail = Self.kinds.first(where: { $0.0 == kind })?.2 {
                        Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            CollectionLookPicker(symbol: $symbol, color: $color, emoji: $emoji, kind: currentKind)
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button(isCreate ? "Create collection" : "Save", action: save)
                    .buttonStyle(.sfPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(namable && name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 420)
        .background(Theme.surface)
        .onAppear {
            guard case .edit(let c) = mode else { return }
            name = c.name
            symbol = c.symbol
            color = c.color
            emoji = c.emoji ?? ""
        }
    }

    private var isCreate: Bool { if case .create = mode { true } else { false } }

    /// The Inbox keeps its name; its look is the person's.
    private var namable: Bool { if case .edit(let c) = mode { c.kind != .inbox } else { true } }

    private var currentKind: NotebookCollection.Kind { if case .edit(let c) = mode { c.kind } else { kind } }

    private func save() {
        Task {
            switch mode {
            case .create:
                switch await model.createCollection(named: name, kind: kind) {
                case .success(let c):
                    await model.setLook(c, emoji: emoji, symbol: symbol, color: color)
                    done(c)
                    dismiss()
                case .failure(let e):
                    error = e
                }
            case .edit(let c):
                if namable, name != c.name, let e = await model.rename(c, to: name) {
                    error = e
                    return
                }
                await model.setLook(c, emoji: emoji, symbol: symbol, color: color)
                done(nil)
                dismiss()
            }
        }
    }
}
