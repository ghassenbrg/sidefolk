import SidefolkCore
import SwiftUI

// Home's navigation besides the sidebar (D64): a rail of icons with a status bar, and the collections column the
// Notebook brings along where there is no sidebar.

/// A narrow rail: the companion's badge (glowing while something runs; a click goes to Today), the four places, and
/// Settings at the foot.
struct HomeRail: View {
    @Bindable var model: HomeModel

    var body: some View {
        let busy = !model.now.workingSessions.isEmpty || !model.now.jobs.isEmpty || model.now.ownRun != nil
        VStack(spacing: Theme.Space.m) {
            Button { model.selection = .now } label: {
                CompanionPortrait(settings: model.services.runtime.settings.current, side: 34)
                    .padding(3)
                    .background(Theme.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(busy ? Theme.accent : Theme.line, lineWidth: busy ? 2 : 1))
                    .shadow(color: busy ? Theme.accent.opacity(0.6) : .clear, radius: busy ? 6 : 0)
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: model.now.nookLine))
            .accessibilityLabel(Text(verbatim: "\(model.services.runtime.settings.current.companionName), \(model.now.nookLine)"))
            ForEach(Array(HomeSelection.places.enumerated()), id: \.offset) { i, place in
                let selected = (model.selection ?? .now).isPlace(place)
                Button { model.go(to: place) } label: {
                    railIcon(place.symbol, place.navColor)
                        .frame(width: 36, height: 32)
                        .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
                        .background(selected ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .overlay(alignment: .topTrailing) {
                            if place == .now, model.now.needsYouCount > 0 {
                                Text(model.now.needsYouCount.formatted()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.onDanger)
                                    .padding(.horizontal, 4).background(Theme.danger, in: Capsule()).offset(x: 4, y: -4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(Text("\(Text(place.title)) (⌘\(i + 1))", comment: "A place, then its shortcut"))
                .accessibilityLabel(Text(place.title))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            // Extensions' pages (D62), under the places, by their own symbols.
            if !model.pages.list.isEmpty {
                Divider().frame(width: 24)
                // As the person arranged them; the rest are in All Extensions (D67).
                ForEach(model.pages.shown + [ExtensionPagesModel.hubInfo]) { p in
                    let selected = model.selection == .page(p.id)
                    Button { model.selection = .page(p.id) } label: {
                        Group {
                            if colorful, p.id != ExtensionPagesModel.hub {
                                PageNavIcon(info: p, size: 24)
                            } else {
                                railIcon(p.symbol ?? "puzzlepiece.extension", Theme.folkColor("byte"))
                            }
                        }
                            .frame(width: 36, height: 32)
                            .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
                            .background(selected ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: p.title))
                    .accessibilityLabel(Text(verbatim: p.title))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Spacer()
            Button { model.services.openSettings(tab: nil) } label: {
                Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(Theme.inkMuted).frame(width: 36, height: 32)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .padding(.top, 44)
        .padding(.bottom, Theme.Space.m)
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }

    private var colorful: Bool { ThemeStore.shared.icons == .colorful }

    /// A glyph, or a white glyph on its colour's tile when the icons are colorful (D67).
    @ViewBuilder private func railIcon(_ symbol: String, _ color: Color) -> some View {
        if colorful {
            NavIcon(symbol: symbol.hasSuffix(".fill") ? symbol : symbol + ".fill", color: color, size: 24)
        } else {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
        }
    }
}

/// A line along the foot, like an editor's: the companion, how Sidefolk asks, which AI, what waits and what runs, and
/// the places' shortcuts.
struct HomeStatusBar: View {
    var model: HomeModel

    var body: some View {
        let now = model.now
        let settings = model.services.runtime.settings.current
        let running = now.workingSessions.count + now.jobs.count
        HStack(spacing: Theme.Space.l) {
            Label {
                Text(verbatim: settings.companionName + " ") + Text("watching \(now.watchers.count + now.reports.count)", comment: "The status bar, after the companion's name: how many watches")
            } icon: {
                Circle().fill(Theme.success).frame(width: 6, height: 6)
            }
            Text("guard: \(now.mode.title.lowercased())", comment: "The status bar: Sidefolk's approval mode")
            Text("model: \(AIName.short(settings.provider.kind))", comment: "The status bar: which AI answers")
            if now.needsYouCount > 0 {
                Text("\(now.needsYouCount) waiting on you").foregroundStyle(Theme.link)
            }
            if running > 0 { Text("\(running) running") }
            Spacer(minLength: Theme.Space.s)
            ViewThatFits(in: .horizontal) {
                // Whole or not at all: cut short, the last place read "⌘5 Ca…".
                Text(verbatim: HomeSelection.places.enumerated().map { "⌘\($0.offset + 1) \(String(localized: $0.element.titleResource))" }.joined(separator: "  "))
                    .fixedSize()
                EmptyView()
            }
            .foregroundStyle(Theme.inkFaint)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Theme.inkMuted)
        .lineLimit(1)
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 24)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

/// Which AI answers, in a word or two.
enum AIName {
    static func short(_ kind: ProviderKind) -> String {
        switch kind {
        case .none: String(localized: "none", comment: "The status bar: no AI is set up")
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .anthropic: "Anthropic API"
        case .openAICompatible: String(localized: "OpenAI-compatible")
        }
    }
}

extension HomeSelection {
    var titleResource: LocalizedStringResource {
        switch self {
        case .now: "Today"
        case .calendar: "Calendar"
        case .collection, .trash: "Notebook"
        case .conversations: "Conversations"
        case .activity: "Activity"
        case .page: "Extensions"
        }
    }
}

/// The Notebook's collections as a column beside its pages, where there is no sidebar to hold them.
struct CollectionColumn: View {
    @Bindable var model: HomeModel

    var body: some View {
        let notebook = model.notebook
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(Text("Collections")).padding(.horizontal, Theme.Space.s).padding(.bottom, Theme.Space.xs)
                ForEach(notebook.collections) { c in
                    row(selected: model.selection == .collection(c.id), count: notebook.counts[c.id] ?? 0) {
                        model.selection = .collection(c.id)
                    } label: {
                        Label { Text(NotebookCollections.shownName(c)) } icon: { CollectionIcon(collection: c) }
                    }
                }
                row(selected: model.selection == .trash, count: notebook.trashCount) { model.selection = .trash } label: {
                    Label("Trash", systemImage: "trash")
                }
                Button { model.collectionSheet = .create } label: { Label("New collection", systemImage: "plus") }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.link)
                    .padding(.horizontal, Theme.Space.s).padding(.top, Theme.Space.s)
            }
            .padding(Theme.Space.s)
        }
        .background(Theme.surface)
    }

    private func row<L: View>(selected: Bool, count: Int, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            HStack {
                label().lineLimit(1)
                Spacer(minLength: Theme.Space.xs)
                if count > 0 { Text(count.formatted()).foregroundStyle(Theme.inkFaint) }
            }
            .font(Theme.Font.body)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 5)
            .background(selected ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Four big friendly tabs floating at the top (D64): the places, Today with what needs you.
struct PillTabs: View {
    @Bindable var model: HomeModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(HomeSelection.places.enumerated()), id: \.offset) { i, place in
                let selected = (model.selection ?? .now).isPlace(place)
                Button { model.go(to: place) } label: {
                    HStack(spacing: 5) {
                        if ThemeStore.shared.icons == .colorful {
                            NavIcon(symbol: place.symbol + ".fill", color: place.navColor, size: 18)
                        } else {
                            Image(systemName: place.symbol)
                        }
                        Text(place.title)
                        if place == .now, model.now.needsYouCount > 0 {
                            Text(model.now.needsYouCount.formatted()).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.onDanger)
                                .padding(.horizontal, 5).background(Theme.danger, in: Capsule())
                        }
                    }
                    .font(Theme.Font.captionStrong)
                    .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, 5)
                    .background(selected ? Theme.surfaceRaised : .clear, in: Capsule())
                    .shadow(color: selected ? .black.opacity(0.08) : .clear, radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .help(Text("\(Text(place.title)) (⌘\(i + 1))", comment: "A place, then its shortcut"))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            // Extensions' pages (D62) after the places, as the person arranged them, then All Extensions (D67): by their icon
            // alone, so the bar still fits the toolbar with a few of them.
            ForEach(model.pages.list.isEmpty ? [] : model.pages.shown + [ExtensionPagesModel.hubInfo]) { p in
                let selected = model.selection == .page(p.id)
                Button { model.selection = .page(p.id) } label: {
                    Group {
                        if ThemeStore.shared.icons == .colorful, p.id != ExtensionPagesModel.hub {
                            PageNavIcon(info: p, size: 18)
                        } else {
                            Image(systemName: p.symbol ?? "puzzlepiece.extension")
                        }
                    }
                    .font(Theme.Font.captionStrong)
                    .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, 5)
                    .background(selected ? Theme.surfaceRaised : .clear, in: Capsule())
                    .shadow(color: selected ? .black.opacity(0.08) : .clear, radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: p.title))
                .accessibilityLabel(Text(verbatim: p.title))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.accentSoft.opacity(0.7), in: Capsule())
    }
}

/// The Notebook's collections across the top (D64): big jars with their picture and count, or washi tabs in each
/// collection's colour.
struct CollectionStrip: View {
    @Bindable var model: HomeModel
    var washi: Bool

    var body: some View {
        let notebook = model.notebook
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: washi ? 4 : Theme.Space.s) {
                ForEach(notebook.collections) { c in
                    let selected = model.selection == .collection(c.id)
                    Button { model.selection = .collection(c.id) } label: {
                        if washi {
                            HStack(spacing: 5) {
                                CollectionIcon(collection: c, size: 11)
                                Text(NotebookCollections.shownName(c)).lineLimit(1)
                            }
                            .font(Theme.Font.captionStrong)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, Theme.Space.m).padding(.vertical, 6)
                            .background(CollectionLook.color(c).opacity(selected ? 0.35 : 0.16),
                                        in: UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5))
                            .overlay(alignment: .bottom) { if selected { Rectangle().fill(CollectionLook.color(c)).frame(height: 2) } }
                        } else {
                            VStack(spacing: 4) {
                                CollectionIcon(collection: c, size: 22)
                                Text(NotebookCollections.shownName(c)).font(Theme.Font.captionStrong).lineLimit(1)
                                Text((notebook.counts[c.id] ?? 0).formatted()).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                            }
                            .foregroundStyle(Theme.ink)
                            .frame(width: 84, height: 82)
                            .background(CollectionLook.color(c).opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2.5))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button { model.selection = .trash } label: {
                    Label("Trash", systemImage: "trash").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).padding(.horizontal, Theme.Space.s)
                }
                .buttonStyle(.plain)
                Button { model.collectionSheet = .create } label: {
                    Label("New collection", systemImage: "plus").font(Theme.Font.caption).foregroundStyle(Theme.link)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, washi ? Theme.Space.s : Theme.Space.m)
        }
        .background(Theme.surface)
    }
}

/// Bookmark ribbons down the right edge (D64), each place its own colour, the open one standing out.
struct RibbonTabs: View {
    @Bindable var model: HomeModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(HomeSelection.places.enumerated()), id: \.offset) { i, place in
                let selected = (model.selection ?? .now).isPlace(place)
                Button { model.go(to: place) } label: {
                    HStack(spacing: 4) {
                        Text(place.title)
                        if place == .now, model.now.needsYouCount > 0 { Text(verbatim: "· \(model.now.needsYouCount)") }
                    }
                    .font(Theme.Font.captionStrong)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 30, height: 118)
                    .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
                    .background(selected ? Theme.accent : Self.tint(i).opacity(0.28),
                                in: UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6))
                }
                .buttonStyle(.plain)
                .help(Text("\(Text(place.title)) (⌘\(i + 1))", comment: "A place, then its shortcut"))
                .accessibilityLabel(Text(place.title))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            // Extensions (D62, D67): one ribbon, All Extensions, which opens each page; a ribbon per page would run off
            // the window's edge with a few of them.
            ForEach(model.pages.list.isEmpty ? [] : [ExtensionPagesModel.hubInfo]) { p in
                let selected: Bool = if case .page = model.selection { true } else { false }
                Button { model.selection = .page(p.id) } label: {
                    Text(verbatim: p.title)
                        .font(Theme.Font.captionStrong)
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                        .frame(width: 30, height: 118)
                        .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
                        .background(selected ? Theme.accent : Theme.inkFaint.opacity(0.2),
                                    in: UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: p.title))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            Button { model.services.openSettings(tab: nil) } label: {
                Image(systemName: "gearshape").foregroundStyle(Theme.inkMuted).frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .padding(.top, 60)
        .padding(.bottom, Theme.Space.m)
        .frame(width: 34)
        .frame(maxHeight: .infinity)
        .background(Theme.surfaceSunken)
    }

    /// The ribbons' colours, Today's first: the theme's own, then the app's quiet ones.
    static func tint(_ i: Int) -> Color {
        [Theme.accent, Theme.success, Theme.link, Theme.sun][i % 4]
    }
}

extension HomeSelection {
    /// A place's colour in the navigation, as the sidebar draws it.
    var navColor: Color {
        switch self {
        case .now: Theme.sun
        case .calendar: Theme.folkColor("tempo")
        case .collection, .trash: Theme.coral
        case .conversations: Theme.aqua
        case .activity: Theme.folkColor("guard")
        case .page: Theme.folkColor("byte")
        }
    }
}
