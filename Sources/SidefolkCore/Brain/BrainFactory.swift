import Foundation

/// The backend for one run and the model name it will use ("" lets Claude Code pick its default).
public struct BrainChoice: Sendable {
    public var backend: any BrainBackend
    public var model: String
    public init(backend: any BrainBackend, model: String) {
        self.backend = backend
        self.model = model
    }
}

/// Turns the AI settings into a backend. `.standard` is what the app uses; tests can pass any closure.
public struct BrainFactory: Sendable {
    private let choose: @Sendable (ProviderSettings, Bool) throws(UserFacingError) -> BrainChoice

    public init(_ choose: @escaping @Sendable (ProviderSettings, Bool) throws(UserFacingError) -> BrainChoice) {
        self.choose = choose
    }

    /// - Parameter thinkHarder: use the smart model (when set) and a larger output allowance.
    public func make(_ provider: ProviderSettings, thinkHarder: Bool) throws(UserFacingError) -> BrainChoice {
        try choose(provider, thinkHarder)
    }

    /// - Parameters:
    ///   - secrets: where API keys live (`KeychainSecretStore` in the app).
    ///   - claudeCodeBackend: builds the Claude Code CLI backend; nil while it isn't available.
    ///   - codexBackend: builds the Codex CLI backend (the flag is "think harder"); nil while it isn't available.
    public static func standard(
        secrets: any SecretStore, transport: any HTTPTransport = URLSessionTransport(), retry: RetryPolicy = .standard,
        limits: LoopLimits = .standard, clock: any Clock = SystemClock(),
        claudeCodeBackend: (@Sendable (ProviderSettings) -> (any BrainBackend)?)? = nil,
        codexBackend: (@Sendable (ProviderSettings, Bool) -> (any BrainBackend)?)? = nil
    ) -> BrainFactory {
        let keys = ProviderKeys(store: secrets)
        return BrainFactory { (provider: ProviderSettings, thinkHarder: Bool) throws(UserFacingError) -> BrainChoice in
            let main = provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
            let smart = provider.smartModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let chosen = thinkHarder && !smart.isEmpty ? smart : main
            var loopLimits = limits
            if thinkHarder { loopLimits.maxOutputTokens = max(loopLimits.maxOutputTokens, 16_000) }

            switch provider.kind {
            case .none:
                throw UserFacingError("That needs AI, which isn't set up yet.",
                                      recovery: "Choose Claude Code, Codex, an API key or Ollama in Settings › AI.")

            case .claudeCode:
                guard let backend = claudeCodeBackend?(provider) else {
                    throw UserFacingError("Claude Code isn't ready to help yet. Nothing was changed.",
                                          recovery: "Check Claude Code in Settings › AI, or choose another provider.")
                }
                return BrainChoice(backend: backend, model: chosen)

            case .codex:
                guard let backend = codexBackend?(provider, thinkHarder) else {
                    throw UserFacingError("Codex isn't ready to help yet. Nothing was changed.",
                                          recovery: "Check Codex in Settings › AI, or choose another provider.")
                }
                return BrainChoice(backend: backend, model: chosen)

            case .anthropic:
                guard let key = try keys.key(account: SecretKey.anthropicAPIKey, host: ProviderKeys.anthropicHost) else {
                    throw UserFacingError("I need your Anthropic API key for that.", recovery: "Add it in Settings › AI.")
                }
                let name = chosen.isEmpty ? AnthropicModel.defaultModel : chosen
                let model = AnthropicModel(apiKey: key, transport: transport, retry: retry)
                return BrainChoice(backend: LoopBackend(model: model, checkModel: name, limits: loopLimits, clock: clock), model: name)

            case .openAICompatible:
                let preset = provider.preset
                let url = try OpenAICompatibleModel.validate(baseURL: provider.resolvedBaseURL)
                let key = try keys.key(for: preset, host: ProviderKeys.host(of: url))
                if preset.keyNeed == .required, key == nil {
                    throw UserFacingError("I need your \(preset.name) API key for that. Nothing was changed.",
                                          recovery: "Add it in Settings › AI.")
                }
                let model = try OpenAICompatibleModel(baseURL: provider.resolvedBaseURL, apiKey: key,
                                                      name: preset == .custom ? nil : preset.name, transport: transport, retry: retry)
                // No model chosen yet: the preset's first suggestion, as Settings shows it.
                var name = chosen
                if name.isEmpty, thinkHarder { name = preset.defaultSmartModel(available: nil) ?? "" }
                if name.isEmpty { name = preset.defaultModel(available: nil) ?? "" }
                guard !name.isEmpty else {
                    throw UserFacingError("I need to know which \(model.providerName) model to use.", recovery: "Choose one in Settings › AI.")
                }
                return BrainChoice(backend: LoopBackend(model: model, checkModel: name, limits: loopLimits, clock: clock), model: name)
            }
        }
    }
}
