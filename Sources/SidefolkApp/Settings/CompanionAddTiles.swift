import AppKit
import SidefolkCore
import SwiftUI

// The tiles after the person's companions (D77): their own to add, and the gallery's to get.

/// The tile that adds one's own: a popover with each way and one line about it.
struct AddCompanionTile: View {
    var model: SettingsModel

    var body: some View {
        @Bindable var chooser = model.chooser
        Button { chooser.adding = true } label: {
            ActionTileLabel(systemImage: "plus", title: Text("Add Your Own", comment: "The tile after the companions in Settings: add one you made"),
                            detail: Text("3D or 2D", comment: "Under Add Your Own: the kinds of companion you can add"))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $chooser.adding, arrowEdge: .bottom) { AddCompanionOptions(model: model) }
        .accessibilityLabel(Text("Add your own companion", comment: "The Add Your Own tile, for VoiceOver"))
    }
}

/// The ways to add one's own companion, each with what it needs.
struct AddCompanionOptions: View {
    var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            option(systemImage: "cube", title: "A 3D companion",
                   detail: "A folder made like the gallery's: an addon.json, a character file, a model and two pictures.",
                   action: "Choose Folder…", run: chooseFolder)
            Rectangle().fill(Theme.line).frame(height: 1)
            option(systemImage: "scribble.variable", title: "A 2D companion",
                   detail: "A folder with a species.json and SVG shapes, saved in your companions folder. It appears here by itself.",
                   action: "Open Companions Folder", run: openMadeFolder)
        }
        .frame(width: 380)
    }

    private func option(systemImage: String, title: LocalizedStringKey, detail: LocalizedStringKey, action: LocalizedStringKey,
                        run: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: systemImage).font(.system(size: 18)).foregroundStyle(Theme.inkMuted).frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                Button(action, action: run).buttonStyle(.sf(.secondary)).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.l)
    }

    /// The folder of a 3D companion to add: it is checked, and added only once the person agrees (D60, D71).
    private func chooseFolder() {
        model.chooser.adding = false
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose Companion")
        panel.message = String(localized: "Choose a 3D companion's folder: its addon.json, character, model and pictures.")
        Task {
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
            guard response == .OK, let url = panel.url else { return }
            await model.gallery.add(companionFolder: url)
            model.chooser.reload()
        }
    }

    /// `<home>/companions/`, made if it isn't there yet: what is saved in it is read when Sidefolk comes back to the front.
    private func openMadeFolder() {
        model.chooser.adding = false
        let folder = SidefolkPaths.standard().home.appendingPathComponent("companions", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

/// The tile that leads to the gallery, with how many it has that aren't here yet.
struct MoreCompanionsTile: View {
    var count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionTileLabel(systemImage: "square.grid.2x2",
                            title: Text("Get More", comment: "The tile after the companions in Settings: browse the gallery"),
                            detail: count > 0 ? Text("\(count) in the gallery", comment: "Under Get More: how many companions the gallery has that aren't here")
                                              : Text("Browse the gallery", comment: "Under Get More, when nothing new is known yet"))
        }
        .buttonStyle(.plain)
    }
}

/// A dashed tile the size of a companion's, for something to do rather than someone to wear.
private struct ActionTileLabel: View {
    var systemImage: String
    var title: Text
    var detail: Text

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage).font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(width: 84, height: 84)
            title.font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
            detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Theme.Space.xs)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
