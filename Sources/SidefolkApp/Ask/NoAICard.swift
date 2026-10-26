import SidefolkCore
import SwiftUI

/// A request that needs AI while none is chosen. AI setup is offered when it is first needed
/// (PRODUCT §5): a plan this Mac is already signed in to comes first, one click away, then what works
/// without AI (a reminder it understood, a task, a note), then Settings.
struct NoAICard: View {
    var request: NoAIRequest
    /// The card's own entry, which becomes a line saying which AI answers from now on.
    var entry: AskEntry.ID
    var model: AskModel

    var body: some View {
        SFCard(accent: Theme.folkColor("byte")) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(request.guess == nil ? "That needs AI, which isn't set up." : "That needs AI — or I can do this:")
                    .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                if let first = request.ready.first {
                    found(first).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    ButtonRow {
                        ForEach(request.ready, id: \.self) { kind in
                            Button { model.actions?.answer(request, with: kind, replacing: entry, in: model) } label: { answer(with: kind) }
                                .buttonStyle(.sf(kind == first ? .primary : .secondary))
                                .disabled(model.busy)
                        }
                    }
                }
                if let guess = request.guess {
                    Button {
                        model.actions?.remind(guess, in: model)
                    } label: {
                        Label {
                            Text("\(guess.label): \(guess.title)",
                                 comment: "A label, then what it is about: “Remind me Tomorrow 09:00: Call the bank”, “Claude Code: Saved “Tea ideas””")
                        } icon: {
                            Image(systemName: "alarm")
                        }
                        .lineLimit(1)
                    }
                    .buttonStyle(.sf(request.ready.isEmpty ? .primary : .secondary))
                }
                // Nothing on this Mac can answer yet, so the way to an answer leads; otherwise it closes the card.
                if setUpLeads { setUp }
                ButtonRow { localActions }
                if !setUpLeads { setUp }
            }
        }
    }

    private var setUpLeads: Bool { request.ready.isEmpty && request.guess == nil }

    private var setUp: some View {
        Button("Set up AI…") { model.actions?.openSettings(tab: .ai) }.buttonStyle(.sf(setUpLeads ? .primary : .plain))
    }

    /// What works without AI: keep the words as a task or a note, or set a reminder for them.
    @ViewBuilder private var localActions: some View {
        Button("Save as task") { model.actions?.saveAsTask(request.text, in: model) }.buttonStyle(.sf(.secondary)).fixedSize()
        if request.guess == nil {
            Button("Remind me…") { model.actions?.askWhen(toRemind: request.text, in: model) }.buttonStyle(.sf(.secondary)).fixedSize()
        }
        Button("Save as note") { model.actions?.saveAnswer(request.text, tainted: false, in: model) }.buttonStyle(.sf(.secondary)).fixedSize()
    }

    /// One sentence per plan, so no language has to build it from pieces.
    private func found(_ kind: ProviderKind) -> Text {
        kind == .codex ? Text("Codex is on this Mac: I can answer with your ChatGPT plan.")
            : Text("Claude Code is on this Mac: I can answer with your Claude plan.")
    }

    private func answer(with kind: ProviderKind) -> Text {
        kind == .codex ? Text("Answer with Codex") : Text("Answer with Claude Code")
    }
}
