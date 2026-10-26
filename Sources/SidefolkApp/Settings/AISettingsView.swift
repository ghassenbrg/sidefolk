import SidefolkCore
import SwiftUI

/// Settings › AI: which brain answers questions, its models, a connection test, and exactly what
/// Sidefolk last sent to it.
struct AISettingsView: View {
    var model: SettingsModel
    @State private var showPayload: Bool

    init(model: SettingsModel, showPayload: Bool = false) {
        self.model = model
        _showPayload = State(initialValue: showPayload)
    }

    private var provider: ProviderSettings { model.settings.provider }

    var body: some View {
        SettingsPage {
            Label {
                Text("Notes, reminders and watches work without AI. AI is only used for questions and open-ended requests.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.folkColor("byte"))
            }
            .font(Theme.Font.body)
            .foregroundStyle(Theme.ink)
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            SettingsGroup(title: "AI provider") {
                ForEach(ProviderKind.allCases, id: \.self) { kind in
                    ChoiceRow(title: title(kind), detail: detail(kind), selected: provider.kind == kind) { model.setProvider(kind) }
                }
            }

            switch provider.kind {
            case .none: EmptyView()
            case .claudeCode: ClaudeCodeFields(model: model)
            case .anthropic: AnthropicFields(model: model)
            case .openAICompatible: OpenAIFields(model: model)
            }

            if provider.kind != .none {
                SettingsGroup(title: "Connection") {
                    SettingsRow(title: "Check that it answers", detail: "Sends one tiny request. It counts toward your usage.") {
                        Button(model.checking ? "Testing…" : "Test connection") { Task { await model.checkProvider() } }
                            .buttonStyle(.sf(.secondary))
                            .disabled(model.checking)
                    }
                    if let result = model.checkResult {
                        checkLine(result)
                    }
                }
            }

            SettingsGroup(title: "What Sidefolk sends",
                          footer: "Your notes and messages go only to the AI you chose, and only what's needed for the request.") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    DisclosureGroup(isExpanded: $showPayload) {
                        payload.padding(.top, Theme.Space.s)
                    } label: {
                        Text("Last request").font(Theme.Font.body).foregroundStyle(Theme.ink)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.m)
            }
        }
    }

    @ViewBuilder private var payload: some View {
        if let preview = model.contextPreview, !preview.isEmpty {
            ScrollView {
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.m)
            }
            .frame(height: 220)
            .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
            .accessibilityLabel("Last request sent to the AI")
        } else {
            Text("Nothing sent yet. After your first question, you'll see here exactly what went out.")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
    }

    private func checkLine(_ result: Result<String, UserFacingError>) -> some View {
        Group {
            switch result {
            case .success(let text):
                Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
            case .failure(let error):
                Label(error.description, systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
            }
        }
        .font(Theme.Font.caption)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }

    private func title(_ kind: ProviderKind) -> String {
        switch kind {
        case .none: "No AI"
        case .claudeCode: "Claude Code"
        case .anthropic: "Anthropic API"
        case .openAICompatible: "OpenAI-compatible"
        }
    }

    private func detail(_ kind: ProviderKind) -> String {
        switch kind {
        case .none: "Everything local keeps working. Questions wait until you pick an AI."
        case .claudeCode: "Uses your Claude subscription through the claude command. No API key needed."
        case .anthropic: "Pay as you go with your own Anthropic API key."
        case .openAICompatible: "OpenAI, Ollama, LM Studio, OpenRouter or any compatible server."
        }
    }
}

// MARK: - Per-provider fields

private struct ModelRows: View {
    var model: SettingsModel
    var placeholder: String
    var smartPlaceholder: String

    var body: some View {
        SettingsRow(title: "Model", detail: "Answers most requests.") {
            CommitField(label: "Model", prompt: placeholder, value: model.settings.provider.model, width: 220, monospaced: true) { m in
                model.update { $0.provider.model = m }
            }
        }
        SettingsRow(title: "Smart model", detail: "Used when you ask it to think harder. Empty uses the model above.") {
            CommitField(label: "Smart model", prompt: smartPlaceholder, value: model.settings.provider.smartModel, width: 220,
                        monospaced: true) { m in
                model.update { $0.provider.smartModel = m }
            }
        }
    }
}

private struct ClaudeCodeFields: View {
    var model: SettingsModel

