import SidefolkCore
import SwiftUI

/// All Extensions (D67): every page and tile extensions add, as cards, with each one's state, its main switch, and
/// where it shows (the sidebar, Today). The place that keeps many extensions easy: hide pages from the sidebar and
/// they stay one click away here.
struct ExtensionsHubView: View {
    var pages: ExtensionPagesModel
    var open: (String) -> Void

    var body: some View {
        PageScroll(maxWidth: 1100) {
            VStack(alignment: .leading, spacing: 3) {
                Text("All Extensions", comment: "Home's sidebar: the page listing every extension's page and tile")
                    .font(Theme.Font.title).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Text("Pages and tiles your extensions add. Choose what shows in the sidebar and on Today; right-click a page in the sidebar to move it.",
                     comment: "Under All Extensions' title")
                    .font(Theme.Font.body).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            if pages.list.isEmpty {
                RowsCard { InlineEmpty(text: "No extension adds a page right now.", systemImage: "puzzlepiece.extension") }
            } else {
                CardGrid(minWidth: 300, maxColumns: 3, spacing: Theme.Space.m) {
                    ForEach(pages.all) { info in ExtensionHubCard(info: info, pages: pages, open: open) }
                }
            }
            if let problem = pages.problem {
                Text(verbatim: problem).font(Theme.Font.caption).foregroundStyle(Theme.danger)
            }
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "info.circle").foregroundStyle(Theme.inkFaint)
                Text("Extensions that add only tools and commands, and extensions to add, are in Settings.", comment: "At the foot of All Extensions")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                Button { pages.services.openSettings(tab: .extensions) } label: { Text("Open Settings").font(Theme.Font.captionStrong) }
                    .buttonStyle(.sfPlain).foregroundStyle(Theme.link)
            }
        }
        .task { await pages.refreshSummaries() }
    }
}

private struct ExtensionHubCard: View {
    var info: ExtensionPageInfo
    var pages: ExtensionPagesModel
    var open: (String) -> Void

    var body: some View {
        let summary = pages.summaries[info.id]
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                PageIcon(info: info, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: info.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    if info.extensionName != info.title {
                        Text("Added by \(info.extensionName)", comment: "Under an extension page's title: the extension it comes from")
                            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                if let control = summary?.control { QuickControl(info: info, control: control, pages: pages) }
            }
            if let tagline = info.tagline, !tagline.isEmpty {
                Text(verbatim: tagline).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            if let summary {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if summary.tone != .neutral { Image(systemName: summary.tone.symbol).foregroundStyle(summary.tone.color).imageScale(.small) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: summary.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                        if !summary.detail.isEmpty {
                            Text(verbatim: summary.detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).monospacedDigit()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Divider()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Toggle(isOn: Binding(get: { pages.layout.inSidebar(info.id) }, set: { pages.setInSidebar(info.id, $0) })) {
                        Text("In the sidebar", comment: "All Extensions: whether a page has a row in Home's sidebar")
                    }
                    if info.widget {
                        Toggle(isOn: Binding(get: { pages.layout.tile(info.id) }, set: { pages.setTile(info.id, $0) })) {
                            Text("Tile on Today", comment: "All Extensions: whether a page shows its tile on Today")
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .font(Theme.Font.caption)
                Spacer(minLength: Theme.Space.s)
                Button("Open") { open(info.id) }.buttonStyle(.sf(.secondary))
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
        .contextMenu { ExtensionPageMenu(info: info, pages: pages) }
    }
}
