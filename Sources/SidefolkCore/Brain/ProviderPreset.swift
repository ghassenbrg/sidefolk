import Foundation

/// The services that speak OpenAI's chat completions API, so one transport (`OpenAICompatibleModel`)
/// serves them all (D26). A preset knows the address, whether a key is needed and where to get one,
/// how to list models, and which models to suggest. Model names go stale, so suggestions are tried
/// against the provider's own list when it can be fetched; the first is the default when it can't.
public enum ProviderPreset: String, Codable, Sendable, CaseIterable {
    case openAI, gemini, mistral, groq, xai, deepSeek, openRouter
    case ollama, lmStudio
    case custom

    public enum KeyNeed: Sendable {
        case required, none, optional
    }

    public enum Group: Sendable {
        /// Pay-as-you-go cloud APIs.
        case apiKey
        /// Servers that run on this Mac.
        case local
        case custom
    }

    public enum Listing: Sendable {
        /// `GET {base}/models`, OpenAI's shape (`data[].id`).
        case openAI
        /// Ollama's `GET /api/tags`, which also says which models can use tools and which run in Ollama's cloud.
        case ollama
    }

    public static let apiKeyPresets: [ProviderPreset] = [.openAI, .gemini, .mistral, .groq, .xai, .deepSeek, .openRouter]
    public static let localPresets: [ProviderPreset] = [.ollama, .lmStudio]

    public var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .mistral: "Mistral"
        case .groq: "Groq"
        case .xai: "xAI"
        case .deepSeek: "DeepSeek"
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .custom: "Custom endpoint"
        }
    }

    public var group: Group {
        switch self {
        case .ollama, .lmStudio: .local
        case .custom: .custom
        default: .apiKey
        }
    }

    /// The fixed address, or "" for a custom endpoint (the user's own `baseURL`).
    public var baseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .mistral: "https://api.mistral.ai/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .xai: "https://api.x.ai/v1"
        case .deepSeek: "https://api.deepseek.com/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        case .custom: ""
        }
    }

    public var keyNeed: KeyNeed {
        switch self {
        case .ollama, .lmStudio: .none
        case .custom: .optional
        default: .required
        }
    }

    /// Where the user creates a key, opened from Settings.
    public var keyPage: URL? {
        let page: String? = switch self {
        case .openAI: "https://platform.openai.com/api-keys"
        case .gemini: "https://aistudio.google.com/apikey"
        case .mistral: "https://console.mistral.ai/api-keys"
        case .groq: "https://console.groq.com/keys"
        case .xai: "https://console.x.ai"
        case .deepSeek: "https://platform.deepseek.com/api_keys"
        case .openRouter: "https://openrouter.ai/keys"
        case .ollama, .lmStudio, .custom: nil
        }
        return page.flatMap(URL.init(string:))
    }

    /// Where to get the app, for the local servers.
    public var downloadPage: URL? {
        switch self {
        case .ollama: URL(string: "https://ollama.com/download")
        case .lmStudio: URL(string: "https://lmstudio.ai")
        default: nil
        }
    }

    public var listing: Listing { self == .ollama ? .ollama : .openAI }

    /// Models to use, best first: the first one the provider lists becomes the default. Long-lived
    /// aliases where the provider has them. Local servers suggest nothing: it depends on what's installed.
    public var suggestedModels: [String] {
        switch self {
        case .openAI: ["gpt-5-mini", "gpt-4.1-mini"]
        case .gemini: ["gemini-flash-latest", "gemini-2.5-flash"]
        case .mistral: ["mistral-small-latest"]
        case .groq: ["llama-3.3-70b-versatile", "openai/gpt-oss-120b"]
        case .xai: ["grok-4-fast-non-reasoning", "grok-3-mini"]
        case .deepSeek: ["deepseek-chat"]
        case .openRouter: ["openrouter/auto"]
        case .ollama, .lmStudio, .custom: []
        }
    }

    /// "Think harder" models, best first; none means the main model with a larger allowance.
    public var suggestedSmartModels: [String] {
        switch self {
        case .openAI: ["gpt-5", "gpt-4.1"]
        case .gemini: ["gemini-pro-latest", "gemini-2.5-pro"]
        case .mistral: ["mistral-large-latest", "mistral-medium-latest"]
        case .groq: ["openai/gpt-oss-120b"]
        case .xai: ["grok-4"]
        case .deepSeek: ["deepseek-reasoner"]
        case .openRouter, .ollama, .lmStudio, .custom: []
        }
    }

    /// The first suggestion the provider offers, or the first suggestion when its list is unknown.
    public func defaultModel(available: [String]?) -> String? {
        Self.pick(suggestedModels, from: available)
    }

    public func defaultSmartModel(available: [String]?) -> String? {
        Self.pick(suggestedSmartModels, from: available)
    }

    static func pick(_ wanted: [String], from available: [String]?) -> String? {
        guard let available else { return wanted.first }
        return wanted.first { available.contains($0) }
    }

    /// The Keychain account for this preset's key. OpenAI keeps the account every OpenAI-compatible
    /// key used before presets existed, so those keys still work (`ProviderKeys` also falls back to it).
    public var keyAccount: String {
        switch self {
        case .openAI: SecretKey.openAIAPIKey
        default: "provider.\(rawValue).apiKey"
        }
    }

    /// The preset an address belongs to: how settings saved before presets existed are read.
    public static func matching(baseURL: String) -> ProviderPreset {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host?.lowercased() else {
            return .custom
        }
        if OpenAICompatibleModel.isLoopback(host) {
            switch url.port {
            case 11434: return .ollama
            case 1234: return .lmStudio
            default: return .custom
            }
        }
        return apiKeyPresets.first { preset in
            guard let fixed = URL(string: preset.baseURL) else { return false }
            return fixed.host == host && url.path.hasPrefix(fixed.path)
        } ?? .custom
    }
}

extension ProviderSettings {
    /// The address requests go to: the preset's, or the user's own for a custom endpoint.
    public var resolvedBaseURL: String { preset == .custom ? baseURL : preset.baseURL }
}
