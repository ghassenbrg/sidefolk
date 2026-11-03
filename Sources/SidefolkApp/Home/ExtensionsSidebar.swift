import SidefolkCore
import SwiftUI

/// Extensions' pages in Home's sidebar (D62, D67, D84): a group that folds away, each page where the person put it (drag,
/// or Move Up and Down), an on/off feature's switch or state right on its row, the pages put out of the sidebar in one
/// menu, and "Get add-ons", which opens the Gallery. There is no separate All Extensions page any more (D84).
struct ExtensionsSidebarSection: View {
    var pages: ExtensionPagesModel
    var selection: HomeSelection?
    var getAddOns: () -> Void

    var body: some View {
        Section(isExpanded: Binding(get: { !pages.layout.collapsed }, set: { pages.setCollapsed(!$0) })) {
            ForEach(pages.shown) { p in
                HStack(spacing: Theme.Space.s + 2) {
                    PageSquircle(info: p)
                    Text(verbatim: p.title).font(selection == .page(p.id) ? Theme.Font.bodyStrong : Theme.Font.body)
                        .foregroundStyle(selection == .page(p.id) ? Theme.onSidebarSelected : Theme.sidebarInk).lineLimit(1)
                    if pages.services.updates.addonUpdate(for: p.extensionId) != nil { AddonUpdateDot() }
                    Spacer(minLength: Theme.Space.xs)
                    if let control = pages.summaries[p.id]?.control, case .toggle = control.kind {
                        QuickControl(info: p, control: control, pages: pages, small: true)
                    }
                }
                .background(SidebarHighlightOff())
                .tag(HomeSelection.page(p.id))
                .listRowBackground(SidebarRowFill(selected: selection == .page(p.id)))
                .help(Text("Added by \(p.extensionName)", comment: "Under an extension page's title: the extension it comes from"))
                .contextMenu { ExtensionPageMenu(info: p, pages: pages) }
            }
            .onMove { from, to in
                let shown = pages.shown
                guard let i = from.first, shown.indices.contains(i) else { return }
                pages.move(shown[i].id, before: to < shown.count ? shown[to].id : nil)
            }
            if !pages.hidden.isEmpty {
                Menu {
                    ForEach(pages.hidden) { p in
                        Button(String(localized: "Show “\(p.title)” in the Sidebar", comment: "A page put out of Home's sidebar, brought back")) {
                            pages.setInSidebar(p.id, true)
                        }
                    }
                } label: {
                    Label { Text("\(pages.hidden.count) more", comment: "Home's sidebar: extension pages put out of it") } icon: {
                        Image(systemName: "ellipsis").frame(width: 20)
                    }
                    .font(Theme.Font.body)
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(Theme.sidebarInkMuted)
                .selectionDisabled()
            }
            Button(action: getAddOns) {
                HStack(spacing: Theme.Space.s + 2) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 20)
                    Text("Get add-ons", comment: "Home's sidebar: opens the Gallery of companions, extensions and themes")
                        .font(Theme.Font.body)
                    let updates = pages.services.updates.addonPending.count
                    if updates > 0 {
                        Spacer(minLength: Theme.Space.xs)
                        CountBadge(count: updates, waiting: false)
                            .help(Text(verbatim: AddonUpdateWords.count(updates)))
                            .accessibilityLabel(Text(verbatim: AddonUpdateWords.count(updates)))
                    }
                }
                .foregroundStyle(selection == .gallery ? Theme.onSidebarSelected : Theme.sidebarInkMuted)
            }
            .buttonStyle(.sfBare)
            .background(SidebarHighlightOff())
            .tag(HomeSelection.gallery)
            .listRowBackground(SidebarRowFill(selected: selection == .gallery))
            .help(Text("Companions, extensions and themes in the Gallery"))
        } header: {
            Text("Extensions").foregroundStyle(Theme.sidebarInkMuted)
        }
    }
}

/// An extension page's icon in the sidebar: its extension's own, or its symbol on a tinted squircle (03-system).
struct PageSquircle: View {
    var info: ExtensionPageInfo
    var size: CGFloat = 20

    var body: some View {
        if info.iconPath != nil {
            ExtensionBadge(look: ExtensionLook(name: info.extensionName, iconPath: info.iconPath, folk: "byte"), size: size,
                           symbol: info.symbol ?? "puzzlepiece.extension")
        } else {
            SidebarSquircle(symbol: info.symbol ?? "puzzlepiece.extension", color: Theme.folkColor("byte"), size: size)
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
