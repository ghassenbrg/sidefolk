import SidefolkCore
import SwiftUI

/// Guard's question to the user. Shows exactly what would happen (never the model's wording),
/// stays inert for a moment so a stray keypress can't approve it; high risk needs ⌘⏎, other apps a click.
struct ApprovalCard: View {
    var request: ApprovalRequest
    /// The extension whose tool is asking, shown by its icon and name under the title.
    var look: ExtensionLook? = nil
    var decide: (ApprovalDecision) -> Void
    @State private var armed = false

    var body: some View {
        SFCard(accent: Theme.folkColor("guard")) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "checkmark.shield").foregroundStyle(Theme.folkColor("guard"))
                    Text(request.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let look {
                    HStack(spacing: 6) {
                        ExtensionBadge(look: look, size: 16)
                        Text("From the \(look.name) extension", comment: "Under an approval's title: which extension's tool asks")
                            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
                Text(riskLabel).font(Theme.Font.eyebrow).textCase(.uppercase)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(riskTint, in: Capsule())
                    .foregroundStyle(Theme.ink)
                Text(request.summary).font(Theme.Font.body).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                details
                if request.tainted {
                    Label("This came up while reading outside content. Check it carefully.", systemImage: "exclamationmark.triangle")
                        .font(Theme.Font.caption).foregroundStyle(Theme.danger)
                }
                if request.caller != .user {
                    asker.font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
                ButtonRow {
                    Button("Not now") { decide(.deny) }
                        .buttonStyle(.sf(.secondary))
                        .keyboardShortcut(.cancelAction)
                    if request.canAlways {
                        Button("Always allow") { decide(.allowAlways) }
                            .buttonStyle(.sf(.secondary))
                            .disabled(!armed)
                    } else if request.canAllowForRequest {
                        Button("Allow for this request") { decide(.allowForRequest) }
                            .buttonStyle(.sf(.secondary))
                            .disabled(!armed)
                            .help("Until this request is done, Sidefolk does this again without asking. Offered only for steps that send nothing anywhere but to your AI.")
                    }
                    allowButton
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permission request: \(request.title)")
    }

    @ViewBuilder private var allowButton: some View {
        let button = Button(allowTitle) { decide(.allowOnce) }
            .buttonStyle(.sf(request.risk == .high ? .destructive : .primary))
            .disabled(!armed)
        // Keys approve only your own and Sidefolk's requests (Return, or ⌘⏎ for high risk). Other apps and
        // extensions always need a click: they may ask while you are typing somewhere else.
        let ours = request.caller.kind == "user" || request.caller.kind == "agent"
        if ours, request.risk == .high {
            button.keyboardShortcut(.return, modifiers: .command)
        } else if ours {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }

    private var asker: Text {
        switch request.caller {
        // The name is whatever the other app sent; nothing checks it.
        case .external(let client): Text("Asked by another app that says it's \(AgentFacingTools.displayName(client))")
        case .extension(let id): Text("Asked by the extension \(id)")
        case .agent: Text("Asked by Sidefolk")
        case .routine: Text("Asked by a routine")
        case .user: Text("Asked by you")
        }
    }

    private var details: some View { ApprovalDetails(details: request.details) }

    private var allowTitle: LocalizedStringKey {
        if case .folderAccess = request.details { return "Allow once" }
        return request.risk == .high ? "Allow ⌘⏎" : "Allow"
    }

    /// Shown in capitals (`textCase`), so each language capitalizes its own words.
    private var riskLabel: LocalizedStringKey {
        if case .folderAccess(_, let write) = request.details { return write ? "Folder access · can change files" : "Folder access · read only" }
        return switch request.risk {
        case .low: "Low"
        case .medium:
            switch request.effect {
            case .readsPrivateData: "Reads private data"
            case .readsFiles: "Reads files"
            case .usesInternet: "Uses the internet"
            case .opensApps: "Opens a link or app"
            case .usesExtension: "Uses an extension"
            case .changesFiles: "Changes files"
            case .runsPrograms: "Runs a program"
            case .changesThings: "Changes things"
            }
        case .high: "High risk"
        }
    }

    private var riskTint: Color {
        switch request.risk {
        case .low: Theme.accentSoft
        case .medium: Theme.surfaceSunken
        case .high: Theme.dangerSoft
        }
    }
}

/// Exactly what an approval is about: the verbatim command, the full address, the paths, the text to
/// read. Shown on the card, and again beside a skipped step in Now (D37).
struct ApprovalDetails: View {
    var details: ApprovalRequest.Details
    @State private var showDetails = false

    var body: some View {
        switch details {
        case .none:
            EmptyView()
        case .command(let command):
            DisclosureGroup(isExpanded: $showDetails) {
                Text(verbatim: command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(Theme.Space.s).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6))
            } label: {
                Text("Exact command").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            .onAppear { showDetails = true }
        case .url(let url):
            Text(verbatim: url).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.inkMuted).lineLimit(2).textSelection(.enabled)
        case .paths(let paths):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(paths.prefix(5), id: \.self) { p in
                    Text(verbatim: FolderAccess.displayPath(p)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                if paths.count > 5 { Text("and \(paths.count - 5) more").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint) }
            }
        case .text(let text):
            ScrollView {
                Text(text).font(Theme.Font.caption).foregroundStyle(Theme.ink).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(Theme.Space.s)
            .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6))
        case .folderAccess(let folder, let write):
            let path = FolderAccess.displayPath(folder)
            (write ? Text("Read and change files in \(path)") : Text("Read files in \(path)"))
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
    }
}
