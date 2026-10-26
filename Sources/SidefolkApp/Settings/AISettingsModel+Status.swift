import Foundation
import SidefolkCore

/// Where each option stands, worded for the person choosing, with the exact next step.
extension AISettingsModel {
    /// Qwen 3 is small, runs well on a Mac and can use tools.
    static let suggestedOllamaPull = "ollama pull qwen3"

    func status(_ option: AIChoice) -> AIProviderStatus {
        switch option {
        case .none:
            return AIProviderStatus(line: "Notes, reminders and watches still work. Questions need an AI.", tone: .info)
        case .claudeCode:
            return cliStatus(detection?.claude, command: "claude",
                             install: ("Not installed. Run this in Terminal, sign in when claude asks, then click Look again.",
                                       "npm install -g @anthropic-ai/claude-code && claude"))
        case .codex:
            return cliStatus(detection?.codex, command: "codex",
                             install: ("Not installed. Run this in Terminal (or use Homebrew: brew install --cask codex), sign in "
                                       + "with your ChatGPT account, then click Look again.", "npm install -g @openai/codex && codex login"))
        case .anthropic:
            return keyStatus(.anthropic, name: "Anthropic", host: ProviderKeys.anthropicHost,
                             page: URL(string: "https://console.anthropic.com/settings/keys"))
        case .preset(let preset):
            switch preset.group {
            case .apiKey:
                return keyStatus(.preset(preset), name: preset.name, host: URL(string: preset.baseURL)?.host ?? preset.name, page: preset.keyPage)
            case .local:
                return localStatus(preset)
            case .custom:
                let host = URL(string: provider.baseURL)?.host
                return AIProviderStatus(line: host.map { "Requests go to \($0)." } ?? "Enter the server's address. It usually ends in /v1.",
                                        tone: host == nil ? .attention : .info)
            }
        }
    }

    private func cliStatus(_ status: CLIStatus?, command: String, install: (line: String, command: String)) -> AIProviderStatus {
        guard let status else {
            return AIProviderStatus(badge: .init(text: "Checking…", tone: .neutral), line: "Looking for \(command)…", tone: .info)
        }
        switch status {
        case .notFound:
            return AIProviderStatus(badge: .init(text: "Not installed", tone: .neutral), line: install.line, tone: .attention,
                                    command: install.command)
        case .unusable(let reason):
            return AIProviderStatus(badge: .init(text: "Can't use", tone: .danger, symbol: "exclamationmark.triangle.fill"),
                                    line: reason, tone: .problem)
        case .ready(let path, let version, let login):
            let found = "Found \(command) \(version) at \(FolderAccess.displayPath(path))"
            switch login {
            case nil:
                return AIProviderStatus(badge: .init(text: "Found", tone: .success, symbol: "checkmark"),
                                        line: "\(found). It uses the account you signed in with.", tone: .ready)
            case .chatGPT?:
                return AIProviderStatus(badge: .init(text: "Signed in", tone: .success, symbol: "checkmark"),
                                        line: "\(found), signed in with your ChatGPT plan.", tone: .ready)
            case .apiKey?:
                return AIProviderStatus(badge: .init(text: "Signed in with a key", tone: .warning),
                                        line: "\(found), signed in with an API key, so it's billed to that key. "
                                            + "To use your ChatGPT plan instead, run this in Terminal:",
                                        tone: .ready, command: "\(command) login")
            case .signedOut?:
                return AIProviderStatus(badge: .init(text: "Not signed in", tone: .warning, symbol: "person.crop.circle.badge.exclamationmark"),
                                        line: "\(found), but it isn't signed in. Run this in Terminal, then click Look again.",
                                        tone: .attention, command: "\(command) login")
            }
        }
    }

    private func keyStatus(_ target: APIKeyTarget, name: String, host: String, page: URL?) -> AIProviderStatus {
        if keySaved[target] == true {
            return AIProviderStatus(badge: .init(text: "Key saved", tone: .success, symbol: "key.fill"),
                                    line: "Your key is in the Keychain and is only sent to \(host).", tone: .ready)
        }
        return AIProviderStatus(line: "Paste your \(name) API key below. It stays in your Keychain.", tone: .attention,
                                link: page.map { ("Get a key", $0) })
    }

    private func localStatus(_ preset: ProviderPreset) -> AIProviderStatus {
        let state = preset == .ollama ? detection?.ollama : detection?.lmStudio
        guard let state else {
            return AIProviderStatus(badge: .init(text: "Checking…", tone: .neutral), line: "Looking for \(preset.name)…", tone: .info)
        }
        let ollama = preset == .ollama
        switch state {
        case .notInstalled:
            return AIProviderStatus(badge: .init(text: "Not installed", tone: .neutral),
                                    line: ollama ? "Not installed. Download Ollama, then get a model that can use tools:"
                                        : "Not installed. Download LM Studio, get a model that can use tools, and start its server.",
                                    tone: .attention, link: preset.downloadPage.map { ("Download \(preset.name)", $0) },
                                    command: ollama ? Self.suggestedOllamaPull : nil)
        case .installedNotRunning:
            return AIProviderStatus(badge: .init(text: "Not running", tone: .warning),
                                    line: ollama ? "Installed but not running. Open Ollama, then click Look again."
                                        : "Installed, but its server is off. In LM Studio, start the server (Developer tab), then click Look again.",
                                    tone: .attention)
        case .running(let models) where models.isEmpty:
            return AIProviderStatus(badge: .init(text: "Running", tone: .success, symbol: "checkmark"),
                                    line: ollama ? "Running, but there are no models yet. Get one that can use tools:"
                                        : "Running, but no model is loaded. Load one in LM Studio, then click Look again.",
                                    tone: .attention, command: ollama ? Self.suggestedOllamaPull : nil)
        case .running(let models):
            var line = "Running with \(models.count) model\(models.count == 1 ? "" : "s")."
            if models.contains(where: \.cloud) { line += " Models marked Cloud run on ollama.com, not on this Mac." }
            return AIProviderStatus(badge: .init(text: "Running", tone: .success, symbol: "checkmark"), line: line, tone: .ready)
        }
    }
}
