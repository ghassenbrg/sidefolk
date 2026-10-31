import AppKit
import SidefolkCore
import SwiftUI

/// What installing an extension would allow, in Guard's style, before anything is installed. The same
/// sheet serves the gallery, a folder the person chose, a sample, and a draft Sidefolk's AI wrote for them (D39):
/// the same facts for each, said as loudly as its source calls for (D71).
struct InstallPreviewSheet: View {
    var preview: ExtensionInstallPreview
    var model: SettingsModel
    /// Closes the window it is shown in (`InstallPreviewWindow`); nil when it is a sheet.
    var close: (() -> Void)? = nil
    @State private var armed = false
    @State private var installing = false
    @State private var showsAdds = false
    @State private var error: UserFacingError?
    /// How tall the details may be before they scroll, taken once as the sheet opens.
    @State private var room = InstallPreviewSheet.roomForDetails
    /// The details at their full height, measured; until then, as much room as there is.
    @State private var detailsHeight: CGFloat = InstallPreviewSheet.roomForDetails
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The details scroll inside a height the screen has room for; the buttons stay below them. A sheet can't be
        // moved, and a big extension's sheet grew past the bottom of the screen with its buttons out of reach.
        VStack(spacing: 0) {
            ScrollView {
                details.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailsHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(detailsHeight, room))
            if detailsHeight > room { Divider() }
            footer
        }
        .frame(width: 480)
        .background(Theme.surface)
        .task {
            // Like approval cards: inert for a moment so a stray Return can't install it.
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
        }
    }

    /// Everything the person reads before deciding.
    private var details: some View {
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
            // Where it comes from first: that's what tells how much to read into the rest (D71).
            InstallSourceRow(source: review.source)
            if !preview.description.isEmpty {
                Text(preview.description).font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let update = review.update { InstallUpdateBox(update: update, tone: review.tone) }
            // A warning comes before what it warns about; a calm note can follow the list it sums up.
            if !review.cautions.isEmpty, review.tone == .careful { InstallCautionBox(cautions: review.cautions, tone: .careful) }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Eyebrow(text: "What it can do").accessibilityAddTraits(.isHeader)
                if review.lines.isEmpty {
                    Text("Nothing beyond its own data folder.").font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                }
                ForEach(review.lines, id: \.self) { InstallPermissionRow(line: $0) }
            }
            if !review.cautions.isEmpty, review.tone == .goodToKnow { InstallCautionBox(cautions: review.cautions, tone: .goodToKnow) }
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "After you install").accessibilityAddTraits(.isHeader)
                ForEach(review.next, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.fill").font(.system(size: 4)).foregroundStyle(Theme.inkFaint).offset(y: -3).accessibilityHidden(true)
                        Text(verbatim: line).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !preview.toolNames.isEmpty || !preview.watcherNames.isEmpty || !preview.pageNames.isEmpty {
                // What it adds is long for a big extension and isn't a permission: folded, one click away.
                DisclosureGroup(isExpanded: $showsAdds) {
                    adds.padding(.top, 4)
                } label: {
                    Eyebrow(text: "It adds")
                }
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What went wrong, if anything, and the choice: always in sight, whatever the sheet holds.
    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
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
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }

    /// The details' height before they scroll. A sheet hangs from just under its window's toolbar, so its room is
    /// from there down to the Dock, less the buttons and a margin; a window of its own gets the screen's height.
    private static var roomForDetails: CGFloat {
        let screen = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let top = NSApp.keyWindow.map { min($0.frame.maxY, screen.maxY) - 90 } ?? screen.maxY
        return max(280, top - screen.minY - 150)
    }

    private var review: InstallReview { preview.review }

    private var adds: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !preview.toolNames.isEmpty {
                Text(ExtensionWords.tools(preview.toolNames)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            if !preview.watcherNames.isEmpty {
                Text(ExtensionWords.watchers(preview.watcherNames)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            if !preview.pageNames.isEmpty {
                Text(ExtensionWords.pages(preview.pageNames, background: preview.pagesInBackground))
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            if !preview.commands.isEmpty {
                Text(ExtensionWords.commands(preview.commands)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finish() {
        if let close { close() } else { dismiss() }
    }

    private var origin: Text {
        // A gallery download sits in a temporary folder whose path means nothing; a folder's path says which one.
        guard review.source == .folder else { return Text("Version \(preview.version)") }
        return Text("Version \(preview.version) · from \(FolderAccess.displayPath(preview.sourceFolder.path))")
    }
}
