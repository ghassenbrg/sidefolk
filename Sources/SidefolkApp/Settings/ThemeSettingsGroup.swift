import AppKit
import SidefolkCore
import SwiftUI

/// Settings › General › Theme (D58): the themes on this Mac as small previews, and a theme of your own, made in a
/// folder Sidefolk follows: each save repaints every window, and what's wrong is said here, in words.
struct ThemeSettingsGroup: View {
    var model: SettingsModel
    @State private var themes: [InstalledTheme] = []
    @State private var removing: InstalledTheme?
    @State private var error: UserFacingError?

    private var library: ThemeLibrary { .app(model.runtime.paths) }
    private var shown: ThemeTokens { ThemeStore.shared.style.tokens }

    var body: some View {
        SettingsGroup(title: "Theme", footer: "A theme changes colours, type, spacing and corners. It can't run anything.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                ForEach(themes, id: \.id) { theme in
                    ThemeCard(tokens: theme.tokens, selected: theme.id == shown.id) { use(theme) }
                        .contextMenu {
                            if theme.folder != nil {
                                Button("Remove “\(theme.tokens.name)”…") { removing = theme }
                            }
                        }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            gallery
            suggestion
            following
            SettingsRow(title: "Make your own",
                        detail: "Start from a copy of Harbor in a folder, or use a theme folder you have. Sidefolk repaints each time you save.") {
                // Side by side where they fit; stacked in longer languages and larger theme type.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.s) { makeButtons }
                    VStack(alignment: .trailing, spacing: Theme.Space.xs) { makeButtons }
                }
            }
            if let error { InlineError(error: error).padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s) }
        }
        .onAppear(perform: reload)
        .task { if model.gallery.available { await model.gallery.load() } }
        .onChange(of: model.gallery.progress.isEmpty) { reload() }
        .onChange(of: shown.id) { reload() }
        .confirmationDialog(Text("Remove “\(removing?.tokens.name ?? "")”?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) { if let removing { remove(removing) } }
        } message: {
            Text("Sidefolk's copy goes away; the folder you made it in stays where it is.")
        }
    }

    // MARK: Parts

    /// Themes in the add-on gallery not on this Mac yet, or with a newer version (D55): a click gets one and wears it.
    @ViewBuilder private var gallery: some View {
        let offered = model.gallery.entries(.theme).filter { entry in
            if case .installed = model.gallery.state(entry) { false } else { true }
        }
        if !offered.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Eyebrow(Text("From the gallery"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                    ForEach(offered) { entry in GalleryThemeCard(entry: entry, model: model.gallery) }
                }
                ForEach(offered.compactMap { model.gallery.failures[$0.id] }, id: \.message) { InlineError(error: $0) }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.m)
        }
        if model.gallery.hidesSnapshots(.theme) {
            RowsCard { SnapshotsHiddenNote(gallery: model.gallery) }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.m)
        }
    }

    @ViewBuilder private var makeButtons: some View {
        Button("Start a Theme…", action: startTheme).buttonStyle(.sf(.secondary)).fixedSize()
        Button("Load from Folder…", systemImage: "folder", action: chooseFolder).buttonStyle(.sf(.secondary)).fixedSize()
    }

    /// The theme was drawn with a companion in mind: offered, never chosen for the person.
    @ViewBuilder private var suggestion: some View {
        if let choice = shown.nook.suggests, choice != model.settings.companion || model.settings.customCompanion != nil
            || model.settings.localCompanion != nil {
            let entry = model.gallery.entries(.companion).first { $0.companion == choice.rawValue }
            if CompanionArt.offered.contains(choice) || entry != nil {
                SettingsRow(title: Text("\(shown.name) was drawn for \(choice.defaultName)"),
                            detail: Text("Your companion stays yours unless you switch.")) {
                    Button("Use \(choice.defaultName)") {
                        if CompanionArt.offered.contains(choice) {
                            model.update { $0.choose(choice) }
                        } else if let entry {
                            Task { await model.gallery.get(companion: entry, choose: true) }
                        }
                    }
                    .buttonStyle(.sf(.secondary))
                }
            }
        }
    }

    /// The folder being followed, and what its last check said.
    @ViewBuilder private var following: some View {
        if let path = model.settings.themeFolder {
            SettingsRow(title: Text("Following your theme folder"), detail: Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)) {
                HStack(spacing: Theme.Space.s) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path).appendingPathComponent("theme.json")])
                    }
                    .buttonStyle(.sf(.plain))
                    Button("Stop Following") { model.update { $0.themeFolder = nil } }.buttonStyle(.sf(.secondary))
                }
            }
            if let report = ThemeStore.shared.folderReport, !report.problems.isEmpty {
                ThemeProblems(report: report).padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.m)
            }
        }
    }

    // MARK: Actions

    private func reload() { themes = library.all() }

    private func use(_ theme: InstalledTheme) {
        error = nil
        model.update {
            $0.theme = theme.id
            $0.themeFolder = nil
        }
    }

    private func remove(_ theme: InstalledTheme) {
        do {
            if theme.id == shown.id { use(themes[0]) }
            try library.remove(id: theme.id)
            reload()
        } catch {
            self.error = error as? UserFacingError ?? UserFacingError("The theme couldn't be removed.")
        }
    }

    /// Follows the folder: the app checks it, uses it when it can, and keeps watching for saves.
    private func follow(_ folder: URL) {
        error = nil
        model.update { $0.themeFolder = folder.path }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Use Theme")
        panel.message = String(localized: "Choose a folder with a theme.json. Sidefolk checks it, copies it and follows your changes.")
        Task {
            guard await run(panel) == .OK, let url = panel.url else { return }
            follow(url)
        }
    }

    private func startTheme() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "My Theme", comment: "The folder name a new theme starts with")
        panel.prompt = String(localized: "Start Theme")
        panel.message = String(localized: "Sidefolk makes a folder with a copy of Harbor and a short guide, then follows it.")
        Task {
            guard await run(panel) == .OK, let url = panel.url else { return }
            do {
                let folder = try ThemeLibrary.start(url.lastPathComponent, at: url)
                follow(folder)
                NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent("theme.json")])
            } catch {
                self.error = error as? UserFacingError ?? UserFacingError("The theme folder couldn't be made.")
            }
        }
    }

    private func run(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        if let window = NSApp.keyWindow { await panel.beginSheetModal(for: window) } else { panel.runModal() }
    }
}

