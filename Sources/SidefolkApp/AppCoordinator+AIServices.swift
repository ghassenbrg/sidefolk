import AppKit
import SidefolkCore

/// Settings › AI's side of `AppServices`: what's installed, keys, model lists and the one-click test.
extension AppCoordinator {
    func detectProviders(_ provider: ProviderSettings) async -> ProviderDetection {
        let workdir = runtime.paths.brainWorkdir.path
        async let claude = ClaudeBinary.status(configured: provider.claudePath, workdir: workdir)
        async let codex = CodexBinary.status(configured: provider.codexPath, workdir: workdir)
        async let ollama = LocalServers.probe(.ollama, installed: LocalServers.isInstalled(.ollama))
        async let lmStudio = LocalServers.probe(.lmStudio, installed: LocalServers.isInstalled(.lmStudio))
        let (codexStatus, codexModels) = await codex
        return ProviderDetection(claude: await claude, codex: codexStatus, codexModels: codexModels, ollama: await ollama,
                                 lmStudio: await lmStudio)
    }

    func testProvider(_ provider: ProviderSettings) async -> Result<String, UserFacingError> { await agent.testProvider(provider) }

    func listModels(_ provider: ProviderSettings) async -> Result<[ModelOption], UserFacingError> {
        var key: Secret?
        if let host = Self.keyHost(provider.preset, customAddress: provider.baseURL) {
            do { key = try ProviderKeys(store: secrets).key(for: provider.preset, host: host) } catch { return .failure(error) }
        }
        return await ModelCatalog.list(provider.preset, baseURL: provider.resolvedBaseURL, key: key)
    }

    func hasAPIKey(_ target: APIKeyTarget, customAddress: String) -> Bool {
        switch target {
        case .anthropic:
            return (try? secrets.get(SecretKey.anthropicAPIKey)) != nil
        case .preset(let preset):
            guard let host = Self.keyHost(preset, customAddress: customAddress) else { return false }
            return (try? ProviderKeys(store: secrets).key(for: preset, host: host)) != nil
        }
    }

    func setAPIKey(_ key: String?, for target: APIKeyTarget, customAddress: String) {
        let keys = ProviderKeys(store: secrets)
        let clean = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch target {
        case .anthropic:
            if clean.isEmpty {
                try? keys.remove(account: SecretKey.anthropicAPIKey)
            } else {
                try? keys.save(Secret(clean), account: SecretKey.anthropicAPIKey, host: ProviderKeys.anthropicHost)
            }
        case .preset(let preset):
            guard let host = Self.keyHost(preset, customAddress: customAddress) else { break }
            if clean.isEmpty {
                try? keys.remove(preset: preset, host: host)
            } else {
                try? keys.save(Secret(clean), account: preset.keyAccount, host: host)
            }
        }
        runtime.events.changed(.settings)
    }

    func moveCustomKey(from oldAddress: String, to newAddress: String) {
        let keys = ProviderKeys(store: secrets)
        guard let oldHost = Self.keyHost(.custom, customAddress: oldAddress), let newHost = Self.keyHost(.custom, customAddress: newAddress),
              let key = try? keys.key(for: .custom, host: oldHost) else { return }
        try? keys.save(key, account: ProviderPreset.custom.keyAccount, host: newHost)
        runtime.events.changed(.settings)
    }

    /// The host a preset's key is bound to: fixed for presets, the custom endpoint's own otherwise.
    private static func keyHost(_ preset: ProviderPreset, customAddress: String) -> String? {
        let address = preset == .custom ? customAddress : preset.baseURL
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), url.host != nil else { return nil }
        return ProviderKeys.host(of: url)
    }

    func lastContextPreview() async -> String? {
        guard let p = await agent.lastSent() else { return nil }
        var text = "Sent to \(p.provider) (\(p.model.isEmpty ? "default model" : p.model)) at "
            + p.at.formatted(date: .abbreviated, time: .standard) + (p.tainted ? " — included outside content" : "") + "\n\n"
        text += "SYSTEM\n" + p.system + "\n\n"
        for m in p.messages { text += m.role.rawValue.uppercased() + "\n" + m.text + "\n\n" }
        text += "TOOLS\n" + p.tools.joined(separator: ", ")
        return text
    }
}
