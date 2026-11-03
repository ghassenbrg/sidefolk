import SidefolkCore
import SwiftUI

/// Every watcher in one list (D116), opened from On duty: drag to arrange, choose where a live value shows, what stands
/// around its value, pause, resume, stop. The order is the one beside the companion, in On duty and for agents.
struct WatchersView: View {
    var home: HomeModel
    @State private var order: [String] = []

    private var now: NowModel { home.now }

    /// In the engine's order, or just dragged, in the order it's about to be saved in.
    private var all: [Watcher] {
        let found = (now.reports + now.watchers).sorted { ($0.sortOrder, $0.createdAt, $0.id) < ($1.sortOrder, $1.createdAt, $1.id) }
        guard !order.isEmpty else { return found }
        let byId = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return order.compactMap { byId[$0] } + found.filter { !order.contains($0.id) }
    }

    var body: some View {
        let watchers = all
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Button { home.selection = .onDuty } label: { Label("On duty", systemImage: "chevron.backward") }
                .buttonStyle(.sf(.quiet))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("All watchers", comment: "Home: the page listing every watcher").font(Theme.Font.title1).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader).homePageTitle()
                Text("Drag to arrange. The first live values set to show stand beside \(home.companionName); \(WatchLimits.maxBeside) fit there, and the rest run on.",
                     comment: "The page listing every watcher")
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                if let problem = home.watcherProblem {
                    Text(verbatim: problem).font(Theme.Font.callout).foregroundStyle(Theme.warning)
                }
            }
            if watchers.isEmpty {
                EmptyState(title: Text("Nothing is being watched"), message: Text("Ask \(home.companionName) to watch a page or show a value."),
                           systemImage: "binoculars", folk: "scout", actionTitle: Text("Watch something")) {
                    home.services.openAsk(prefill: "tell me when ")
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(watchers) { w in
                        WatcherRow(watcher: w, reading: now.readings[w.id], home: home)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in
                        var ids = watchers.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        order = ids
                        Task {
                            await home.services.reorderWatchers(ids)
                            await now.reload()
                            order = []
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, Theme.Size.contentPadding)
        .padding(.vertical, Theme.Space.l)
        .frame(maxWidth: Theme.Size.contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await now.reload() }
    }
}

/// One watcher in the list: what it is, what it last read, where it shows and its other choices.
struct WatcherRow: View {
    var watcher: Watcher
    var reading: WatchReading?
    var home: HomeModel
    @State private var hovering = false
    @State private var formatting = false

    private var now: NowModel { home.now }

    /// "Every 10 s · Quietly", for a live value's rows; beside the companion needs no saying.
    static func meta(_ w: Watcher) -> String {
        w.display == .beside ? Describe.reportSchedule(w) : "\(Describe.reportSchedule(w)) · \(display(w.display))"
    }

    static func display(_ display: Watcher.Display) -> String {
        switch display {
        case .beside: String(localized: "Beside the companion", comment: "Where a live value shows")
        case .notify: String(localized: "Now and then", comment: "Where a live value shows: a moment beside the companion at each reading")
        case .quiet: String(localized: "Quietly", comment: "Where a live value shows: only when looked for")
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "line.3.horizontal").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                .accessibilityHidden(true)
            Image(systemName: Describe.watcherKind(watcher.kind).symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: reading?.label ?? watcher.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1)
                Text(verbatim: watcher.mode == .report ? Describe.reportSchedule(watcher) : Describe.interval(watcher.intervalS).capitalizedFirst)
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { home.now.openWatch?(watcher.id) }
            Spacer(minLength: Theme.Space.s)
            if let reading {
                Text(verbatim: reading.value).font(Theme.Font.callout.monospacedDigit())
                    .foregroundStyle(watcher.state == .paused ? Theme.inkFaint : Theme.ink).lineLimit(1)
            } else if watcher.state == .paused {
                Chip("Paused", tone: .neutral)
            }
            if watcher.mode == .report {
                Menu {
                    ForEach(Watcher.Display.allCases, id: \.self) { d in
                        Button { Task { await change(d) } } label: {
                            if d == watcher.display { Label(Self.display(d), systemImage: "checkmark") } else { Text(verbatim: Self.display(d)) }
                        }
                    }
                } label: {
                    Text(verbatim: Self.display(watcher.display)).font(Theme.Font.callout)
                }
                .menuStyle(.button).buttonStyle(.sf(.secondary, size: .small)).fixedSize()
                .help(Text("Where this value shows. It goes on running whichever."))
            }
            Menu {
                if watcher.state == .paused {
                    Button("Resume") { Task { await now.resume(watcher) } }
                } else {
                    Button("Pause") { Task { await now.pause(watcher) } }
                }
                if watcher.mode == .report {
                    Button("Symbols and Units…") { formatting = true }
                }
                Button("Open") { home.now.openWatch?(watcher.id) }
                Divider()
                Button("Stop", role: .destructive) { Task { await now.stop(watcher) } }
            } label: {
                Image(systemName: "ellipsis").frame(width: Theme.Size.hitTarget, height: Theme.Size.hitTarget)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(Text("More for \(watcher.title)"))
            .popover(isPresented: $formatting, arrowEdge: .bottom) {
                ValueAffixFields(watcher: watcher, value: reading?.value, services: home.services) { Task { await now.reload() } }
                    .padding(Theme.Space.l).frame(width: 320)
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .padding(.horizontal, Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(hovering ? Theme.ink.opacity(0.04) : .clear))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private func change(_ display: Watcher.Display) async {
        home.watcherProblem = await home.services.setWatcherDisplay(watcher.id, display)
        await now.reload()
    }
}

/// A live value's page: where it shows and what stands around it (D116).
struct LiveValueLook: View {
    var watcher: Watcher
    var value: String?
    var services: any AppServices
    var changed: () -> Void
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                Text("Where it shows", comment: "A live value's page").font(Theme.Font.callout).foregroundStyle(Theme.inkMuted)
                Picker(selection: Binding(get: { watcher.display }, set: { new in
                    Task {
                        problem = await services.setWatcherDisplay(watcher.id, new)
                        changed()
                    }
                })) {
                    ForEach(Watcher.Display.allCases, id: \.self) { d in Text(verbatim: WatcherRow.display(d)).tag(d) }
                } label: { EmptyView() }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            if let problem { Text(verbatim: problem).font(Theme.Font.caption).foregroundStyle(Theme.warning) }
            ValueAffixFields(watcher: watcher, value: value, services: services, changed: changed)
        }
    }
}

/// What stands around a value: a symbol or a unit, the live result beneath, numbers left as they are.
struct ValueAffixFields: View {
    var watcher: Watcher
    var value: String?
    var services: any AppServices
    var changed: () -> Void
    @State private var prefix = ""
    @State private var suffix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                field(Text("Before", comment: "Short text before a live value, like $"), $prefix)
                Text(verbatim: value ?? "42").font(Theme.Font.callout.monospacedDigit()).foregroundStyle(Theme.inkMuted).lineLimit(1)
                field(Text("After", comment: "Short text after a live value, like GPU"), $suffix)
            }
        }
        .onAppear {
            prefix = watcher.valuePrefix ?? ""
            suffix = watcher.valueSuffix ?? ""
        }
        .onChange(of: prefix) { save() }
        .onChange(of: suffix) { save() }
    }

    private func field(_ title: Text, _ text: Binding<String>) -> some View {
        TextField(text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(WatchLimits.maxAffix)) }), prompt: Text(verbatim: "")) { title }
            .fieldHint(title, showing: text.wrappedValue.isEmpty)
            .lanternField().frame(width: 90)
    }

    private func save() {
        guard prefix != (watcher.valuePrefix ?? "") || suffix != (watcher.valueSuffix ?? "") else { return }
        let (before, after) = (prefix, suffix)
        Task {
            await services.setWatcherAffixes(watcher.id, prefix: before, suffix: after)
            changed()
        }
    }
}
