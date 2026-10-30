import SidefolkCore
import SwiftUI

/// Home › Trash: items moved out of the Notebook in the last 30 days.
struct TrashView: View {
    var model: NotebookModel
    @State private var confirming: NotebookItem?
    @State private var confirmingEmpty = false

    var body: some View {
        PageScroll {
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
            IconTile(symbol: ItemKindStyle.symbol(item.kind), folk: "pip")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? String(localized: "Untitled") : item.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                Text(detail(item)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
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
        let left = max(0, 30 - Int(Date().timeIntervalSince(deleted) / 86400))
        let gone = left == 0 ? String(localized: "gone today") : left == 1 ? String(localized: "gone tomorrow") : String(localized: "gone in \(left) days")
        return String(localized: "From \(from) · deleted \(TimeText.relative(deleted)) · \(gone)",
                      comment: "“From Inbox · deleted 2 days ago · gone in 28 days”")
    }
}
