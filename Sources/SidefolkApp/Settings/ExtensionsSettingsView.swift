import AppKit
import SidefolkCore
import SwiftUI

/// Settings › Extensions: the extensions that come with Sidefolk, the ones the person added (folders and
/// MCP servers), drafts Sidefolk's AI wrote for them, and skills. Each is one line until clicked, under a search and
/// an All / On / Off filter (D39). Beside "Installed", the add-on gallery (D55).
struct ExtensionsSettingsView: View {
    var model: SettingsModel
    @State private var addingServer = false
    @State private var uninstalling: ExtensionInfo?
    @State private var deletingSkill: SkillInfo?
    @State private var deletingDraft: ExtensionDraftInfo?
    @State private var search: String
    @State private var show: ExtensionListQuery.Show
    @State private var page: Page

    enum Page: String, Hashable { case installed, gallery }
    @State private var expanded: Set<String>
    /// Rows that need the person (changed tools) open by themselves; these are the ones they closed anyway.
    @State private var closed: Set<String> = []
    /// Switched on or off while the list was narrowed: they stay in sight until the words or the filter change,
    /// rather than vanishing under the pointer.
    @State private var kept: Set<String> = []
    @FocusState private var focus: ExtensionListFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False when the snapshots set the filter: it is the person's, only the page changes it.
    private let remembers: Bool

