import KeyboardShortcuts
import SidefolkCore
import SwiftUI

/// Settings › General (D84): a version of Sidefolk waiting, how it starts, updates, and what times of day mean. The
/// theme moved to Appearance; quiet mode, notifications and the morning brief to Attention.
struct GeneralSettingsView: View {
    var model: SettingsModel

    var body: some View {
        SettingsPage {
            UpdateHero(updates: model.services.updates)

            SettingsGroup(title: Text(verbatim: SettingKey.openAtLogin.section)) {
                SettingsRow(.openAtLogin) {
                    Toggle("Open at login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                        .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                }
                if let error = model.loginError {
                    InlineError(error: error).padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                }
                SettingsRow(.askShortcut) {
                    // The menu bar and the Ask panel show the shortcut, so tell the app when it changes.
                    KeyboardShortcuts.Recorder(for: .ask) { _ in model.services.settingsChanged() }
                        .accessibilityLabel("Ask shortcut")
                }
                LanguageRow()
            }

            UpdatesSettingsGroup(model: model)

            SettingsGroup(title: Text(verbatim: SettingKey.timesOfDay.section)) {
                SettingsRow(.timesOfDay) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Space.s) { hourPickers }
                        VStack(alignment: .trailing, spacing: Theme.Space.xs) { hourPickers }
                    }
                }
                SettingsRow(.welcome) {
                    Button("Show welcome") { model.services.replayOnboarding() }.buttonStyle(.sf(.secondary))
                }
            }
        }
    }

    @ViewBuilder private var hourPickers: some View {
        hourPicker(Text("Morning"), hours: 5...11, key: \.morningHour)
        hourPicker(Text("Afternoon"), hours: 12...17, key: \.afternoonHour)
        hourPicker(Text("Evening"), hours: 16...23, key: \.eveningHour)
    }

    /// "Morning 09:00" as one small menu: the word, then the hour it means.
    private func hourPicker(_ title: Text, hours: ClosedRange<Int>, key: WritableKeyPath<AppSettings, Int> & Sendable) -> some View {
        let value = model.settings[keyPath: key]
        return Menu {
            Picker(selection: Binding(get: { model.settings[keyPath: key] }, set: { h in model.update { $0[keyPath: key] = h } })) {
                ForEach(Array(Set(hours).union([value])).sorted(), id: \.self) { Text(verbatim: TimeText.hour($0)).tag($0) }
            } label: { title }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: Theme.Space.xs) {
                title.foregroundStyle(Theme.inkMuted)
                Text(verbatim: TimeText.hour(value)).font(Theme.Font.bodyStrong.monospacedDigit()).foregroundStyle(Theme.ink)
            }
            .font(Theme.Font.body)
            .padding(.horizontal, Theme.Space.s)
            .frame(minHeight: Theme.Size.field)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("\(title) \(TimeText.hour(value))"))
    }
}

/// A version of Sidefolk waiting, at the top of General (D84): what it is, a few lines of what's new, and the one
/// step it needs. Nothing while there's nothing to install.
struct UpdateHero: View {
    var updates: UpdateModel

    var body: some View {
        if let offer = shown {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.s) {
                        Text("\(offer.version.shown) is ready", comment: "Settings › General: a new version, “0.1.0 snapshot 560 is ready”")
                            .font(Theme.Font.headline).foregroundStyle(Theme.ink)
                        Chip(text: Text("New", comment: "A chip beside an update that waits"), tone: .accent)
                    }
                    Text(verbatim: subline(offer)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    let lines = ReleaseNotesView.highlights(offer.notes, limit: 3)
                    if !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                    Circle().fill(Theme.accent).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0.height + 1 }
                                    Text(line).font(Theme.Font.body).foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, Theme.Space.xs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: Theme.Space.s) {
                    Spacer(minLength: 0)
                    HStack(spacing: Theme.Space.s) {
                        Button("What's new") { updates.actions?.showUpdates() }.buttonStyle(.sf(.plain))
                        if updates.readyOffer != nil {
                            Button("Restart now") { updates.actions?.restartNow() }.buttonStyle(.sf(.primary))
                        } else {
                            Button(updates.plan == .replace ? "Update and Restart" : "Download") { updates.actions?.install(offer) }
                                .buttonStyle(.sf(.primary))
                        }
                    }
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.card, bottomLeadingRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.accent).frame(width: 3)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var shown: UpdateOffer? {
        switch updates.phase {
        case .available(let o), .ready(let o): o
        default: nil
        }
    }

    private func subline(_ offer: UpdateOffer) -> String {
        var parts = [String(localized: "You have \(updates.running)", comment: "Settings › General: the version that runs, beside a new one")]
        if offer.image.size > 0 { parts.append(Wording.bytes(offer.image.size)) }
        if updates.readyOffer != nil { parts.append(String(localized: "downloaded and checked")) }
        return parts.joined(separator: " · ")
    }
}

/// The scrolling body of a Settings tab, which scrolls to a setting search jumped to (D84). Left-aligned under the
/// tab's title, at most 720 wide.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.settingsNavigation) private var navigation
    @Environment(\.rendersFullPage) private var fullPage

    var body: some View {
        if fullPage {
            column.background { PageBackground() }
        } else {
            ScrollViewReader { proxy in
                ScrollView { column }
                    .scrollContentBackground(.hidden)
                    .background { PageBackground() }
                    .task(id: navigation?.revealed) {
                        guard let key = navigation?.revealed else { return }
                        // After the first layout, or there is nothing to scroll to yet.
                        try? await Task.sleep(for: .milliseconds(80))
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(key, anchor: .center) }
                        try? await Task.sleep(for: .seconds(2.4))
                        if navigation?.revealed == key { navigation?.revealed = nil }
                    }
            }
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) { content }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.xs)
            .padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The language Sidefolk speaks. It follows the Mac until one is chosen; a change applies on relaunch.
private struct LanguageRow: View {
    @State private var chosen = AppLanguage.chosen
    private let running = AppLanguage.current

    var body: some View {
        SettingsRow(title: Text("Language"), detail: detail) {
            HStack(spacing: Theme.Space.s) {
                if (chosen ?? AppLanguage.system) != running {
                    Button("Restart now") { AppLanguage.relaunch() }.buttonStyle(.sf(.primary))
                }
                Picker("Language", selection: Binding(get: { chosen ?? "" }, set: { code in
                    chosen = code.isEmpty ? nil : code
                    AppLanguage.chosen = chosen
                })) {
                    Text(verbatim: Self.sameAsMac).tag("")
                    Divider()
                    ForEach(AppLanguage.supported, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                }
                .labelsHidden()
                .frame(width: Self.pickerWidth)
            }
        }
    }

    private static let sameAsMac = String(localized: "Same as the Mac (\(AppLanguage.name(of: AppLanguage.system)))")

    /// As wide as its widest choice, measured here once (the language is fixed for the launch). Left to size itself,
    /// the popup was sometimes measured before its items were in, and showed one letter until it was opened.
    private static let pickerWidth: CGFloat = {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: [sameAsMac] + AppLanguage.supported.map(\.name))
        return ceil(popup.fittingSize.width)
    }()

    private var detail: Text {
        (chosen ?? AppLanguage.system) == running
            ? Text("Typed requests are understood in English without AI; with AI, in any language.")
            : Text("Sidefolk switches language when it restarts.")
    }
}
