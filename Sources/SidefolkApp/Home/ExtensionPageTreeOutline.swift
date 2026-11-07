import SidefolkCore
import SwiftUI

/// What can be done to a card, the same on its menu, under a right click, in the outline and for VoiceOver.
struct TreeCardActions: View {
    var node: ExtensionPage.Tree.Node
    var tree: ExtensionPage.Tree
    var model: ExtensionPageModel
    /// On a card chosen with others on the board: Remove takes them all.
    var removeChosen: (() -> Void)?

    var body: some View {
        if let reorder = tree.reorder, !node.fixed {
            if let up = tree.move(node.id, by: -1) {
                Button { Task { await model.run(tool: reorder.tool, input: reorder.input(up)) } } label: { Text("Move up", comment: "A row or card on an extension's page: its menu") }
            }
            if let down = tree.move(node.id, by: 1) {
                Button { Task { await model.run(tool: reorder.tool, input: reorder.input(down)) } } label: { Text("Move down", comment: "A row or card on an extension's page: its menu") }
            }
            let spots = tree.spots(for: node.id)
            if !spots.isEmpty {
                Menu {
                    ForEach(spots) { spot in
                        Button {
                            guard let place = tree.place(node.id, after: spot.id) else { return }
                            Task { await model.run(tool: reorder.tool, input: reorder.input(place)) }
                        } label: { Text(verbatim: Self.words(spot)) }
                    }
                } label: { Text("Move to", comment: "A card on an extension's page: its menu, listing everywhere it can go") }
            }
        }
        if let removeChosen {
            Button(role: .destructive, action: removeChosen) { Text("Remove the chosen cards", comment: "A card on an extension's board, chosen with others: its menu, removes them all") }
        } else if let remove = tree.remove, !node.fixed {
            Button(role: .destructive) { Task { await model.run(tool: remove.tool, input: remove.input(.string(node.id))) } } label: { Text("Remove", comment: "A card on an extension's page: its menu") }
        }
    }

    private static func words(_ spot: ExtensionPage.Tree.Spot) -> String {
        let indent = String(repeating: "    ", count: spot.depth)
        switch spot.place {
        case .after(let title): return indent + String(localized: "After “\(title.clipped(40))”", comment: "Where a card can move to, in a list of the cards it can follow")
        case .start(let branch, let of): return indent + String(localized: "First under “\(branch)” of “\(of.clipped(30))”", comment: "Where a card can move to: the start of a path that splits from another card")
        }
    }
}

/// The same tree as a plain list: every card with its place in the structure, for reading through, moving precisely and VoiceOver. Nothing here means anything of its own.
struct TreeOutline: View {
    var tree: ExtensionPage.Tree
    var model: ExtensionPageModel
    @Environment(\.pageSelected) private var chosen

    private enum Row: Identifiable {
        case card(ExtensionPage.Tree.Node, depth: Int)
        case branch(ExtensionPage.Tree.Branch, depth: Int)
        var id: String {
            switch self {
            case .card(let n, _): "card-\(n.id)"
            case .branch(let b, _): "branch-\(b.id)"
            }
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        func walk(_ nodes: [ExtensionPage.Tree.Node], _ depth: Int) {
            for node in nodes {
                out.append(.card(node, depth: depth))
                for branch in node.branches {
                    out.append(.branch(branch, depth: depth + 1))
                    walk(branch.nodes, depth + 2)
                }
            }
        }
        walk(tree.nodes, 0)
        return out
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xxs) {
                ForEach(rows) { row in
                    switch row {
                    case .card(let node, let depth): card(node).padding(.leading, CGFloat(depth) * 18)
                    case .branch(let branch, let depth):
                        Text(ext: branch.label).font(Theme.Font.caption.weight(.semibold)).foregroundStyle(branch.tone == .neutral ? Theme.inkMuted : branch.tone.color)
                            .padding(.leading, CGFloat(depth) * 18).padding(.top, Theme.Space.xs)
                    }
                }
            }
            .padding(EdgeInsets(top: Theme.Space.m, leading: 64, bottom: Theme.Space.xxl, trailing: Theme.Space.l))
        }
    }

    private func card(_ node: ExtensionPage.Tree.Node) -> some View {
        Button {
            guard let select = tree.select else { return }
            Task { await model.run(tool: select.tool, input: select.input(.string(node.id))) }
        } label: {
            HStack(spacing: Theme.Space.s) {
                TreeTile(symbol: node.symbol, color: node.color, side: 26, tone: node.state == .attention ? .warn : nil)
                if let kind = node.kind { Text(ext: kind).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1) }
                Text(ext: node.title).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                if let pill = node.pill { TreePill(badge: pill) }
            }
            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xxs + 2)
            .background(tree.selected == node.id ? (chosen ?? Theme.accent).opacity(0.12) : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .contextMenu { TreeCardActions(node: node, tree: tree, model: model) }
        .accessibilityActions { TreeCardActions(node: node, tree: tree, model: model) }
        .accessibilityAddTraits(tree.selected == node.id ? .isSelected : [])
    }
}