    /// `query` and `expanded` show the page in a given state (UISnapshots); otherwise it opens on the filter the
    /// person left it on.
    init(model: SettingsModel, query: ExtensionListQuery? = nil, expanded: Set<String> = [], page: Page? = nil) {
        self.model = model
        _page = State(initialValue: page ?? (query == nil ? Self.savedPage : .installed))
        let start = query ?? ExtensionListQuery(show: Self.savedShow)
        _search = State(initialValue: start.text)
        _show = State(initialValue: start.show)
        _expanded = State(initialValue: expanded)
        remembers = query == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.l)
                .frame(maxWidth: .infinity)
            SettingsPage {
                if page == .gallery {
                    GalleryExtensionsView(model: model)
                } else {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: Theme.Space.xl) { groups }
                            .onChange(of: focus) {
                                guard case .row(let id) = focus else { return }
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                            }
                    }
                }
            }
        }
        .background(Theme.surfaceSunken)
        // ⌘F, as everywhere on the Mac.
        .background {
            Button("Find") { focus = .search }.keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onChange(of: search) { kept = [] }
        .onChange(of: show) {
            kept = []
            if remembers { Self.savedShow = show }
        }
        .onChange(of: page) { if remembers { Self.savedPage = page } }
        .onDisappear { kept = [] }
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

    // MARK: What is shown

    private var query: ExtensionListQuery { ExtensionListQuery(text: search, show: show) }

    private func visible(_ items: [ExtensionInfo]) -> [ExtensionInfo] {
        let query = self.query
        return items.filter { query.includes($0) || kept.contains($0.id) }
    }

    private var builtIns: [ExtensionInfo] { visible(model.extensions.filter(\.bundled)) }
    private var added: [ExtensionInfo] { visible(model.extensions.filter { !$0.bundled }) }
    private var unavailable: [UnavailableExtension] { query.filter(model.unavailable) }
    /// Drafts and skills are neither on nor off: they are listed under All only, and searched there.
    private var drafts: [ExtensionDraftInfo] { show == .all ? model.drafts.filter { query.matches($0.searchTexts) } : [] }
    private var skills: [SkillInfo] { show == .all ? model.skills.filter { query.matches($0.searchTexts) } : [] }
    private var counts: ExtensionListQuery.Counts { query.counts(model.extensions) + query.counts(model.unavailable) }

    /// The rows the keyboard moves through, top to bottom.
    private var rowIds: [String] {
        builtIns.map(\.id) + added.map(\.id) + drafts.map(DraftRow.rowId) + skills.map(SkillRow.rowId)
    }

    private var nothingShown: Bool {
        builtIns.isEmpty && unavailable.isEmpty && added.isEmpty && drafts.isEmpty && skills.isEmpty
    }

    /// Changed tools wait for the person, so that row starts open.
    private func isExpanded(_ id: String, needsYou: Bool = false) -> Bool {
        expanded.contains(id) || (needsYou && !closed.contains(id))
    }

    private func toggle(_ id: String, needsYou: Bool = false) {
        let open = !isExpanded(id, needsYou: needsYou)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            if open {
                expanded.insert(id)
                closed.remove(id)
            } else {
                expanded.remove(id)
                closed.insert(id)
            }
        }
    }

    private func move(from id: String, by step: Int) {
        let ids = rowIds
        guard let index = ids.firstIndex(of: id) else { return }
        let next = index + step
        if next < 0 { focus = .search } else if next < ids.count { focus = .row(ids[next]) }
    }

    private func focusFirstRow() {
        if let first = rowIds.first { focus = .row(first) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                Picker("Page", selection: $page) {
                    Text("Installed", comment: "Settings › Extensions: the title over the extensions and skills on this Mac")
                        .tag(Page.installed)
                    Text("Gallery", comment: "Settings › Extensions: extensions to add from the add-on gallery").tag(Page.gallery)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: Theme.Space.s)
                if page == .installed {
                    Picker("Show", selection: $show) {
                        Text("All \(counts.all)", comment: "A filter in Settings › Extensions with how many it shows: “All 15”")
                            .tag(ExtensionListQuery.Show.all)
                        Text("On \(counts.on)", comment: "A filter in Settings › Extensions: the extensions switched on, “On 9”")
                            .tag(ExtensionListQuery.Show.on)
                        Text("Off \(counts.off)", comment: "A filter in Settings › Extensions: the extensions switched off, “Off 6”")
                            .tag(ExtensionListQuery.Show.off)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Show every extension, or only those switched on or off")
                }
            }
            if page == .installed {
                SearchBox(text: $search, prompt: Text("Search names, tools and permissions"), focus: $focus, focusValue: .search,
                          submit: focusFirstRow)
            }
        }
    }

    // MARK: Groups

    @ViewBuilder private var groups: some View {
        if query.isNarrowed, nothingShown {
            noMatch
        }
        if !builtIns.isEmpty || !unavailable.isEmpty { builtIn }
        if !query.isNarrowed || !added.isEmpty { installed }
        if !drafts.isEmpty { draftGroup }
        if show == .all, !query.isSearching || !skills.isEmpty { skillGroup }
    }

    /// Nothing left after the words or the filter, and the way back.
    private var noMatch: some View {
        RowsCard {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(Theme.inkFaint)
                    .accessibilityHidden(true)
                Text(verbatim: noMatchText).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Space.s) {
                    if query.isSearching { Button("Clear Search") { search = "" }.buttonStyle(.sf(.secondary)) }
                    if show != .all { Button("Show All") { show = .all }.buttonStyle(.sf(.secondary)) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.xl)
        }
    }

    private var noMatchText: String {
        let words = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch (query.isSearching, show) {
        case (true, .all): String(localized: "Nothing installed matches “\(words)”.", comment: "Settings › Extensions, a search that found nothing")
        case (true, .on): String(localized: "No extension that is on matches “\(words)”.", comment: "Settings › Extensions, a search among those switched on")
        case (true, .off): String(localized: "No extension that is off matches “\(words)”.", comment: "Settings › Extensions, a search among those switched off")
        case (false, .on): String(localized: "No extension is on.", comment: "Settings › Extensions, the On filter with nothing in it")
        case (false, _): String(localized: "Every extension is on.", comment: "Settings › Extensions, the Off filter with nothing in it")
        }
    }

    private func row(_ ext: ExtensionInfo, uninstall: (() -> Void)?) -> some View {
        let needsYou = !ext.pendingTools.isEmpty
        // A row found by something its name and description don't say names what matched.
        let hit = query.isSearching && !query.matches([ext.name, ext.description]) ? query.hit(in: ext.searchTexts).map(ext.shownHit) : nil
        return ExtensionRow(ext: ext, model: model, expanded: isExpanded(ext.id, needsYou: needsYou), hit: hit, focus: $focus,
                            toggle: { toggle(ext.id, needsYou: needsYou) }, move: { move(from: ext.id, by: $0) },
                            switched: { if query.isNarrowed { kept.insert(ext.id) } }, uninstall: uninstall)
            .id(ext.id)
    }

    /// Extensions answer requests in your own words, so without an AI they have nothing to answer.
    private var builtInFooter: LocalizedStringKey {
        if model.settings.provider.kind == .none {
            return "These come with Sidefolk and are updated with it, each in its own sandbox. They answer through your AI, so choose one in Settings › AI first."
        }
        return "These come with Sidefolk and are updated with it. Each runs in its own sandbox; switch off any you don't want."
    }

    // MARK: Built in

    private var builtIn: some View {
        SettingsGroup(title: "Built in", footer: builtInFooter) {
            ForEach(builtIns) { ext in
                row(ext, uninstall: nil)
            }
            ForEach(unavailable) { item in
                UnavailableExtensionRow(item: item) { Task { await model.retryBuiltIns() } }
            }
        }
    }

    // MARK: Added by you

    /// While the list is narrowed, only what matches; the ways to add one are under All with nothing searched.
    private var installed: some View {
        SettingsGroup(title: "Added by you",
                      footer: "Extensions run in a sandbox limited to what they asked for at install. MCP servers run with your full permissions.") {
            if added.isEmpty {
                InlineEmpty(text: "Nothing added yet. Install an extension from a folder, add an MCP server, or ask Sidefolk to build one.",
                            systemImage: "puzzlepiece.extension")
            }
            ForEach(added) { ext in
                row(ext) { uninstalling = ext }
            }
            if !query.isNarrowed {
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

    private var draftGroup: some View {
        SettingsGroup(title: "Drafts",
                      footer: "Extensions Sidefolk wrote at your request. Nothing in a draft runs until you review it and install it.") {
            ForEach(drafts) { draft in
                let id = DraftRow.rowId(draft)
                DraftRow(draft: draft, expanded: isExpanded(id), focus: $focus, toggle: { toggle(id) }, move: { move(from: id, by: $0) },
                         review: {
                             model.clearExtensionError()
                             Task { await model.review(folder: draft.folder) }
                         }, reveal: { model.revealDraft(draft) }, delete: { deletingDraft = draft })
                    .id(id)
            }
        }
    }

    // MARK: Skills

    private var skillGroup: some View {
        SettingsGroup(title: "Skills", footer: "Skills are written instructions Sidefolk reads when a request needs them.") {
            if skills.isEmpty {
                InlineEmpty(text: "No skills yet. Ask “write a skill for my weekly review” and approve it.", systemImage: "text.book.closed")
            }
            ForEach(skills) { skill in
                let id = SkillRow.rowId(skill)
                SkillRow(skill: skill, expanded: isExpanded(id), focus: $focus, toggle: { toggle(id) }, move: { move(from: id, by: $0) },
                         delete: { deletingSkill = skill })
                    .id(id)
            }
        }
    }

    // MARK: Remembered

    private static let showKey = "settings.extensions.show"

    /// The filter the person left the list on: a convenience of theirs, so it lives in their defaults, not the store.
    /// Installed or Gallery, as the person left it.
    private static var savedPage: Page {
        get { UserDefaults.standard.string(forKey: "settings.extensions.page").flatMap(Page.init(rawValue:)) ?? .installed }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "settings.extensions.page") }
    }

    private static var savedShow: ExtensionListQuery.Show {
        get { UserDefaults.standard.string(forKey: showKey).flatMap(ExtensionListQuery.Show.init(rawValue:)) ?? .all }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: showKey) }
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
