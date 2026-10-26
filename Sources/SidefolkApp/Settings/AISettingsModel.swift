import Foundation
import Observation
import SidefolkCore

/// One option on Settings › AI.
enum AIChoice: Hashable {
    case none, claudeCode, codex, anthropic
    case preset(ProviderPreset)

    /// The option the saved settings select.
    init(_ provider: ProviderSettings) {
        switch provider.kind {
        case .none: self = .none
        case .claudeCode: self = .claudeCode
        case .codex: self = .codex
        case .anthropic: self = .anthropic
        case .openAICompatible: self = .preset(provider.preset)
        }
    }

    var keyTarget: APIKeyTarget? {
        switch self {
        case .anthropic: .anthropic
        case .preset(let preset) where preset.keyNeed != .none: .preset(preset)
        default: nil
        }
    }
}

/// Settings › AI: which brain answers, what's installed and signed in, keys, models, the one-click
/// test and what was last sent. Status comes from local reads (`detectProviders`, Keychain, model
/// lists); only "Test" sends a prompt.
@MainActor @Observable
final class AISettingsModel {
    private unowned let parent: SettingsModel
    private var services: AppServices { parent.services }

    private(set) var detection: ProviderDetection?
    private(set) var keySaved: [APIKeyTarget: Bool] = [:]
    /// The chosen OpenAI-compatible service's models; nil until listed (or when it needs a key first).
    private(set) var models: [ModelOption]?
    private(set) var modelsError: UserFacingError?
    private(set) var loadingModels = false
    private(set) var testing = false
    private(set) var testResult: Result<String, UserFacingError>?
    private(set) var contextPreview: String?
    private(set) var baseURLError: UserFacingError?

    init(parent: SettingsModel) { self.parent = parent }

    var provider: ProviderSettings { parent.settings.provider }
    var choice: AIChoice { AIChoice(provider) }

    func refresh() async {
        refreshKeys()
        contextPreview = await services.lastContextPreview()
        await redetect()
    }

    func redetect() async {
        detection = await services.detectProviders(provider)
        await loadModels()
    }

    // MARK: Choosing

    /// Each provider keeps its own models (`ProviderSettings.switchProvider`).
    func choose(_ next: AIChoice) {
        guard next != choice else { return }
        parent.update { s in
            switch next {
            case .none: s.provider.switchProvider(to: .none)
            case .claudeCode: s.provider.switchProvider(to: .claudeCode)
            case .codex: s.provider.switchProvider(to: .codex)
            case .anthropic: s.provider.switchProvider(to: .anthropic)
            case .preset(let preset): s.provider.switchProvider(to: .openAICompatible, preset: preset)
            }
        }
        testResult = nil
        models = nil
        modelsError = nil
        baseURLError = nil
        Task { await loadModels() }
    }

    func setModel(_ name: String) {
        parent.update { $0.provider.model = name }
        testResult = nil
    }

    func setSmartModel(_ name: String) {
        parent.update { $0.provider.smartModel = name }
    }

    func setCLIPath(_ path: String, codex: Bool) {
        parent.update { s in
            if codex { s.provider.codexPath = path } else { s.provider.claudePath = path }
        }
        Task { await redetect() }
    }

    // MARK: Models

    /// Lists the chosen service's models (free), and fills in a model when none is chosen yet: the
    /// first suggestion the service offers, or for a local server the first model that can use tools.
    func loadModels() async {
        guard case .preset(let preset) = choice else {
            models = nil
            return
        }
        if preset.keyNeed == .required, keySaved[.preset(preset)] != true {
            models = nil
            modelsError = nil
            return
        }
        if preset == .custom, provider.baseURL.isEmpty { return }
        loadingModels = true
        let listed = await services.listModels(provider)
        loadingModels = false
        guard choice == .preset(preset) else { return }
        switch listed {
        case .success(let list):
            models = list
            modelsError = nil
            let ids = list.map(\.id)
            let model = preset.group == .local ? ModelCatalog.defaultLocalModel(list) : preset.defaultModel(available: ids)
            if provider.model.isEmpty, let model { setModel(model) }
            if provider.smartModel.isEmpty, let smart = preset.defaultSmartModel(available: ids) { setSmartModel(smart) }
        case .failure(let error):
            models = nil
            modelsError = error
        }
    }

    // MARK: Keys

    func refreshKeys() {
        let address = provider.baseURL
        var saved: [APIKeyTarget: Bool] = [.anthropic: services.hasAPIKey(.anthropic, customAddress: address)]
        for preset in ProviderPreset.allCases where preset.keyNeed != .none {
            saved[.preset(preset)] = services.hasAPIKey(.preset(preset), customAddress: address)
        }
        keySaved = saved
    }

    func saveKey(_ key: String, for target: APIKeyTarget) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        services.setAPIKey(clean, for: target, customAddress: provider.baseURL)
        refreshKeys()
        testResult = nil
        Task { await loadModels() }
    }

    func removeKey(for target: APIKeyTarget) {
        services.setAPIKey(nil, for: target, customAddress: provider.baseURL)
        refreshKeys()
        testResult = nil
        models = nil
    }

    // MARK: Test

    /// One tiny request, only on the user's click.
    func test() async {
        testing = true
        testResult = nil
        testResult = await services.testProvider(provider)
        testing = false
    }

    // MARK: Custom endpoint

    enum BaseURLCheck: Equatable {
        case ok
        case invalid
        /// A key is saved for another host; sending it to this one needs the user's yes (SECURITY T18).
        case needsKeyConfirmation(oldHost: String, newHost: String)
    }

    /// Checks a new custom address: http(s) only, plain http only on this Mac.
    func checkBaseURL(_ text: String) -> BaseURLCheck {
        baseURLError = nil
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty
        else {
            baseURLError = UserFacingError("That isn't a web address. Nothing was saved.", recovery: "It should look like https://api.example.com/v1.")
            return .invalid
        }
        if scheme == "http", !["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) {
            baseURLError = UserFacingError("Plain http is only allowed for servers on this Mac. Nothing was saved.",
                                           recovery: "Use an https address.")
            return .invalid
        }
        let oldHost = URL(string: provider.baseURL)?.host?.lowercased() ?? ""
        if keySaved[.preset(.custom)] == true, !oldHost.isEmpty, oldHost != host {
            return .needsKeyConfirmation(oldHost: oldHost, newHost: host)
        }
        return .ok
    }

    enum SavedKey { case untouched, moved, removed }

    /// - Parameter key: what the user chose for a key saved for another address (moved: send it to
    ///   the new one from now on).
    func setBaseURL(_ text: String, key: SavedKey = .untouched) {
        switch key {
        case .untouched: break
        case .moved: services.moveCustomKey(from: provider.baseURL, to: text)
        case .removed: removeKey(for: .preset(.custom))
        }
        parent.update { $0.provider.baseURL = text }
        baseURLError = nil
        testResult = nil
        models = nil
        refreshKeys()
        Task { await loadModels() }
    }
}
