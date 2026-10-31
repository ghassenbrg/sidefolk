import SidefolkCore
import SwiftUI

/// The Settings window (D84): a sidebar with search, the eight tabs and their badges, and the page or the search's
/// results beside it. ⌘F searches; ↑↓ move through the results and Return opens one where it lives.
struct SettingsRoot: View {
    var model: SettingsModel
    @FocusState private var searchFocused: Bool
    private var navigation: SettingsNavigation { model.navigation }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(model: model, searchFocused: $searchFocused)
                .frame(width: Theme.Size.sidebar)
                .padding(Theme.Space.s)
            VStack(alignment: .leading, spacing: 0) {
                header
                Group {
                    if navigation.searching {
                        SettingsSearchResults(model: model)
                    } else {
                        SettingsTabContent(tab: navigation.tab, model: model)
                            .id(navigation.tab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surfaceSunken)
        // The sidebar holds the window's buttons and the title sits level with them, as in System Settings.
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.settingsNavigation, navigation)
        .background {
            Button("Search Settings") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// The tab's name level with the window's buttons, or what the search found.
    private var header: some View {
        HStack(spacing: Theme.Space.m) {
            if navigation.searching {
                let count = navigation.results.count
                Text(count == 0 ? String(localized: "Nothing for “\(navigation.query)”", comment: "Settings search: no results")
                     : String(localized: "\(count) results for “\(navigation.query)”", comment: "Settings search: “6 results for “quiet””"))
                    .font(Theme.Font.title2).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                if count > 0 {
                    HStack(spacing: Theme.Space.xs) {
                        KeyHint("↑")
                        KeyHint("↓")
                        Text("to move", comment: "Settings search: arrow keys move through the results").font(Theme.Font.caption)
                        KeyHint("↩").padding(.leading, Theme.Space.xs)
                        Text("to open", comment: "Settings search: Return opens the result where it lives").font(Theme.Font.caption)
                    }
                    .foregroundStyle(Theme.inkMuted)
                }
            } else {
                Text(verbatim: navigation.tab.title).font(Theme.Font.title2).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(height: 52)
    }
}

/// The sidebar: the search, the tabs with their tiles and what waits in them, and the version at the bottom.
private struct SettingsSidebar: View {
    var model: SettingsModel
    var searchFocused: FocusState<Bool>.Binding
    private var navigation: SettingsNavigation { model.navigation }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            // Room for the window's buttons.
            Color.clear.frame(height: 30)
            SettingsSearchField(navigation: navigation, focused: searchFocused)
                .padding(.bottom, Theme.Space.s)
            ForEach(SettingsTab.allCases) { tab in
                SidebarTab(tab: tab, selected: !navigation.searching && navigation.tab == tab, badge: badge(tab),
                           found: found(tab)) {
                    navigation.query = ""
                    navigation.tab = tab
                }
            }
            Spacer(minLength: Theme.Space.l)
            Rectangle().fill(Theme.line).frame(height: 1)
            Text(verbatim: "Sidefolk \(model.services.updates.running)")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.s)
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card + 2, style: .continuous).strokeBorder(Theme.line))
    }

    /// What waits in a tab: a version of Sidefolk to install, add-ons that need a look.
    private func badge(_ tab: SettingsTab) -> Int {
        switch tab {
        case .general: model.services.updates.readyOffer != nil || isAvailable ? 1 : 0
        case .addons: model.services.updates.addonReview.count + model.extensions.filter { !$0.pendingTools.isEmpty }.count
        default: 0
        }
    }

    private var isAvailable: Bool {
        if case .available = model.services.updates.phase { return true }
        return false
    }

    /// While searching: how many results the tab has (nil when not searching).
    private func found(_ tab: SettingsTab) -> Int? {
        navigation.searching ? navigation.results.filter { $0.tab == tab }.count : nil
    }
}

private struct SidebarTab: View {
    var tab: SettingsTab
    var selected: Bool
    var badge: Int
    var found: Int?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tab.tint.gradient)
                    .frame(width: 22, height: 22)
                    .overlay { Image(systemName: tab.symbol).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white) }
                    .accessibilityHidden(true)
                Text(verbatim: tab.title)
                    .font(selected ? Theme.Font.bodyStrong : Theme.Font.body)
                    .foregroundStyle(selected ? Theme.link : Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.xs)
                if let found {
                    if found > 0 {
                        Text(verbatim: found.formatted()).font(Theme.Font.captionStrong.monospacedDigit()).foregroundStyle(Theme.link)
                    }
                } else if badge > 0 {
                    CountBadge(count: badge)
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .frame(height: Theme.Size.sidebarRow + 2)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(selected ? Theme.accentSoft : hovering ? Theme.well : .clear)
            }
            .contentShape(Rectangle())
            .opacity(found == 0 ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: tab.title))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The sidebar's search: a well like `SearchBox`, whose arrow keys move through the results and whose Return opens
