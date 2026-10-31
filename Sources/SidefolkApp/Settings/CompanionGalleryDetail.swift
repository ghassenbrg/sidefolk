import SidefolkCore
import SwiftUI

/// A gallery companion up close (D77): its picture large, who made it, its version, size and looks,
/// what it is like, where it comes from, and Get or Wear, with the download's progress in place.
struct CompanionGalleryDetail: View {
    var entry: AddonEntry
    var model: SettingsModel
    @Environment(\.dismiss) private var dismiss
    private var chooser: CompanionChooserModel { model.chooser }

    var body: some View {
        let state = chooser.state(entry)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                GalleryPicture(url: chooser.preview(entry), side: 168)
                    .padding(Theme.Space.s)
                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(spacing: 6) {
                        Text(verbatim: entry.name).font(Theme.Font.title).foregroundStyle(Theme.ink)
                        if entry.official { OfficialSeal(size: 15) }
                    }
                    Text(verbatim: CompanionChooserModel.tagline(entry)).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                    facts.padding(.top, Theme.Space.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !entry.description.isEmpty {
                Text(verbatim: entry.description).font(Theme.Font.body).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label {
                Text("From the Sidefolk gallery · Signed by Sidefolk and checked before install",
                     comment: "Where a gallery companion comes from, in its details")
            } icon: {
                Image(systemName: "checkmark.shield")
            }
            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            if let failure = model.gallery.failures[entry.id] { InlineError(error: failure) }
            buttons(state)
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
        .background(Theme.surface)
    }

    /// Who made it, its version and size, its looks.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 4) {
            fact("person", Text("By \(entry.author)", comment: "A gallery companion's maker, in its details"))
            fact("number", Text("Version \(entry.version)", comment: "A gallery companion's version, in its details"))
            fact("arrow.down.circle", Text(verbatim: ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)))
            fact("cube", entry.looks.contains(.twoD)
                 ? Text("Comes in 3D and 2D", comment: "A gallery companion's looks, in its details")
                 : Text("Comes in 3D", comment: "A gallery companion's looks, in its details"))
        }
    }

    private func fact(_ systemImage: String, _ text: Text) -> some View {
        Label { text } icon: { Image(systemName: systemImage).frame(width: 16) }
            .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
    }

    @ViewBuilder private func buttons(_ state: CompanionChooserModel.EntryState) -> some View {
        HStack(spacing: Theme.Space.s) {
            switch state {
            case .working(let p):
                ProgressView(value: max(p, 0.02)).progressViewStyle(.linear).frame(width: 140)
                Text("Downloading…", comment: "A gallery companion's details while it downloads").font(Theme.Font.caption)
                    .foregroundStyle(Theme.inkMuted)
            case .wearing:
                Label("Wearing", systemImage: "checkmark.circle.fill").font(Theme.Font.captionStrong).foregroundStyle(Theme.accent)
            case .owned, .update:
                Label("On this Mac", systemImage: "checkmark").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            case .get:
                EmptyView()
            }
            Spacer()
            Button("Close") { dismiss() }.buttonStyle(.sf(.secondary)).keyboardShortcut(.cancelAction)
            switch state {
            case .get:
                Button("Get") { chooser.get(entry, wear: false) }.buttonStyle(.sf(.secondary))
                Button("Get and Wear") { chooser.get(entry, wear: true) }.buttonStyle(.sf(.primary)).keyboardShortcut(.defaultAction)
            case .update:
                Button("Update") { chooser.update(entry) }.buttonStyle(.sf(.secondary))
                Button("Wear") { chooser.get(entry, wear: true) }.buttonStyle(.sf(.primary)).keyboardShortcut(.defaultAction)
            case .owned:
                Button("Wear") { chooser.get(entry, wear: true) }.buttonStyle(.sf(.primary)).keyboardShortcut(.defaultAction)
            case .wearing, .working:
                EmptyView()
            }
        }
    }
}
