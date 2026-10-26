import AppKit

/// The services' own logos, from LobeHub Icons (MIT; sources, versions and the trademark note in
/// Resources/Brand/third-party/README.md), as vector PDFs loaded once (D36). The trademarks belong to
/// their owners; a logo only says which service an option uses.
///
/// Marks the owner draws in colour (Claude, Gemini, Mistral, DeepSeek) keep every colour, untinted.
/// Marks that are black or white by design (OpenAI, Ollama, xAI, ...) are templates: the app tints them
/// black on light and white on dark, never a colour of its own.
enum ProviderLogo: String {
    case claude = "claude-color"
    case openAI = "openai"
    case codex
    case gemini = "gemini-color"
    case mistral = "mistral-color"
    case groq
    case xai
    case deepSeek = "deepseek-color"
    case openRouter = "openrouter"
    case ollama
    case lmStudio = "lmstudio"

    @MainActor private static var loaded: [ProviderLogo: NSImage?] = [:]

    /// Drawn in one colour, which the app picks for the appearance, rather than in the brand's own colours.
    var isMonochrome: Bool { !rawValue.hasSuffix("-color") }

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
        image.isTemplate = isMonochrome
        return image
    }
}
