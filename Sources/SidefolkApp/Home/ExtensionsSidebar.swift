import SidefolkCore
import SwiftUI

/// Extensions' pages in Home's sidebar (D62, D67): a group that folds away, each page where the person put it (drag,
/// or Move Up and Down), out of the sidebar when they'd rather (it stays in All Extensions), and an on/off feature's
/// switch right on its row.
struct ExtensionsSidebarSection: View {
    var pages: ExtensionPagesModel

    var body: some View {
        Section(isExpanded: Binding(get: { !pages.layout.collapsed }, set: { pages.setCollapsed(!$0) })) {
            ForEach(pages.shown) { p in
                HStack(spacing: Theme.Space.xs) {
                    Label { Text(verbatim: p.title) } icon: { PageNavIcon(info: p) }
                    Spacer(minLength: Theme.Space.xs)
                    if let control = pages.summaries[p.id]?.control, case .toggle = control.kind {
                        QuickControl(info: p, control: control, pages: pages, small: true)
                    }
                }
                .tag(HomeSelection.page(p.id))
                .help(Text("Added by \(p.extensionName)", comment: "Under an extension page's title: the extension it comes from"))
                .contextMenu { ExtensionPageMenu(info: p, pages: pages) }
            }
            .onMove { from, to in
                let shown = pages.shown
                guard let i = from.first, shown.indices.contains(i) else { return }
                pages.move(shown[i].id, before: to < shown.count ? shown[to].id : nil)
            }
            Label {
                Text("All Extensions", comment: "Home's sidebar: the page listing every extension's page and tile")
            } icon: {
                NavIcon(symbol: "square.grid.2x2", color: Theme.inkMuted)
            }
            .tag(HomeSelection.page(ExtensionPagesModel.hub))
            .help(Text("Every extension's page and tile, and where each one shows", comment: "Home's sidebar: All Extensions"))
        } header: {
            Text("Extensions")
        }
    }
}

/// What a page's row (and its card in All Extensions) offers on Control-click.
struct ExtensionPageMenu: View {
    var info: ExtensionPageInfo
    var pages: ExtensionPagesModel

    var body: some View {
        let inSidebar = pages.layout.inSidebar(info.id)
        if inSidebar {
            let shown = pages.shown.map(\.id)
            Button("Move Up") { pages.step(info.id, by: -1) }.disabled(shown.first == info.id)
            Button("Move Down") { pages.step(info.id, by: 1) }.disabled(shown.last == info.id)
            Divider()
        }
        Button(inSidebar ? String(localized: "Hide from Sidebar") : String(localized: "Show in Sidebar")) {
            pages.setInSidebar(info.id, !inSidebar)
        }
        if info.widget {
            let tile = pages.layout.tile(info.id)
            Button(tile ? String(localized: "Remove Tile from Today") : String(localized: "Show Tile on Today")) {
                pages.setTile(info.id, !tile)
            }
        }
        Divider()
        Button("Extension Settings…") { pages.services.openSettings(tab: .extensions) }
    }
}