    var body: some View {
        SettingsGroup(title: "Claude Code") {
            SettingsRow(title: "claude command", detail: found) {
                Button("Look again") { Task { await model.redetect() } }.buttonStyle(.sf(.secondary))
            }
            SettingsRow(title: "Custom path", detail: "Only if it's installed somewhere unusual.") {
                CommitField(label: "Custom path to claude", prompt: "/usr/local/bin/claude", value: model.settings.provider.claudePath,
                            width: 220, monospaced: true) { path in
                    model.update { $0.provider.claudePath = path }
                }
            }
            ModelRows(model: model, placeholder: "sonnet", smartPlaceholder: "opus")
        }
    }

    private var found: String {
        guard let detection = model.detection else { return "Looking…" }
        guard let path = detection.claudePath else { return "Not found. Install Claude Code, or set its path below." }
        let version = detection.claudeVersion.map { " \($0)" } ?? ""
        return "Found claude\(version) at \(FolderAccess.displayPath(path))."
    }
}

/// The Keychain-backed key row: never shows the key, only whether one is saved.
private struct APIKeyRow: View {
    var model: SettingsModel
    var kind: ProviderKind
    var optional = false
    @State private var draft = ""

    var body: some View {
        if model.keySaved[kind] == true {
            SettingsRow(title: "API key", detail: "Saved in your Keychain. Sent only to this provider.") {
                HStack(spacing: Theme.Space.s) {
                    Chip("Saved", tone: .success, systemImage: "key.fill")
                    Button("Remove key") { model.removeKey(for: kind) }.buttonStyle(.sf(.destructive))
                }
            }
        } else {
            SettingsRow(title: "API key", detail: optional ? "Optional. Local servers like Ollama don't need one." : "Stored in your Keychain, never in Sidefolk's files.") {
                HStack(spacing: Theme.Space.s) {
                    SecureField("API key", text: $draft, prompt: Text(kind == .anthropic ? "sk-ant-…" : "sk-…"))
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
        model.saveKey(draft, for: kind)
        draft = ""
    }
}

private struct AnthropicFields: View {
    var model: SettingsModel

    var body: some View {
        SettingsGroup(title: "Anthropic API") {
            APIKeyRow(model: model, kind: .anthropic)
            ModelRows(model: model, placeholder: "claude-sonnet-4-5", smartPlaceholder: "claude-opus-4-1")
        }
    }
}

private struct OpenAIFields: View {
    var model: SettingsModel
    @State private var confirm: (url: String, oldHost: String, newHost: String)?

    var body: some View {
        SettingsGroup(title: "OpenAI-compatible") {
            SettingsRow(title: "Server", detail: "The API's base address.") {
                HStack(spacing: Theme.Space.s) {
                    CommitField(label: "Server address", prompt: "https://api.openai.com/v1", value: model.settings.provider.baseURL,
                                width: 230, monospaced: true, commit: propose)
                    Menu("Presets") {
                        ForEach(SettingsModel.presets, id: \.url) { preset in
                            Button("\(preset.name) — \(preset.url)") { propose(preset.url) }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.sf(.secondary))
                    .fixedSize()
                }
            }
            if let error = model.baseURLError {
                InlineError(error: error).padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
            }
            APIKeyRow(model: model, kind: .openAICompatible, optional: true)
            ModelRows(model: model, placeholder: "gpt-4o-mini", smartPlaceholder: "gpt-4o")
            if let detection = model.detection, detection.ollamaRunning, !detection.ollamaModels.isEmpty {
                SettingsRow(title: "Ollama models on this Mac", detail: Describe.list(Array(detection.ollamaModels.prefix(4)))) {
                    Menu("Use a model") {
                        ForEach(detection.ollamaModels, id: \.self) { name in
                            Button(name) {
                                model.update { $0.provider.model = name }
                                if !model.settings.provider.baseURL.contains("11434") { propose(SettingsModel.presets[1].url) }
                            }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.sf(.secondary))
                    .fixedSize()
                }
            }
        }
        .confirmationDialog("Send your saved key to \(confirm?.newHost ?? "")?", isPresented: Binding(
            get: { confirm != nil }, set: { if !$0 { confirm = nil } }
        ), presenting: confirm) { c in
            Button("Use my key with \(c.newHost)") { model.setBaseURL(c.url) }
            Button("Remove the key and switch") { model.setBaseURL(c.url, removingKey: true) }
            Button("Cancel", role: .cancel) {}
        } message: { c in
            Text("Your key was saved for \(c.oldHost). Sidefolk only sends a key to the server it was saved for.")
        }
    }

    private func propose(_ url: String) {
        guard url != model.settings.provider.baseURL else { return }
        switch model.checkBaseURL(url) {
        case .ok: model.setBaseURL(url)
        case .invalid: break
        case .needsKeyConfirmation(let oldHost, let newHost): confirm = (url, oldHost, newHost)
        }
    }
}
