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
struct ExtensionAISwitchRow: View {
    var status: ExtensionAIStatus
    var change: (Bool) -> Void

    var body: some View {
        SettingsToggle(title: Text("Let it use your AI", comment: "An extension's row: the person's switch for its use of their AI"),
                       detail: Text("It says it uses it \(status.purpose). \(status.usedToday) of \(status.dailyCap) requests today.",
                                    comment: "Under the AI switch of an extension: the author's purpose, “to write quiz questions”, then requests made today and the daily limit"),
                       isOn: Binding(get: { status.on }, set: change))
    }
}
