import SidefolkCore
import SwiftUI

/// The Say bar's panel in Home (D84): it hangs from the toolbar's field while it has words and says, before Return,
/// what will happen in plain words, whether AI is used, and what each key does; then what the words found. The
/// sentence and chips come from the same parse that runs the words (`IntentPlan`, `services.plan(for:)`), so what it
/// says is what Return does. Nothing happens until a key or a click.
struct SayPanel: View {
    var find: FindModel
    var services: AppServices
    var send: (AskHow) -> Void
    /// Opens something found, and closes the panel.
    var open: (Found) -> Void

    var body: some View {
        let words = SayWords(text: find.query, services: services)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if words.blocked {
                    NoAIHelp(services: services, send: send)
                } else {
                    UnderstandingRow(symbol: words.symbol, sentence: words.sentence, keys: []) {
                        ForEach(words.chips, id: \.self) { chip in Chip(verbatim: chip, tone: .neutral) }
                        if let kind = words.kindChip { Chip(verbatim: kind.0, tone: .accent, systemImage: kind.1) }
                        Chip(text: words.aiChip, tone: words.usesAI ? .warning : .success,
                             systemImage: words.usesAI ? "sparkles" : "checkmark.circle")
                    }
                    keys(words)
                }
            }
            .padding(Theme.Space.l)
            if !find.results.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                FoundList(results: find.results, each: 3, open: open)
                    .padding(Theme.Space.l)
            } else if find.searching, !words.understood {
                Rectangle().fill(Theme.line).frame(height: 1)
                Text("Nothing in your notes, conversations or watches matches “\(find.query)”.")
                    .font(Theme.Font.callout).foregroundStyle(Theme.inkFaint)
                    .padding(Theme.Space.l)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .elevation(.e3, radius: Theme.Radius.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What your words will do"))
    }

    /// The keys, each a button too: Return does it (without AI when understood), ⌘Return asks the AI, ⌥Return keeps the
    /// words as a note in the Inbox.
    private func keys(_ words: SayWords) -> some View {
        ButtonRow(spacing: Theme.Space.m) {
            keyButton("↩", words.doTitle, primary: true) { send(.auto) }
            if words.understood && words.hasAI {
                keyButton("⌘↩", Text("Ask \(words.companion)"), primary: false) { send(.ai) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            keyButton("⌥↩", Text("Save as note"), primary: false) { send(.note) }
                .keyboardShortcut(.return, modifiers: .option)
        }
    }

    private func keyButton(_ keys: String, _ title: Text, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(verbatim: "\u{2066}\(keys)\u{2069}")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(primary ? Theme.onAccent : Theme.inkMuted)
                    .padding(.horizontal, 5)
                    .frame(minHeight: 18)
                    .background(primary ? Theme.accent : Theme.well, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                title.font(Theme.Font.callout).fontWeight(primary ? .semibold : .regular)
                    .foregroundStyle(primary ? Theme.link : Theme.inkMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
    }
}

/// What typed words will do, in the person's words (principle 4): one sentence, its parts as chips, and whether AI is
/// used. Built from `IntentPlan`, the parse `LocalIntentRunner` runs.
struct SayWords {
    let text: String
    let plan: IntentPlan?
    let companion: String
    let provider: ProviderKind

    init(text: String, services: AppServices) {
        self.text = text
        plan = services.understands(text) ? services.plan(for: text) : nil
        companion = services.runtime.settings.current.companionName
        provider = services.runtime.settings.current.provider.kind
    }

    var understood: Bool { plan?.tool != nil }
    var hasAI: Bool { provider != .none }
    var usesAI: Bool { !understood }
    /// Words only the AI could do, with no AI set up: the panel says what still works instead.
    var blocked: Bool { !understood && !hasAI }

    var symbol: String {
        switch plan?.tool {
        case "reminders.create": "bell"
        case "notes.save": "note.text"
        case "profile.remember": "person"
        case "watch.create": "binoculars"
        case "watch.report", "watch.read": "gauge.with.dots.needle.33percent"
        case "companion.play": "gamecontroller"
        default: Theme.Symbol.say
        }
    }

    /// The sentence: what happens, in plain words, with the parts that matter in bold.
    var sentence: Text {
        guard let plan, let tool = plan.tool else {
            return Text("\(companion) will ask the AI and answer here.",
                        comment: "The Say bar: words not understood on the Mac go to the AI; a chip beside it says which AI")
        }
        let title = Text(verbatim: plan.title).bold()
        switch tool {
        case "reminders.create" where plan.chips.count >= 2:
            let when = Text(verbatim: "\(plan.chips[0]) \(plan.chips[1])").bold()
            return Text("I'll remind you \(when) to \(title).", comment: "The Say bar: “I'll remind you Tomorrow 09:00 to send the deck to Acme.”")
        case "notes.save" where plan.chips.count >= 3:
            let when = Text(verbatim: "\(plan.chips[1]) \(plan.chips[2])").bold()
            return Text("I'll save the task \(title) to \(Text(verbatim: plan.chips[0])) and remind you \(when).",
                        comment: "The Say bar: a task with a reminder, “I'll save the task Call Sam to Inbox and remind you Tomorrow 09:00.”")
        case "notes.save":
            return Text("I'll save \(title) to \(Text(verbatim: plan.chips.first ?? "")).", comment: "The Say bar: “I'll save Oat milk to Groceries.”")
        case "profile.remember":
            return Text("I'll keep in mind that \(title).", comment: "The Say bar: a fact about the person, “I'll keep in mind that I prefer short answers.”")
        case "watch.create":
            return Text("I'll tell you when \(title) changes.", comment: "The Say bar: a new watch, “I'll tell you when example.com/pricing changes.”")
        default:
            return Text(verbatim: plan.kind).bold() + Text(verbatim: plan.title.isEmpty ? "" : ": \(plan.title)")
        }
    }

    /// The parts as chips: when, where, how often.
    var chips: [String] {
        guard let plan, plan.tool != nil else { return [] }
        if plan.tool == "reminders.create", plan.chips.count >= 2 {
            return ["\(plan.chips[0]), \(plan.chips[1])"] + plan.chips.dropFirst(2)
        }
        return plan.chips
    }

    /// The kind, with its symbol.
    var kindChip: (String, String)? {
        guard let plan, plan.tool != nil else { return nil }
        return (plan.kind, symbol)
    }

    var aiChip: Text {
        usesAI ? Text("Uses \(AIName.long(provider))", comment: "The Say bar: these words go to the AI, “Uses Claude, through Claude Code”")
            : Text("On this Mac, no AI", comment: "The Say bar: these words are done on the Mac without AI")
    }

    /// What Return does, on its key.
    var doTitle: Text {
        guard let tool = plan?.tool else { return Text("Ask \(companion)") }
        return switch tool {
        case "reminders.create": Text("Set it", comment: "The Say bar's Return: set the reminder")
        case "notes.save", "profile.remember": Text("Save it", comment: "The Say bar's Return: save the note or fact")
        case "watch.create": Text("Start watching", comment: "The Say bar's Return: start the watch")
        default: Text("Do it", comment: "The Say bar's Return")
        }
    }
}

/// Words only the AI could do, and no AI set up (A3): what still works, each with its key, and one way to set AI up.
private struct NoAIHelp: View {
    var services: AppServices
    var send: (AskHow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Label { Text("That needs AI, which isn't set up yet. These still work on this Mac:") } icon: {
                Image(systemName: "sparkles").foregroundStyle(Theme.inkFaint)
            }
            .font(Theme.Font.body).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                example("remind me at 5 to stretch", "bell")
                example("add oat milk to groceries", "note.text")
                example("tell me when example.com changes", "binoculars")
            }
            HStack(spacing: Theme.Space.s) {
                Button { send(.note) } label: { Text("Save as note") }
                    .buttonStyle(.sf(.secondary))
                    .keyboardShortcut(.return, modifiers: .option)
                Spacer()
                Button("Set up AI…") { services.openSettings(tab: .ai) }.buttonStyle(.sf(.primary))
            }
        }
    }

    private func example(_ words: String, _ symbol: String) -> some View {
        Label { Text(verbatim: "“\(words)”").foregroundStyle(Theme.inkMuted) } icon: { Image(systemName: symbol).foregroundStyle(Theme.inkFaint) }
            .font(Theme.Font.callout)
    }
}

/// Which AI answers, in a few words.
enum AIName {
    static func short(_ kind: ProviderKind) -> String {
        switch kind {
        case .none: String(localized: "none", comment: "No AI is set up")
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .anthropic: "Anthropic API"
        case .openAICompatible: String(localized: "OpenAI-compatible")
        }
    }

    /// "Claude, through Claude Code", "Codex", "your API key".
    static func long(_ kind: ProviderKind) -> String {
        switch kind {
        case .claudeCode: String(localized: "Claude, through Claude Code", comment: "Which AI answers")
        case .codex: String(localized: "Codex", comment: "Which AI answers")
        case .anthropic: String(localized: "Claude, with your API key", comment: "Which AI answers")
        case .openAICompatible: String(localized: "your AI", comment: "Which AI answers: an OpenAI-compatible one")
        case .none: String(localized: "your AI", comment: "Which AI answers")
        }
    }
}
