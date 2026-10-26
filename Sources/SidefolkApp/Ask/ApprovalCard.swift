import SidefolkCore
import SwiftUI

/// Guard's question to the user. Shows exactly what would happen (never the model's wording),
/// stays inert for a moment so a stray keypress can't approve it; high risk needs ⌘⏎, other apps a click.
struct ApprovalCard: View {
    var request: ApprovalRequest
    var decide: (ApprovalDecision) -> Void
    @State private var armed = false
    @State private var showDetails = false

    var body: some View {
        SFCard(accent: Theme.folkColor("guard")) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "checkmark.shield").foregroundStyle(Theme.folkColor("guard"))
                    Text(request.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(riskLabel).font(Theme.Font.eyebrow)
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
                    Text("Asked by \(askerName)").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
                HStack(spacing: 6) {
                    Button("Not now") { decide(.deny) }
                        .buttonStyle(.sf(.secondary))
                        .keyboardShortcut(.cancelAction)
                    if request.canAlways {
                        Button("Always allow") { decide(.allowAlways) }
                            .buttonStyle(.sf(.secondary))
                            .disabled(!armed)
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

    private var askerName: String {
        switch request.caller {
        // The name is whatever the other app sent; nothing checks it.
        case .external(let client): "another app that says it's \(AgentFacingTools.displayName(client))"
        case .extension(let id): "the extension \(id)"
        case .agent: "Sidefolk"
        case .routine: "a routine"
        case .user: "you"
        }
    }

    @ViewBuilder private var details: some View {
        switch request.details {
        case .none:
            EmptyView()
        case .command(let command):
            DisclosureGroup(isExpanded: $showDetails) {
                Text(command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(Theme.Space.s).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6))
            } label: {
                Text("Exact command").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            .onAppear { showDetails = true }
        case .url(let url):
            Text(url).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.inkMuted).lineLimit(2).textSelection(.enabled)
        case .paths(let paths):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(paths.prefix(5), id: \.self) { p in
                    Text(FolderAccess.displayPath(p)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.inkMuted).lineLimit(1)
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
            Text("\(write ? "Read and change" : "Read") files in \(FolderAccess.displayPath(folder))")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
        }
    }

    private var allowTitle: String {
        if case .folderAccess = request.details { return "Allow once" }
        return request.risk == .high ? "Allow ⌘⏎" : "Allow"
    }

    private var riskLabel: String {
        if case .folderAccess(_, let write) = request.details { return write ? "FOLDER ACCESS · CAN CHANGE FILES" : "FOLDER ACCESS · READ ONLY" }
        return switch request.risk {
        case .low: "LOW"
        case .medium: "CHANGES THINGS"
        case .high: "HIGH RISK"
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
