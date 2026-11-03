import AppKit
import SidefolkCore
import SwiftUI

// The richer parts of an extension's page (D100): a hero with a scene and a figure, a strip of numbers, a grid of cards with
// pictures from the pack, tabs, badges, the last things that happened and the extension's settings. Enough for an extension
// to draw a whole center of its own. Sidefolk's drawing in the theme's colours; the words and pictures are the extension's,
// and every click runs one of its own tools as the person, through Guard.

/// One of the parts above, by kind.
struct RichBlockView: View {
    var block: ExtensionPage.Block
    var model: ExtensionPageModel

    var body: some View {
        switch block {
        case .stats(let strip): PageStatStrip(strip: strip)
        case .cards(let grid): PageCardGrid(grid: grid, model: model)
        case .tabs(let tabs): PageTabs(tabs: tabs, model: model)
        case .badges(let list): PageBadges(list: list)
        case .recent(let list): PageRecent(list: list, model: model)
        case .settings(let rows): PageSettings(rows: rows, model: model)
        case .scene(let scene): PageSceneBlock(block: scene, model: model)
        case .table(let table): PageTableView(table: table, model: model)
        case .steps(let steps): PageStepsView(steps: steps, model: model)
        case .tree(let tree): PageTreeView(tree: tree, model: model).frame(minHeight: 420)
        case .bar(let bar): PageBarView(bar: bar, model: model)
        case .nav(let nav): PageNavView(nav: nav, model: model)
        case .notice(let notice): PageNoticeView(notice: notice, model: model)
        case .ticks(let ticks): PageTicksView(ticks: ticks)
        default: EmptyView()
        }
    }
}

// MARK: Pictures

/// A picture a page names: decoded off the main thread and kept while the page lives, or nothing when it can't be read: the part
/// draws without it. Dark mode's version where the pack has one.
struct PagePictureView: View {
    var picture: PagePicture
    var model: ExtensionPageModel
    var side: Int
    var fill = true
    /// What it stands on, once it is there: a tile of plain colour on its own reads as a missing picture.
    var backing: Color?
    var backingInset: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: fill ? .fill : .fit)
                    .padding(backingInset).background(backing ?? .clear)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
        .task(id: "\(picture)\(scheme == .dark)") { image = await model.image(picture, dark: scheme == .dark, side: side) }
    }
}

// MARK: Hero with a scene

/// A hero with a picture behind it at its trailing end and a figure standing there, its words in a bubble inside the page. Its title
/// is large, as the page's own (`homePageTitle`), so the toolbar's shows only once this has scrolled away.
struct PageSceneHero: View {
    var hero: ExtensionPage.Hero
    var model: ExtensionPageModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.surfaceRaised
            if let wash { LinearGradient(colors: [wash.first ?? .clear, wash.last ?? .clear], startPoint: .top, endPoint: .bottom) }
            if let scene = hero.scene {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PagePictureView(picture: scene, model: model, side: 840)
                        .frame(width: 420, height: 230, alignment: .bottom).clipped()
                        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing)
                            .environment(\.layoutDirection, .leftToRight).flipsForRightToLeftLayoutDirection(true))
                }
                .allowsHitTesting(false)
            }
            HStack(alignment: .bottom, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let eyebrow = hero.eyebrow {
                        Text(ext: eyebrow).font(Theme.Font.callout.weight(.semibold)).foregroundStyle(hero.tone == .neutral ? Theme.accent : hero.tone.color)
                    }
                    HStack(spacing: Theme.Space.m) {
                        if let symbol = hero.symbol {
                            let tile = hero.tile.compactMap { Color(extensionHex: $0) }
                            Image(systemName: symbol).font(.system(size: 24, weight: .bold)).foregroundStyle(tile.isEmpty ? Theme.accent : Color.white)
                                .frame(width: 52, height: 52)
                                .background(tile.isEmpty ? AnyShapeStyle(Theme.accentSoft) : AnyShapeStyle(LinearGradient(colors: tile.count == 1 ? tile + tile : tile, startPoint: .top, endPoint: .bottom)),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ext: hero.title).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                                .accessibilityAddTraits(.isHeader).homePageTitle()
                            if let detail = hero.detail { Text(ext: detail).font(Theme.Font.body).foregroundStyle(Theme.inkMuted) }
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Space.s) { actions }
                        VStack(alignment: .leading, spacing: Theme.Space.s) { actions }
                    }
                }
                .padding(Theme.Space.xl)
                Spacer(minLength: 0)
                if let figure = hero.figure {
                    VStack(alignment: .trailing, spacing: 0) {
                        if let says = hero.says {
                            Text(ext: says).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true).lineLimit(5)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background {
                                    HeroBubbleShape().fill(Theme.surface).shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                                        .overlay(HeroBubbleShape().stroke(Theme.line, lineWidth: 1))
                                }
                                .frame(maxWidth: 220, alignment: .trailing)
                        }
                        ZStack(alignment: .bottom) {
                            Ellipse().fill(RadialGradient(colors: [.black.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 50))
                                .frame(width: 110, height: 12).offset(y: 5)
                            PagePictureView(picture: figure, model: model, side: 440, fill: false).frame(width: 130, height: 120, alignment: .bottom)
                        }
                        .frame(width: 130, height: 120, alignment: .bottom)
                        .accessibilityHidden(true)
                    }
                    .padding(.trailing, Theme.Space.xl).padding(.top, Theme.Space.m)
                }
            }
        }
        .frame(minHeight: 230)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .elevation(.e1, radius: Theme.Radius.panel)
    }

    private var actions: some View {
        ForEach(Array(hero.actions.enumerated()), id: \.offset) { _, c in PageButton(control: c, model: model, large: true) }
    }

    /// Soft, so what stands on it stays readable: the colours the extension names at a tenth or so of their strength, a little more in the dark.
    @Environment(\.colorScheme) private var scheme
    private var wash: [Color]? {
        let colors = hero.wash.compactMap { Color(extensionHex: $0) }
        guard let top = colors.first else { return nil }
        return [top.opacity(0.10), (colors.last ?? top).opacity(scheme == .dark ? 0.22 : 0.16)]
    }
}

