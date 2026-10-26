import Foundation

/// The backend for one run, the model name it will use ("" lets a CLI pick its default) and the
/// reasoning effort to ask for (nil sends nothing).
public struct BrainChoice: Sendable {
    public var backend: any BrainBackend
    public var model: String
    public var effort: ReasoningEffort?
    public init(backend: any BrainBackend, model: String, effort: ReasoningEffort? = nil) {
        self.backend = backend
        self.model = model
        self.effort = effort
    }
}

/// Turns the AI settings into a backend. `.standard` is what the app uses; tests can pass any closure.
public struct BrainFactory: Sendable {
    private let choose: @Sendable (ProviderSettings, Bool) throws(UserFacingError) -> BrainChoice

    public init(_ choose: @escaping @Sendable (ProviderSettings, Bool) throws(UserFacingError) -> BrainChoice) {
        self.choose = choose
    }

    /// - Parameter thinkHarder: use the smart model (when set), its effort and a larger output allowance.
    public func make(_ provider: ProviderSettings, thinkHarder: Bool) throws(UserFacingError) -> BrainChoice {
        try choose(provider, thinkHarder)
    }

    /// - Parameters:
    ///   - secrets: where API keys live (`KeychainSecretStore` in the app).
    ///   - claudeCodeBackend: builds the Claude Code CLI backend; nil while it isn't available.
    ///   - codexBackend: builds the Codex CLI backend; nil while it isn't available.
    public static func standard(
        secrets: any SecretStore, transport: any HTTPTransport = URLSessionTransport(), retry: RetryPolicy = .standard,
        limits: LoopLimits = .standard, clock: any Clock = SystemClock(),
        claudeCodeBackend: (@Sendable (ProviderSettings) -> (any BrainBackend)?)? = nil,
        codexBackend: (@Sendable (ProviderSettings) -> (any BrainBackend)?)? = nil
    ) -> BrainFactory {
        let keys = ProviderKeys(store: secrets)
        return BrainFactory { (provider: ProviderSettings, thinkHarder: Bool) throws(UserFacingError) -> BrainChoice in
            let name = provider.modelName(thinkHarder: thinkHarder)
            // The CLIs learn what they accept when they're probed, so their backends check the effort.
            let requested = provider.requestedEffort(thinkHarder: thinkHarder)
            let effort = EffortSupport.accepted(requested, in: EffortSupport.levels(provider, thinkHarder: thinkHarder))
            var loopLimits = limits
            // Thinking counts toward the output allowance, and the top efforts think at length.
            if thinkHarder || effort.map({ $0 >= .xhigh }) == true {
                loopLimits.maxOutputTokens = max(loopLimits.maxOutputTokens, 16_000)
            }

            switch provider.kind {
            case .none:
                throw UserFacingError("That needs AI, which isn't set up yet.",
                                      recovery: "Choose Claude Code, Codex, an API key or Ollama in Settings › AI.")

            case .claudeCode:
                guard let backend = claudeCodeBackend?(provider) else {
                    throw UserFacingError("Claude Code isn't ready to help yet. Nothing was changed.",
                                          recovery: "Check Claude Code in Settings › AI, or choose another provider.")
                }
                return BrainChoice(backend: backend, model: name, effort: requested)

            case .codex:
                guard let backend = codexBackend?(provider) else {
                    throw UserFacingError("Codex isn't ready to help yet. Nothing was changed.",
                                          recovery: "Check Codex in Settings › AI, or choose another provider.")
                }
                return BrainChoice(backend: backend, model: name, effort: requested)

            case .anthropic:
                guard let key = try keys.key(account: SecretKey.anthropicAPIKey, host: ProviderKeys.anthropicHost) else {
                    throw UserFacingError("I need your Anthropic API key for that.", recovery: "Add it in Settings › AI.")
                }
                let model = AnthropicModel(apiKey: key, transport: transport, retry: retry)
                return BrainChoice(backend: LoopBackend(model: model, checkModel: name, limits: loopLimits, clock: clock), model: name,
                                   effort: effort)

            case .openAICompatible:
                let preset = provider.preset
                let url = try OpenAICompatibleModel.validate(baseURL: provider.resolvedBaseURL)
                let key = try keys.key(for: preset, host: ProviderKeys.host(of: url))
                if preset.keyNeed == .required, key == nil {
                    throw UserFacingError("I need your \(preset.name) API key for that. Nothing was changed.",
                                          recovery: "Add it in Settings › AI.")
                }
                let model = try OpenAICompatibleModel(baseURL: provider.resolvedBaseURL, apiKey: key,
                                                      name: preset == .custom ? nil : preset.name,
                                                      effortStyle: preset == .openRouter ? .reasoningObject : .reasoningEffort,
                                                      transport: transport, retry: retry)
                // No model chosen yet: `modelName` took the preset's first suggestion, as Settings shows it.
                guard !name.isEmpty else {
                    throw UserFacingError("I need to know which \(model.providerName) model to use.", recovery: "Choose one in Settings › AI.")
                }
                return BrainChoice(backend: LoopBackend(model: model, checkModel: name, limits: loopLimits, clock: clock), model: name,
                                   effort: effort)
            }
        }
    }
}
