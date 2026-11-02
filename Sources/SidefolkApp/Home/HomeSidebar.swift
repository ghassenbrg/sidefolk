import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// Home's sidebar (D84): the companion live in its nook, on its light, in the same state as on the desktop; the five
/// places; the Notebook (You, the Inbox and collections, the Trash last); the person's extension pages, arranged by
/// dragging; and Quiet and Settings at the foot. One layout in every theme (themes dress it).
struct HomeSidebar: View {
    @Bindable var model: HomeModel
    @State private var deleting: NotebookCollection?

    private var notebook: NotebookModel { model.notebook }
    private var now: NowModel { model.now }

    var body: some View {
        // Above the list, not in it: only the list scrolls, however many collections and pages it holds.
        VStack(spacing: 0) {
            Button { model.selection = .now } label: { SidebarNook(model: now) }
                .buttonStyle(.sfBare)
                .padding(.horizontal, Theme.Space.m)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xs)
            list
        }
        // A translucent theme leaves the sidebar to the Mac's own material, the desktop showing faintly through.
        .background(ThemeStore.shared.style.tokens.material.sidebar == .solid ? Theme.surface : .clear)
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { c in
            Button("Delete collection", role: .destructive) {
                if model.selection == .collection(c.id) { model.selection = .now }
                Task { await notebook.delete(c) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { c in
            let n = notebook.counts[c.id] ?? 0
            if n == 0 {
                Text("It's empty.")
            } else {
                Text("\(n) items in it move to the Trash for 30 days. Restored items go to the Inbox.")
            }
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            Section {
                ForEach(Array(HomeSelection.places.enumerated()), id: \.offset) { i, place in
                    placeRow(place, index: i)
                }
            }
            Section {
                row(Text("You", comment: "Notebook › You: what Sidefolk knows about the person"), count: 0) {
                    SidebarSquircle(symbol: "person", color: Theme.coral)
                }
                .tag(HomeSelection.you)
                .help(Text("What \(model.companionName) keeps in mind about you, and where each fact came from."))
                ForEach(notebook.collections.filter { $0.kind != .profile }) { c in
                    collectionRow(c).moveDisabled(c.kind == .inbox)
                }
                .onMove { from, to in notebook.arrange(from: from, to: to) }
                row(Text("Trash"), count: notebook.trashCount, quiet: true) {
                    Image(systemName: "trash").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkFaint).frame(width: 20)
                }
                .tag(HomeSelection.trash)
            } header: {
                HStack {
                    Text("Notebook")
                    Spacer()
                    Button { model.collectionSheet = .create } label: { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.sfIcon(side: 22))
                        .foregroundStyle(Theme.inkMuted)
                        .help("New collection")
                        .accessibilityLabel("New collection")
                }
            }
            ExtensionsSidebarSection(pages: model.pages) { model.selection = .gallery }
            if !notebook.archived.isEmpty {
                Section("Archived") {
                    ForEach(notebook.archived) { c in
                        row(Text(NotebookCollections.shownName(c)), count: notebook.counts[c.id] ?? 0, quiet: true) {
                            Image(systemName: "archivebox").foregroundStyle(Theme.inkFaint).frame(width: 20)
                        }
                        .tag(HomeSelection.collection(c.id))
                        .contextMenu {
                            Button("Unarchive") { Task { await notebook.setArchived(c, false) } }
                            Button("Delete…") { deleting = c }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                QuietPill(model: model)
                Spacer(minLength: Theme.Space.xs)
                // Sidefolk lives in the menu bar, so the app menu (and ⌘,) is only there while a window is in front.
                Button { model.services.openSettings(tab: nil) } label: {
                    Image(systemName: "gearshape").font(.system(size: 14))
                }
                .buttonStyle(.sfIcon)
                .foregroundStyle(Theme.inkMuted)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, Theme.Space.m) }
        }
    }

    /// A place, with its shortcut in its help; Today counts what needs you (amber, as the shoulder badge), On duty what runs.
    @ViewBuilder private func placeRow(_ place: HomeSelection, index: Int) -> some View {
        let count: Int = switch place {
        case .now: now.needsYouCount
        case .onDuty: model.onDutyRunning
        default: 0
        }
        let selected = (model.selection ?? .now).isPlace(place) && !(place == .collection("") && model.selection == .you)
        row(Text(place.title), count: count, waiting: place == .now) {
            Image(systemName: place.symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Theme.link : Theme.inkMuted).frame(width: 20)
        }
        .tag(place)
        .help(Text("\(Text(place.title)) (⌘\(index + 1))", comment: "A place, then its shortcut"))
    }

    private func collectionRow(_ c: NotebookCollection) -> some View {
        row(Text(NotebookCollections.shownName(c)), count: notebook.counts[c.id] ?? 0) { CollectionTile(collection: c, size: 20) }
            .tag(HomeSelection.collection(c.id))
            .help(Text(verbatim: c.name))
            .contextMenu {
                Button("Edit…") { model.collectionSheet = .edit(c) }
                if c.kind != .inbox {
                    Button("Archive") {
                        if model.selection == .collection(c.id) { model.selection = .now }
                        Task { await notebook.setArchived(c, true) }
                    }
                    Divider()
                    Button("Delete…") { deleting = c }
                }
            }
    }

    private func row<Icon: View>(_ title: Text, count: Int, waiting: Bool = false, quiet: Bool = false,
                                 @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: Theme.Space.s + 2) {
            icon()
            title.font(Theme.Font.body).foregroundStyle(quiet ? Theme.inkMuted : Theme.ink).lineLimit(1)
            Spacer(minLength: Theme.Space.xs)
            if count > 0 {
                if waiting {
                    CountBadge(count: count)
                } else {
                    Text(count > 99 ? "99+" : count.formatted()).font(Theme.Font.caption.monospacedDigit()).foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .frame(minHeight: Theme.Size.sidebarRow - 6)
        .accessibilityElement(children: .combine)
    }
}

/// A sidebar icon in a 20 pt squircle tinted with its colour (03-system › Iconography), like a collection's.
struct SidebarSquircle: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay { Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(color) }
            .accessibilityHidden(true)
    }
}

/// The companion's nook (D84): its picture on its light pool, in the pose the desktop shows, its name with a state
/// chip, and one line of what it's on. A click goes to Today.
struct SidebarNook: View {
    var model: NowModel

    var body: some View {
        let settings = model.services.runtime.settings.current
        HStack(alignment: .top, spacing: Theme.Space.s + 2) {
            ZStack(alignment: .bottom) {
                LightPool(state: model.poolState, width: 60, still: true).offset(y: 6)
                CompanionPortrait(settings: settings, state: pose, side: 46)
            }
            .overlay(alignment: .topTrailing) { ShoulderBadge(state: shoulder).scaleEffect(0.7).offset(x: 6, y: -4) }
            .frame(width: 50, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                // The state beside the name where it fits, under it where it doesn't (German, a long name).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.xs) { name(settings); chip }
                    VStack(alignment: .leading, spacing: 3) { name(settings); chip }
                }
                Text(verbatim: line).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s + 2)
        .background { NookBackdrop() }
        .cardSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(settings.companionName). \(model.stateWord ?? "") \(line)"))
        .accessibilityHint(Text("Opens Today"))
    }

    private func name(_ settings: AppSettings) -> some View {
        Text(verbatim: settings.companionName).font(Theme.Font.headline).foregroundStyle(Theme.ink).lineLimit(1).fixedSize()
    }

    @ViewBuilder private var chip: some View {
        if let word = model.stateWord { Chip(verbatim: word, tone: tone).fixedSize() }
    }

    /// The badge on the nook shows Quiet's moon only; the count is already on Today's row.
    private var shoulder: LightPoolState { model.poolState == .quiet ? .quiet : .idle }

    private var pose: CharacterState {
        switch model.poolPose {
        case .sleeping: .sleeping
        case .waiting: .waiting
        case .working: .working(.laptop)
        case .idle: .idle
        }
    }

    private var tone: ChipTone {
        switch model.poolState {
        case .waiting, .alert: .warning
        case .working: .accent
        default: .neutral
        }
    }

    private var line: String {
        if let until = model.quietUntil {
            return String(localized: "Only urgent things until \(TimeFormat.clock(until, calendar: .current))",
                          comment: "The companion's nook while Quiet is on")
        }
        return model.nookLine
    }
}

/// Open, Focus or Quiet at the sidebar's foot (D84), with the half circle and the moon (`Theme.Symbol`): the same choice
/// and ends as Settings › Attention and the Pocket.
/// The theme's nook art (`companion.backdrop`, D84: themes dress the nook) behind the companion's card, faded so its
/// name and line still read, and clipped to the card: scaled to fill, it would spill over the sidebar otherwise.
private struct NookBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let art = Theme.Art.backdrop(dark: scheme == .dark) {
            // In a clear frame of the card's size, so the clip is the card's and not the larger filled image's.
            Color.clear
                .overlay { Image(decorative: art, scale: 2).resizable().scaledToFill() }
                .opacity(0.35)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .allowsHitTesting(false)
        }
    }
}

struct QuietPill: View {
    var model: HomeModel

