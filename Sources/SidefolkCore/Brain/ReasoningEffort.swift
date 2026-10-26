import Foundation

/// How hard a model thinks before it answers (D36). The raw values are the words providers take on
/// the wire (`reasoning_effort`, `output_config.effort`, `--effort`, `model_reasoning_effort`); which
/// of them a provider and model accept is `EffortSupport`'s job. Codex's "ultra" is left out on
/// purpose: it delegates to sub-agents, which the isolated brain switches off (D26).
public enum ReasoningEffort: String, Codable, Sendable, CaseIterable, Comparable {
    /// "none" on the wire; named so it can't be mistaken for an optional's `.none`.
    case off = "none"
    case minimal, low, medium, high, xhigh, max

    /// For people, in the app's language.
    public var displayName: String {
        switch self {
        case .off: String(localized: "Off", comment: "Reasoning effort: the model doesn't reason before answering")
        case .minimal: String(localized: "Minimal", comment: "Reasoning effort")
        case .low: String(localized: "Low", comment: "Reasoning effort")
        case .medium: String(localized: "Medium", comment: "Reasoning effort")
        case .high: String(localized: "High", comment: "Reasoning effort")
        case .xhigh: String(localized: "Extra high", comment: "Reasoning effort, between High and Max")
        case .max: String(localized: "Max", comment: "Reasoning effort: the most a model can think")
        }
    }

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// The known words in a provider's list, weakest first; words Sidefolk doesn't know are dropped.
    static func known(_ words: [String]) -> [ReasoningEffort] {
        Set(words.compactMap { ReasoningEffort(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }).sorted()
    }
}

extension ProviderSettings {
    /// The model a request runs on, as `BrainFactory` picks it: the slot's own, the main one when
    /// "Think harder" has none, then the provider's default ("" lets a CLI choose its own).
    public func modelName(thinkHarder: Bool) -> String {
        let main = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let smart = smartModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = thinkHarder && !smart.isEmpty ? smart : main
        switch kind {
        case .anthropic:
            return chosen.isEmpty ? AnthropicModel.defaultModel : chosen
        case .openAICompatible:
            var name = OpenAICompatibleModel.wireName(chosen)
            if name.isEmpty, thinkHarder { name = preset.defaultSmartModel(available: nil) ?? "" }
            if name.isEmpty { name = preset.defaultModel(available: nil) ?? "" }
            return name
        case .none, .claudeCode, .codex:
            return chosen
        }
    }

    /// The effort the slot asks for, before checking what the model accepts; nil is "Default".
    public func requestedEffort(thinkHarder: Bool) -> ReasoningEffort? {
        ReasoningEffort(rawValue: thinkHarder ? smartEffort : effort)
    }
}

/// Which efforts a provider and model accept (D36): what Settings offers, and the only values ever
/// sent. An empty list hides the control and sends nothing. The CLIs say what they take (`claude
/// --help`, Codex's model catalog); for the APIs these are the providers' documented values by model
/// family, and a model Sidefolk can't place gets no control rather than a guess.
public enum EffortSupport {
    /// - Parameters:
    ///   - claudeCLI: the levels `claude --help` lists for `--effort`.
    ///   - codexModels: Codex's own model catalog, with each model's levels.
    public static func levels(_ provider: ProviderSettings, thinkHarder: Bool, claudeCLI: [ReasoningEffort] = [],
                              codexModels: [ModelOption] = []) -> [ReasoningEffort] {
        let model = provider.modelName(thinkHarder: thinkHarder)
        switch provider.kind {
        case .none: return []
        case .claudeCode: return claudeCode(model: model, cli: claudeCLI)
        case .codex: return codex(model: model, catalog: codexModels)
        case .anthropic: return anthropic(model: model)
        case .openAICompatible: return openAICompatible(provider.preset, model: model)
        }
    }

    /// `effort` when it's on the list, else nil (send nothing).
    public static func accepted(_ effort: ReasoningEffort?, in levels: [ReasoningEffort]) -> ReasoningEffort? {
        effort.flatMap { levels.contains($0) ? $0 : nil }
    }

    // MARK: Subscription CLIs

    /// Aliases ("sonnet", "opus") get what the CLI lists; a full model id also only what that model takes.
    static func claudeCode(model: String, cli: [ReasoningEffort]) -> [ReasoningEffort] {
        let id = model.lowercased()
        guard id.hasPrefix("claude-") else { return cli }
        let api = anthropic(model: id)
        return cli.filter(api.contains)
    }

    /// The model's own levels from the catalog. Codex's default model, or one the catalog doesn't
    /// list, gets the levels every listed model shares; without a catalog, the three every Codex
    /// reasoning model has taken.
    static func codex(model: String, catalog: [ModelOption]) -> [ReasoningEffort] {
        if let known = catalog.first(where: { $0.id == model }), !known.efforts.isEmpty { return known.efforts }
        let lists = catalog.map(\.efforts).filter { !$0.isEmpty }
        guard var shared = lists.first else { return [.low, .medium, .high] }
        for list in lists.dropFirst() { shared = shared.filter(list.contains) }
        return shared
    }

    // MARK: APIs

