import AppKit
import SidefolkCore
import SwiftUI

/// Every companion the person can wear, in one grid (D77): Sidefolk's own, the gallery's, those made
/// from data and those added from a folder, each saying where it came from and in which look it is worn, with a
/// visible "…" menu (also its context menu) for what applies to it. After them, Add your own and the way to the
/// gallery. A click wears one, at once on the desktop.
struct CompanionGrid: View {
    var model: SettingsModel
    private var chooser: CompanionChooserModel { model.chooser }
    private var gallery: AddonGalleryModel { model.gallery }

    var body: some View {
        let owned = chooser.owned
        let worn = chooser.worn(in: owned)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                ForEach(owned) { companion in
                    let wearing = companion.wear == worn
                    CompanionTile(companion: companion, picture: picture(companion), wearing: wearing, look: look(companion),
                                  actions: chooser.actions(for: companion, worn: wearing)) { action in
                        chooser.perform(action, on: companion)
                    }
                }
                AddCompanionTile(model: model)
                if gallery.available { MoreCompanionsTile(count: chooser.notYetHere) { chooser.page = .gallery } }
            }
            ForEach(owned.compactMap { $0.galleryID.flatMap { gallery.failures[$0] } }, id: \.message) { InlineError(error: $0) }
            if let error = gallery.companionError { InlineError(error: error) }
            ForEach(chooser.unreadable, id: \.name) { broken in
                Label {
                    Text("“\(broken.name)” in your companions folder can't be used: \(broken.reason)",
                         comment: "Under the companions in Settings: a made-by-you folder with a problem, and the problem")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, Theme.Space.xs)
            }
        }
        .alert(removalTitle, isPresented: Binding(get: { chooser.removing != nil }, set: { if !$0 { chooser.removing = nil } }),
               presenting: chooser.removing) { companion in
            Button(companion.origin == .made ? "Move to Trash" : "Remove", role: .destructive) {
                Task { await chooser.remove(companion) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { companion in
            Text(verbatim: removalMessage(companion, worn: companion.wear == worn, owned: owned))
        }
    }

    private func picture(_ companion: OwnedCompanion) -> NSImage? {
        if let still = CompanionArt.still(companion, settings: model.settings, side: 84) { return still }
        // One worn by name whose still isn't here yet: its picture in the gallery.
        guard let id = companion.galleryID, let url = gallery.catalog?.entry(id).flatMap(gallery.preview) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func look(_ companion: OwnedCompanion) -> CompanionDimension {
        if case .choice(let choice) = companion.wear { return CompanionArt.threeD(choice, in: model.settings) ? .threeD : .twoD }
        return companion.looks.first ?? .threeD
    }

    // MARK: Removing

    private var removalTitle: String { chooser.removing.map(CompanionRemovalWords.title) ?? "" }

    private func removalMessage(_ companion: OwnedCompanion, worn: Bool, owned: [OwnedCompanion]) -> String {
        CompanionRemovalWords.message(companion, actions: chooser.actions(for: companion, worn: worn),
                                      replacement: CompanionLibrary.replacement(removing: companion, in: model.settings, owned: owned),
                                      owned: owned)
    }
}

/// What the confirmation before removing a companion says: what goes, whether it can come back, and who takes its
/// place on the desktop.
enum CompanionRemovalWords {
    static func title(_ companion: OwnedCompanion) -> String {
        companion.origin == .made
            ? String(localized: "Move “\(companion.name)” to the Trash?", comment: "Confirming the removal of a companion made from data")
            : String(localized: "Remove “\(companion.name)”?", comment: "Confirming the removal of a companion")
    }

    static func message(_ companion: OwnedCompanion, actions: [CompanionAction], replacement: CompanionChoice?,
                        owned: [OwnedCompanion]) -> String {
        let name = companion.name
        let removal = actions.lazy.compactMap { action -> CompanionRemoval? in if case .remove(let r) = action { r } else { nil } }.first
        let what: String = switch removal {
        case .download(again: true)?:
            String(localized: "\(name)'s files are removed from this Mac. You can download it again from the gallery at any time.",
                   comment: "Removing a companion the gallery still has")
        case .download(again: false)?:
            String(localized: "\(name)'s files are removed from this Mac. It isn't in the gallery now, so you may not be able to download it again.",
                   comment: "Removing a companion the gallery no longer offers")
        case .copy?:
            String(localized: "The copy Sidefolk made of \(name) is removed. The folder you added it from isn't touched: add it again from there at any time.",
                   comment: "Removing a 3D companion added from a folder")
        case .trash?:
            String(localized: "Its folder goes to the Trash, where you can put it back.",
                   comment: "Moving a companion made from data to the Trash")
        case nil: ""
        }
        guard let replacement else { return what }
        let stand = owned.first { $0.wear == .choice(replacement) }?.name ?? replacement.defaultName
        return what + " " + String(localized: "\(stand) takes its place on your desktop.",
                                   comment: "Removing the companion worn now: who is worn instead")
    }
}

/// One companion: its still in the look it is worn in, its name, where it came from, and its "…" menu.
private struct CompanionTile: View {
    var companion: OwnedCompanion
    var picture: NSImage?
    var wearing: Bool
    var look: CompanionDimension
    var actions: [CompanionAction]
    var perform: (CompanionAction) -> Void

    private var update: String? {
        actions.lazy.compactMap { action -> String? in if case .update(let version) = action { version } else { nil } }.first
    }

    var body: some View {
        Button { if !wearing { perform(.wear) } } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let picture {
                            Image(nsImage: picture).resizable().scaledToFit()
                        } else {
                            Circle().fill(Theme.surfaceSunken).padding(8)
                        }
                    }
                    .frame(width: 84, height: 84)
                    LookChip(look: look)
                }
                Text(verbatim: companion.name).font(wearing ? Theme.Font.bodyStrong : Theme.Font.body).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(verbatim: CompanionWords.origin(companion.origin)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity)
            .background(wearing ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(wearing ? Theme.accent : Theme.line, lineWidth: wearing ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(companion.tagline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [companion.name, companion.tagline, CompanionWords.origin(companion.origin),
                                            look == .threeD ? "3D" : "2D"].filter { !$0.isEmpty }.joined(separator: ", ")))
        .accessibilityAddTraits(wearing ? [.isButton, .isSelected] : .isButton)
        .accessibilityActions { CompanionMenuItems(companion: companion, actions: actions, perform: perform) }
        .contextMenu { CompanionMenuItems(companion: companion, actions: actions, perform: perform) }
        .overlay(alignment: .topTrailing) {
            Menu { CompanionMenuItems(companion: companion, actions: actions, perform: perform) } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 22, height: 22)
                    .background(Theme.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.line))
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(Theme.Space.xs)
            .help(Text("What you can do with \(companion.name)", comment: "The … button on a companion in Settings"))
            .accessibilityLabel(Text("More for \(companion.name)", comment: "The … button on a companion in Settings"))
        }
        .overlay(alignment: .topLeading) {
            if let update {
                Button { perform(.update(version: update)) } label: {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(Theme.Space.xs)
                .help(Text("Update \(companion.name) to \(update)", comment: "A companion's menu: install the gallery's newer version"))
                .accessibilityLabel(Text("Update \(companion.name) to \(update)", comment: "A companion's menu: install the gallery's newer version"))
            }
        }
    }
}

