import SidefolkCore
import SwiftUI

/// The size of the mark at the start of each row, so details line up under the name.
enum ExtensionListLayout {
    static let badge: CGFloat = 28
}

/// Where the keyboard is in Settings › Extensions: the search field, or a row's header.
enum ExtensionListFocus: Hashable {
    case search
    case row(String)
}

/// A row in Settings › Extensions: one line to tell it apart, its details a click away (D39). With a dozen built-ins
/// and more added, every row open at once was a wall of permissions. The header is one button (a click, Space or
/// Return opens it; → and ← open and close; ↑ and ↓ move between rows); the trailing control, a switch or Review…,
/// stays outside it so it never opens the row by accident.
struct CompactRow<Badge: View, Title: View, Subtitle: View, Trailing: View, Details: View>: View {
    var id: String
    var expanded: Bool
    /// The row in one phrase for VoiceOver: its name and what it does.
    var label: Text
    var focus: FocusState<ExtensionListFocus?>.Binding
    var toggle: () -> Void
    /// Moves the keyboard to the row before (-1) or after (+1) this one.
    var move: (Int) -> Void
    @ViewBuilder var badge: Badge
    @ViewBuilder var title: Title
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var details: Details

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Space.s) {
                Button(action: toggle) {
                    HStack(alignment: .center, spacing: Theme.Space.m) {
                        badge
                        VStack(alignment: .leading, spacing: 2) {
                            title
                            subtitle
                        }
                        Spacer(minLength: Theme.Space.s)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkFaint)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .flipsForRightToLeftLayoutDirection(true)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused(focus, equals: .row(id))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(expanded ? Text("Details shown") : Text("Details hidden"))
                .accessibilityHint(expanded ? Text("Hides the details") : Text("Shows the details"))
                .help(expanded ? Text("Hide details") : Text("Show details"))
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.rightArrow) { if !expanded { toggle() }; return .handled }
                .onKeyPress(.leftArrow) { if expanded { toggle() }; return .handled }
                .onKeyPress(.return) { toggle(); return .handled }
                trailing
            }
            if expanded {
                VStack(alignment: .leading, spacing: Theme.Space.xs + 2) { details }
                    .padding(.leading, ExtensionListLayout.badge + Theme.Space.m)
                    .padding(.top, Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }
}

/// One installed extension or MCP server in Settings › Extensions: its name and one line, then on a click what it
/// can do, its tools, where it came from and what can be done with it.
struct ExtensionRow: View {
    var ext: ExtensionInfo
    var model: SettingsModel
    var expanded: Bool
    /// While searching, why it matched when its name and description don't show it ("Tools: Unzip an archive").
    var hit: String?
    var focus: FocusState<ExtensionListFocus?>.Binding
    var toggle: () -> Void
    var move: (Int) -> Void
    /// The switch changed: a filtered list keeps the row until the filter changes, not under the pointer.
    var switched: () -> Void = {}
    /// Nil for extensions that come with Sidefolk: they can be switched off, not uninstalled.
    var uninstall: (() -> Void)?

    var body: some View {
        CompactRow(id: ext.id, expanded: expanded, label: Text(verbatim: ext.accessibilityPhrase), focus: focus,
                   toggle: toggle, move: move) {
            ExtensionBadge(look: ext.look, size: ExtensionListLayout.badge)
                .opacity(ext.enabled ? 1 : 0.6)
        } title: {
            HStack(spacing: Theme.Space.s) {
                Text(ext.name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                if ext.kind == .mcpServer { Chip("MCP server", tone: .neutral) }
                if ext.fromDraft { Chip("Written for you", tone: .accent) }
                if !ext.pendingTools.isEmpty { Chip("Needs review", tone: .warning, systemImage: "exclamationmark.triangle") }
            }
        } subtitle: {
            subtitle
        } trailing: {
            Toggle("Enable \(ext.name)", isOn: Binding(get: { ext.enabled }, set: { on in
                switched()
                Task { await model.setEnabled(ext, on) }
            }))
            .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
        } details: {
            details
        }
    }

    /// The one line under the name: what stopped it, why a search found it, or what it does.
    @ViewBuilder private var subtitle: some View {
        if let error = ext.lastError, !expanded {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(Theme.Font.caption).foregroundStyle(Theme.danger).lineLimit(1)
        } else if let hit, !expanded {
            Label { Text(verbatim: hit) } icon: { Image(systemName: "magnifyingglass") }
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
        } else if !ext.shortLine.isEmpty {
            Text(ext.shortLine).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .lineLimit(expanded ? nil : 1)
                .fixedSize(horizontal: false, vertical: expanded)
        } else if let command = ext.command {
            Text(verbatim: command).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkMuted)
                .lineLimit(expanded ? nil : 1).truncationMode(.middle)
        }
    }

