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
    var title: String {
        switch self {
        case .none: "No AI"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .anthropic: "Anthropic"
        case .preset(.custom): "Your own server"
        case .preset(let preset): preset.name
        }
    }

    var subtitle: String {
        switch self {
        case .none: "Everything local keeps working. Questions wait until you pick an AI."
        case .claudeCode: "Your Claude subscription, through the claude command."
        case .codex: "Your ChatGPT plan, through the codex command."
        case .anthropic: "Claude models, pay as you go."
        case .preset(let preset):
            switch preset {
            case .openAI: "GPT models, pay as you go."
            case .gemini: "Google's Gemini models."
            case .mistral: "Mistral's models."
            case .groq: "Open models, served fast."
            case .xai: "Grok models."
            case .deepSeek: "DeepSeek's models."
            case .openRouter: "Many providers' models behind one key."
            case .ollama, .lmStudio: "Free models that run on this Mac."
            case .custom: "Any server that speaks OpenAI's chat API."
            }
        }
    }

    /// Initials for the option's tile: never a company's logo.
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

