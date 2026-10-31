import SidefolkCore
import SwiftUI

/// A tile on Today for an extension page whose manifest asks for one (D62): the page's summary, and a click opens it.
struct ExtensionWidget: Identifiable, Equatable {
    var info: ExtensionPageInfo
    var summary: ExtensionPage.Summary?
    var at: Date?
    var id: String { info.id }
}

extension NowModel {
    /// What each tile's page said last. Sidefolk reads those pages once a minute in the background; a tile it hasn't
    /// read yet, or not for two minutes, is read now.
    func reloadWidgets() async {
        let host = services.runtime.extensions
        var out: [ExtensionWidget] = []
        for info in await host.pages() where info.widget {
            var latest = await host.latestPage(extensionId: info.extensionId, page: info.page)
            if latest == nil || Date().timeIntervalSince(latest!.at) > 120,
               let page = try? await host.renderPage(extensionId: info.extensionId, page: info.page, language: ExtensionPageModel.language) {
                latest = (Date(), page)
            }
            out.append(ExtensionWidget(info: info, summary: latest?.page.summary, at: latest?.at))
        }
        if out != widgets { widgets = out }
    }
}

/// Tiles side by side where there's room; one a line in a narrow column (a 280-point minimum overflowed a Desk's
/// 230-point column).
struct ExtensionWidgetsSection: View {
    var model: NowModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.Space.m, alignment: .top)], alignment: .leading,
                  spacing: Theme.Space.m) {
            ForEach(model.widgets) { w in
                Button { model.openPage?(w.id) } label: { tile(w) }
                    .buttonStyle(.plain)
                    .help(Text("Open \(w.info.title)", comment: "A Today tile for an extension's page; the page's title"))
            }
        }
    }

    private func tile(_ w: ExtensionWidget) -> some View {
        let tone = w.summary?.tone ?? .neutral
        return HStack(spacing: Theme.Space.m) {
            PageIcon(info: w.info, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: w.info.title).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                HStack(spacing: 6) {
                    if tone != .neutral { Image(systemName: tone.symbol).foregroundStyle(tone.color).imageScale(.small) }
                    Text(verbatim: w.summary?.title ?? String(localized: "Not read yet", comment: "A Today tile whose extension page hasn't been read"))
                        .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                }
                if let detail = w.summary?.detail, !detail.isEmpty {
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Theme.inkFaint).imageScale(.small)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .contentShape(Rectangle())
    }
}