/// A rounded bubble with a small tail under its middle, toward whoever stands below it.
nonisolated struct HeroBubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: 18, style: .continuous)
        p.move(to: CGPoint(x: r.midX - 10, y: r.maxY - 1))
        p.addQuadCurve(to: CGPoint(x: r.midX + 2, y: r.maxY + 11), control: CGPoint(x: r.midX - 2, y: r.maxY + 6))
        p.addQuadCurve(to: CGPoint(x: r.midX + 10, y: r.maxY - 1), control: CGPoint(x: r.midX + 5, y: r.maxY + 4))
        return p
    }
}

// MARK: Numbers

struct PageStatStrip: View {
    var strip: ExtensionPage.StatStrip

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) { items }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.s)], spacing: Theme.Space.s) { items }
        }
        .padding(Theme.Space.s)
        .cardSurface(radius: Theme.Radius.panel)
    }

    private var items: some View {
        ForEach(Array(strip.items.enumerated()), id: \.offset) { _, item in
            HStack(spacing: Theme.Space.m) {
                if let symbol = item.symbol {
                    Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(item.color.flatMap { Color(extensionHex: $0) } ?? (item.tone == .neutral ? Theme.accent : item.tone.color)).frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(ext: item.value).font(Theme.Font.number).monospacedDigit().foregroundStyle(Theme.ink).lineLimit(1)
                    Text(ext: item.label).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.well))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: Cards

struct PageCardGrid: View {
    var grid: ExtensionPage.CardGrid
    var model: ExtensionPageModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: grid.size == .large ? 400 : 270), spacing: Theme.Space.m, alignment: .top)], alignment: .leading,
                  spacing: Theme.Space.m) {
            ForEach(Array(grid.items.enumerated()), id: \.offset) { _, item in PageCard(item: item, size: grid.size, model: model) }
        }
    }
}

struct PageCard: View {
    var item: ExtensionPage.CardGrid.Item
    var size: ExtensionPage.CardGrid.Size
    var model: ExtensionPageModel

    private var side: CGFloat { size == .large ? 84 : 56 }

    var body: some View {
        if let press = item.press {
            // The whole card goes somewhere (D125).
            card
                .contentShape(Rectangle())
                .onTapGesture { Task { await model.run(press, on: nil) } }
                .accessibilityAction(named: Text(ext: press.label)) { Task { await model.run(press, on: nil) } }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            plain
            // Its tree's small drawing at its foot (D125).
            if let tree = item.tree { TreeMini(tree: tree).frame(maxWidth: .infinity) }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .cardSurface(radius: Theme.Radius.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ext: [item.title, item.detail].compactMap { $0 }.joined(separator: ", ")))
    }

