import SidefolkCore
import SwiftUI

/// One installed extension or MCP server in Settings › Extensions.
struct ExtensionRow: View {
    var ext: ExtensionInfo
    var model: SettingsModel
    /// Nil for extensions that come with Sidefolk: they can be switched off, not uninstalled.
    var uninstall: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ExtensionBadge(look: ext.look, size: 32)
            VStack(alignment: .leading, spacing: Theme.Space.xs + 2) {
                HStack(spacing: Theme.Space.s) {
                    Text(ext.name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    if !ext.version.isEmpty {
                        Text(ext.version).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                    }
                    if ext.kind == .mcpServer { Chip("MCP server", tone: .neutral) }
                    if ext.fromDraft { Chip("Written for you", tone: .accent) }
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
                if ext.bundled, ext.enabled, let example = BuiltInExamples.request(for: ext.id) {
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
                        }
                    }
                    .padding(.top, 2)
                }
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
        if !ext.toolNames.isEmpty { parts.append(ExtensionWords.tools(ext.toolNames)) }
        if !ext.watcherNames.isEmpty { parts.append(ExtensionWords.watchers(ext.watcherNames)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A built-in extension this Mac can't run yet, with the reason and a way to try again.
struct UnavailableExtensionRow: View {
    var item: UnavailableExtension
    var retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ExtensionBadge(look: item.look, size: 32).saturation(0).opacity(0.6)
            VStack(alignment: .leading, spacing: Theme.Space.xs + 2) {
                Text(item.name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Label(item.message, systemImage: "exclamationmark.circle")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                Button("Try Again", action: retry).buttonStyle(.sf(.secondary)).padding(.top, 2)
            }
            Spacer(minLength: Theme.Space.s)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }
}

/// An extension draft Sidefolk's AI wrote, waiting for the person to review it (D39).
struct DraftRow: View {
    var draft: ExtensionDraftInfo
    var review: () -> Void
    var reveal: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ExtensionBadge(look: ExtensionLook(name: draft.title, iconPath: nil, folk: nil), size: 32)
            VStack(alignment: .leading, spacing: Theme.Space.xs + 2) {
                HStack(spacing: Theme.Space.s) {
                    Text(verbatim: draft.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    if let version = draft.version {
                        Text(verbatim: version).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                    }
                    Chip("Draft", tone: .neutral)
                }
                Text("Written by Sidefolk \(draft.modified.formatted(.relative(presentation: .named)))",
                     comment: "When an extension draft was written: “Written by Sidefolk 5 minutes ago”")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                HStack(spacing: Theme.Space.s) {
                    Button("Review…", action: review).buttonStyle(.sf(.primary))
                    Button("Show in Finder", action: reveal).buttonStyle(.sf(.secondary))
                    Button("Move to Trash…", action: delete).buttonStyle(.sf(.plain))
                }
                .padding(.top, 2)
            }
            Spacer(minLength: Theme.Space.s)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }
}

/// What an extension adds, as Settings and the install preview list it.
enum ExtensionWords {
    static func tools(_ names: [String]) -> String { String(localized: "Tools: \(Wording.list(names))") }
    static func watchers(_ names: [String]) -> String { String(localized: "Watchers: \(Wording.list(names))") }
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