/// the one they're on.
private struct SettingsSearchField: View {
    @Bindable var navigation: SettingsNavigation
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            TextField("Search settings", text: $navigation.query, prompt: Text("Search settings"))
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .focused(focused)
                .onSubmit(open)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onExitCommand { navigation.query = "" }
                .onChange(of: navigation.query) { navigation.highlighted = navigation.results.first }
            if !navigation.query.isEmpty {
                Button { navigation.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(minHeight: Theme.Size.field + 2)
        .fieldChrome(focused: focused.wrappedValue)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let results = navigation.results
        guard !results.isEmpty else { return .ignored }
        let index = navigation.highlighted.flatMap(results.firstIndex(of:)) ?? (step > 0 ? -1 : results.count)
        navigation.highlighted = results[min(max(index + step, 0), results.count - 1)]
        return .handled
    }

    private func open() {
        guard let key = navigation.highlighted ?? navigation.results.first else { return }
        navigation.jump(to: key)
    }
}

/// What the search found, grouped by tab: each row in the page's words with the match marked, the control itself
/// where it is a switch or a short choice, and a click (or Return) to open it where it lives.
struct SettingsSearchResults: View {
    var model: SettingsModel
    private var navigation: SettingsNavigation { model.navigation }

    var body: some View {
        let results = navigation.results
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    if results.isEmpty {
                        EmptyState(title: Text("Nothing in Settings says that", comment: "Settings search: no results"),
                                   message: Text("Try another word, like “quiet”, “folder” or “voice”.", comment: "Settings search: no results"),
                                   systemImage: "magnifyingglass")
                    } else {
                        Text("Each result is the real setting. Change it here, or open its tab to see the rest.",
                             comment: "Settings search: under the title")
                            .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    }
                    // The tab with the best match first.
                    ForEach(results.map(\.tab).reduce(into: [SettingsTab]()) { tabs, tab in if !tabs.contains(tab) { tabs.append(tab) } }) { tab in
                        group(tab, keys: results.filter { $0.tab == tab })
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: navigation.highlighted) { _, key in
                guard let key else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(key, anchor: .center) }
            }
        }
    }

    private func group(_ tab: SettingsTab, keys: [SettingKey]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tab.tint.gradient).frame(width: 20, height: 20)
                    .overlay { Image(systemName: tab.symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white) }
                    .accessibilityHidden(true)
                Text(verbatim: tab.title).font(Theme.Font.headline).foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    navigation.query = ""
                    navigation.tab = tab
                } label: {
                    HStack(spacing: 3) {
                        Text("Open \(tab.title)", comment: "Settings search: opens a tab, “Open Attention”")
                        Image(systemName: "chevron.forward").font(.system(size: 9, weight: .bold))
                    }
                    .font(Theme.Font.captionStrong)
                    .foregroundStyle(Theme.link)
                }
                .buttonStyle(.plain)
            }
            RowsCard {
                ForEach(keys, id: \.self) { key in
                    SearchResultRow(key: key, model: model, highlighted: navigation.highlighted == key) { navigation.jump(to: key) }
                        .id(key)
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    var key: SettingKey
    var model: SettingsModel
    var highlighted: Bool
    var open: () -> Void
    @Environment(\.settingsNavigation) private var navigation

    var body: some View {
        let query = navigation?.query ?? ""
        HStack(alignment: .center, spacing: Theme.Space.l) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    marked(key.section, query: query).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    marked(key.title, query: query).font(Theme.Font.body).foregroundStyle(Theme.ink)
                    marked(key.detail, query: query).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens it in \(key.tab.title)", comment: "VoiceOver: a Settings search result opens its tab"))
            SettingInlineControl(key: key, model: model)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m - 1)
        .background(highlighted ? Theme.accentSoft : .clear)
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5)
                    .padding(1)
            }
        }
    }

    /// `text` with what the search matched on a soft amber mark.
    private func marked(_ text: String, query: String) -> Text {
        var attributed = AttributedString(text)
        for range in SettingsSearch.matches(of: query, in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].backgroundColor = Theme.warningSoft
        }
        return Text(attributed)
    }
}

/// The control itself, for settings that are one switch or a short choice; the rest open where they live.
struct SettingInlineControl: View {
    var key: SettingKey
    var model: SettingsModel

    var body: some View {
        switch key {
        case .openAtLogin: toggle(Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
        case .addonUpdates: toggle(setting(\.updates.addons))
        case .eyesFollow: toggle(setting(\.eyesFollowPointer))
        case .folks: toggle(setting(\.showFolks))
        case .sleep: toggle(setting(\.sleepWhenIdle))
        case .gameSounds: toggle(setting(\.games.sounds))
        case .sounds: toggle(setting(\.sounds))
        case .hiddenNotifications: toggle(setting(\.useSystemNotificationsWhenHidden))
        case .morningBrief: toggle(setting(\.morningBrief))
        case .quietHours: toggle(setting(\.quietHours.on))
        case .debugLogging: toggle(Binding(get: { model.settings.debugLogging }, set: { model.setDebugLogging($0) }))
        case .attentionMode: AttentionDial(model: model, compact: true)
        case .lightOrDark: AppearancePicker(model: model)
        case .density: DensityPicker(model: model)
        default:
            Image(systemName: "chevron.forward").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                .flipsForRightToLeftLayoutDirection(true)
                .accessibilityHidden(true)
        }
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { Text(verbatim: key.title) }.toggleStyle(.switch).labelsHidden().tint(Theme.accent)
    }

    private func setting(_ path: WritableKeyPath<AppSettings, Bool> & Sendable) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: path] }, set: { on in model.update { $0[keyPath: path] = on } })
    }
}
