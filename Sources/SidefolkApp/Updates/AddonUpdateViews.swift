import SidefolkCore
import SwiftUI

// Add-on updates wherever add-ons appear (D89), all from `UpdateModel` (kept by `AddonUpdateController`): the Gallery's
// Updates, a row's inline "New version", an extension page's strip, Today's one row. Their buttons ask the controller,
// which updates by D70's rule: what asks for nothing new installs, what would let an extension do more opens its sheet.

enum AddonUpdateWords {
    /// "Version 1.0.0 snapshot 5".
    static func version(_ entry: AddonEntry) -> String {
        String(localized: "Version \(ReleaseVersion(entry.version)?.shown ?? entry.version)",
               comment: "An add-on's new version: “Version 1.0.0 snapshot 5”")
    }

    static func kind(_ entry: AddonEntry) -> String {
        switch entry.kind {
        case .companion: String(localized: "Companion", comment: "An add-on's kind, in its update row")
        case .extension: String(localized: "Extension", comment: "An add-on's kind, in its update row")
        case .theme: String(localized: "Theme", comment: "An add-on's kind, in its update row")
        }
    }

    static func symbol(_ kind: AddonEntry.Kind) -> String {
        switch kind {
        case .companion: "face.smiling"
        case .extension: "puzzlepiece.extension"
        case .theme: "paintpalette"
        }
    }

    /// The line under an update's name: its version, why it waits for a look, or what went wrong.
    /// `kind` names what it is ("Theme · Version 1.1.0") where rows of every kind sit together.
    @MainActor static func meta(_ entry: AddonEntry, _ updates: UpdateModel, kind showsKind: Bool = true) -> Text {
        if case .failed(let why)? = updates.addonSteps[entry.id] { return Text(verbatim: why).foregroundStyle(Theme.danger) }
        if updates.addonNeedsReview(entry.id) {
            return Text("\(version(entry)) asks for more. Review shows what's new.",
                        comment: "An extension update waiting for review: “Version 1.1.0 asks for more. Review shows what's new.”")
        }
        return Text(verbatim: showsKind ? kind(entry) + " · " + version(entry) : version(entry))
    }

    /// "2 add-on updates": Today's row, the Pocket's.
    static func count(_ n: Int) -> String {
        String(localized: "\(n) add-on updates", comment: "Today and the Pocket: “2 add-on updates”")
    }
}

/// One add-on's update control: Update, Review… when its new version would do more, its progress, Updated, or Try
/// again with what went wrong.
struct AddonUpdateButton: View {
    var entry: AddonEntry
    var updates: UpdateModel
    var size: SFButtonStyle.Size = .small

    var body: some View {
        let name = entry.shownName
        switch updates.addonSteps[entry.id] {
        case .updating?:
            HStack(spacing: Theme.Space.xs) {
                ProgressView().controlSize(.small)
                Text("Updating…", comment: "An add-on's update row while it installs").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            .accessibilityElement(children: .combine)
        case .updated?:
            Label { Text("Updated", comment: "An add-on's update row once it installed") } icon: { Image(systemName: "checkmark") }
                .font(Theme.Font.caption).foregroundStyle(Theme.success)
        case .failed(let why)?:
            Button("Try again") { updates.addonActions?.update(entry) }.buttonStyle(.sf(.secondary, size: size))
                .help(Text(verbatim: why))
                .accessibilityLabel(Text("Try updating \(name) again", comment: "After an add-on's update failed"))
        case .needsReview?, nil:
            if updates.addonNeedsReview(entry.id) {
                Button("Review…") { updates.addonActions?.review(entry) }.buttonStyle(.sf(.secondary, size: size))
                    .accessibilityLabel(Text("Review \(name)'s update", comment: "An update that would let an extension do more"))
            } else {
                Button("Update") { updates.addonActions?.update(entry) }.buttonStyle(.sf(.secondary, size: size))
                    .disabled(updates.addonsBusy)
                    .accessibilityLabel(Text("Update \(name)", comment: "A button in the add-on gallery"))
            }
        }
    }
}

/// The Gallery's Updates, at its top (D89): every update that waits, Update all for those that ask for nothing new,
/// each row's progress, and what the last Update all did.
struct AddonUpdatesSection: View {
    var updates: UpdateModel
    var gallery: AddonGalleryModel