/// "3D" or "2D" in a corner of a companion's picture: the look it is worn in.
private struct LookChip: View {
    var look: CompanionDimension

    var body: some View {
        Text(verbatim: look == .threeD ? "3D" : "2D")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Theme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))
            .accessibilityHidden(true)
    }
}

/// The items of a companion's "…" menu and context menu: only what applies, and why Remove isn't there when it isn't.
struct CompanionMenuItems: View {
    var companion: OwnedCompanion
    var actions: [CompanionAction]
    var perform: (CompanionAction) -> Void

    var body: some View {
        ForEach(actions, id: \.self) { action in
            switch action {
            case .wear:
                Button("Wear \(companion.name)", systemImage: "checkmark.circle") { perform(action) }
            case .update(let version):
                Button("Update to \(version)", systemImage: "arrow.down.circle") { perform(action) }
            case .showInFinder:
                Button("Show in Finder", systemImage: "folder") { perform(action) }
            case .remove(let removal):
                Divider()
                Button(removal == .trash ? "Move to Trash…" : "Remove…", systemImage: "trash", role: .destructive) { perform(action) }
            case .keep(let keep):
                Divider()
                Button(keep == .builtIn ? "Comes with Sidefolk: can't be removed" : "Comes with an extension: remove the extension instead",
                       systemImage: "lock") {}
                    .disabled(true)
            }
        }
    }
}

/// Where a companion came from, in words.
enum CompanionWords {
    static func origin(_ origin: OwnedCompanion.Origin) -> String {
        // Their own keys: one companion's words, which other languages agree with it (“Built in” elsewhere is an extension).
        switch origin {
        case .builtIn: String(localized: "companion.origin.builtIn", defaultValue: "Built in",
                              comment: "Where a companion came from: it comes with Sidefolk")
        case .gallery: String(localized: "companion.origin.gallery", defaultValue: "From the gallery",
                              comment: "Where a companion came from: downloaded from the add-on gallery")
        case .made: String(localized: "companion.origin.made", defaultValue: "Made by you",
                           comment: "Where one companion came from: made from data in your companions folder")
        case .folder: String(localized: "companion.origin.folder", defaultValue: "From a folder",
                             comment: "Where a companion came from: a 3D companion added from a folder on this Mac")
        }
    }

    /// Under the worn companion's name: where it came from, with its version and maker when known.
    static func provenance(_ companion: OwnedCompanion) -> String {
        [origin(companion.origin), companion.version, companion.author.map {
            String(localized: "by \($0)", comment: "Who made a companion, after where it came from: “From the gallery · 1.0.0 · by Sidefolk”")
        }].compactMap { $0 }.joined(separator: " · ")
    }
}