    @ViewBuilder private var details: some View {
        // The whole description, when the line above is only its tagline or its first sentence.
        if !ext.description.isEmpty, ext.description != ext.shortLine {
            Text(ext.description).font(Theme.Font.caption).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text(verbatim: origin).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
        if ext.kind == .mcpServer, let command = ext.command, !ext.description.isEmpty {
            Text(verbatim: command).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkMuted)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
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
        if !ext.commands.isEmpty {
            Label(ExtensionWords.commands(ext.commands), systemImage: "bolt")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
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
        if ext.bundled || ext.fromGallery, ext.enabled, let example = BuiltInExamples.request(for: ext.id) {
            // What to say to use it, one click from the Ask panel; nothing is sent until Return.
            Button { model.services.openAsk(prefill: example) } label: {
                Label { Text("Try “\(example)”", comment: "A button under a built-in extension: opens the Ask panel with these words") }
                    icon: { Image(systemName: "text.bubble") }
            }
            .buttonStyle(.sf(.secondary))
            .padding(.top, 2)
            .help("Opens the Ask panel with these words, ready to send")
        }
        if !ext.pendingTools.isEmpty || uninstall != nil {
            HStack(spacing: Theme.Space.s) {
                if !ext.pendingTools.isEmpty {
                    Button("Review changed tools…") { Task { await model.reviewToolChanges(ext) } }.buttonStyle(.sf(.primary))
                }
                if let uninstall {
                    Button("Uninstall…", action: uninstall).buttonStyle(.sf(.secondary))
                        .accessibilityLabel("Uninstall \(ext.name)")
                }
            }
            .padding(.top, 2)
        }
    }

    /// Its version and where it came from, in one line.
    private var origin: String {
        let source = if ext.bundled {
            String(localized: "Comes with Sidefolk", comment: "Where an extension came from, under its name in Settings")
        } else if ext.fromGallery {
            String(localized: "From Sidefolk's add-on gallery", comment: "Where an extension came from, under its name in Settings")
        } else if ext.fromDraft {
            String(localized: "Written by Sidefolk at your request", comment: "Where an extension came from, under its name in Settings")
        } else if ext.kind == .mcpServer {
            String(localized: "An MCP server you added", comment: "Where an extension came from, under its name in Settings")
        } else {
            String(localized: "Installed by you from a folder", comment: "Where an extension came from, under its name in Settings")
        }
        var parts = [source]
        if !ext.version.isEmpty { parts.insert(String(localized: "Version \(ext.version)", comment: "An extension's version: “Version 1.1.0”"), at: 0) }
        if let author = ext.author, !author.isEmpty, !ext.bundled, !ext.fromGallery {
            parts.append(String(localized: "by \(author)", comment: "Who wrote an extension: “by Jane Doe”"))
        }
        return parts.joined(separator: " · ")
    }

    private var toolsLine: String? {
        var parts: [String] = []
        if !ext.toolNames.isEmpty { parts.append(ExtensionWords.tools(ext.toolNames)) }
        if !ext.watcherNames.isEmpty { parts.append(ExtensionWords.watchers(ext.watcherNames)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A built-in extension this Mac can't run yet: the reason stays in sight, it is what the person can act on.
struct UnavailableExtensionRow: View {
    var item: UnavailableExtension
    var retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            ExtensionBadge(look: item.look, size: ExtensionListLayout.badge)
                .saturation(0).opacity(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Label(item.message, systemImage: "exclamationmark.circle")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            Button("Try Again", action: retry).buttonStyle(.sf(.secondary)).fixedSize()
                .accessibilityLabel("Try \(item.name) again")
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }
}

/// An extension draft Sidefolk's AI wrote, waiting for the person to review it (D39). Review stays in sight: it is
/// the one thing a draft is waiting for.
struct DraftRow: View {
    var draft: ExtensionDraftInfo
    var expanded: Bool
    var focus: FocusState<ExtensionListFocus?>.Binding
    var toggle: () -> Void
    var move: (Int) -> Void
    var review: () -> Void
    var reveal: () -> Void
    var delete: () -> Void

    var body: some View {
        CompactRow(id: Self.rowId(draft), expanded: expanded, label: Text(verbatim: draft.title), focus: focus, toggle: toggle, move: move) {
            ExtensionBadge(look: ExtensionLook(name: draft.title, iconPath: nil, folk: nil),
                           size: ExtensionListLayout.badge)
        } title: {
            HStack(spacing: Theme.Space.s) {
                Text(verbatim: draft.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                Chip("Draft", tone: .neutral)
            }
        } subtitle: {
            Text("Written by Sidefolk \(draft.modified.formatted(.relative(presentation: .named)))",
                 comment: "When an extension draft was written: “Written by Sidefolk 5 minutes ago”")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
        } trailing: {
            Button("Review…", action: review).buttonStyle(.sf(.primary)).fixedSize()
                .accessibilityLabel("Review \(draft.title)")
        } details: {
            if let version = draft.version {
                Text("Version \(version)", comment: "An extension's version: “Version 1.1.0”")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            }
            HStack(spacing: Theme.Space.s) {
                Button("Show in Finder", action: reveal).buttonStyle(.sf(.secondary))
                Button("Move to Trash…", action: delete).buttonStyle(.sf(.plain))
            }
            .padding(.top, 2)
        }
    }

    static func rowId(_ draft: ExtensionDraftInfo) -> String { "draft:" + draft.id }
}

/// A skill: its name and first line, the whole description and Delete a click away.
struct SkillRow: View {
    var skill: SkillInfo
    var expanded: Bool
    var focus: FocusState<ExtensionListFocus?>.Binding
    var toggle: () -> Void
    var move: (Int) -> Void
    var delete: () -> Void

    var body: some View {
        CompactRow(id: Self.rowId(skill), expanded: expanded, label: Text(verbatim: "\(skill.name), \(skill.description)"),
                   focus: focus, toggle: toggle, move: move) {
            IconTile(symbol: "text.book.closed", folk: "seed", size: ExtensionListLayout.badge)
        } title: {
            HStack(spacing: Theme.Space.s) {
                Text(skill.name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                Chip(skill.bundled ? "Built in" : "Yours", tone: skill.bundled ? .neutral : .accent)
            }
        } subtitle: {
            Text(skill.description).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .lineLimit(expanded ? nil : 1)
                .fixedSize(horizontal: false, vertical: expanded)
        } trailing: {
            EmptyView()
        } details: {
            if !skill.bundled {
                Button("Delete…", action: delete).buttonStyle(.sf(.secondary))
                    .accessibilityLabel("Delete \(skill.name)")
            }
        }
    }

    static func rowId(_ skill: SkillInfo) -> String { "skill:" + skill.name }
}

/// What an extension adds, as Settings and the install preview list it.
enum ExtensionWords {
    static func tools(_ names: [String]) -> String { String(localized: "Tools: \(Wording.list(names))") }
    /// What it answers at once, without the AI (D50): "Answers without AI: “time in …”, “what time is it in …”".
    static func commands(_ sentences: [String]) -> String {
        let shown = sentences.prefix(8).map { "“\($0)”" } + (sentences.count > 8 ? ["…"] : [])
        return String(localized: "Answers without AI: \(shown.joined(separator: ", "))",
                      comment: "Sentences an extension answers at once, each in quotes, “…” standing for the words the person fills in")
    }
    static func watchers(_ names: [String]) -> String { String(localized: "Watchers: \(Wording.list(names))") }
    /// Pages in Home (D62); one read in the background says so, since it runs while nobody looks.
    static func pages(_ names: [String], background: Bool) -> String {
        background ? String(localized: "Pages in Home: \(Wording.list(names)), read once a minute in the background for their charts and Today's tile")
            : String(localized: "Pages in Home: \(Wording.list(names))")
    }
}

/// Small caption lines with a leading mark, for permission and warning lists.
struct BulletLabelStyle: LabelStyle {
    var color: Color = Theme.inkMuted

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.inkFaint)
            configuration.title.font(Theme.Font.caption).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
    }
}
