import SidefolkCore
import SwiftUI

// The pieces of the install sheet (D71): where it comes from first, then what it may do with what guards each
// thing, the risky combinations in a tone set by the source, and what happens after Install.

/// Where the extension comes from, as a row of its own: the first thing to know, not a word in the subtitle.
struct InstallSourceRow: View {
    var source: InstallSource

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                .frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                title.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        switch source {
        case .gallery: Text("From the Sidefolk gallery", comment: "Install sheet: where an extension comes from")
        case .draft: Text("Written by Sidefolk for you", comment: "Install sheet: an extension Sidefolk's AI wrote at the person's request")
        case .folder: Text("From a folder on this Mac", comment: "Install sheet: where an extension comes from")
        }
    }

    private var detail: Text {
        switch source {
        case .gallery: Text("Signed by Sidefolk and checked before install")
        case .draft: Text("Sidefolk's AI wrote it at your request, and nobody else has read its code. You can read its files first.")
        case .folder: Text("Not checked by Sidefolk: install it only if you trust who made it.")
        }
    }

    private var symbol: String {
        switch source {
        case .gallery: "checkmark.seal.fill"
        case .draft: "sparkles"
        case .folder: "folder.badge.questionmark"
        }
    }

    private var color: Color {
        switch source {
        case .gallery: Theme.success
        case .draft: Theme.folkColor("byte")
        case .folder: Theme.inkMuted
        }
    }

    private var tint: Color {
        switch source {
        case .gallery: Theme.successSoft
        case .draft: Theme.accentSoft
        case .folder: ChipTone.warning.tint
        }
    }
}

/// The risky combinations: the same sentences for every source, strong for code Sidefolk didn't sign as its
/// own, calm for its own. The heading says which, so VoiceOver reads the level before the facts.
struct InstallCautionBox: View {
    var cautions: [String]
    var tone: InstallReview.Tone

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Eyebrow(careful ? Text("Read this before installing") : Text("Good to know", comment: "Install sheet: facts about a signed extension from Sidefolk"),
                    color: careful ? Theme.danger : Theme.inkMuted)
                .accessibilityAddTraits(.isHeader)
            ForEach(cautions, id: \.self) { caution in
                Label {
                    Text(verbatim: caution).font(careful ? Theme.Font.bodyStrong : Theme.Font.body).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: careful ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(careful ? Theme.danger : Theme.inkMuted).accessibilityHidden(true)
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(careful ? Theme.dangerSoft : Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var careful: Bool { tone == .careful }
}

/// What an update changes. One that asks for more stays prominent whoever signed it.
struct InstallUpdateBox: View {
    var update: InstallReview.Update
    var tone: InstallReview.Tone

    var body: some View {
        if update.widens {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Eyebrow(Text("This update asks for more"), color: Theme.ink).accessibilityAddTraits(.isHeader)
                Text(verbatim: update.line).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                ForEach(update.added, id: \.self) { line in
                    Label {
                        Text("New permission: \(line)").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(tone == .careful ? Theme.danger : Theme.ink).accessibilityHidden(true)
                    }
                }
                removed
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone == .careful ? Theme.dangerSoft : ChipTone.warning.tint,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .accessibilityElement(children: .contain)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text("\(update.line) No new permissions.", comment: "Install sheet: “Updates 1.0 to 1.1.” then this").fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath").accessibilityHidden(true)
                }
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                removed
            }
        }
    }

    @ViewBuilder private var removed: some View {
        ForEach(update.removed, id: \.self) { line in
            Label(String(localized: "Removed permission: \(line)"), systemImage: "minus").labelStyle(BulletLabelStyle())
        }
    }
}

/// One thing it may do, with what keeps it in check underneath when Sidefolk or macOS enforces something.
struct InstallPermissionRow: View {
    var line: PermissionSummary.Line

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.text).font(Theme.Font.body).foregroundStyle(Theme.ink)
                if let note = line.note {
                    Text(verbatim: note).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.folkColor("guard")).frame(width: 18).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch line.kind {
        case .network: "network"
        case .read: "folder"
        case .write: "folder.badge.gearshape"
        case .exec: "terminal"
        case .media: "photo"
        case .clipboard: "doc.on.clipboard"
        case .power: "bolt"
        case .screen: "rectangle.on.rectangle"
        case .udp: "dot.radiowaves.left.and.right"
        case .none: "lock"
        case .unsandboxed: "exclamationmark.triangle"
        }
    }
}
