import SidefolkCore
import SwiftUI

/// Says that the page showing takes the window (D126): Home folds its sidebar while it does. The person can still open it with the toolbar's button.
struct PageTakesWindow: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// A page that takes the window (D126): a column of places at the start, the main part in the middle and what's selected at the end. Each scrolls on its own, and a tree in
/// the middle fills what's left. Narrower, the places go first; narrower still, the end column sits under the main part. What goes where stays the extension's word.
struct PageWorkspace: View {
    var page: ExtensionPage
    var model: ExtensionPageModel

    private static let places: CGFloat = 232
    private static let details: CGFloat = 320

    private var leading: [ExtensionPage.Section] { page.sections.filter { $0.place == .side } }
    private var trailing: [ExtensionPage.Section] { page.sections.filter { $0.place == .trailing } }
    private var middle: [ExtensionPage.Section] { page.sections.filter { $0.place == .main || $0.place == .bottom } }
    /// Heads stay put while what's under them scrolls.
    private var heads: [ExtensionPage.Section] { Array(middle.prefix { $0.isHead }) }
    private var rest: [ExtensionPage.Section] { Array(middle.drop { $0.isHead }) }

    var body: some View {
        GeometryReader { geo in
            let showsPlaces = geo.size.width >= 900 && !leading.isEmpty
            let beside = geo.size.width >= 780
            HStack(spacing: 0) {
                if showsPlaces {
                    column(leading, padded: Theme.Space.m)
                        // At the foot of the places, where nothing it stands on can be pressed.
                        .safeAreaInset(edge: .bottom, spacing: 0) { if standsBy { companion } }
                        .frame(width: Self.places)
                    Divider()
                }
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        status(named: showsPlaces && leading.contains { $0.blocks.contains { if case .nav(let nav) = $0 { nav.brand } else { false } } })
                        ForEach(Array(heads.enumerated()), id: \.offset) { _, section in SectionView(section: section, model: model) }
                    }
                    .padding(.horizontal, Theme.Space.xl).padding(.top, Theme.Space.m).padding(.bottom, heads.isEmpty ? 0 : Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !heads.isEmpty { Divider() }
                    HStack(spacing: 0) {
                        main
                        if beside, !trailing.isEmpty {
                            column(trailing, padded: Theme.Space.l)
                                .frame(width: Self.details)
                                .background(Theme.surfaceRaised)
                                .overlay(alignment: .leading) { Divider() }
                        }
                    }
                    if !beside, !trailing.isEmpty {
                        Divider()
                        column(trailing, padded: Theme.Space.l)
                            .frame(maxHeight: geo.size.height * 0.42)
                            .background(Theme.surfaceRaised)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.setWidth($0) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { PageGround(dress: page.dress, model: model) }
        .preference(key: PageTakesWindow.self, value: true)
    }

    /// While something's happening on a tree, it stands there instead.
    private var standsBy: Bool {
        page.companion && !middle.contains { $0.blocks.contains { if case .tree(let t) = $0 { t.reading.contains { $0.state == .active } } else { false } } }
    }

    private var companion: some View {
        PagePictureView(picture: .companion(.full), model: model, side: 180, fill: false)
            .frame(width: 64, height: 64)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.Space.s)
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    /// What went wrong with a click, and the words a click just copied, are Sidefolk's to say whatever the page draws (D105).
    /// `named`: the column of places already says whose page this is, as Sidefolk knows it.
    @ViewBuilder private func status(named: Bool) -> some View {
        // The way back stays with no head to draw it (D105).
        if let back = page.back, model.state.canGoBack, !heads.contains(where: { $0.blocks.contains { if case .bar = $0 { true } else { false } } }) {
            Button { Task { await model.go(PageGo(back: true)) } } label: {
                Label { Text(ext: back) } icon: { Image(systemName: "chevron.backward") }
            }
            .buttonStyle(.sf(.quiet))
            .keyboardShortcut("[", modifiers: .command)
        }
        // Whose page this is stays Sidefolk's to say (D105).
        if !named {
            Text("Added by \(model.info.extensionName)", comment: "Under an extension page's title: the extension it comes from")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
        }
        if let problem = model.problem { NoteView(note: ExtensionPage.Note(text: problem, tone: .bad)) }
        if let copied = model.copied {
            Label { Text("Copied: \(copied)", comment: "An extension's page: the exact words a button just put on the clipboard") } icon: { Image(systemName: "doc.on.clipboard") }
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
        }
        if let updates = model.updates, let entry = updates.addonUpdate(for: model.info.extensionId) {
            AddonUpdateStrip(entry: entry, updates: updates)
        }
    }

    /// What Sidefolk adds to any extension's page: its palettes' keys and what it needs, and its heads-ups. They want the middle's width, so they go on a screen that scrolls.
    @ViewBuilder private var hostParts: some View {
        if model.info.needsAccessibility || !model.palettes.isEmpty { HostControls(model: model) }
        if !model.alerts.isEmpty { HeadsUps(model: model) }
    }

    @ViewBuilder private var main: some View {
        if let only = rest.first, rest.count == 1, case .tree(let tree)? = only.blocks.first, only.blocks.count == 1 {
            PageTreeView(tree: tree, model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    ForEach(Array(rest.enumerated()), id: \.offset) { _, section in SectionView(section: section, model: model) }
                    hostParts
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: page.maxWidth.map { CGFloat($0) } ?? 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func column(_ sections: [ExtensionPage.Section], padded: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in SectionView(section: section, model: model) }
            }
            .padding(padded)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}

extension ExtensionPage.Section {
    /// A head and the tabs under it: stays put while the rest scrolls.
    fileprivate var isHead: Bool {
        !blocks.isEmpty && blocks.allSatisfy { if case .bar = $0 { true } else if case .tabs(let tabs) = $0 { tabs.tabs.allSatisfy(\.sections.isEmpty) && tabs.sections.isEmpty } else { false } }
    }
}

// MARK: The head

/// A page's own compact head (D126): the way back, its title and state, one sentence, and what can be done from here.
struct PageBarView: View {
    var bar: ExtensionPage.PageHead
    var model: ExtensionPageModel

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            if let back = model.page?.back, model.state.canGoBack {
                Button { Task { await model.go(PageGo(back: true)) } } label: {
                    Image(systemName: "chevron.backward").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.sfBare)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
                .keyboardShortcut("[", modifiers: .command)
                .help(Text(ext: back))
                .accessibilityLabel(Text(ext: back))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.s) {
                    Text(ext: bar.title).font(Theme.Font.title).foregroundStyle(Theme.ink).lineLimit(1).accessibilityAddTraits(.isHeader).homePageTitle()
                    if let pill = bar.pill { TreePill(badge: pill) }
                }
                if let detail = bar.detail { Text(ext: detail).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).lineLimit(2) }
            }
            Spacer(minLength: Theme.Space.m)
            if !bar.menu.isEmpty {
                Menu {
                    ForEach(Array(bar.menu.enumerated()), id: \.offset) { _, control in
                        Button(role: control.style == .destructive ? .destructive : nil) { Task { await model.run(control, on: nil) } } label: {
                            Label { Text(ext: control.label) } icon: { Image(systemName: control.symbol ?? "circle") }
                        }
                        .disabled(control.disabled)
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).frame(width: 32, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .tint(Theme.ink)
                .accessibilityLabel(Text("More", comment: "A card on an extension's page: its menu"))
            }
            ForEach(Array(bar.actions.enumerated()), id: \.offset) { _, control in PageButton(control: control, model: model).fixedSize() }
        }
    }
}

// MARK: Places

/// A column of places to go (D126). It may be headed by the extension's own icon and name, as Sidefolk knows them.
struct PageNavView: View {
    var nav: ExtensionPage.Nav
    var model: ExtensionPageModel
    @Environment(\.pageSelected) private var accent
    @Environment(\.colorScheme) private var scheme

    private var selection: PageSelection { PageSelection(accent: accent, dark: scheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if nav.brand {
                HStack(spacing: Theme.Space.s) {
                    PageIcon(info: model.info, size: 30)
                    Text(ext: model.info.extensionName).font(Theme.Font.title2).foregroundStyle(Theme.ink).lineLimit(1)
                }
                .padding(.bottom, Theme.Space.s)
            }
            if nav.title != nil || nav.add != nil {
                HStack {
                    if let title = nav.title { Text(ext: title).font(Theme.Font.headline).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
                    Spacer(minLength: 0)
                    if let add = nav.add {
                        Button { Task { await model.run(add, on: nil) } } label: {
                            Image(systemName: add.symbol ?? "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink).frame(width: 24, height: 24)
                                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous).strokeBorder(Theme.line))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.sfBare)
                        .help(Text(ext: add.detail ?? add.label))
                        .accessibilityLabel(Text(ext: add.label))
                    }
                }
            }
            if !nav.filters.isEmpty {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(nav.filters) { filter in
                        Button { Task { await model.run(filter.press, on: nil) } } label: {
                            Text(ext: filter.title).font(Theme.Font.caption.weight(.medium)).lineLimit(1).foregroundStyle(filter.selected ? Theme.ink : Theme.inkMuted)
                                .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
                                .background(filter.selected ? Theme.well : Theme.surfaceRaised, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.line))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.sfBare)
                        .accessibilityAddTraits(filter.selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, Theme.Space.xxs)
            }
            ForEach(nav.items) { item in row(item) }
            if nav.items.isEmpty, let empty = nav.empty {
                Text(ext: empty).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).padding(.vertical, Theme.Space.xs)
            }
        }
    }

    private func row(_ item: ExtensionPage.Nav.Item) -> some View {
        Button { Task { await model.run(item.press, on: nil) } } label: {
            HStack(spacing: Theme.Space.s) {
                if item.color != nil {
                    TreeTile(symbol: item.symbol, color: item.color, side: 30)
                } else if let symbol = item.symbol {
                    Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(item.selected ? selection.ink : Theme.ink).frame(width: 22).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(ext: item.title).font(Theme.Font.body.weight(.medium)).foregroundStyle(item.selected && item.color == nil ? selection.ink : Theme.ink).lineLimit(1)
                    if let status = item.status {
                        HStack(spacing: 4) {
                            Circle().fill(item.tone == .neutral ? Theme.inkFaint : item.tone == .info ? selection.ink : item.tone.color).frame(width: 6, height: 6).accessibilityHidden(true)
                            Text(ext: status).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.xs).padding(.vertical, Theme.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(item.selected ? selection.soft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .help(Text(ext: item.press.detail ?? item.title))
        .accessibilityAddTraits(item.selected ? .isSelected : [])
    }
}

// MARK: What arrives

/// What a person will receive, drawn as it will arrive (D126).
struct PageNoticeView: View {
    var notice: ExtensionPage.Notice
    var model: ExtensionPageModel
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var breathing = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous) }

    var body: some View {
        if let placeholder = notice.placeholder {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: "bell").font(.system(size: 20)).foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
                Text(ext: placeholder).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity)
            .overlay(shape.strokeBorder(Theme.controlBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        } else {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                PageIcon(info: model.info, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        if let title = notice.title { Text(ext: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1) }
                        Spacer(minLength: Theme.Space.s)
                        if let time = notice.time { Text(ext: time).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).monospacedDigit() }
                    }
                    if let body = notice.body {
                        Text(ext: body).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                            .opacity(notice.forming && breathing ? 0.5 : 1)
                    }
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.line))
            .elevation(.e1)
            .accessibilityElement(children: .combine)
            .onAppear {
                guard notice.forming, !still else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { breathing = true }
            }
            if let footer = notice.footer {
                Label { Text(ext: footer) } icon: { Image(systemName: "calendar") }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).padding(.top, Theme.Space.xs)
            }
        }
    }
}

/// A row of recent results (D126): each a mark, its word on hover and to VoiceOver.
struct PageTicksView: View {
    var ticks: ExtensionPage.Ticks

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let title = ticks.title { Text(ext: title).font(Theme.Font.headline).foregroundStyle(Theme.ink) }
            HStack(spacing: Theme.Space.xs) {
                ForEach(Array(ticks.items.enumerated()), id: \.offset) { _, tick in
                    Group {
                        if tick.hollow {
                            Circle().strokeBorder(Theme.inkFaint, lineWidth: 1.5).frame(width: 16, height: 16)
                        } else {
                            Image(systemName: tick.tone == .neutral ? "circle.fill" : tick.tone.symbol).font(.system(size: 16)).foregroundStyle(tick.tone == .neutral ? Theme.inkFaint : tick.tone.color)
                        }
                    }
                    .help(Text(ext: tick.label))
                    .accessibilityElement().accessibilityLabel(Text(ext: tick.label))
                }
                if let caption = ticks.caption {
                    Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).padding(.leading, Theme.Space.s)
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
