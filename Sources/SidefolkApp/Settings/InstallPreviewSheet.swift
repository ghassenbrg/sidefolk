import AppKit
import SidefolkCore
import SwiftUI

/// What installing an extension would allow, in Guard's style, before anything is installed. The same
/// sheet serves a folder the person chose, a sample, and a draft Sidefolk's AI wrote for them (D39).
struct InstallPreviewSheet: View {
    var preview: ExtensionInstallPreview
    var model: SettingsModel
    /// Closes the window it is shown in (`InstallPreviewWindow`); nil when it is a sheet.
    var close: (() -> Void)? = nil
    @State private var armed = false
    @State private var installing = false
    @State private var error: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                // The extension's own icon, with Guard on duty: this is a permission question.
                ExtensionBadge(look: preview.look, size: 44)
                    .overlay(alignment: .bottomTrailing) { FolkBadge(name: "guard", size: 20).offset(x: 6, y: 6) }
                VStack(alignment: .leading, spacing: 2) {
                    (preview.isUpdate ? Text("Update \(preview.name)?") : Text("Install \(preview.name)?"))
                        .font(Theme.Font.heading).foregroundStyle(Theme.ink)
                    origin.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1).truncationMode(.middle)
                }
            }
            if !preview.description.isEmpty {
                Text(preview.description).font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if preview.fromDraft {
                Label {
                    Text("Sidefolk wrote this for you. It runs only with the permissions below, and you can read its files first.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(Theme.folkColor("byte"))
                }
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
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
                Eyebrow(text: "What it can do")
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
                        Text(ExtensionWords.tools(preview.toolNames)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                    if !preview.watcherNames.isEmpty {
                        Text(ExtensionWords.watchers(preview.watcherNames)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            Text("It runs in a sandbox limited to the lines above. You can turn it off or uninstall it any time.")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            if let error { InlineError(error: error) }
            HStack {
                Button("Show Files") { NSWorkspace.shared.activateFileViewerSelecting([preview.sourceFolder]) }
                    .buttonStyle(.sf(.plain))
                Spacer()
                Button("Cancel", action: finish).buttonStyle(.sfSecondary).keyboardShortcut(.cancelAction)
                Button(installing ? "Installing…" : preview.isUpdate ? "Update \(preview.name)" : "Install \(preview.name)") {
                    installing = true
                    Task {
                        error = await model.install(preview)
                        installing = false
                        if error == nil { finish() }
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

    private func finish() {
        if let close { close() } else { dismiss() }
    }

    private var origin: Text {
        preview.fromDraft
            ? Text("Version \(preview.version) · written by Sidefolk for you")
            : Text("Version \(preview.version) · from \(FolderAccess.displayPath(preview.sourceFolder.path))")
    }
}
