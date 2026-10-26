import AppKit
import SidefolkCore
import SwiftUI

/// The chosen option's setup, under its row: where it stands and what to do next, then only the
/// fields it needs (key, models, address, path) and the one-click test.
struct ProviderSetup: View {
    var option: AIChoice
    var ai: AISettingsModel
    var status: AIProviderStatus

    private var provider: ProviderSettings { ai.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            StatusLine(status: status, lookAgain: needsLookAgain ? { Task { await ai.redetect() } } : nil)
            fields
            if canTest { TestRow(ai: ai, local: isLocal) }
        }
    }

    @ViewBuilder private var fields: some View {
        switch option {
        case .none:
            EmptyView()
        case .claudeCode:
            if case .ready? = ai.detection?.claude {
                ModelPicker(title: "Model", detail: "Answers most requests.", value: provider.model, placeholder: "sonnet") { ai.setModel($0) }
                ModelPicker(title: "Think harder", detail: "Empty uses the model above.", value: provider.smartModel, placeholder: "opus") {
                    ai.setSmartModel($0)
                }
            }
            PathRow(title: "Custom path to claude", value: provider.claudePath, placeholder: "/usr/local/bin/claude") { ai.setCLIPath($0, codex: false) }
        case .codex:
            if case .ready? = ai.detection?.codex {
                let models = ai.detection?.codexModels ?? []
                ModelPicker(title: "Model", detail: "Empty uses Codex's default.", value: provider.model, placeholder: "Codex's default",
                            options: models) { ai.setModel($0) }
                ModelPicker(title: "Think harder", detail: "Always asks Codex for high reasoning effort; empty keeps the model above.",
                            value: provider.smartModel, placeholder: "Same model", options: models) { ai.setSmartModel($0) }
            }
            PathRow(title: "Custom path to codex", value: provider.codexPath, placeholder: "/usr/local/bin/codex") { ai.setCLIPath($0, codex: true) }
        case .anthropic:
            KeyRow(ai: ai, target: .anthropic, prompt: "sk-ant-…")
            ModelPicker(title: "Model", detail: "Empty uses Sidefolk's default.", value: provider.model, placeholder: AnthropicModel.defaultModel) {
                ai.setModel($0)
            }
            ModelPicker(title: "Think harder", detail: "Empty uses the model above.", value: provider.smartModel, placeholder: "Same model") {
                ai.setSmartModel($0)
            }
        case .preset(let preset):
            if preset == .custom { AddressRow(ai: ai) }
            if preset.keyNeed != .none { KeyRow(ai: ai, target: .preset(preset), prompt: preset == .custom ? "Optional" : "Paste key") }
            if preset.keyNeed != .required || ai.keySaved[.preset(preset)] == true {
                presetModels(preset)
            }
        }
    }

    @ViewBuilder private func presetModels(_ preset: ProviderPreset) -> some View {
        let options = ai.models ?? []
        let suggested = preset.defaultModel(available: nil) ?? ""
        ModelPicker(title: "Model", detail: "Answers most requests.", value: provider.model,
                    placeholder: suggested.isEmpty ? "Pick a model" : suggested, options: options, loading: ai.loadingModels) { ai.setModel($0) }
        if let chosen = options.first(where: { $0.id == provider.model }), chosen.usesTools == false {
            Label("This model can't use tools, and Sidefolk acts through them. Pick one that can.", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Font.caption).foregroundStyle(Theme.danger)
        }
        ModelPicker(title: "Think harder", detail: "Empty uses the model above.", value: provider.smartModel, placeholder: "Same model",
                    options: options, loading: ai.loadingModels) { ai.setSmartModel($0) }
        if let error = ai.modelsError { InlineError(error: error) }
    }

    private var isLocal: Bool {
        if case .preset(let preset) = option { return preset.group == .local }
        return false
    }

    private var needsLookAgain: Bool {
        switch option {
        case .claudeCode, .codex: true
        case .preset(let preset): preset.group == .local
        default: false
        }
    }

    /// Only once there's something to test: a key, a server, a signed-in CLI.
    private var canTest: Bool {
        switch status.tone {
        case .ready: true
        case .info: option == .preset(.custom)
        case .attention, .problem: option == .preset(.custom) && !provider.baseURL.isEmpty
        }
    }
}

/// Where the option stands, in one line, with the next step's link or a "Look again".
private struct StatusLine: View {
    var status: AIProviderStatus
    var lookAgain: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(status.line).font(Theme.Font.caption).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: Theme.Space.s)
                if let link = status.link {
                    Link(destination: link.url) { Label(link.title, systemImage: "arrow.up.right") }
                        .font(Theme.Font.captionStrong)
                        .fixedSize()
                }
                if let lookAgain {
                    Button("Look again", action: lookAgain).buttonStyle(.sf(.secondary)).fixedSize()
                }
            }
            if let command = status.command { CommandLine(command: command) }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private var symbol: String {
        switch status.tone {
        case .ready: "checkmark.circle.fill"
        case .attention: "arrow.right.circle.fill"
        case .problem: "exclamationmark.circle.fill"
        case .info: "info.circle"
        }
    }

    private var color: Color {
        switch status.tone {
        case .ready: Theme.success
        case .attention: Theme.folkColor("scout")
        case .problem: Theme.danger
        case .info: Theme.inkMuted
        }
    }
}

