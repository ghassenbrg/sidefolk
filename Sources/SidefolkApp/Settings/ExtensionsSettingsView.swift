import AppKit
import SidefolkCore
import SwiftUI

/// Settings › Extensions: installed extensions and MCP servers, skills, and the agents Sidefolk
/// is connected to.
struct ExtensionsSettingsView: View {
    var model: SettingsModel
    @State private var preview: ExtensionInstallPreview?
    @State private var addingServer = false
    @State private var uninstalling: ExtensionInfo?
    @State private var deletingSkill: SkillInfo?

    var body: some View {
        SettingsPage {
            installed
            skills
        }
        .sheet(item: $preview) { p in InstallPreviewSheet(preview: p, model: model) }
        .sheet(isPresented: $addingServer) { AddServerSheet(model: model) }
        .alert("Uninstall “\(uninstalling?.name ?? "")”?", isPresented: Binding(
            get: { uninstalling != nil }, set: { if !$0 { uninstalling = nil } }
        ), presenting: uninstalling) { ext in
            Button("Uninstall", role: .destructive) { Task { await model.uninstall(ext) } }
            Button("Cancel", role: .cancel) {}
        } message: { ext in
            Text(ext.kind == .mcpServer ? "Its tools stop working right away." : "Its tools and watchers stop, and its files are removed.")
        }
        .alert("Delete the skill “\(deletingSkill?.name ?? "")”?", isPresented: Binding(
            get: { deletingSkill != nil }, set: { if !$0 { deletingSkill = nil } }
        ), presenting: deletingSkill) { skill in
            Button("Delete skill", role: .destructive) { Task { await model.deleteSkill(skill) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its instructions are removed. This can't be undone.")
        }
    }

    // MARK: Installed

    private var installed: some View {
        SettingsGroup(title: "Installed",
                      footer: "Extensions run in a sandbox limited to what they asked for at install. MCP servers run with your full permissions.") {
            if model.extensions.isEmpty {
                InlineEmpty(text: "No extensions yet. Install one from a folder, or add an MCP server.", systemImage: "puzzlepiece.extension")
            }
            ForEach(model.extensions) { ext in
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
                            Button("\(sample.name)…") {
                                model.clearExtensionError()
                                Task { preview = await model.preview(folder: sample.folder) }
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
        panel.prompt = "Review Extension"
        panel.message = "Choose an extension folder. You'll see what it can do before anything is installed."
        Task {
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
            guard response == .OK, let url = panel.url else { return }
            preview = await model.preview(folder: url)
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

// MARK: - Extension row

private struct ExtensionRow: View {
    var ext: ExtensionInfo
    var model: SettingsModel
    var uninstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            FolkBadge(name: ext.folk, size: 32)
            VStack(alignment: .leading, spacing: Theme.Space.xs + 2) {
                HStack(spacing: Theme.Space.s) {
                    Text(ext.name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    if !ext.version.isEmpty {
                        Text(ext.version).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                    }
                    if ext.kind == .mcpServer { Chip("MCP server", tone: .neutral) }
                }
                if !ext.description.isEmpty {
                    Text(ext.description).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if ext.sandboxed {
                    Chip("Sandboxed", tone: .success, systemImage: "lock.shield")
                } else {
                    Chip("Runs with your full permissions", tone: .warning, systemImage: "exclamationmark.triangle")
                }
                if !ext.permissionLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(ext.permissionLines, id: \.self) { line in
                            Label(line, systemImage: "checkmark").labelStyle(BulletLabelStyle())
                        }
                    }
                }
                if let tools = toolsLine {
                    Text(tools).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                // Tools on hold for approval, or a manifest and program that disagree: worth knowing, not errors.
                ForEach(ext.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                if let error = ext.lastError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(Theme.Font.caption).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Theme.Space.s) {
                    if !ext.pendingTools.isEmpty {
                        Button("Review changed tools…") { Task { await model.reviewToolChanges(ext) } }.buttonStyle(.sf(.primary))
                    }
                    if !ext.bundled {
                        Button("Uninstall…", action: uninstall).buttonStyle(.sf(.secondary))
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: Theme.Space.s)
            Toggle("Enable \(ext.name)", isOn: Binding(get: { ext.enabled }, set: { on in Task { await model.setEnabled(ext, on) } }))
                .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .opacity(ext.enabled ? 1 : 0.75)
    }

    private var toolsLine: String? {
        var parts: [String] = []
        if !ext.toolNames.isEmpty { parts.append("Tools: " + ext.toolNames.joined(separator: ", ")) }
        if !ext.watcherNames.isEmpty { parts.append("Watchers: " + ext.watcherNames.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Small caption lines with a leading mark, for permission and warning lists.
private struct BulletLabelStyle: LabelStyle {
    var color: Color = Theme.inkMuted

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.inkFaint)
            configuration.title.font(Theme.Font.caption).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Install preview (Guard style)

struct InstallPreviewSheet: View {
    var preview: ExtensionInstallPreview
    var model: SettingsModel
    @State private var armed = false
    @State private var installing = false
    @State private var error: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                FolkBadge(name: "guard", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(preview.isUpdate ? "Update" : "Install") \(preview.name)?").font(Theme.Font.heading).foregroundStyle(Theme.ink)
                    Text("Version \(preview.version) · from \(FolderAccess.displayPath(preview.sourceFolder.path))")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.middle)
                }
            }
            if !preview.description.isEmpty {
                Text(preview.description).font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(preview.warnings, id: \.self) { warning in
                        Label {
                            Text(warning).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                        }
                    }
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Eyebrow(text: "It will be able to")
                if preview.permissionLines.isEmpty {
                    Text("Nothing beyond its own data folder.").font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                }
                ForEach(preview.permissionLines, id: \.self) { line in
                    Label {
                        Text(line).font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.shield").foregroundStyle(Theme.folkColor("guard"))
                    }
                }
            }
            if !preview.toolNames.isEmpty || !preview.watcherNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "It adds")
                    if !preview.toolNames.isEmpty {
                        Text("Tools: " + preview.toolNames.joined(separator: ", ")).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                    if !preview.watcherNames.isEmpty {
                        Text("Watchers: " + preview.watcherNames.joined(separator: ", ")).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            Text("It runs in a sandbox limited to the lines above. You can turn it off or uninstall it any time.")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            if let error { InlineError(error: error) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button(installing ? "Installing…" : "\(preview.isUpdate ? "Update" : "Install") \(preview.name)") {
                    installing = true
                    Task {
                        error = await model.install(preview)
                        installing = false
                        if error == nil { dismiss() }
                    }
                }
                .buttonStyle(.sfPrimary)
                .disabled(!armed || installing)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 480)
        .background(Theme.surface)
        .task {
            // Like approval cards: inert for a moment so a stray Return can't install it.
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
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
                    Text(([command] + parsedArguments).joined(separator: " "))
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

    private func field(_ label: String, text: Binding<String>, prompt: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted)
            TextField(label, text: text, prompt: Text(prompt))
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
        return versioned ? nil : "\(cmd) downloads the newest \(package) every time it starts. Pin a version, like \(package)@1.2.3."
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

/// Settings › Agents: Claude Code, Codex and the `sidefolk` command.
struct AgentsGroup: View {
    var model: SettingsModel
    @State private var hooks = true

    var body: some View {
        SettingsGroup(title: "Connect your agents",
                      footer: "Sidefolk saves a backup next to each file before changing it. Disconnect removes only what it added.") {
            if let status = model.integration {
                claude(status)
                codex(status)
                commandLine(status)
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
        if let s = model.integration, s.claudeMCPInstalled { hooks = s.claudeHooksInstalled }
    }

    private func claude(_ s: IntegrationStatus) -> some View {
        AgentCard(
            name: "Claude Code",
            status: !s.claudeCodeFound ? "Not installed" : s.claudeMCPInstalled ? (s.claudeHooksInstalled ? "Connected, with session taps" : "Connected") : "Not connected",
            connected: s.claudeMCPInstalled,
            found: s.claudeCodeFound,
            changes: ["Adds a “sidefolk” MCP server to ~/.claude.json, so Claude Code can save notes, set reminders, watch and notify."]
                + (hooks ? ["Adds hooks to ~/.claude/settings.json, so I notice when a session needs you or finishes."] : []),
            busy: model.integrationBusy,
            connect: { Task { await model.connectClaudeCode(hooks: hooks) } },
            disconnect: { Task { await model.disconnectClaudeCode() } }
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Tap me when a session needs you", isOn: $hooks)
                    .toggleStyle(.checkbox)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                if s.claudeMCPInstalled, hooks != s.claudeHooksInstalled {
                    Button(hooks ? "Add Session Taps" : "Remove Session Taps") {
                        Task { await model.connectClaudeCode(hooks: hooks) }
                    }
                    .buttonStyle(.sf(.secondary))
                    .disabled(model.integrationBusy)
                }
            }
        }
    }

    private func commandLine(_ s: IntegrationStatus) -> some View {
        AgentCard(
            name: "sidefolk command",
            status: s.cliLinked ? "Installed" : "Not installed",
            connected: s.cliLinked,
            found: true,
            changes: ["Adds ~/.local/bin/sidefolk, so “sidefolk run -- npm test” tells you when a command ends."],
            busy: model.integrationBusy,
            connect: { Task { await model.installCommandLineTool() } },
            disconnect: { Task { await model.removeCommandLineTool() } }
        ) { EmptyView() }
    }

    private func codex(_ s: IntegrationStatus) -> some View {
        AgentCard(
            name: "Codex",
            status: !s.codexFound ? "Not installed" : s.codexMCPInstalled ? "Connected" : "Not connected",
            connected: s.codexMCPInstalled,
            found: s.codexFound,
            changes: ["Adds a [mcp_servers.sidefolk] entry to ~/.codex/config.toml, so Codex can use Sidefolk's tools."],
            busy: model.integrationBusy,
            connect: { Task { await model.connectCodex() } },
            disconnect: { Task { await model.disconnectCodex() } }
        ) { EmptyView() }
    }
}

private struct AgentCard<Extra: View>: View {
    var name: String
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
            FolkBadge(name: "byte", size: 32)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    Text(name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    Chip(status, tone: connected ? .success : .neutral, systemImage: connected ? "checkmark" : nil)
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
