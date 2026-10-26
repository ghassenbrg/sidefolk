import Foundation

/// A model a provider offers, as Settings lists it.
public struct ModelOption: Sendable, Hashable, Identifiable {
    public var id: String
    /// Whether it can call tools, when the server says (Ollama does); nil when unknown.
    public var usesTools: Bool?
    /// Runs on the provider's servers, not this Mac (Ollama's cloud models): the request leaves the Mac.
    public var cloud: Bool

    public init(id: String, usesTools: Bool? = nil, cloud: Bool = false) {
        self.id = id
        self.usesTools = usesTools
        self.cloud = cloud
    }
}

/// Reads the models a provider offers. Listing costs nothing (no tokens), so Settings can do it
/// whenever a key is saved or a local server is found.
public enum ModelCatalog {
    public static func list(_ preset: ProviderPreset, baseURL: String, key: Secret?,
                            transport: any HTTPTransport = URLSessionTransport(), timeout: TimeInterval = 10)
        async -> Result<[ModelOption], UserFacingError> {
        let base: URL
        do { base = try OpenAICompatibleModel.validate(baseURL: baseURL) } catch { return .failure(error) }
        let url = preset.listing == .ollama ? ollamaTags(base) : base.appendingPathComponent("models")
        var headers = ["accept": "application/json"]
        if let key, !key.isEmpty { headers["authorization"] = "Bearer \(key.reveal())" }
        let name = preset == .custom ? OpenAICompatibleModel.displayName(for: base) : preset.name
        do {
            let response = try await transport.send(HTTPRequest(method: "GET", url: url, headers: headers, timeout: timeout))
            switch response.status {
            case 200:
                let models = preset.listing == .ollama ? parseOllama(response.body) : parseOpenAI(response.body)
                return .success(ordered(models, preset: preset))
            case 401, 403:
                return .failure(UserFacingError(key == nil ? "\(name) needs an API key." : "\(name) didn't accept the key.",
                                                recovery: "Paste a new key below.", detail: ProviderHTTP.detail(response)))
            default:
                return .failure(UserFacingError("\(name) didn't list its models.", recovery: "You can still type a model name.",
                                                detail: ProviderHTTP.detail(response)))
            }
        } catch {
            return .failure(ProviderHTTP.networkError(error, provider: name, local: OpenAICompatibleModel.isLoopback(base.host)))
        }
    }

    /// `http://localhost:11434/v1` → `http://localhost:11434/api/tags`.
    static func ollamaTags(_ base: URL) -> URL {
        var parts = URLComponents()
        parts.scheme = base.scheme
        parts.host = base.host
        parts.port = base.port
        parts.path = "/api/tags"
        return parts.url ?? base
    }

    /// `{"data": [{"id": …}]}`. Gemini prefixes ids with "models/", which its chat endpoint doesn't need.
    /// Embedding, speech, image and moderation models can't answer, so they're left out of the picker.
    static func parseOpenAI(_ data: Data) -> [ModelOption] {
        let json = try? JSONValue.parse(data)
        let ids = (json?["data"]?.arrayValue ?? json?["models"]?.arrayValue ?? []).compactMap { $0.string("id") ?? $0.string("name") }
        let unusable = ["embed", "tts", "whisper", "dall-e", "moderation", "transcribe", "audio", "realtime", "image", "guard",
                        "ocr", "sora", "rerank"]
        return ids.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
            .filter { id in !unusable.contains { id.lowercased().contains($0) } }
            .map { ModelOption(id: $0) }
    }

    /// `{"models": [{"name", "capabilities": ["completion", "tools"], "remote_host"}]}`. Older Ollama
    /// versions don't send capabilities, so tool use is then unknown.
    static func parseOllama(_ data: Data) -> [ModelOption] {
        let models = (try? JSONValue.parse(data))?["models"]?.arrayValue ?? []
        return models.compactMap { m in
            guard let name = m.string("name") else { return nil }
            let capabilities = m["capabilities"]?.arrayValue?.compactMap(\.stringValue)
            let cloud = m.string("remote_host") != nil || name.hasSuffix(":cloud") || name.hasSuffix("-cloud")
            return ModelOption(id: name, usesTools: capabilities.map { $0.contains("tools") }, cloud: cloud)
        }
    }

    /// Suggested models first (in their order), then the rest alphabetically, without duplicates.
    static func ordered(_ models: [ModelOption], preset: ProviderPreset) -> [ModelOption] {
        var seen = Set<String>()
        let unique = models.filter { seen.insert($0.id).inserted }
        let wanted = preset.suggestedModels + preset.suggestedSmartModels
        let first = wanted.compactMap { id in unique.first { $0.id == id } }
        let rest = unique.filter { !wanted.contains($0.id) }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        var picked = Set<String>()
        return (first + rest).filter { picked.insert($0.id).inserted }
    }

    /// The model a fresh local setup should use: the first that can call tools, then any that might.
    public static func defaultLocalModel(_ models: [ModelOption]) -> String? {
        (models.first { $0.usesTools == true && !$0.cloud } ?? models.first { $0.usesTools == true }
            ?? models.first { $0.usesTools == nil })?.id
    }
}

/// Whether Ollama or LM Studio is installed and running on this Mac.
public enum LocalServerState: Sendable, Hashable {
    case running(models: [ModelOption])
    case installedNotRunning
    case notInstalled
}

public enum LocalServers {
    /// Lists the models (a short timeout keeps Settings snappy when nothing answers).
    public static func probe(_ preset: ProviderPreset, transport: any HTTPTransport = URLSessionTransport(),
                             installed: Bool) async -> LocalServerState {
        switch await ModelCatalog.list(preset, baseURL: preset.baseURL, key: nil, transport: transport, timeout: 1.5) {
        case .success(let models): return .running(models: models)
        case .failure: return installed ? .installedNotRunning : .notInstalled
        }
    }

    /// The app or its command line tool in the usual places.
    public static func isInstalled(_ preset: ProviderPreset, home: String = NSHomeDirectory(),
                                   exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        let paths: [String] = switch preset {
        case .ollama: ["/Applications/Ollama.app", home + "/Applications/Ollama.app", "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
        case .lmStudio: ["/Applications/LM Studio.app", home + "/Applications/LM Studio.app", home + "/.lmstudio/bin/lms"]
        default: []
        }
        return paths.contains(where: exists)
    }
}
