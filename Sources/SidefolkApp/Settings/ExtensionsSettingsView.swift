import AppKit
import SidefolkCore
import SwiftUI

/// Settings › Extensions: the extensions that come with Sidefolk, the ones the person added (folders and
/// MCP servers), drafts Sidefolk's AI wrote for them, and skills.
struct ExtensionsSettingsView: View {
    var model: SettingsModel
    @State private var addingServer = false
    @State private var uninstalling: ExtensionInfo?
    @State private var deletingSkill: SkillInfo?
    @State private var deletingDraft: ExtensionDraftInfo?

    var body: some View {
        SettingsPage {
            if !builtIns.isEmpty || !model.unavailable.isEmpty { builtIn }
            installed
            if !model.drafts.isEmpty { drafts }
            skills
        }
        .sheet(item: Binding(get: { model.installPreview }, set: { model.installPreview = $0 })) { p in
            InstallPreviewSheet(preview: p, model: model)
        }
        .sheet(isPresented: $addingServer) { AddServerSheet(model: model) }
        .alert("Uninstall “\(uninstalling?.name ?? "")”?", isPresented: Binding(
            get: { uninstalling != nil }, set: { if !$0 { uninstalling = nil } }
        ), presenting: uninstalling) { ext in
            Button("Uninstall", role: .destructive) { Task { await model.uninstall(ext) } }
            Button("Cancel", role: .cancel) {}
        } message: { ext in
            Text(ext.kind == .mcpServer ? "Its tools stop working right away." : "Its tools and watches stop, and its files are removed.")
        }
        .alert("Delete the skill “\(deletingSkill?.name ?? "")”?", isPresented: Binding(
            get: { deletingSkill != nil }, set: { if !$0 { deletingSkill = nil } }
        ), presenting: deletingSkill) { skill in
            Button("Delete skill", role: .destructive) { Task { await model.deleteSkill(skill) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its instructions are removed. This can't be undone.")
        }
        .alert("Move the draft “\(deletingDraft?.title ?? "")” to the Trash?", isPresented: Binding(
            get: { deletingDraft != nil }, set: { if !$0 { deletingDraft = nil } }
        ), presenting: deletingDraft) { draft in
            Button("Move to Trash", role: .destructive) { Task { await model.deleteDraft(draft) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("An extension already installed from it stays installed.")
        }
    }

    private var builtIns: [ExtensionInfo] { model.extensions.filter(\.bundled) }

    // MARK: Built in

    private var builtIn: some View {
        SettingsGroup(title: "Built in",
                      footer: "These come with Sidefolk and are updated with it. Each runs in its own sandbox; switch off any you don't want.") {
            ForEach(builtIns) { ext in
                ExtensionRow(ext: ext, model: model, uninstall: nil)
            }
            ForEach(model.unavailable) { item in
                UnavailableExtensionRow(item: item) { Task { await model.retryBuiltIns() } }
            }
        }
    }

    // MARK: Added by you

    private var installed: some View {
        SettingsGroup(title: "Added by you",
                      footer: "Extensions run in a sandbox limited to what they asked for at install. MCP servers run with your full permissions.") {
            let added = model.extensions.filter { !$0.bundled }
            if added.isEmpty {
                InlineEmpty(text: "Nothing added yet. Install an extension from a folder, add an MCP server, or ask Sidefolk to build one.",
                            systemImage: "puzzlepiece.extension")
            }
            ForEach(added) { ext in
                ExtensionRow(ext: ext, model: model) { uninstalling = ext }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    Button("Install from Folder…", action: chooseFolder).buttonStyle(.sf(.secondary))
                    Button("Add MCP Server…") { addingServer = true }.buttonStyle(.sf(.secondary))
                }
                if !model.samples.isEmpty {
                    HStack(spacing: Theme.Space.s) {
                        Text("Try a sample:").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        ForEach(model.samples, id: \.folder) { sample in
                            Button {
                                model.clearExtensionError()
                                Task { model.installPreview = await model.preview(folder: sample.folder) }
                            } label: {
                                Text(verbatim: "\(sample.name)…")
                            }
                            .buttonStyle(.sf(.plain))
                        }
                    }
                }
                if let error = model.extensionError { InlineError(error: error) }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
        }
    }

    private func chooseFolder() {
        model.clearExtensionError()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Review Extension")
        panel.message = String(localized: "Choose an extension folder. You'll see what it can do before anything is installed.")
        Task {
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
            guard response == .OK, let url = panel.url else { return }
            model.installPreview = await model.preview(folder: url)
        }
    }

    // MARK: Drafts

    private var drafts: some View {
        SettingsGroup(title: "Drafts",
                      footer: "Extensions Sidefolk wrote at your request. Nothing in a draft runs until you review it and install it.") {
            ForEach(model.drafts) { draft in
                DraftRow(draft: draft, review: {
                    model.clearExtensionError()
                    Task { await model.review(folder: draft.folder) }
                }, reveal: { model.revealDraft(draft) }, delete: { deletingDraft = draft })
            }
        }
    }

    // MARK: Skills

    private var skills: some View {
        SettingsGroup(title: "Skills", footer: "Skills are written instructions Sidefolk reads when a request needs them.") {
            if model.skills.isEmpty {
                InlineEmpty(text: "No skills yet. Ask “write a skill for my weekly review” and approve it.", systemImage: "text.book.closed")
            }
            ForEach(model.skills) { skill in
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    IconTile(symbol: "text.book.closed", folk: "seed", size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Space.s) {
                            Text(skill.name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                            Chip(skill.bundled ? "Built in" : "Yours", tone: skill.bundled ? .neutral : .accent)
                        }
                        Text(skill.description).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Theme.Space.s)
                    if !skill.bundled {
                        Button("Delete") { deletingSkill = skill }.buttonStyle(.sf(.secondary))
                            .accessibilityLabel("Delete \(skill.name)")
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.m)
            }
        }
    }
}

// MARK: - Add MCP server

struct AddServerSheet: View {
    var model: SettingsModel
    @State private var name = ""
    @State private var command = ""
    @State private var arguments = ""
    @State private var adding = false
    @State private var error: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Add an MCP server").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            Label {
                Text("MCP servers run outside Sidefolk's sandbox, with your full permissions and the folders you shared with Sidefolk. Only add servers you trust. Their tools ask before changing anything, and what they return is treated as untrusted.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
            }
            .font(Theme.Font.body)
            .foregroundStyle(Theme.ink)
            .padding(Theme.Space.m)
            .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            field("Name", text: $name, prompt: "GitHub", monospaced: false)
            field("Command", text: $command, prompt: "npx", monospaced: true)
            field("Arguments", text: $arguments, prompt: "-y @modelcontextprotocol/server-github@2025.4.8", monospaced: true)

            if !command.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Sidefolk will run")
                    Text(verbatim: ([command] + parsedArguments).joined(separator: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .padding(Theme.Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            if let unpinned = unpinnedWarning {
                Label(unpinned, systemImage: "exclamationmark.circle")
                    .font(Theme.Font.caption).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
            }
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button(adding ? "Adding…" : "Add Server") {
                    adding = true
                    Task {
                        error = await model.addMCPServer(name: name.trimmingCharacters(in: .whitespaces),
                                                         command: command.trimmingCharacters(in: .whitespaces),
                                                         arguments: parsedArguments)
                        adding = false
                        if error == nil { dismiss() }
                    }
                }
                .buttonStyle(.sfPrimary)
                .disabled(adding || name.trimmingCharacters(in: .whitespaces).isEmpty || command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 500)
        .background(Theme.surface)
    }

    /// `prompt` is an example, shown as it is.
    private func field(_ label: LocalizedStringKey, text: Binding<String>, prompt: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
            TextField(label, text: text, prompt: Text(verbatim: prompt))
                .textFieldStyle(.roundedBorder)
                .font(monospaced ? .system(size: 12, design: .monospaced) : Theme.Font.body)
                .accessibilityLabel(label)
        }
    }

    private var parsedArguments: [String] { ShellWords.split(arguments) }

    /// `npx -y pkg` and `uvx pkg` fetch new code on every launch unless a version is pinned (SECURITY T16).
    private var unpinnedWarning: String? {
        let cmd = URL(fileURLWithPath: command.trimmingCharacters(in: .whitespaces)).lastPathComponent
        guard cmd == "npx" || cmd == "uvx" || cmd == "bunx" else { return nil }
        let packages = parsedArguments.filter { !$0.hasPrefix("-") }
        guard let package = packages.first else { return nil }
        let versioned = package.dropFirst().contains("@") || package.contains("==")
        return versioned ? nil : String(localized: "\(cmd) downloads the newest \(package) every time it starts. Pin a version, like \(package)@1.2.3.")
    }
}

/// Splits an argument line the way a shell would for plain words and quotes; nothing is expanded.
enum ShellWords {
    static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var inWord = false
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                inWord = true
            } else if ch.isWhitespace {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(ch)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}

// MARK: - Connect your agents

/// Settings › Agents: Claude Code, Codex, the `sidefolk` command, and setup for any other MCP app.
struct AgentsGroup: View {
    var model: SettingsModel
    @State private var hooks = true
    @State private var codexHooks = true

    var body: some View {
        SettingsGroup(title: "Connect your agents",
                      footer: "Sidefolk saves a backup next to each file before changing it. Disconnect removes only what it added.") {
            if let status = model.integration {
                claude(status)
                codex(status)
                commandLine(status)
                OtherAgentsRow(copy: model.copySetupInstructions)
            } else {
                InlineEmpty(text: "Checking your agents…")
            }
            if let error = model.integrationError {
                InlineError(error: error).padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
            }
        }
        .onAppear(perform: syncHooks)
        .onChange(of: model.integration) { syncHooks() }
    }

    /// Once connected, the checkbox shows what is installed; before that it's the user's choice.
    private func syncHooks() {
        guard let s = model.integration else { return }
        if s.claudeMCPInstalled { hooks = s.claudeHooksInstalled }
        if s.codexMCPInstalled { codexHooks = s.codexHooksInstalled }
    }

    private func claude(_ s: IntegrationStatus) -> some View {
        AgentCard(
            name: "Claude Code",
            symbol: "sparkle",
            logo: .claude,
            status: !s.claudeCodeFound ? String(localized: "Not installed")
                : s.claudeMCPInstalled ? (s.claudeHooksInstalled ? String(localized: "Connected, with session taps") : String(localized: "Connected"))
                : String(localized: "Not connected"),
            connected: s.claudeMCPInstalled,
            found: s.claudeCodeFound,
            changes: [String(localized: "Adds a “sidefolk” MCP server to ~/.claude.json, so Claude Code can save notes, set reminders, watch and notify.")]
                + (s.claudeSkillNote == nil ? [String(localized: "Adds the Sidefolk skill to ~/.claude/skills, so Claude Code knows when and how to use it.")] : [])
                + (hooks ? [String(localized: "Adds hooks to ~/.claude/settings.json, so I notice when a session needs you or finishes.")] : []),
            busy: model.integrationBusy,
            connect: { Task { await model.connectClaudeCode(hooks: hooks) } },
            disconnect: { Task { await model.disconnectClaudeCode() } }
        ) {
            AgentOptions(hooks: $hooks, connected: s.claudeMCPInstalled, hooksInstalled: s.claudeHooksInstalled,
                         skillMissing: s.claudeSkillNote == nil && !s.claudeSkillInstalled, skillNote: s.claudeSkillNote,
                         busy: model.integrationBusy) { Task { await model.connectClaudeCode(hooks: hooks) } }
        }
    }

    private func commandLine(_ s: IntegrationStatus) -> some View {
        AgentCard(
            name: String(localized: "sidefolk command", comment: "The `sidefolk` command-line tool; keep “sidefolk” as it is"),
            symbol: "terminal",
            status: s.cliLinked ? String(localized: "Installed") : String(localized: "Not installed"),
            connected: s.cliLinked,
            found: true,
            changes: [String(localized: "Adds ~/.local/bin/sidefolk, so “sidefolk run -- npm test” tells you when a command ends.")],
            busy: model.integrationBusy,
            connect: { Task { await model.installCommandLineTool() } },
            disconnect: { Task { await model.removeCommandLineTool() } }
        ) { EmptyView() }
    }

    private func codex(_ s: IntegrationStatus) -> some View {
        AgentCard(
            name: "Codex",
            symbol: "chevron.left.forwardslash.chevron.right",
            logo: .codex,
            status: !s.codexFound ? String(localized: "Not installed")
                : s.codexMCPInstalled ? (s.codexHooksInstalled ? String(localized: "Connected, with session taps") : String(localized: "Connected"))
                : String(localized: "Not connected"),
            connected: s.codexMCPInstalled,
            found: s.codexFound,
            changes: [String(localized: "Adds a [mcp_servers.sidefolk] entry to ~/.codex/config.toml, so Codex can use Sidefolk's tools.")]
                + (s.codexSkillNote == nil ? [String(localized: "Adds the Sidefolk skill to ~/.codex/skills, so Codex knows when and how to use it.")] : [])
                + (codexHooks ? [String(localized: "Adds hooks to ~/.codex/hooks.json, so I notice when a session needs you or finishes. Codex asks you to trust them once.")] : []),
            busy: model.integrationBusy,
            connect: { Task { await model.connectCodex(hooks: codexHooks) } },
            disconnect: { Task { await model.disconnectCodex() } }
        ) {
            AgentOptions(hooks: $codexHooks, connected: s.codexMCPInstalled, hooksInstalled: s.codexHooksInstalled,
                         skillMissing: s.codexSkillNote == nil && !s.codexSkillInstalled, skillNote: s.codexSkillNote,
                         busy: model.integrationBusy) { Task { await model.connectCodex(hooks: codexHooks) } }
        }
    }
}

/// Under a connected agent: the session-taps choice, and a button when what is installed differs from the card
/// (taps switched on or off, or a skill that came with a newer Sidefolk). Connect does the rest.
private struct AgentOptions: View {
    @Binding var hooks: Bool
    var connected: Bool
    var hooksInstalled: Bool
    var skillMissing: Bool
    var skillNote: String?
    var busy: Bool
    var update: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Notice when a session needs you", isOn: $hooks)
                .toggleStyle(.checkbox)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.ink)
            if let skillNote {
                Text(verbatim: skillNote).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            if connected, hooks != hooksInstalled || skillMissing {
                Button(hooks != hooksInstalled ? (hooks ? "Add Session Taps" : "Remove Session Taps") : "Add the Skill", action: update)
                    .buttonStyle(.sf(.secondary))
                    .disabled(busy)
            }
        }
    }
}

/// Any other app that speaks MCP (Cursor, VS Code, Zed…): Sidefolk changes nothing there, it hands over the command.
private struct OtherAgentsRow: View {
    var copy: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(symbol: "square.on.square", folk: "byte", size: 32)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Other apps").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Text("Cursor, VS Code, Zed or any app that speaks MCP: copy the command, a setup snippet for each, and where the Sidefolk skill is.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: Theme.Space.s)
            Button(copied ? "Copied" : "Copy Setup Instructions") {
                copy()
                copied = true
            }
            .buttonStyle(.sf(.secondary))
            .fixedSize()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }
}

private struct AgentCard<Extra: View>: View {
    var name: String
    var symbol: String
    /// The agent's own logo; the symbol where it has none, or while the logos can't be loaded (D36).
    var logo: ProviderLogo? = nil
    var status: String
    var connected: Bool
    var found: Bool
    var changes: [String]
    var busy: Bool
    var connect: () -> Void
    var disconnect: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            // Each agent its own mark (one Byte per card read as three); the command, which has no logo, keeps Byte's colour.
            IconTile(symbol: symbol, folk: "byte", size: 32, logo: logo)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    Text(name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    Chip(verbatim: status, tone: connected ? .success : .neutral, systemImage: connected ? "checkmark" : nil)
                }
                if found {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(changes, id: \.self) { line in
                            Label(line, systemImage: "plus").labelStyle(BulletLabelStyle())
                        }
                    }
                    extra
                } else {
                    Text("Install \(name) first, then connect it here.").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if connected {
                Button("Disconnect", action: disconnect).buttonStyle(.sf(.secondary)).disabled(busy)
                    .accessibilityLabel("Disconnect \(name)")
            } else {
                Button("Connect", action: connect).buttonStyle(.sf(.primary)).disabled(busy || !found)
                    .accessibilityLabel("Connect \(name)")
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }
}