    var body: some View {
        let rows = updates.addonRows
        if !rows.isEmpty {
            SectionHeader(title: Text("Updates", comment: "The Gallery's section of add-on updates"), count: updates.addonPending.count,
                          detail: updates.addonSummary.map { Text(verbatim: $0) }) {
                if !updates.addonInstallable.isEmpty {
                    Button("Update all") { updates.addonActions?.updateAddonsNow() }
                        .buttonStyle(.sf(.primary, size: .regular, working: updates.addonsBusy))
                        .disabled(updates.addonsBusy)
                }
            }
            RowsCard {
                ForEach(rows) { entry in
                    ListRow(title: Text(verbatim: entry.shownName), meta: AddonUpdateWords.meta(entry, updates)) {
                        AddonUpdateIcon(url: gallery.preview(entry), kind: entry.kind, size: 32)
                    } trailing: {
                        AddonUpdateButton(entry: entry, updates: updates)
                    }
                }
            }
        }
    }
}

/// An add-on's picture from the gallery, or its kind's symbol on a tinted squircle.
struct AddonUpdateIcon: View {
    var url: URL?
    var kind: AddonEntry.Kind
    var size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: AddonUpdateWords.symbol(kind)).font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Theme.link)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accentSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) { image = await GalleryPicture.load(url, side: size * 2) }
    }
}

/// "New version 1.1.0 · Update" beside a row's switch in Settings › Add-ons (D89).
struct AddonUpdateInline: View {
    var entry: AddonEntry
    var updates: UpdateModel

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if updates.addonSteps[entry.id] == nil {
                Text("New version \(ReleaseVersion(entry.version)?.shown ?? entry.version)",
                     comment: "Settings › Add-ons, beside an extension's switch: “New version 1.1.0”")
                    .font(Theme.Font.caption).foregroundStyle(Theme.link).lineLimit(1)
            }
            AddonUpdateButton(entry: entry, updates: updates)
        }
        .fixedSize()
    }
}

/// "Update available" at the top of an extension's page (D89), with What's new: the install sheet, which says what
/// the new version changes (its permissions and tools, D71) and installs it from there.
struct AddonUpdateStrip: View {
    var entry: AddonEntry
    var updates: UpdateModel

    var body: some View {
        WrapRow(minimum: 300, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.link).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available", comment: "An extension's page: a newer version is in the gallery")
                        .font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    AddonUpdateWords.meta(entry, updates, kind: false).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Theme.Space.s) {
                if !updates.addonNeedsReview(entry.id), updates.addonSteps[entry.id] == nil {
                    Button("What's new") { updates.addonActions?.review(entry) }.buttonStyle(.sf(.quiet, size: .regular))
                }
                AddonUpdateButton(entry: entry, updates: updates, size: .regular)
            }
            .fixedSize()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contrastEdge(radius: Theme.Radius.card)
        .accessibilityElement(children: .contain)
    }
}

/// Today's one row about add-on updates (D89): how many, their names, Update all and Show; never a card each.
struct AddonUpdatesTodayRow: View {
    var updates: UpdateModel

    var body: some View {
        let pending = updates.addonPending
        if !pending.isEmpty {
            RowsCard {
                ListRow(title: Text(verbatim: AddonUpdateWords.count(pending.count)),
                        meta: Text(verbatim: updates.addonSummary ?? Wording.list(pending.map(\.shownName)))) {
                    AddonUpdateIcon(url: nil, kind: .extension, size: 28).overlay {
                        Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.onAccent)
                            .frame(width: 13, height: 13).background(Theme.accent, in: Circle())
                            .offset(x: 10, y: 10)
                    }
                } trailing: {
                    HStack(spacing: Theme.Space.s) {
                        if !updates.addonInstallable.isEmpty {
                            Button("Update all") { updates.addonActions?.updateAddonsNow() }
                                .buttonStyle(.sf(.secondary, size: .small, working: updates.addonsBusy)).disabled(updates.addonsBusy)
                        }
                        Button("Show", action: { updates.addonActions?.showAddonUpdates() })
                            .buttonStyle(.sf(.quiet, size: .small))
                            .accessibilityLabel(Text("Show add-on updates", comment: "Today: opens the Gallery's Updates"))
                    }
                    .fixedSize()
                }
            }
        }
    }
}

/// The small mark on an extension's row in Home's sidebar: a newer version waits (D89).
struct AddonUpdateDot: View {
    var body: some View {
        Circle().fill(Theme.accent).frame(width: 7, height: 7)
            .help(Text("Update available", comment: "An extension's page: a newer version is in the gallery"))
            .accessibilityLabel(Text("Update available", comment: "An extension's page: a newer version is in the gallery"))
    }
}