/// A theme as a small window: its sidebar, a card with its accent, and its name in its own display face.
private struct ThemeCard: View {
    var tokens: ThemeTokens
    var selected: Bool
    var action: () -> Void

    var body: some View {
        let c = tokens.colors
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Circle().fill(Color(c.accent)).frame(width: 8, height: 8)
                        ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color(c.inkFaint).opacity(0.5)).frame(width: 18, height: 3) }
                    }
                    .padding(6)
                    .frame(width: 34, height: 64, alignment: .topLeading)
                    .background(Color(c.surface))
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color(c.ink)).frame(width: 40, height: 4)
                        RoundedRectangle(cornerRadius: min(tokens.radius.card, 10) / 2, style: .continuous)
                            .fill(Color(c.surfaceRaised))
                            .overlay(alignment: .leading) {
                                HStack(spacing: 4) {
                                    Capsule().fill(Color(c.accent)).frame(width: 14, height: 6)
                                    Capsule().fill(Color(c.inkMuted).opacity(0.6)).frame(width: 30, height: 3)
                                }
                                .padding(.horizontal, 5)
                            }
                            .overlay { RoundedRectangle(cornerRadius: min(tokens.radius.card, 10) / 2, style: .continuous).strokeBorder(Color(c.line)) }
                            .frame(height: 22)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(c.surfaceSunken))
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1)
                }
                HStack(spacing: Theme.Space.xxs) {
                    Text(verbatim: tokens.name).font(.system(size: 12, weight: .semibold, design: design)).foregroundStyle(Theme.ink)
                    if selected { Image(systemName: "checkmark.circle.fill").imageScale(.small).foregroundStyle(Theme.link) }
                }
                .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tokens.name))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var design: Font.Design {
        switch tokens.type.display {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        }
    }
}

/// What the last check of a theme folder said: errors keep it from being used, warnings were fixed on the way in.
/// The words are the check's own, as `sidefolk theme check` prints them, since they name the file's keys.
struct ThemeProblems: View {
    var report: ThemeReport

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Label(report.isUsable ? "Used, with these fixed on the way in:" : "Not used yet. The last theme that worked stays on.",
                  systemImage: report.isUsable ? "exclamationmark.circle" : "xmark.octagon")
                .font(Theme.Font.captionStrong)
                .foregroundStyle(report.isUsable ? Theme.inkMuted : Theme.danger)
            ForEach(Array(report.problems.enumerated()), id: \.offset) { _, problem in
                Text(verbatim: "• \(problem.message)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(problem.level == .error ? Theme.danger : Theme.inkMuted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.s)
        .background(report.isUsable ? Theme.surfaceSunken : Theme.dangerSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

/// A theme in the gallery: its picture, name and line, and what a click does (get it, update it, or how far along).
private struct GalleryThemeCard: View {
    var entry: AddonEntry
    var model: AddonGalleryModel

    var body: some View {
        let state = model.state(entry)
        Button {
            Task { await model.get(theme: entry, use: true) }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Group {
                    if let url = model.preview(entry), let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Theme.surfaceSunken
                    }
                }
                .frame(height: 64).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line))
                HStack {
                    Text(verbatim: entry.name).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: Theme.Space.xs)
                    switch state {
                    case .working(let p): ProgressView(value: max(p, 0.02)).progressViewStyle(.linear).frame(width: 44)
                    case .update(let from): Text("Update from \(from)").font(Theme.Font.caption).foregroundStyle(Theme.link)
                    default: Label("Get", systemImage: "arrow.down.circle").font(Theme.Font.caption).foregroundStyle(Theme.link)
                    }
                }
                Text(verbatim: entry.tagline).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled({ if case .working = state { true } else { false } }())
        .accessibilityLabel(Text(verbatim: "\(entry.name), \(entry.tagline)"))
        .accessibilityHint(Text("Downloads it and uses it"))
    }
}
