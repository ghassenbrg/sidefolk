import SidefolkCore
import SwiftUI

/// A setting an extension declared (D100), drawn from its schema by Sidefolk, on the extension's page and in Settings › Add-ons alike.
/// A change goes through `extensions.setting`, so Guard and History see it.
struct ExtensionSettingRowView: View {
    var row: ExtensionSettingRow
    var change: (JSONValue) -> Void
    @State private var draft: String?

    var body: some View {
        SettingsRow(title: Text(ext: row.title), detail: row.detail.map { Text(ext: $0) }) { control }
    }

    @ViewBuilder private var control: some View {
        switch row.type {
        case .switch:
            Toggle(isOn: Binding(get: { row.value.boolValue ?? false }, set: { change(.bool($0)) })) { Text(ext: row.title) }
                .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
        case .choice where row.segmented:
            SegmentedPicker(Text(ext: row.title), selection: Binding(get: { row.value.stringValue ?? "" }, set: { change(.string($0)) }),
                            segments: row.options.map { .init($0.value, Text(ext: $0.title)) })
                .frame(maxWidth: 320)
        case .choice:
            Picker(selection: Binding(get: { row.value.stringValue ?? "" }, set: { change(.string($0)) })) {
                ForEach(row.options, id: \.value) { option in Text(ext: option.title).tag(option.value) }
            } label: {
                Text(ext: row.title)
            }
            .labelsHidden().fixedSize()
        case .number:
            HStack(spacing: Theme.Space.s) {
                Text(verbatim: row.valueWords).font(Theme.Font.body).monospacedDigit().foregroundStyle(Theme.ink)
                Stepper(value: Binding(get: { row.value.doubleValue ?? 0 }, set: { change(.number($0)) }),
                        in: (row.minimum ?? 0)...(row.maximum ?? 0), step: row.step ?? 1) { Text(ext: row.title) }
                    .labelsHidden()
            }
        case .text:
            TextField(text: Binding(get: { draft ?? row.value.stringValue ?? "" }, set: { draft = String($0.prefix(row.length)) })) { Text(ext: row.title) }
                .textFieldStyle(.roundedBorder).labelsHidden().frame(maxWidth: 220)
                .onSubmit {
                    if let draft { change(.string(draft.trimmingCharacters(in: .whitespaces))) }
                    draft = nil
                }
        }
    }
}

/// The person's switch for an extension's use of their AI (D100), with what it says it is for and how much it asked today.
/// A plan the person allowed for an extension (D110), with the way to end it: its calls then ask again.
struct ExtensionPlanRow: View {
    var plan: ExtensionPlanInfo
    var end: () -> Void

    /// What the row says its actions do: a count where they always run without asking, and where they don't, when they do.
    private var detail: Text {
        switch plan.stands {
        case .always where plan.actions == 0: Text("Runs by itself, with no actions on its list. \(plan.when)", comment: "Settings › Add-ons: an extension's plan that has no actions listed; then its own words for when it runs")
        case .always: Text("Runs \(plan.actions) actions without asking. \(plan.when)", comment: "Settings › Add-ons: an extension's plan; a count, then its own words for when it runs")
        case .fullAccessUnread: Text("Its actions run without asking only while Full access is on, and nobody read this plan. \(plan.when)", comment: "Settings › Add-ons: a plan Full access answered with no card; then its own words for when it runs")
        case .fullAccessSome: Text("Some of its actions run without asking only while Full access is on. \(plan.when)", comment: "Settings › Add-ons: a plan with lines that stand only in Full access; then its own words for when it runs")
        case .autoSome: Text("Some of its actions run without asking only while Auto is on, and nobody read them. \(plan.when)", comment: "Settings › Add-ons: a plan with lines Auto let through; then its own words for when it runs")
        case .either: Text("Some of its actions run without asking only while Full access or Auto is on. \(plan.when)", comment: "Settings › Add-ons: a plan with lines that stand only in Full access or only in Auto; then its own words for when it runs")
        }
    }

    var body: some View {
        SettingsRow(title: Text(ext: plan.title.isEmpty ? plan.id : plan.title), detail: detail) {
            Button(action: end) { Text("End", comment: "Settings › Add-ons: ends an extension's plan") }.buttonStyle(.sf(.secondary))
        }
    }
}

struct ExtensionAISwitchRow: View {
    var status: ExtensionAIStatus
    /// A signed pack's own words for it.
    var title: String?
    var detail: String?
    var change: (Bool) -> Void

    var body: some View {
        SettingsToggle(title: title.map { Text(ext: $0) } ?? Text("Let it use your AI", comment: "An extension's row: the person's switch for its use of their AI"),
                       detail: status.heldBack.map { Text(verbatim: $0) } ?? detail.map { Text(ext: $0) }
                           ?? Text("It says it uses it \(status.purpose). \(status.usedToday) of \(status.dailyCap) requests today.",
                                   comment: "Under the AI switch of an extension: the author's purpose, “to write quiz questions”, then requests made today and the daily limit"),
                       isOn: Binding(get: { status.on }, set: change))
    }
}

extension ExtensionWords {
    /// What an install sheet says the extension adds to Sidefolk's own places, in the person's language (D100): nothing it adds is a
    /// surprise, and all of it goes when it does.
    static func additions(_ m: ExtensionManifest, strings: ExtensionStrings?) -> [String] {
        let w = strings?.words(for: ExtensionStrings.current)
        func titles(_ place: ExtensionManifest.EntryMeta.Place) -> String {
            Wording.list(m.entries.filter { $0.places.contains(place) }.map { w?.entries[$0.id] ?? $0.title })
        }
        var out: [String] = []
        if m.entries.contains(where: { $0.places.contains(.companion) }) {
            out.append(String(localized: "In the companion's menu: \(titles(.companion))", comment: "Install sheet: items an extension adds; their titles"))
        }
        if m.entries.contains(where: { $0.places.contains(.pocket) }) {
            out.append(String(localized: "In the menu bar's menu: \(titles(.pocket))", comment: "Install sheet: items an extension adds; their titles"))
        }
        if m.entries.contains(where: { $0.places.contains(.ask) }) {
            out.append(String(localized: "A tab in Ask: \(titles(.ask))", comment: "Install sheet: a tab an extension adds; its title"))
        }
        if !m.drops.isEmpty {
            let offered = Wording.list(m.drops.map { w?.drops[$0.id]?.title ?? $0.title })
            out.append(String(localized: "When you drop something on the companion: \(offered)", comment: "Install sheet: what an extension offers for a drop; their titles"))
        }
        if !m.settings.isEmpty {
            out.append(String(localized: "\(m.settings.count) settings, in Settings › Add-ons", comment: "Install sheet: how many settings an extension declares"))
        }
        return out
    }
}
