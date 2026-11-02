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
    @Environment(\.colorScheme) private var scheme
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: fill ? .fill : .fit)
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
                            Image(systemName: symbol).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.accent)
                                .frame(width: 52, height: 52)
                                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .frame(maxHeight: .infinity)
                Spacer(minLength: 0)
                if let figure = hero.figure {
                    VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                        if let says = hero.says {
                            Text(ext: says).font(Theme.Font.callout).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                                .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
                                .frame(maxWidth: 220, alignment: .trailing)
                        }
                        PagePictureView(picture: figure, model: model, side: 440, fill: false).frame(width: 130, height: 120)
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
                    Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(item.tone == .neutral ? Theme.accent : item.tone.color).frame(width: 30)
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
        HStack(alignment: size == .large ? .top : .center, spacing: Theme.Space.m) {
            if let first = item.actions.first, !first.disabled {
                Button { Task { await model.run(first, on: nil) } } label: { tile }.buttonStyle(.plain).accessibilityHidden(true)
            } else {
                tile
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Space.xs) {
                    Text(ext: item.title).font(size == .large ? .system(size: 16, weight: .heavy, design: .rounded) : Theme.Font.headline)
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    if let badge = item.badge {
                        Text(ext: badge.text).font(Theme.Font.caption.weight(.bold)).foregroundStyle(badge.tone == .neutral ? Theme.ink : badge.tone.color)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(badge.tone == .neutral ? Theme.well : badge.tone.soft, in: Capsule())
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
                    ForEach(Array(item.actions.enumerated()), id: \.offset) { _, c in PageButton(control: c, model: model) }
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
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Theme.Radius.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ext: [item.title, item.detail].compactMap { $0 }.joined(separator: ", ")))
    }

    @ViewBuilder private var tile: some View {
        if let picture = item.picture {
            PagePictureView(picture: picture, model: model, side: Int(side) * 2)
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

    var body: some View {
        let key = tabs.tabs.map(\.id).joined(separator: "/")
        let shown = model.tabChoices[key].flatMap { id in tabs.tabs.first { $0.id == id } } ?? tabs.tabs.first { $0.id == tabs.selected } ?? tabs.tabs[0]
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SegmentedPicker(Text("Show", comment: "VoiceOver: tabs on an extension's page"),
                            selection: Binding(get: { shown.id }, set: { model.tabChoices[key] = $0 }),
                            segments: tabs.tabs.map { tab in
                                .init(tab.id, tab.badge.map { Text(ext: tab.label) + Text(verbatim: " ") + Text(ext: $0) } ?? Text(ext: tab.label), symbol: tab.symbol)
                            })
                .fixedSize()
            ForEach(Array(shown.sections.enumerated()), id: \.offset) { _, section in SectionView(section: section, model: model) }
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
        let chosen = rows.keys.isEmpty ? model.settingRows : rows.keys.compactMap { key in model.settingRows.first { $0.key == key } }
        if !chosen.isEmpty || (rows.ai && model.aiStatus != nil) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let title = rows.title { Text(ext: title).font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
                RowsCard {
                    ForEach(chosen) { row in ExtensionSettingRowView(row: row) { value in Task { await model.set(row, to: value) } } }
                    if rows.ai, let ai = model.aiStatus {
                        ExtensionAISwitchRow(status: ai) { on in Task { await model.setAI(on) } }
                    }
                }
            }
        }
    }
}
