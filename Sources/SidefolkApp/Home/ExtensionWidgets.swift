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
        // In the person's order, without the tiles they took off Today (D67).
        let layout = services.runtime.settings.current.homePages
        let pages = await host.pages()
        let byId = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for info in layout.sorted(pages.map(\.id)).compactMap({ byId[$0] }) where info.widget && layout.tile(info.id) {
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
    /// Home's pages, for a tile's main switch (D67); absent where nothing can run it (UI snapshots).
    @Environment(ExtensionPagesModel.self) private var pages: ExtensionPagesModel?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.Space.m, alignment: .top)], alignment: .leading,
                  spacing: Theme.Space.m) {
            ForEach(model.widgets) { w in tile(w) }
        }
    }

    /// The page's summary opens the page; its main switch, when it has one, works right here.
    private func tile(_ w: ExtensionWidget) -> some View {
        let tone = w.summary?.tone ?? .neutral
        return HStack(spacing: Theme.Space.m) {
            Button { model.openPage?(w.id) } label: {
                HStack(spacing: Theme.Space.m) {
                    PageIcon(info: w.info, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ext: w.info.title).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        HStack(spacing: 6) {
                            if tone != .neutral { Image(systemName: tone.symbol).foregroundStyle(tone.color).imageScale(.small) }
                            Text(ext: w.summary?.title ?? String(localized: "Not read yet", comment: "A Today tile whose extension page hasn't been read"))
                                .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        if let detail = w.summary?.detail, !detail.isEmpty {
                            Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Open \(w.info.title)", comment: "A Today tile for an extension's page; the page's title"))
            if let control = w.summary?.control {
                QuickControl(info: w.info, control: control, pages: pages)
            } else {
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkFaint).imageScale(.small)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// An extension page's main switch or button (D67) where people are: on its Today tile and its sidebar row. It runs
/// the extension's own tool as the person, like the same switch on the page.
struct QuickControl: View {
    var info: ExtensionPageInfo
    var control: ExtensionPage.Control
    var pages: ExtensionPagesModel?
    var small = false
    @State private var running = false

    var body: some View {
        switch control.kind {
        case .toggle(let on):
            Toggle(isOn: Binding(get: { pages?.isOn(info.id) ?? on }, set: { new in
                guard let pages else { return }
                Task { await pages.flip(info, control, on: new) }
            })) { Text(ext: control.label) }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(small ? .mini : .regular)
                .disabled(pages == nil || pages?.switching[info.id] != nil)
                .help(Text(ext: control.detail ?? control.label))
                .accessibilityLabel(Text(ext: "\(info.title), \(control.label)"))
        case .button:
            Button {
                guard let pages else { return }
                running = true
                Task {
                    await pages.flip(info, control, on: nil)
                    running = false
                }
            } label: {
                if let symbol = control.symbol, small {
                    Image(systemName: symbol)
                } else {
                    Text(ext: control.label)
                }
            }
            .buttonStyle(.sf(style))
            .controlSize(small ? .mini : .small)
            .disabled(pages == nil || running || control.disabled)
            .help(Text(ext: control.detail ?? control.label))
        }
    }

    /// The page's own emphasis (D74): "Start sharing" filled, "Stop sharing" red.
    private var style: SFButtonStyle.Kind {
        switch control.style ?? .secondary {
        case .primary: .primary
        case .destructive: .destructive
        case .secondary, .plain: .secondary
        }
    }
}
