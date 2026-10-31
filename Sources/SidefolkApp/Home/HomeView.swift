import SidefolkCore
import SwiftUI

/// The Home window: the theme's navigation (D64; a sidebar with Today, Conversations, the Notebook's collections and
/// Activity, or a rail with a status bar) and the selected page.
struct HomeView: View {
    @Bindable var model: HomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searching: Bool

    private var navigation: ThemeLayout.Navigation { ThemeStore.shared.style.tokens.layout.navigation }

    var body: some View {
        Group {
            switch navigation {
            case .rail:
                HStack(spacing: 0) {
                    HomeRail(model: model)
                    Divider()
                    page
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { HomeStatusBar(model: model) }
            case .pills:
                page.toolbar {
                    ToolbarItem(placement: .principal) { PillTabs(model: model) }
                }
            case .ribbons:
                HStack(spacing: 0) {
                    page
                    RibbonTabs(model: model)
                }
            default:
                NavigationSplitView {
                    HomeSidebar(model: model)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
                } detail: {
                    page
                }
            }
        }
        // The one bar (D58): search everything, or type what to do. Return does it, as in the Ask panel.
        .searchable(text: Bindable(model.find).query, placement: .toolbar,
                    prompt: Text("Search, write a note, set a reminder or ask \(model.services.runtime.settings.current.companionName)…"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Everything Home can start, in one place (D58).
                Menu {
                    Button("Note") { Task { await model.newNote() } }
                    Button("Reminder…") { model.services.openAsk(prefill: "remind me ") }
                    Button("Watch…") { model.services.openAsk(prefill: "tell me when ") }
                    Divider()
                    Button("Collection…") { model.collectionSheet = .create }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .help("New note, reminder, watch or collection")
            }
        }
        .searchFocused($searching)
        .onSubmit(of: .search) { model.send(.auto) }
        .background {
            Button("Search") { searching = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
            // ⌘1–4 go to the four places in every navigation (D64).
            ForEach(Array(HomeSelection.places.enumerated()), id: \.offset) { i, place in
                Button(place.title) { model.go(to: place) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(item: $model.collectionSheet) { mode in
            CollectionSheet(mode: mode, model: model.notebook) { created in
                if let created { model.selection = .collection(created.id) }
            }
        }
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

    /// The selected page, or what the one bar found while it has words.
    private var page: some View {
        Group {
            if model.find.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detail
            } else {
                SearchPage(find: model.find, services: model.services) { model.send($0) }
            }
        }
        .overlay { ThemeGrain() }
        .environment(model.pages)
    }

    /// Without a sidebar, the Notebook's pages bring their collections along (D64).
    @ViewBuilder private func withCollections<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        switch navigation {
        case .sidebar:
            content()
        case .rail:
            HStack(spacing: 0) {
                CollectionColumn(model: model).frame(width: 200)
                Divider()
                content()
            }
        case .pills, .ribbons:
            VStack(spacing: 0) {
                CollectionStrip(model: model, washi: navigation == .ribbons)
                Divider()
                content()
            }
        }
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
            withCollections { TrashView(model: model.notebook) }
        case .page(ExtensionPagesModel.hub):
            ExtensionsHubView(pages: model.pages) { model.selection = .page($0) }
        case .page(let id):
            if let info = model.pages.info(id) {
                ExtensionPageView(model: model.pages.model(info))
            } else {
                Theme.surfaceSunken
            }
        case .collection(let id):
            if let collection = model.notebook.collection(id: id) {
                withCollections { NotebookView(model: model.notebook, collection: collection) }
            } else {
                Theme.surfaceSunken
            }
        }
    }
}

// MARK: - Sidebar

private struct HomeSidebar: View {
    @Bindable var model: HomeModel
    private var layout: ThemeLayout { ThemeStore.shared.style.tokens.layout }
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
            // The theme's layout may put it at the foot instead (D64).
            if layout.nook == .top {
                Button { model.selection = .now } label: {
                    CompanionNook(settings: model.services.runtime.settings.current, line: model.now.nookLine)
                }
                .buttonStyle(.plain)
                .selectionDisabled()
                .listRowSeparator(.hidden)
                .padding(.bottom, Theme.Space.s)
            }
            Section {
                Label { Text("Today") } icon: { icon("sun.max.fill", Theme.sun) }
                    .badge(model.now.needsYouCount)
                    .tag(HomeSelection.now)
                Label { Text("Conversations") } icon: { icon("bubble.left.and.bubble.right.fill", Theme.aqua) }
                    .tag(HomeSelection.conversations)
            }
            Section("Notebook") {
                ForEach(notebook.collections) { c in collectionRow(c) }
            }
            // Pages extensions add (D62), under the extension's own name for the page, as the person arranged them (D67).
            if !model.pages.list.isEmpty {
                ExtensionsSidebarSection(pages: model.pages)
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
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if layout.nook == .foot {
                    Button { model.selection = .now } label: {
                        NookBubble(settings: model.services.runtime.settings.current, greeting: model.now.nookGreeting, line: model.now.nookLine)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Theme.Space.s)
                }
                HStack {
                    // The Trash at the foot, out of the way of the collections (D58); a new collection is in the New menu.
                    Button { model.selection = .trash } label: {
                        Label { Text("Trash") + Text(verbatim: notebook.trashCount > 0 ? " · \(notebook.trashCount)" : "") }
                            icon: { Image(systemName: "trash") }
                            .fixedSize()
                    }
                    .buttonStyle(.sfPlain)
                    .foregroundStyle(model.selection == .trash ? Theme.ink : Theme.inkMuted)
                    Spacer()
                    // Sidefolk lives in the menu bar, so the app menu (and ⌘,) is only there while a window
                    // is in front; Settings is also one click from wherever Home is.
                    Button { model.services.openSettings(tab: nil) } label: {
                        // The word where it fits; a roomy theme or a long language keeps the gear alone.
                        ViewThatFits(in: .horizontal) {
                            Label("Settings", systemImage: "gearshape").fixedSize()
                            Image(systemName: "gearshape").accessibilityLabel(Text("Settings"))
                        }
                    }
                    .buttonStyle(.sfPlain)
                    .foregroundStyle(Theme.inkMuted)
                    .help("Settings (⌘,)")
                }
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.s)
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
        Label { Text(NotebookCollections.shownName(c)) } icon: { CollectionIcon(collection: c, nav: true) }
            .badge(notebook.counts[c.id] ?? 0)
            .tag(HomeSelection.collection(c.id))
            .help(c.kind == .profile ? Text("Sidefolk keeps these in mind in every conversation.") : Text(verbatim: c.name))
            .contextMenu {
                if c.kind != .profile {
                    Button("Edit…") { model.collectionSheet = .edit(c) }
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
        NavIcon(symbol: name, color: color)
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