    /// `output_config.effort`: from Opus 4.5 (low to high); 4.6 adds max, 4.7 and later xhigh.
    /// Sonnet and Haiku 4.5 and everything older reject it.
    static func anthropic(model: String) -> [ReasoningEffort] {
        guard let (family, version) = version(of: model.lowercased(), after: #"claude-(opus|sonnet|haiku|fable|mythos)-"#)
        else { return [] }
        switch version {
        case ..<405: return []
        case 405: return family == "opus" ? [.low, .medium, .high] : []
        case 406: return [.low, .medium, .high, .max]
        default: return [.low, .medium, .high, .xhigh, .max]
        }
    }

    /// `reasoning_effort` (OpenRouter: `reasoning.effort`), per service and model family.
    static func openAICompatible(_ preset: ProviderPreset, model: String) -> [ReasoningEffort] {
        let id = model.lowercased()
        switch preset {
        case .openAI: return openAI(id)
        case .gemini: return gemini(id)
        case .mistral: return mistral(id)
        case .groq:
            if id.contains("gpt-oss") { return [.low, .medium, .high] }
            return id.contains("qwen3") ? [.off, .low, .medium, .high] : []
        case .xai: return xai(id)
        // OpenRouter maps one effort scale onto each model; its routers pick the model themselves.
        case .openRouter: return id.hasPrefix("openrouter/") ? [] : ReasoningEffort.allCases
        // DeepSeek's reasoner thinks by model choice, not by a setting; local and custom servers vary.
        case .deepSeek, .ollama, .lmStudio, .custom: return []
        }
    }

    /// o-series: low to high. GPT-5: minimal to high; 5.1 adds none; 5.2 to 5.5 add xhigh; 5.6 and
    /// later go from low to max. GPT-4 and the chat-tuned GPT-5s don't reason.
    static func openAI(_ id: String) -> [ReasoningEffort] {
        if id.range(of: #"^o\d"#, options: .regularExpression) != nil {
            return id.hasPrefix("o1-mini") || id.hasPrefix("o1-preview") ? [] : [.low, .medium, .high]
        }
        guard !id.contains("-chat"), let (_, version) = version(of: id, after: #"(gpt)-"#) else { return [] }
        switch version {
        case ..<500: return []
        case 500: return [.minimal, .low, .medium, .high]
        case 501: return [.off, .low, .medium, .high]
        case ..<506: return [.off, .low, .medium, .high, .xhigh]
        default: return [.low, .medium, .high, .xhigh, .max]
        }
    }

    /// Gemini's OpenAI endpoint maps the efforts onto thinking levels and budgets; only 2.5 Flash
    /// can stop thinking. Gemma and Gemini before 2.5 don't think.
    static func gemini(_ id: String) -> [ReasoningEffort] {
        if id.hasPrefix("gemini-"), id.hasSuffix("-latest") { return [.minimal, .low, .medium, .high] }
        guard let (_, version) = version(of: id, after: #"(gemini)-"#), version >= 205 else { return [] }
        return version == 205 && id.contains("flash") ? [.off, .minimal, .low, .medium, .high] : [.minimal, .low, .medium, .high]
    }

    /// Small 4, Medium 3.5 and Large 4 on: think fully or barely. GLM through Mistral: low, high, max.
    static func mistral(_ id: String) -> [ReasoningEffort] {
        if id.hasPrefix("zai-glm") { return [.low, .high, .max] }
        if id.range(of: #"^mistral-(small|medium|large)-latest$"#, options: .regularExpression) != nil { return [.off, .high] }
        guard let (size, version) = version(of: id, after: #"mistral-(small|medium|large)-"#) else { return [] }
        return version >= (size == "medium" ? 305 : 400) ? [.off, .high] : []
    }

    /// Grok 3 Mini: low or high; Grok 4.5: up to high; 4.6 on: up to xhigh. Other Groks reason as they
    /// are (in the multi-agent model the setting means something else).
    static func xai(_ id: String) -> [ReasoningEffort] {
        if id.hasPrefix("grok-3-mini") { return [.low, .high] }
        guard !id.contains("multi-agent"), !id.contains("non-reasoning"), let (_, version) = version(of: id, after: #"(grok)-"#)
        else { return [] }
        switch version {
        case ..<405: return []
        case 405: return [.low, .medium, .high]
        default: return [.low, .medium, .high, .xhigh]
        }
    }

    /// The family and version as major × 100 + minor, so 4.20 sorts after 4.6: "claude-opus-4-8" →
    /// ("opus", 408), "gpt-5.2-mini" → ("gpt", 502), "claude-sonnet-4-20250514" → ("sonnet", 400) (a
    /// date is not a minor version).
    static func version(of id: String, after prefix: String) -> (String, Int)? {
        let pattern = "^" + prefix + #"(\d+)(?:[.-](\d{1,2}))?(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) else { return nil }
        func group(_ i: Int) -> String? { Range(match.range(at: i), in: id).map { String(id[$0]) } }
        guard let family = group(1), let major = group(2).flatMap({ Int($0) }) else { return nil }
        return (family, major * 100 + (group(3).flatMap { Int($0) } ?? 0))
    }
}
