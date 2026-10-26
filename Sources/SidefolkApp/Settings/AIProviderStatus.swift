import Foundation
import SidefolkCore

/// What Settings › AI says about one option: a short chip in the list, and for the chosen option
/// a line saying where it stands and exactly what to do next.
struct AIProviderStatus {
    struct Badge {
        var text: String
        var tone: ChipTone
        var symbol: String?
    }

    enum Tone { case ready, attention, problem, info }

    var badge: Badge?
    var line: String
    var tone: Tone
    /// A page to open for the next step (get a key, download an app).
    var link: (title: String, url: URL)?
    /// A Terminal command for the next step, shown so it can be copied.
    var command: String?
}

extension AIChoice {
    /// The option's name: a product's own name, or what it is.
    var title: String {
        switch self {
        case .none: String(localized: "No AI")
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .anthropic: "Anthropic"
        case .preset(.custom): String(localized: "Your own server")
        case .preset(let preset): preset.name
        }
    }

    var subtitle: String {
        switch self {
        case .none: String(localized: "Everything local keeps working. Questions wait until you pick an AI.")
        case .claudeCode: String(localized: "Your Claude subscription, through the claude command.")
        case .codex: String(localized: "Your ChatGPT plan, through the codex command.")
        case .anthropic: String(localized: "Claude models, pay as you go.")
        case .preset(let preset):
            switch preset {
            case .openAI: String(localized: "GPT models, pay as you go.")
            case .gemini: String(localized: "Google's Gemini models.")
            case .mistral: String(localized: "Mistral's models.")
            case .groq: String(localized: "Open models, served fast.")
            case .xai: String(localized: "Grok models.")
            case .deepSeek: String(localized: "DeepSeek's models.")
            case .openRouter: String(localized: "Many providers' models behind one key.")
            case .ollama, .lmStudio: String(localized: "Free models that run on this Mac.")
            case .custom: String(localized: "Any server that speaks OpenAI's chat API.")
            }
        }
    }

    /// The service's own logo (D36). Claude Code and the Anthropic API both show Claude's mark: the API
    /// row's own subtitle says "Claude models", and Claude is the name people look for, where Anthropic's
    /// letter A would read as a different service. Codex has its own mark, apart from OpenAI's.
    var logo: ProviderLogo? {
        switch self {
        case .claudeCode, .anthropic: .claude
        case .codex: .codex
        case .preset(.openAI): .openAI
        case .preset(.gemini): .gemini
        case .preset(.mistral): .mistral
        case .preset(.groq): .groq
        case .preset(.xai): .xai
        case .preset(.deepSeek): .deepSeek
        case .preset(.openRouter): .openRouter
        case .preset(.ollama): .ollama
        case .preset(.lmStudio): .lmStudio
        case .preset(.custom), .none: nil
        }
    }

    /// Initials for the option's tile while the logos can't be loaded (a dev build without `SIDEFOLK_RESOURCES`).
    var monogram: String {
        switch self {
        case .none: ""
        case .claudeCode: "CC"
        case .codex: "Cx"
        case .anthropic: "A"
        case .preset(let preset):
            switch preset {
            case .openAI: "O"
            case .gemini: "G"
            case .mistral: "M"
            case .groq: "Gq"
            case .xai: "x"
            case .deepSeek: "DS"
            case .openRouter: "OR"
            case .ollama: "Ol"
            case .lmStudio: "LM"
            case .custom: ""
            }
        }
    }

    /// Shown instead of initials.
    var symbol: String? {
        switch self {
        case .none: "moon.zzz"
        case .preset(.custom): "link"
        default: nil
        }
    }

    /// The tile's folk color, by group: plans are Byte's, keys Pip's, this Mac Scout's.
    var folk: String {
        switch self {
        case .claudeCode, .codex: "byte"
        case .anthropic: "pip"
        case .preset(let preset): preset.group == .local ? "scout" : preset.group == .custom ? "guard" : "pip"
        case .none: "seed"
        }
    }
}

