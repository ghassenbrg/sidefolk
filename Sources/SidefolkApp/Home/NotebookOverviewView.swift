import SidefolkCore
import SwiftUI

/// Home › Notebook (D134): the Notebook's own page, not a jump to one of its collections. What needs doing, every
/// collection, what's pinned, and a search across all of it.
struct NotebookOverviewView: View {
    var home: HomeModel
    @State private var query = ""
    @State private var results: [NotebookItem] = []
    @FocusState private var searchFocused: Bool

    private var model: NotebookModel { home.notebook }
    private var overview: NotebookOverview { model.overview }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HomePage {
            header
            if searching {
                searchResults
            } else {
                if !overview.needsDoing.isEmpty { needsDoing }
                collections
                if !overview.pinned.isEmpty { pinned }
                foot
            }
        }
        // Again when the Notebook changes: a task finished from a result stays true to what it is now.
        .task(id: SearchKey(query: query, overview: overview)) {
            guard searching else { return results = [] }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            results = await model.searchEverything(query)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notebook").font(Theme.Font.display).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .homePageTitle()
                    Text(verbatim: NotebookOverviewWords.count(overview)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: Theme.Space.s)
                Button {
                    Task { await home.newNote() }
                } label: {
                    Label("New note", systemImage: "square.and.pencil").labelStyle(.iconOnly)
                }
                .buttonStyle(.sf(.secondary))
                .keyboardShortcut("n", modifiers: .command)
                .help(Text("\(String(localized: "New note")) (⌘N)", comment: "A button's name, then its shortcut"))
            }
            searchBox
        }
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Search", text: $query, prompt: Text(verbatim: "")).fieldHint(Text("Search everything"), showing: query.isEmpty)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .focused($searchFocused)
                .accessibilityLabel(Text("Search everything"))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.sfIcon(side: 22))
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityLabel("Clear search")
            }
        }
        // The clear button's height, so the box doesn't jump at the first letter.
        .frame(minHeight: 22)
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 6)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
        // ⌘F, as everywhere on the Mac.
        .background {
            Button("Find") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var searchResults: some View {
        if results.isEmpty {
            Text("Nothing found.").font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
        } else {
            rows(results)
        }
    }

    private struct SearchKey: Equatable {
        var query: String
        var overview: NotebookOverview
    }

    private var needsDoing: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: "Needs doing", count: overview.needsDoingCount) {
                Button("See in Calendar") { home.selection = .calendar }.buttonStyle(.sf(.quiet))
            }
            rows(overview.needsDoing)
        }
    }

    private var collections: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: "Collections") { EmptyView() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.Space.m, alignment: .top)], alignment: .leading, spacing: Theme.Space.m) {
                ForEach(overview.collections) { c in
                    CollectionOverviewTile(collection: c, tile: overview.tiles[c.id] ?? .init()) { home.selection = .collection(c.id) }
                }
                NewCollectionTile { home.collectionSheet = .create }
            }
            if overview.itemCount == 0 {
                Text("What you and \(home.companionName) save lands here. New notes go to the Inbox.")
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pinned: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: "Pinned") { EmptyView() }
            rows(overview.pinned)
        }
    }

    private func rows(_ items: [NotebookItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, Theme.Space.l) }
                OverviewItemRow(item: item, model: model) { Task { await home.reveal(item) } }
            }
        }
        .cardSurface()
    }

    /// Where the rest of the Notebook is, quietly: nothing to see when both are empty.
    @ViewBuilder private var foot: some View {
        if model.trashCount > 0 || !model.archived.isEmpty {
            HStack(spacing: Theme.Space.s) {
                if model.trashCount > 0 {
                    Button { home.selection = .trash } label: {
                        Text(verbatim: "\(String(localized: "Trash")) · \(model.trashCount)")
                    }
                    .buttonStyle(.sf(.quiet))
                }
                if !model.archived.isEmpty {
                    Menu {
                        ForEach(model.archived) { c in
                            Button(NotebookCollections.shownName(c)) { home.selection = .collection(c.id) }
                        }
                    } label: {
                        Text(verbatim: "\(String(localized: "Archived")) · \(model.archived.count)")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.sf(.quiet))
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
        }
    }
}

enum NotebookOverviewWords {
    static func count(_ overview: NotebookOverview) -> String {
        String(localized: "\(overview.itemCount) items") + " · " + String(localized: "\(overview.collections.count) collections")
    }
}

/// A collection on the Notebook's page: a click opens it. What's in it, what's still to do, and when it last changed.
private struct CollectionOverviewTile: View {
    var collection: NotebookCollection
    var tile: NotebookOverview.Tile
    var open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: Theme.Space.s + 2) {
                CollectionTile(collection: collection)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: NotebookCollections.shownName(collection))
                        .font(Theme.Font.body.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(verbatim: facts).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    if let change = tile.lastChange {
                        Text("Updated \(TimeText.relative(change))", comment: "A collection: when something in it last changed")
                            .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .cardSurface()
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(hovered ? Theme.inkFaint : .clear)
            }
        }
        .buttonStyle(.sfBare)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.micro, value: hovered)
    }

    private var facts: String {
        guard tile.items > 0 else { return String(localized: "Empty") }
        let items = String(localized: "\(tile.items) items")
        return tile.openTasks > 0 ? items + " · " + String(localized: "\(tile.openTasks) open tasks") : items
    }
}

private struct NewCollectionTile: View {
    var create: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: create) {
            Label("New collection", systemImage: "plus")
                .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 84)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(hovered ? Theme.inkFaint : Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
        }
        .buttonStyle(.sfBare)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.micro, value: hovered)
    }
}

/// A task with its circle to finish it where it stands, or a note, idea or link; a click opens it in its collection.
private struct OverviewItemRow: View {
    var item: NotebookItem
    var model: NotebookModel
    var open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s + 2) {
            if item.kind == .task {
                CheckCircle(checked: item.status == .done,
                            label: item.status == .done ? Text("Mark “\(title)” not done") : Text("Mark “\(title)” done")) {
                    Task { await model.toggleDone(item) }
                }
                .padding(.top, 1)
            } else {
                Image(systemName: ItemKindStyle.symbol(item.kind))
                    .font(.system(size: 13)).foregroundStyle(Theme.inkFaint)
                    .frame(width: 18).padding(.top, 1)
                    .accessibilityHidden(true)
            }
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title).font(Theme.Font.body).foregroundStyle(item.title.isEmpty ? Theme.inkFaint : Theme.ink).lineLimit(1)
                    HStack(spacing: Theme.Space.xs) {
                        if let name = model.collectionName(item.collectionId) { Text(verbatim: name).lineLimit(1) }
                        if let due = item.dueAt, item.status == .open {
                            Text(verbatim: "·").accessibilityHidden(true)
                            DueBadge(due: due, allDay: item.dueAllDay)
                        }
                    }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.sfBare)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private var title: String { item.title.isEmpty ? String(localized: "Untitled") : item.title }
}
