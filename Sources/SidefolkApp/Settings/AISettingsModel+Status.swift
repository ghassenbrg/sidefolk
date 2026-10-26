import Foundation
import SidefolkCore

/// Where each option stands, worded for the person choosing, with the exact next step.
extension AISettingsModel {
    /// Qwen 3 is small, runs well on a Mac and can use tools.
    static let suggestedOllamaPull = "ollama pull qwen3"

    func status(_ option: AIChoice) -> AIProviderStatus {
        switch option {
        case .none:
            return AIProviderStatus(line: String(localized: "Notes, reminders and watches still work. Questions need an AI."), tone: .info)
        case .claudeCode:
            return cliStatus(detection?.claude, command: "claude",
                             install: (String(localized: "Not installed. Run this in Terminal, sign in when claude asks, then click Look again."),
                                       "npm install -g @anthropic-ai/claude-code && claude"))
        case .codex:
            return cliStatus(detection?.codex, command: "codex",
                             install: (String(localized: """
                                 Not installed. Run this in Terminal (or use Homebrew: brew install --cask codex), sign in \
                                 with your ChatGPT account, then click Look again.
                                 """), "npm install -g @openai/codex && codex login"))
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
                return AIProviderStatus(line: host.map { String(localized: "Requests go to \($0).") }
                                            ?? String(localized: "Enter the server's address. It usually ends in /v1."),
                                        tone: host == nil ? .attention : .info)
            }
        }
    }

    private func cliStatus(_ status: CLIStatus?, command: String, install: (line: String, command: String)) -> AIProviderStatus {
        guard let status else {
            return AIProviderStatus(badge: .init(text: String(localized: "Checking…"), tone: .neutral),
                                    line: String(localized: "Looking for \(command)…"), tone: .info)
        }
        switch status {
        case .notFound:
            return AIProviderStatus(badge: .init(text: String(localized: "Not installed"), tone: .neutral), line: install.line, tone: .attention,
                                    command: install.command)
        case .unusable(let reason):
            return AIProviderStatus(badge: .init(text: String(localized: "Can't use"), tone: .danger, symbol: "exclamationmark.triangle.fill"),
                                    line: reason, tone: .problem)
        case .ready(let path, let version, let login):
            let at = FolderAccess.displayPath(path)
            switch login {
            case nil:
                return AIProviderStatus(badge: .init(text: String(localized: "Found"), tone: .success, symbol: "checkmark"),
                                        line: String(localized: "Found \(command) \(version) at \(at). It uses the account you signed in with."),
                                        tone: .ready)
            case .chatGPT?:
                return AIProviderStatus(badge: .init(text: String(localized: "Signed in"), tone: .success, symbol: "checkmark"),
                                        line: String(localized: "Found \(command) \(version) at \(at), signed in with your ChatGPT plan."),
                                        tone: .ready)
            case .apiKey?:
                return AIProviderStatus(badge: .init(text: String(localized: "Signed in with a key"), tone: .warning),
                                        line: String(localized: """
                                            Found \(command) \(version) at \(at), signed in with an API key, so it's billed to that key. \
                                            To use your ChatGPT plan instead, run this in Terminal:
                                            """),
                                        tone: .ready, command: "\(command) login")
            case .signedOut?:
                return AIProviderStatus(badge: .init(text: String(localized: "Not signed in"), tone: .warning,
                                                     symbol: "person.crop.circle.badge.exclamationmark"),
                                        line: String(localized: "Found \(command) \(version) at \(at), but it isn't signed in. Run this in Terminal, then click Look again."),
                                        tone: .attention, command: "\(command) login")
            }
        }
    }

    private func keyStatus(_ target: APIKeyTarget, name: String, host: String, page: URL?) -> AIProviderStatus {
        if keySaved[target] == true {
            return AIProviderStatus(badge: .init(text: String(localized: "Key saved"), tone: .success, symbol: "key.fill"),
                                    line: String(localized: "Your key is in the Keychain and is only sent to \(host)."), tone: .ready)
        }
        return AIProviderStatus(line: String(localized: "Paste your \(name) API key below. It stays in your Keychain."), tone: .attention,
                                link: page.map { (String(localized: "Get a key"), $0) })
    }

    private func localStatus(_ preset: ProviderPreset) -> AIProviderStatus {
        let state = preset == .ollama ? detection?.ollama : detection?.lmStudio
        guard let state else {
            return AIProviderStatus(badge: .init(text: String(localized: "Checking…"), tone: .neutral),
                                    line: String(localized: "Looking for \(preset.name)…"), tone: .info)
        }
        let ollama = preset == .ollama
        let running = AIProviderStatus.Badge(text: String(localized: "Running"), tone: .success, symbol: "checkmark")
        switch state {
        case .notInstalled:
            return AIProviderStatus(badge: .init(text: String(localized: "Not installed"), tone: .neutral),
                                    line: ollama ? String(localized: "Not installed. Download Ollama, then get a model that can use tools:")
                                        : String(localized: "Not installed. Download LM Studio, get a model that can use tools, and start its server."),
                                    tone: .attention, link: preset.downloadPage.map { (String(localized: "Download \(preset.name)"), $0) },
                                    command: ollama ? Self.suggestedOllamaPull : nil)
        case .installedNotRunning:
            return AIProviderStatus(badge: .init(text: String(localized: "Not running"), tone: .warning),
                                    line: ollama ? String(localized: "Installed but not running. Open Ollama, then click Look again.")
                                        : String(localized: "Installed, but its server is off. In LM Studio, start the server (Developer tab), then click Look again."),
                                    tone: .attention)
        case .running(let models) where models.isEmpty:
            return AIProviderStatus(badge: running,
                                    line: ollama ? String(localized: "Running, but there are no models yet. Get one that can use tools:")
                                        : String(localized: "Running, but no model is loaded. Load one in LM Studio, then click Look again."),
                                    tone: .attention, command: ollama ? Self.suggestedOllamaPull : nil)
        case .running(let models):
            let line = models.contains(where: \.cloud)
                ? String(localized: "Running with \(models.count) models. Models marked Cloud run on ollama.com, not on this Mac.")
                : String(localized: "Running with \(models.count) models.")
            return AIProviderStatus(badge: running, line: line, tone: .ready)
        }
    }
}
