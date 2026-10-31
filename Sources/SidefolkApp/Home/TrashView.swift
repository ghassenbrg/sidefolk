import SidefolkCore
import SwiftUI

/// Notebook › Trash (D84: the Notebook's last filter): items moved out of the Notebook in the last 30 days, each with how
/// long it has left (amber in its last three days), Restore and Delete forever.
struct TrashView: View {
    var model: NotebookModel
    @State private var confirming: NotebookItem?
    @State private var confirmingEmpty = false

    var body: some View {
        HomePage {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                PageTitle(title: "Trash", subtitle: "Things stay here for 30 days, then they're gone for good.")
                if !model.trash.isEmpty {
                    Button("Empty Trash…") { confirmingEmpty = true }.buttonStyle(.sf(.destructive))
                }
            }
            if model.trash.isEmpty {
                EmptyState(title: "The Trash is empty", message: "Things you delete wait here for 30 days, in case you change your mind.",
                           systemImage: "trash", folk: "brew")
                    .frame(maxWidth: .infinity)
            } else {
                RowsCard { ForEach(model.trash) { item in row(item) } }
            }
        }
        .alert("Delete “\(confirming.map { $0.title.isEmpty ? String(localized: "Untitled") : $0.title.clipped(40) } ?? "")” forever?",
               isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } }
        ), presenting: confirming) { item in
            Button("Delete forever", role: .destructive) { Task { await model.deleteForever(item) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert("Delete \(model.trash.count) items forever?", isPresented: $confirmingEmpty) {
            Button("Empty Trash", role: .destructive) { Task { await model.emptyTrash() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything in the Trash is deleted for good. This can't be undone.")
        }
    }

    private func row(_ item: NotebookItem) -> some View {
        HStack(spacing: Theme.Space.m) {
            if let c = model.collection(id: item.collectionId) {
                CollectionTile(collection: c, size: Theme.Size.rowIcon)
            } else {
                IconTile(symbol: ItemKindStyle.symbol(item.kind), folk: "pip", size: Theme.Size.rowIcon)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? String(localized: "Untitled") : item.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                Text(detail(item)).font(Theme.Font.callout).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Chip(verbatim: gone(item), tone: daysLeft(item) <= 3 ? .warning : .neutral)
            Button("Restore") { Task { await model.restore(item) } }.buttonStyle(.sf(.secondary))
            Button("Delete forever") { confirming = item }.buttonStyle(.sf(.destructive))
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .contain)
    }

    private func detail(_ item: NotebookItem) -> String {
        let from = model.collection(id: item.collectionId).map(NotebookCollections.shownName) ?? String(localized: "the Notebook")
        guard let deleted = item.deletedAt else { return String(localized: "From \(from)") }
        return [String(localized: "From \(from)"), TimeText.relative(deleted)].joined(separator: " · ")
    }

    private func daysLeft(_ item: NotebookItem) -> Int {
        guard let deleted = item.deletedAt else { return 30 }
        return max(0, 30 - Int(Date().timeIntervalSince(deleted) / 86400))
    }

    private func gone(_ item: NotebookItem) -> String {
        let left = daysLeft(item)
        return left == 0 ? String(localized: "gone today") : left == 1 ? String(localized: "gone tomorrow") : String(localized: "gone in \(left) days")
    }
}