    private var plain: some View {
        HStack(alignment: size == .large ? .top : .center, spacing: Theme.Space.m) {
            if let first = item.actions.first, !first.disabled {
                Button { Task { await model.run(first, on: nil) } } label: { tile }.buttonStyle(.sfBare).accessibilityHidden(true)
            } else {
                tile
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Space.xs) {
                    Text(ext: item.title).font(size == .large ? .system(size: 16, weight: .heavy, design: .rounded) : Theme.Font.headline)
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    if let badge = item.badge {
                        if item.press != nil {
                            TreePill(badge: badge)
                        } else {
                            Text(ext: badge.text).font(Theme.Font.caption.weight(.bold)).foregroundStyle(badge.tone == .neutral ? Theme.ink : badge.tone.color)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(badge.tone == .neutral ? Theme.well : badge.tone.soft, in: Capsule())
                        }
                    }
                }
                if let detail = item.detail {
                    Text(ext: detail).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                if let meta = item.meta { Text(ext: meta).font(Theme.Font.caption).foregroundStyle(Theme.ink).lineLimit(2) }
                if let at = item.at { Text(at, format: .relative(presentation: .named)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint) }
            }
            Spacer(minLength: 0)
            if item.done {
                Image(systemName: ExtensionPage.Tone.good.symbol).font(.system(size: 22)).foregroundStyle(ExtensionPage.Tone.good.color)
                    .accessibilityLabel(Text("Done", comment: "A card on an extension's page: what it is about is done for today"))
            }
            if !item.actions.isEmpty || item.menu != nil {
                VStack(spacing: Theme.Space.xs) {
                    // A round action is the card's own, and a tick takes its place once it is done; the picture still runs it.
                    ForEach(Array(item.actions.enumerated()), id: \.offset) { _, c in if !(c.round && item.done) { PageButton(control: c, model: model) } }
                    if let menu = item.menu {
                        Menu {
                            ForEach(Array(menu.items.enumerated()), id: \.offset) { _, c in
                                Button { Task { await model.run(c, on: nil) } } label: { Text(ext: c.label) }.disabled(c.disabled)
                            }
                        } label: {
                            Text(ext: menu.label)
                        }
                        .menuStyle(.borderlessButton).fixedSize().font(Theme.Font.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var tile: some View {
        // A card that's one whole button says what it's about quietly: the words and its tree are what's there to read (D125).
        if item.press != nil, item.picture == nil {
            TreeTile(symbol: item.symbol, color: item.color, side: 44)
        } else if let picture = item.picture {
            // With a colour, the picture stands on a tile of it, a little inside its edges.
            let tile = item.color.flatMap { Color(extensionHex: $0) }
            PagePictureView(picture: picture, model: model, side: Int(side) * 2, fill: tile == nil, backing: tile, backingInset: tile == nil ? 0 : side * 0.07)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: size == .large ? 18 : 12, style: .continuous))
        } else if let symbol = item.symbol {
            Image(systemName: symbol).font(.system(size: side * 0.4, weight: .semibold))
                .foregroundStyle(item.color == nil ? Theme.accent : Color.white)
                .frame(width: side, height: side)
                .background(item.color.flatMap { Color(extensionHex: $0) } ?? Theme.accentSoft, in: RoundedRectangle(cornerRadius: size == .large ? 18 : 12, style: .continuous))
        }
    }
}

// MARK: Tabs

/// Sections one at a time. Switching asks nothing of the program; the choice stays while Home is open.
struct PageTabs: View {
    var tabs: ExtensionPage.Tabs
    var model: ExtensionPageModel
    @Environment(\.colorScheme) private var scheme

    private var chosenFill: Color? { tabs.tint.flatMap { Color(extensionHex: scheme == .dark ? $0.dark : $0.light) } }

    var body: some View {
        let key = tabs.tabs.map(\.id).joined(separator: "/")
        // Tabs that go somewhere are the program's to say; the others stay where the person left them.
        let programs = tabs.tabs.contains { $0.go != nil }
        let shown = (programs ? nil : model.tabChoices[key].flatMap { id in tabs.tabs.first { $0.id == id } }) ?? tabs.tabs.first { $0.id == tabs.selected } ?? tabs.tabs[0]
        let selection = Binding(get: { shown.id }, set: { id in
            if let go = tabs.tabs.first(where: { $0.id == id })?.go { Task { await model.go(go) } } else { model.tabChoices[key] = id }
        })
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            // When they don't all fit, a menu that says which is showing, so none is out of reach (D105).
            ViewThatFits(in: .horizontal) {
                SegmentedPicker(Text("Show", comment: "VoiceOver: tabs on an extension's page"), selection: selection,
                                segments: tabs.tabs.map { tab in
                                    .init(tab.id, tab.badge.map { Text(ext: tab.label) + Text(verbatim: " ") + Text(ext: $0) } ?? Text(ext: tab.label), symbol: tab.symbol)
                                }, chosenFill: chosenFill)
                    .fixedSize()
                Picker(selection: selection) {
                    ForEach(tabs.tabs, id: \.id) { tab in Label { Text(ext: tab.label) } icon: { Image(systemName: tab.symbol ?? "circle") }.tag(tab.id) }
                } label: {
                    Text("Show", comment: "VoiceOver: tabs on an extension's page")
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
            }
            ForEach(Array(shown.sections.enumerated()), id: \.offset) { _, section in SectionView(section: section, model: model) }
            ForEach(Array(tabs.sections.enumerated()), id: \.offset) { _, section in SectionView(section: section, model: model) }
        }
    }
}

// MARK: Badges

struct PageBadges: View {
    var list: ExtensionPage.BadgeList

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let title = list.title { Text(ext: title).font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.Space.s, alignment: .top)], alignment: .leading, spacing: Theme.Space.s) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in badge(item) }
            }
        }
    }

    private func badge(_ item: ExtensionPage.BadgeList.Item) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: item.symbol ?? "seal.fill").font(.system(size: 20, weight: .semibold))
                .foregroundStyle(item.earned ? Theme.accent : Theme.inkFaint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(ext: item.title).font(Theme.Font.bodyStrong).foregroundStyle(item.earned ? Theme.ink : Theme.inkMuted).lineLimit(2)
                if let detail = item.detail {
                    Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                if !item.earned, let value = item.value, let goal = item.goal {
                    ProgressView(value: Double(value), total: Double(goal)).controlSize(.small).tint(Theme.accent)
                    Text(verbatim: "\(value.formatted()) / \(goal.formatted())").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

// MARK: Recent

struct PageRecent: View {
    var list: ExtensionPage.RecentList
    var model: ExtensionPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let title = list.title { Text(ext: title).font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
            RowsCard {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: Theme.Space.m) {
                        if let picture = item.picture {
                            PagePictureView(picture: picture, model: model, side: 64).frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            // Meaning is never colour alone (D78): the tone comes with its symbol.
                            Image(systemName: item.symbol ?? item.tone.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(item.tone.color).frame(width: 32)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ext: item.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                            if let detail = item.detail { Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1) }
                        }
                        Spacer(minLength: Theme.Space.s)
                        if let at = item.at { Text(at, format: .relative(presentation: .named)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1) }
                    }
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: Settings on the page

struct PageSettings: View {
    var rows: ExtensionPage.SettingsRows
    var model: ExtensionPageModel

    var body: some View {
        let chosen = rows.keys.isEmpty ? model.settingRows.filter(\.listed) : rows.keys.compactMap { key in model.settingRows.first { $0.key == key } }
        if !chosen.isEmpty || (rows.ai && model.aiStatus != nil) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let title = rows.title { Text(ext: title).font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
                if rows.grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                        ForEach(chosen) { row in gridRow(row) }
                    }
                } else {
                    RowsCard {
                        ForEach(chosen) { row in ExtensionSettingRowView(row: row) { value in Task { await model.set(row, to: value) } } }
                        if rows.ai, let ai = model.aiStatus {
                            // Its own words only where they can be believed; the switch and what it does are the same.
                            let own = model.signedBySidefolk
                            ExtensionAISwitchRow(status: ai, title: own ? rows.aiTitle : nil, detail: own ? rows.aiDetail : nil) { on in Task { await model.setAI(on) } }
                        }
                    }
                }
            }
        }
    }

    /// One choice of many: its picture, its name, and the choice.
    private func gridRow(_ row: ExtensionSettingRow) -> some View {
        HStack(spacing: Theme.Space.m) {
            if let picture = rows.pictures[row.key] {
                PagePictureView(picture: picture, model: model, side: 60).frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text(ext: row.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            Picker(selection: Binding(get: { row.value.stringValue ?? "" }, set: { value in Task { await model.set(row, to: .string(value)) } })) {
                ForEach(row.options, id: \.value) { option in Text(ext: option.title).tag(option.value) }
            } label: {
                Text(ext: row.title)
            }
            .labelsHidden().fixedSize()
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.xs)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surfaceRaised))
    }
}