/// A Terminal command for the next step, selectable and with a Copy button.
private struct CommandLine: View {
    var command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            }
            .buttonStyle(.sf(.secondary))
            .fixedSize()
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
    }
}

/// A field's label on the left, its control on the right, inside an option's setup.
private struct SetupRow<Control: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.Font.body).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
    }
}

/// A model name to type, or to pick from what the provider lists (marked when it can't use tools
/// or runs in a cloud).
private struct ModelPicker: View {
    var title: String
    var detail: String
    var value: String
    var placeholder: String
    var options: [ModelOption] = []
    var loading = false
    var commit: (String) -> Void

    var body: some View {
        SetupRow(title: title, detail: detail) {
            HStack(spacing: Theme.Space.xs) {
                CommitField(label: title, prompt: placeholder, value: value, width: 200, monospaced: true, live: true, commit: commit)
                if loading {
                    ProgressView().controlSize(.small)
                } else if !options.isEmpty {
                    Menu {
                        ForEach(options) { option in
                            Button(Self.label(option)) { commit(option.id) }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Choose a \(title.lowercased()) model")
                }
            }
        }
    }

    static func label(_ option: ModelOption) -> String {
        var notes: [String] = []
        if option.cloud { notes.append("Cloud") }
        if option.usesTools == false { notes.append("can't use tools") }
        return notes.isEmpty ? option.id : "\(option.id) — \(notes.joined(separator: ", "))"
    }
}

/// The Keychain-backed key: never shown, only whether one is saved.
private struct KeyRow: View {
    var ai: AISettingsModel
    var target: APIKeyTarget
    var prompt: String
    @State private var draft = ""

    var body: some View {
        if ai.keySaved[target] == true {
            SetupRow(title: "API key", detail: "Saved in your Keychain.") {
                HStack(spacing: Theme.Space.s) {
                    Chip("Saved", tone: .success, systemImage: "key.fill")
                    Button("Remove key") { ai.removeKey(for: target) }.buttonStyle(.sf(.destructive))
                }
            }
        } else {
            SetupRow(title: "API key", detail: target == .preset(.custom) ? "Only if the server needs one." : nil) {
                HStack(spacing: Theme.Space.s) {
                    SecureField("API key", text: $draft, prompt: Text(prompt))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .onSubmit(save)
                    Button("Save key", action: save)
                        .buttonStyle(.sf(.primary))
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        ai.saveKey(draft, for: target)
        draft = ""
    }
}

private struct PathRow: View {
    var title: String
    var value: String
    var placeholder: String
    var commit: (String) -> Void

    var body: some View {
        SetupRow(title: title, detail: "Only if it's installed somewhere unusual.") {
            CommitField(label: title, prompt: placeholder, value: value, width: 220, monospaced: true, commit: commit)
        }
    }
}

/// The custom endpoint's address. A key saved for another address is never sent to a new one
/// without the user's yes (SECURITY T18).
private struct AddressRow: View {
    var ai: AISettingsModel
    @State private var confirm: (url: String, oldHost: String, newHost: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SetupRow(title: "Address", detail: "The API's base address.") {
                CommitField(label: "Server address", prompt: "https://api.example.com/v1", value: ai.provider.baseURL, width: 240,
                            monospaced: true, commit: propose)
            }
            if let error = ai.baseURLError { InlineError(error: error) }
        }
        .confirmationDialog("Send your saved key to \(confirm?.newHost ?? "")?", isPresented: Binding(
            get: { confirm != nil }, set: { if !$0 { confirm = nil } }
        ), presenting: confirm) { c in
            Button("Use my key with \(c.newHost)") { ai.setBaseURL(c.url, key: .moved) }
            Button("Remove the key and switch") { ai.setBaseURL(c.url, key: .removed) }
            Button("Cancel", role: .cancel) {}
        } message: { c in
            Text("Your key was saved for \(c.oldHost). Sidefolk only sends a key to the server it was saved for.")
        }
    }

    private func propose(_ url: String) {
        guard url != ai.provider.baseURL else { return }
        switch ai.checkBaseURL(url) {
        case .ok: ai.setBaseURL(url)
        case .invalid: break
        case .needsKeyConfirmation(let oldHost, let newHost): confirm = (url, oldHost, newHost)
        }
    }
}

/// One tiny request, only when clicked.
private struct TestRow: View {
    var ai: AISettingsModel
    var local: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SetupRow(title: "Test", detail: local ? "Sends one tiny request to the model."
                     : "Sends one tiny request. It counts toward your usage.") {
                Button(ai.testing ? "Testing…" : "Test") {
                    // Ends editing in an address or path field, so the test uses what was typed; model
                    // fields save as you type. The test starts once SwiftUI has saved the edit.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    DispatchQueue.main.async { Task { await ai.test() } }
                }
                .buttonStyle(.sf(.secondary))
                .disabled(ai.testing)
            }
            if let result = ai.testResult {
                Group {
                    switch result {
                    case .success(let text): Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    case .failure(let error): Label(error.description, systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
                    }
                }
                .font(Theme.Font.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
