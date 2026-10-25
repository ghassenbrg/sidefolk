import SidefolkCore
import SwiftUI

/// Home › Trash: items moved out of the Notebook in the last 30 days.
struct TrashView: View {
    var model: NotebookModel
    @State private var confirming: NotebookItem?

    var body: some View {
        PageScroll {
            PageTitle(title: "Trash", subtitle: "Things stay here for 30 days, then they're gone for good.")
            RowsCard {
                if model.trash.isEmpty {
                    InlineEmpty(text: "The Trash is empty.", systemImage: "trash")
                }
                ForEach(model.trash) { item in row(item) }
            }
        }
        .alert("Delete “\(confirming?.title.clipped(40) ?? "")” forever?", isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } }
        ), presenting: confirming) { item in
            Button("Delete forever", role: .destructive) { Task { await model.deleteForever(item) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func row(_ item: NotebookItem) -> some View {
        HStack(spacing: Theme.Space.m) {
            IconTile(symbol: ItemKindStyle.symbol(item.kind), folk: "pip")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
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
        let from = model.collection(id: item.collectionId)?.name ?? "the Notebook"
        guard let deleted = item.deletedAt else { return "From \(from)" }
        let left = max(0, 30 - Int(Date().timeIntervalSince(deleted) / 86400))
        let gone = left == 0 ? "gone today" : left == 1 ? "gone tomorrow" : "gone in \(left) days"
        return "From \(from) · deleted \(TimeText.relative(deleted)) · \(gone)"
    }
}
