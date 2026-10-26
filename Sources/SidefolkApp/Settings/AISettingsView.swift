import SidefolkCore
import SwiftUI

/// Settings › AI: every way Sidefolk can think, grouped by how you pay for it, each with where it
/// stands and what to do next; the chosen one opens its setup in place. Then exactly what Sidefolk
/// last sent.
struct AISettingsView: View {
    var model: SettingsModel
    @State private var showPayload: Bool

    init(model: SettingsModel, showPayload: Bool = false) {
        self.model = model
        _showPayload = State(initialValue: showPayload)
    }

    private var ai: AISettingsModel { model.ai }

    var body: some View {
        SettingsPage {
            Label {
                Text("Notes, reminders and watches work without AI. AI is only used for questions and open-ended requests.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.folkColor("byte"))
            }
            .font(Theme.Font.body)
            .foregroundStyle(Theme.ink)
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            options("Use a plan you already pay for", [.claudeCode, .codex],
                    footer: "No API key needed. The command's own tools are switched off: it can only act through Sidefolk's.")
            options("Use an API key", [.anthropic] + ProviderPreset.apiKeyPresets.map(AIChoice.preset),
                    footer: "Pay as you go with the provider. Keys stay in your Keychain.")
            options("Run on this Mac", ProviderPreset.localPresets.map(AIChoice.preset),
                    footer: "Free, and your requests stay on this Mac (except with Ollama's Cloud models). Pick a model that can use tools.")
            options("Custom endpoint", [.preset(.custom)])
            options("Without AI", [.none])

            SettingsGroup(title: "What Sidefolk sends",
                          footer: "Your notes and messages go only to the AI you chose, and only what's needed for the request.") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    DisclosureGroup(isExpanded: $showPayload) {
                        payload.padding(.top, Theme.Space.s)
                    } label: {
                        Text("Last request").font(Theme.Font.body).foregroundStyle(Theme.ink)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.m)
            }
        }
    }

    private func options(_ title: LocalizedStringKey, _ list: [AIChoice], footer: LocalizedStringKey? = nil) -> some View {
        SettingsGroup(title: title, footer: footer) {
            ForEach(list, id: \.self) { option in
                ProviderOption(option: option, ai: ai)
            }
        }
    }

    @ViewBuilder private var payload: some View {
        if let preview = ai.contextPreview, !preview.isEmpty {
            ScrollView {
                Text(verbatim: preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.m)
            }
            .frame(height: 220)
            .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
            .accessibilityLabel("Last request sent to the AI")
        } else {
            Text("Nothing sent yet. After your first question, you'll see here exactly what went out.")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// One option: a radio row with its status chip; when chosen, its setup opens beneath it.
private struct ProviderOption: View {
    var option: AIChoice
    var ai: AISettingsModel

    private var selected: Bool { ai.choice == option }

    var body: some View {
        let status = ai.status(option)
        VStack(alignment: .leading, spacing: 0) {
            Button { ai.choose(option) } label: {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    Radio(selected: selected)
                    ProviderTile(option: option)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title).font(selected ? Theme.Font.bodyStrong : Theme.Font.body).foregroundStyle(Theme.ink)
                        Text(option.subtitle).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Theme.Space.s)
                    if let badge = status.badge {
                        Chip(verbatim: badge.text, tone: badge.tone, systemImage: badge.symbol)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.m - 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)

            if selected, option != .none {
                ProviderSetup(option: option, ai: ai, status: status)
                    .padding(.leading, Theme.Space.l + 16 + Theme.Space.m)
                    .padding(.trailing, Theme.Space.l)
                    .padding(.bottom, Theme.Space.m)
            }
        }
        .background(selected ? Theme.accentSoft.opacity(0.35) : .clear)
    }
}

private struct Radio: View {
    var selected: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(selected ? Theme.accent : Theme.inkFaint, lineWidth: 1.5)
            if selected {
                Circle().fill(Theme.accent)
                Circle().fill(Theme.surfaceRaised).frame(width: 6, height: 6)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

/// The service's logo in the ink colour (D36), or initials or a symbol where there is none, on a tile
/// in the group's folk color.
private struct ProviderTile: View {
    var option: AIChoice

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.folkColor(option.folk).opacity(0.24))
            .frame(width: 28, height: 28)
            .overlay {
                if let image = option.logo?.image {
                    // A little wider than tall, so wide marks (Claude Code's) aren't smaller than square ones.
                    Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: 17, height: 15)
                } else if let symbol = option.symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                } else {
                    Text(option.monogram).font(.system(size: 11.5, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(Theme.ink)
            .accessibilityHidden(true)
    }
}
