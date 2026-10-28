import SidefolkCore
import SwiftUI

/// The Home window: a sidebar (Now, Conversations, the Notebook's collections, Trash, Activity) and the selected page.
struct HomeView: View {
    @Bindable var model: HomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            HomeSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            detail
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
        .animation(.spring(duration: 0.3), value: model.notebook.toast?.id)
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
                .padding(.bottom, Theme.Space.m)
            Section {
                Label { Text("Now") } icon: { icon("sun.max.fill", Theme.sun) }
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
        .background(Theme.surface)
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
        Label { Text(NotebookCollections.shownName(c)) } icon: { icon(symbol(c), c.kind == .profile ? Theme.aqua : Theme.folkColor("pip")) }
            .badge(notebook.counts[c.id] ?? 0)
            .tag(HomeSelection.collection(c.id))
            .help(c.kind == .profile ? Text("Sidefolk keeps these in mind in every conversation.") : Text(verbatim: c.name))
            .contextMenu {
                if c.kind != .inbox && c.kind != .profile {
                    Button("Rename…") { sheet = .rename(c) }
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

    private func symbol(_ c: NotebookCollection) -> String {
        switch c.kind {
        case .inbox: "tray.fill"
        case .profile: "person.crop.circle.fill"
        case .project: "folder.fill"
        case .topic: "number"
        case .list: "checklist"
        }
    }
}

// MARK: - New and rename collection

struct CollectionSheet: View {
    enum Mode: Identifiable {
        case create
        case rename(NotebookCollection)

        var id: String {
            switch self {
            case .create: "create"
            case .rename(let c): c.id
            }
        }
    }

    var mode: Mode
    var model: NotebookModel
    var done: (NotebookCollection?) -> Void
    @State private var name = ""
    @State private var kind: NotebookCollection.Kind = .project
    @State private var error: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    private static let kinds: [(NotebookCollection.Kind, LocalizedStringResource, LocalizedStringResource)] = [
        (.project, "Project", "Notes, ideas and tasks for something you're making."),
        (.topic, "Topic", "Things you're learning or thinking about."),
        (.list, "List", "Groceries, books to read, places to go."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(isCreate ? "New collection" : "Rename collection").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            TextField("Name", text: $name, prompt: Text("Name"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
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
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button(isCreate ? "Create collection" : "Rename collection", action: save)
                    .buttonStyle(.sfPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 400)
        .background(Theme.surface)
        .onAppear { if case .rename(let c) = mode { name = c.name } }
    }

    private var isCreate: Bool { if case .create = mode { true } else { false } }

    private func save() {
        Task {
            switch mode {
            case .create:
                switch await model.createCollection(named: name, kind: kind) {
                case .success(let c):
                    done(c)
                    dismiss()
                case .failure(let e):
                    error = e
                }
            case .rename(let c):
                if let e = await model.rename(c, to: name) {
                    error = e
                } else {
                    done(nil)
                    dismiss()
                }
            }
        }
    }
}
