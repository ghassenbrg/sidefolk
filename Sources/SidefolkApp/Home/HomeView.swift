import SidefolkCore
import SwiftUI

/// The Home window (D84): the sidebar with the companion's nook, the places and the Notebook; the Say bar in the
/// toolbar's centre (⌘K); and the selected place. One layout in every theme: themes dress it, they don't arrange it.
struct HomeView: View {
    @Bindable var model: HomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sayFocus = 0
    @State private var detailWidth: CGFloat = 1000

    var body: some View {
        NavigationSplitView {
            HomeSidebar(model: model)
                .navigationSplitViewColumnWidth(min: Theme.Size.sidebarMin, ideal: Theme.Size.sidebar, max: 320)
        } detail: {
            page
        }
        .toolbar {
            // In a narrow window the bar keeps the room; the page says where it is.
            if detailWidth >= 720 { ToolbarItem(placement: .navigation) { PlaceTitle(model: model) } }
            ToolbarItem(placement: .principal) {
                SayBarField(text: Bindable(model.find).query,
                            prompt: Text("Ask \(model.companionName), or type a reminder, note or watch…"),
                            tint: Theme.link,
                            onSubmit: { model.send(.auto) }, focusTrigger: sayFocus,
                            focusChanged: { model.saying = $0 },
                            onEscape: { model.find.query = "" })
                    // The toolbar gives its centre item only its least width: the bar takes what the page leaves beside the
                    // place's title and the New menu, at most 560.
                    .frame(width: min(Theme.Size.sayBarHomeMaxWidth, max(200, detailWidth - (detailWidth >= 720 ? 420 : 180))))
            }
            ToolbarItem(placement: .primaryAction) {
                // Everything Home can start, in one place (D58).
                Menu {
                    Button("Note") { Task { await model.newNote() } }
                    Button("Reminder…") { model.services.openAsk(prefill: "remind me ") }
                    Button("Watch…") { model.services.openAsk(prefill: "tell me when ") }
                    Divider()
                    Button("Collection…") { model.collectionSheet = .create }
                    Button("Fact about you…") {
                        model.selection = .you
                        model.you.adding = true
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .help("New note, reminder, watch or collection")
            }
        }
        .background {
            Button("Say") { sayFocus += 1 }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
            // ⌘1–5 go to the places (D84).
            ForEach(Array(HomeSelection.places.enumerated()), id: \.offset) { i, place in
                Button(place.title) { model.go(to: place) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(item: $model.collectionSheet) { mode in
            CollectionSheet(mode: mode, model: model.notebook) { created in
                if let created { model.selection = .collection(created.id) }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.notebook.toast {
                Toast(message: toast.message, actionTitle: toast.actionTitle) {
                    toast.action?()
                    model.notebook.toast = nil
                }
                .padding(.bottom, Theme.Space.xl)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(Theme.Motion.spring(0.3), value: model.notebook.toast?.id)
    }

    /// The selected place, with the Say bar's panel over it while the bar has words.
    private var page: some View {
        detail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { ThemeGrain() }
            .overlay(alignment: .top) {
                if showsPanel {
                    ZStack(alignment: .top) {
                        // A light scrim over the page only: the sidebar's companion stays in view, listening.
                        Theme.ink.opacity(0.06).ignoresSafeArea().onTapGesture { model.find.query = "" }
                        SayPanel(find: model.find, services: model.services, send: { model.send($0) }) { found in
                            model.find.query = ""
                            model.services.open(found)
                        }
                        .padding(.horizontal, Theme.Space.xl)
                        .padding(.top, Theme.Space.s)
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Theme.Motion.micro, value: showsPanel)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
            .environment(model.pages)
    }

    private var showsPanel: Bool { !model.find.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    @ViewBuilder private var detail: some View {
        switch model.selection ?? .now {
        case .now:
            TodayView(model: model)
        case .calendar:
            CalendarView(model: model.calendar)
        case .onDuty:
            OnDutyView(model: model)
        case .history:
            HistoryView(model: model.history, home: model)
        case .you:
            YouView(model: model.you)
        case .trash:
            TrashView(model: model.notebook)
        case .gallery:
            HomeGalleryView(settings: model.settingsHost)
        case .watch:
            WatchDetailView(home: model, model: model.watch)
        case .page(let id):
            if let info = model.pages.info(id) {
                ExtensionPageView(model: model.pages.model(info))
            } else {
                Theme.surfaceSunken
            }
        case .collection(let id):
            if let collection = model.notebook.collection(id: id) {
                NotebookView(model: model.notebook, collection: collection)
            } else {
                Theme.surfaceSunken
            }
        }
    }
}

/// The place's name and one line under it, at the toolbar's leading edge (A1): "Today / Saturday, 31 October",
/// "On duty / 8 running · 1 paused".
private struct PlaceTitle: View {
    var model: HomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title).font(Theme.Font.headline).foregroundStyle(Theme.ink).lineLimit(1)
            if let subtitle {
                Text(verbatim: subtitle).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
        }
        .fixedSize()
        .padding(.leading, Theme.Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        switch model.selection ?? .now {
        case .now: String(localized: "Today")
        case .calendar: String(localized: "Calendar")
        case .onDuty, .watch: String(localized: "On duty")
        case .history: String(localized: "History")
        case .you: String(localized: "You", comment: "Notebook › You: what Sidefolk knows about the person")
        case .trash: String(localized: "Trash")
        case .gallery: String(localized: "Gallery")
        case .page(let id): model.pages.info(id)?.title ?? String(localized: "Extensions")
        case .collection(let id): model.notebook.collection(id: id).map(NotebookCollections.shownName) ?? String(localized: "Notebook")
        }
    }

    private var subtitle: String? {
        switch model.selection ?? .now {
        case .now:
            return Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .calendar:
            return model.calendar.subtitle
        case .onDuty:
            let duty = model.now.onDuty
            let running = String(localized: "\(model.onDutyRunning) running", comment: "Under On duty's title")
            return duty.paused > 0 ? running + " · " + String(localized: "\(duty.paused) paused", comment: "Under On duty's title") : running
        case .watch:
            return model.watch.watcher.map { Describe.watcherKind($0.kind).label }
        case .history:
            let span = switch model.history.span {
            case .today: String(localized: "Today")
            case .week: String(localized: "Last 7 days")
            case .all: String(localized: "Everything kept")
            }
            return span + " · " + String(localized: "\(model.history.spanCount) things happened", comment: "Under History's title")
        case .you:
            return String(localized: "Notebook · \(model.you.count) things \(model.companionName) knows", comment: "Under You's title")
        case .trash:
            return String(localized: "Notebook · kept 30 days", comment: "Under the Trash's title")
        case .gallery:
            return String(localized: "Companions, extensions and themes", comment: "Under the Gallery's title")
        case .page(let id):
            return model.pages.info(id).map(\.extensionName)
        case .collection(let id):
            let n = model.notebook.counts[id] ?? 0
            return String(localized: "Notebook · \(n) items", comment: "Under a collection's title")
        }
    }
}

// MARK: - New and edit collection

struct CollectionSheet: View {
    enum Mode: Identifiable {
        case create
        case edit(NotebookCollection)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let c): c.id
            }
        }
    }

    var mode: Mode
    var model: NotebookModel
    var done: (NotebookCollection?) -> Void
    @State private var name = ""
    @State private var kind: NotebookCollection.Kind = .project
    @State private var symbol: String?
    @State private var color: String?
    @State private var emoji = ""
    @State private var error: UserFacingError?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private static let kinds: [(NotebookCollection.Kind, LocalizedStringResource, LocalizedStringResource)] = [
        (.project, "Project", "Notes, ideas and tasks for something you're making."),
        (.topic, "Topic", "Things you're learning or thinking about."),
        (.list, "List", "Groceries, books to read, places to go."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(isCreate ? "New collection" : "Edit collection").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            if namable {
                TextField("Name", text: $name, prompt: Text("Name"))
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .padding(.horizontal, Theme.Space.s)
                    .frame(height: Theme.Size.field)
                    .fieldChrome(focused: nameFocused)
            }
            if isCreate {
                VStack(alignment: .leading, spacing: 6) {
                    SegmentedPicker("Kind", selection: $kind, segments: Self.kinds.map { .init($0.0, Text($0.1)) }, equalWidths: true)
                    if let detail = Self.kinds.first(where: { $0.0 == kind })?.2 {
                        Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            CollectionLookPicker(symbol: $symbol, color: $color, emoji: $emoji, kind: currentKind)
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button(isCreate ? "Create collection" : "Save", action: save)
                    .buttonStyle(.sfPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(namable && name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 420)
        .background(Theme.surface)
        .onAppear {
            guard case .edit(let c) = mode else { return }
            name = c.name
            symbol = c.symbol
            color = c.color
            emoji = c.emoji ?? ""
        }
    }

    private var isCreate: Bool { if case .create = mode { true } else { false } }

    /// The Inbox keeps its name; its look is the person's.
    private var namable: Bool { if case .edit(let c) = mode { c.kind != .inbox } else { true } }

    private var currentKind: NotebookCollection.Kind { if case .edit(let c) = mode { c.kind } else { kind } }

    private func save() {
        Task {
            switch mode {
            case .create:
                switch await model.createCollection(named: name, kind: kind) {
                case .success(let c):
                    await model.setLook(c, emoji: emoji, symbol: symbol, color: color)
                    done(c)
                    dismiss()
                case .failure(let e):
                    error = e
                }
            case .edit(let c):
                if namable, name != c.name, let e = await model.rename(c, to: name) {
                    error = e
                    return
                }
                await model.setLook(c, emoji: emoji, symbol: symbol, color: color)
                done(nil)
                dismiss()
            }
        }
    }
}
