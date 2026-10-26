import AppKit

/// The services' own logos, from Simple Icons (CC0; sources and versions in
/// Resources/Brand/third-party/README.md), as vector PDFs loaded once and drawn as templates, so they
/// take the ink colour in light and dark (D36). The trademarks belong to their owners; a logo only
/// says which service an option uses. Services Simple Icons has no logo for keep a monogram or symbol.
enum ProviderLogo: String {
    case anthropic
    case claudeCode = "claudecode"
    case gemini = "googlegemini"
    case mistral = "mistralai"
    case deepSeek = "deepseek"
    case openRouter = "openrouter"
    case ollama
    case lmStudio = "lmstudio"

    @MainActor private static var loaded: [ProviderLogo: NSImage?] = [:]

    /// Nil when the resources aren't there (a dev build without `SIDEFOLK_RESOURCES`): callers fall back.
    @MainActor var image: NSImage? {
        if let image = Self.loaded[self] { return image }
        let image = load()
        Self.loaded[self] = .some(image)
        return image
    }

    private func load() -> NSImage? {
        guard let resources = ResourceLocator.resources else { return nil }
        // The app bundle keeps them in ProviderLogos/; the repository in Brand/third-party/logos/.
        let candidates = ["ProviderLogos/\(rawValue).pdf", "Brand/third-party/logos/\(rawValue).pdf"]
        guard let image = candidates.lazy.compactMap({ NSImage(contentsOf: resources.appendingPathComponent($0)) }).first else { return nil }
        image.isTemplate = true
        return image
    }
}