    var body: some View {
        let host = model.settingsHost
        let now = Date()
        let mode = host.settings.attentionMode(at: now)
        let ends = host.settings.attentionEnds(at: now)
        Menu {
            Button { set(.open, nil) } label: {
                Label("Open to everything", systemImage: mode == .open ? "checkmark" : "circle")
            }
            Section {
                Button("For 1 hour") { set(.focus, now.addingTimeInterval(3600)) }
                Button("For 3 hours") { set(.focus, now.addingTimeInterval(10800)) }
                Button { set(.focus, nil) } label: { Text("Until I turn it off", comment: "When Focus or Quiet ends") }
            } header: {
                Text("Focus: cards that need you, whispers wait", comment: "The sidebar's foot: a section of the Attention menu")
            }
            Section("Quiet: only urgent things, no sound") {
                Button("For 1 hour") { set(.quiet, now.addingTimeInterval(3600)) }
                Button("For 3 hours") { set(.quiet, now.addingTimeInterval(10800)) }
                // The choices end with tomorrow morning, then "until I turn it off".
                Button("Until tomorrow") { set(.quiet, AttentionSpan.choices(settings: host.settings, now: now).dropLast().last?.until) }
            }
        } label: {
            HStack(spacing: 6) {
                switch mode {
                case .open: Circle().fill(Theme.success).frame(width: 8, height: 8)
                case .focus: Image(systemName: Theme.Symbol.focus).foregroundStyle(Theme.melody)
                case .quiet: Image(systemName: Theme.Symbol.quiet).foregroundStyle(Theme.melody)
                }
                switch mode {
                case .open: Text("Open to everything", comment: "The sidebar's foot: everything may reach the person")
                case .focus:
                    if let ends { Text("Focus until \(TimeText.clock(ends))", comment: "Settings › Attention: “Focus until 17:00”") }
                    else { Text("Focus until you turn it off", comment: "Settings › Attention") }
                case .quiet:
                    if let ends { Text("Quiet until \(TimeText.clock(ends))") }
                    else { Text("Quiet until you turn it off", comment: "Settings › Attention") }
                }
            }
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.ink)
        }
        .menuStyle(.button)
        .buttonStyle(.sf(.secondary, size: .small))
        .fixedSize()
        .help(Text("How much \(model.companionName) may interrupt you"))
    }

    /// Through the settings (so it survives a relaunch); the app tells Attention, which holds whispers and bubbles.
    private func set(_ mode: AttentionMode, _ until: Date?) {
        model.settingsHost.setAttention(mode, until: until)
        Task { await model.now.reload() }
    }
}
