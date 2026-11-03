import AppKit
import SidefolkCore
import SwiftUI

extension Attachment {
    /// The words a result shows it came from: dropped text as itself (its label already wears quotes).
    var caption: String {
        if case .text = kind, let text { return text.trimmingCharacters(in: .whitespacesAndNewlines).clipped(60) }
        return label
    }

    /// What was dropped, as the drop card sorts it (D84).
    var dropKind: DropKind {
        switch kind {
        case .url: return .link
        case .text: return .text
        case .file(let url):
            let all = files.isEmpty ? [url] : files
            return all.contains { url in
                var folder: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) && folder.boolValue
            } ? .folder : .file
        }
    }

    /// The dropped files' paths, as the system handed them over.
    var dropFiles: [String] {
        guard case .file(let url) = kind else { return [] }
        return (files.isEmpty ? [url] : files).map(\.path)
    }

    /// What was dropped as an extension's drop action receives it (D100): the address, the path or the words.
    var dropValue: String {
        switch kind {
        case .url(let url): url.absoluteString
        case .file(let url): url.path
        case .text: text ?? label
        }
    }
}

/// The drop card (D84): something dropped on the companion, and four likely things to do with it in a 2×2 grid, each
/// with one plain line of what it does. The first is what Return does while nothing is typed; typing still asks about
/// the item, as a drop always did.
struct DropCard: View {
    var attachment: Attachment
    var choices: [DropChoice]
    /// What extensions offer for it (D100), after Sidefolk's own.
    var offers: [ExtensionDropAction] = []
    var choose: (DropChoice) -> Void
    var chooseOffer: (ExtensionDropAction, ExtensionManifest.DropMeta.MenuItem?) -> Void = { _, _ in }
    var openWith: (URL) -> Void
    var removeFile: () -> Void = {}
    var looks: [String: ExtensionLook] = [:]
    var packPicture: (String, String) async -> NSImage? = { _, _ in nil }

    var body: some View {
        if attachment.dropKind == .file, !offers.isEmpty {
            FileOfferCard(attachment: attachment, choices: choices, offers: offers, chooseOwn: choose, chooseOffer: chooseOffer, openWith: openWith,
                          removeFile: removeFile, looks: looks, packPicture: packPicture)
        } else {
            grid
        }
    }

    @ViewBuilder private var grid: some View {
        let cells = choices.map(Cell.own) + offers.map(Cell.offer)
        Grid(horizontalSpacing: Theme.Space.s, verticalSpacing: Theme.Space.s) {
            ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { row in
                GridRow {
                    ForEach(cells[row..<min(row + 2, cells.count)], id: \.self) { item in
                        switch item {
                        case .own(let choice): cell(choice, first: choice == choices.first)
                        case .offer(let offer): offerCell(offer)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What to do with \(attachment.label)", comment: "VoiceOver: the drop card's four choices"))
    }

    private enum Cell: Hashable {
        case own(DropChoice)
        case offer(ExtensionDropAction)
    }

    /// An extension's offer: its words, and its name under them so it can't pass for Sidefolk's own.
    private func offerCell(_ offer: ExtensionDropAction) -> some View {
        Button { chooseOffer(offer, nil) } label: {
            DropChoiceLabel(symbol: offer.symbol ?? "puzzlepiece.extension", title: Text(ext: offer.title),
                            detail: Text(ext: offer.detail.map { "\($0) · \(offer.extensionName)" } ?? offer.extensionName), first: false)
        }
        .buttonStyle(.sfBare)
    }

    @ViewBuilder private func cell(_ choice: DropChoice, first: Bool) -> some View {
        let words = Self.words(choice, kind: attachment.dropKind)
        if choice == .openWith, case .file(let file) = attachment.kind {
            Menu {
                ForEach(Self.apps(for: file), id: \.self) { app in
                    Button { openWith(app) } label: {
                        Label { Text(verbatim: FileManager.default.displayName(atPath: app.path)) } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        }
                    }
                }
            } label: {
                DropChoiceLabel(symbol: Self.symbol(choice), title: words.title, detail: words.detail, first: first)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.sfBare)
        } else {
            Button { choose(choice) } label: {
                DropChoiceLabel(symbol: Self.symbol(choice, kind: attachment.dropKind), title: words.title, detail: words.detail, first: first)
            }
            .buttonStyle(.sfBare)
        }
    }

    /// The apps that open this file or folder, the default one first, as Finder's Open With has them.
    static func apps(for file: URL) -> [URL] {
        let all = NSWorkspace.shared.urlsForApplications(toOpen: file)
        let main = NSWorkspace.shared.urlForApplication(toOpen: file)
        return Array(([main].compactMap { $0 } + all.filter { $0 != main }).prefix(12))
    }

    static func symbol(_ choice: DropChoice, kind: DropKind = .file) -> String {
        switch choice {
        case .save: kind == .link ? "link.badge.plus" : "square.and.arrow.down"
        case .watch: "eye"
        case .ask: Theme.Symbol.say
        case .openWith: "arrow.up.forward.app"
        case .remind: "alarm"
        case .copy: "doc.on.doc"
        }
    }

    /// The choice's name and one plain line of what it does, by what was dropped.
    static func words(_ choice: DropChoice, kind: DropKind) -> (title: Text, detail: Text) {
        switch (choice, kind) {
        case (.save, .link):
            (Text("Save link", comment: "The drop card: keep a dropped link"),
             Text("Adds it to your Inbox.", comment: "The drop card: what Save link does"))
        case (.save, .text):
            (Text("Save as note"), Text("Keeps the text in your Inbox.", comment: "The drop card: what Save as note does"))
        case (.save, _):
            (Text("Save to notebook"), Text("Notes its name and where it is in your Inbox.", comment: "The drop card: what saving a dropped file does"))
        case (.watch, .link):
            (Text("Watch page", comment: "The drop card: watch a dropped link"),
             Text("Tells you when the page changes.", comment: "The drop card: what Watch page does"))
        case (.watch, .folder):
            (Text("Watch it", comment: "The drop card: watch a dropped file or folder"),
             Text("Tells you when a new file arrives.", comment: "The drop card: what watching a dropped folder does"))
        case (.watch, _):
            (Text("Watch it", comment: "The drop card: watch a dropped file or folder"),
             Text("Tells you when it changes.", comment: "The drop card: what watching a dropped file does"))
        case (.ask, .link):
            (Text("Ask", comment: "The drop card: ask about a dropped link or text"),
             Text("Type a question about the page below.", comment: "The drop card: what Ask does with a link"))
        case (.ask, .text):
            (Text("Ask", comment: "The drop card: ask about a dropped link or text"),
             Text("Type what to do with it below.", comment: "The drop card: what Ask does with dropped text"))
        case (.ask, _):
            (Text("Ask about it", comment: "The drop card: ask about a dropped file or folder"),
             Text("Type a question below. The AI is told where it is.", comment: "The drop card: what Ask about it does with a file"))
        case (.openWith, _):
            (Text("Open with…", comment: "The drop card: open a dropped file in an app"),
             Text("Opens it in an app you pick.", comment: "The drop card: what Open with… does"))
        case (.remind, .text):
            (Text("Remind me"), Text("Asks when, then reminds you of it.", comment: "The drop card: what Remind me does with text"))
        case (.remind, _):
            (Text("Remind me"), Text("Asks when, then reminds you to look at it.", comment: "The drop card: what Remind me does with a link"))
        case (.copy, _):
            (Text("Copy"), Text("Puts the text on the clipboard.", comment: "The drop card: what Copy does"))
        }
    }
}

/// One choice on the drop card: its symbol, its name and what it does; the first carries ↩ and the accent's soft fill.
private struct DropChoiceLabel: View {
    var symbol: String
    var title: Text
    var detail: Text
    var first: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(first ? Theme.link : Theme.inkMuted)
                title.font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
                if first { KeyHint("↩") }
            }
            detail.font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.s + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(first ? Theme.accentSoft : hovering ? Theme.well.opacity(0.8) : Theme.well,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .contrastEdge(radius: Theme.Radius.control)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(first ? Text("Return does this", comment: "VoiceOver: the drop card's first choice is what Return does") : Text(verbatim: ""))
    }
}

/// Files dropped with an extension on offer (D141). Choosing is what lets it read them, so the card is the yes (SECURITY T43): Sidefolk's own
/// words come first and say who reads what, the extension's offers sit apart under its name, nothing is chosen for you, and a
/// click right after the drop doesn't count, because the card opens under a mouse that has just let go.
private struct FileOfferCard: View {
    var attachment: Attachment
    var choices: [DropChoice]
    var offers: [ExtensionDropAction]
    var chooseOwn: (DropChoice) -> Void
    var chooseOffer: (ExtensionDropAction, ExtensionManifest.DropMeta.MenuItem?) -> Void
    var openWith: (URL) -> Void
    var removeFile: () -> Void = {}
    var looks: [String: ExtensionLook] = [:]
    var packPicture: (String, String) async -> NSImage? = { _, _ in nil }
    @State private var ready = FileOfferGuard.skipped
    @State private var showAll = false

    private var names: [String] { attachment.dropFiles.map(DropChoices.shownName) }
    private var groups: [[ExtensionDropAction]] { Dictionary(grouping: offers, by: \.extensionId).values.sorted { $0[0].extensionName < $1[0].extensionName } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if names.count > 1 { fileNames } else { fileRow }
            ForEach(groups, id: \.first?.extensionId) { group in
                if let first = group.first {
                    trust(first)
                    frame(first, group)
                }
            }
            own
        }
        // Also by keyboard and VoiceOver, and again if a new drop changes what's on the card under a waiting pointer.
        .disabled(!ready)
        .task(id: attachment.dropFiles) {
            guard !FileOfferGuard.skipped else { return }
            ready = false
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { ready = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What to do with \(attachment.label)", comment: "VoiceOver: the drop card's four choices"))
    }

    /// The exact count stays in sight, and every name can be reached: a drag can carry more than its picture shows.
    private var fileNames: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(names.count) files", comment: "The drop card: how many files were dropped").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            Text(verbatim: showAll ? names.joined(separator: ", ") : names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : ""))
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            if names.count > 3 {
                Button { showAll.toggle() } label: {
                    if showAll { Text("Show fewer", comment: "The drop card: fold the list of dropped files") } else { Text("Show all", comment: "The drop card: list every dropped file") }
                }
                .buttonStyle(.sf(.quiet, size: .small))
            }
        }
    }

    /// Sidefolk's own line, from the extension's permissions and never its words.
    private func trust(_ offer: ExtensionDropAction) -> some View {
        let many = names.count > 1, count = names.count, who = offer.extensionName
        return HStack(alignment: .top, spacing: Theme.Space.xs) {
            Image(systemName: offer.canSendAway ? "exclamationmark.triangle.fill" : "lock.fill")
                .font(.system(size: 10, weight: .semibold)).padding(.top, 2)
                .foregroundStyle(offer.canSendAway ? Theme.warning : Theme.inkFaint)
            Group {
                if offer.canSendAwayWithoutInternet {
                    if many {
                        Text("\(who) reads these \(count) files only if you choose below. It has no internet access of its own, but other things it's allowed to use could carry them out.", comment: "The drop card, Sidefolk's own words: an extension's name and how many files")
                    } else {
                        Text("\(who) reads this file only if you choose below. It has no internet access of its own, but other things it's allowed to use could carry the file out.", comment: "The drop card, Sidefolk's own words: an extension's name")
                    }
                } else {
                    switch (many, offer.canSendAway) {
                    case (false, false): Text("\(who) reads this file only if you choose below, and only this once. It can't go online by itself.", comment: "The drop card, Sidefolk's own words: an extension's name")
                    case (true, false): Text("\(who) reads these \(count) files only if you choose below, and only this once. It can't go online by itself.", comment: "The drop card, Sidefolk's own words: an extension's name and a count")
                    case (false, true): Text("\(who) reads this file only if you choose below. It can use the internet, so it could send the file anywhere.", comment: "The drop card, Sidefolk's own words: an extension's name")
                    case (true, true): Text("\(who) reads these \(count) files only if you choose below. It can use the internet, so it could send them anywhere.", comment: "The drop card, Sidefolk's own words: an extension's name and a count")
                    }
                }
            }
            .font(Theme.Font.caption).foregroundStyle(offer.canSendAway ? Theme.ink : Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The file itself, on Sidefolk's own ground: its picture at thumbnail size, or a mark saying what kind it is.
    private var fileRow: some View {
        let first = groups.first?.first
        return FrostLoader(path: attachment.dropFiles.first, icon: first.flatMap { looks[$0.extensionId]?.iconPath }) { frost in
            HStack(spacing: Theme.Space.s) {
                FileSheetLoading(frost: frost, mark: first?.mark, extensionId: first?.extensionId, side: 32, packPicture: packPicture)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: names.first ?? "").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                    if let size = attachment.dropFiles.first.flatMap(Self.size) {
                        Text(verbatim: size).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer(minLength: 0)
                Button(action: removeFile) { Image(systemName: "xmark") }
                    .buttonStyle(.sfIcon(side: 22)).foregroundStyle(Theme.inkFaint)
                    .accessibilityLabel("Remove attachment")
            }
        }
    }

    private static func size(_ path: String) -> String? {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
        return bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    /// The extension's words, framed apart and under its name, so a title can't read as Sidefolk's. On a frost from the person's file
    /// (D150), in white and neutrals only; nothing Sidefolk says is on it.
    private func frame(_ first: ExtensionDropAction, _ group: [ExtensionDropAction]) -> some View {
        FrostLoader(path: attachment.dropFiles.first, icon: looks[first.extensionId]?.iconPath) { frost in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Space.xs) {
                    if let look = looks[first.extensionId] { ExtensionBadge(look: look, size: 18) }
                    Text("\(first.extensionName) says it can", comment: "The drop card: above what an extension offers, in its own words")
                        .font(Theme.Font.caption.weight(.semibold)).foregroundStyle(FrostInk.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s + 2)
                ForEach(group) { offer in
                    Rectangle().fill(FrostInk.line).frame(height: 1)
                    FrostOfferRow(offer: offer) { chooseOffer(offer, nil) }
                }
                ForEach(group.filter { !$0.menu.isEmpty }) { offer in
                    Rectangle().fill(FrostInk.line).frame(height: 1)
                    Menu {
                        ForEach(offer.menu, id: \.self) { item in
                            Button { chooseOffer(offer, item) } label: { Text(ext: item.title) }
                        }
                    } label: {
                        HStack(spacing: Theme.Space.xs) {
                            Text("Another choice", comment: "The drop card: a menu of more things an extension offers").font(Theme.Font.callout).foregroundStyle(FrostInk.text)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(FrostInk.text)
                        }
                    }
                    .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.sfBare)
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s + 1)
                }
            }
            .background(FrostGround(frost: frost))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    /// Sidefolk's own choices stay available, small, below.
    private var own: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(choices.filter { $0 != .ask && ($0 != .openWith || names.count == 1) }, id: \.self) { choice in
                if choice == .openWith, case .file(let file) = attachment.kind {
                    // Never the app macOS would pick by itself: a dropped `.command` would run.
                    Menu {
                        ForEach(DropCard.apps(for: file), id: \.self) { app in
                            Button { openWith(app) } label: { Text(verbatim: FileManager.default.displayName(atPath: app.path)) }
                        }
                    } label: { DropCard.words(choice, kind: .file).title }
                        .menuStyle(.button).menuIndicator(.hidden)
                        .buttonStyle(.sf(.quiet, size: .small))
                } else {
                    Button { chooseOwn(choice) } label: { DropCard.words(choice, kind: .file).title }
                        .buttonStyle(.sf(.quiet, size: .small))
                }
            }
        }
    }
}

/// One thing an extension offers, on the frost: a quiet tag for what it makes, its title and its detail.
private struct FrostOfferRow: View {
    var offer: ExtensionDropAction
    var choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Theme.Space.m) {
                if let tag = offer.tag {
                    Text(verbatim: tag).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundStyle(FrostInk.text)
                        .frame(width: 42, height: 22)
                        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 1))
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ext: offer.title).font(Theme.Font.bodyStrong).foregroundStyle(FrostInk.text)
                    if let detail = offer.detail {
                        Text(ext: detail).font(Theme.Font.caption).foregroundStyle(FrostInk.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s + 1)
            .background(.black.opacity(hovering ? 0.14 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .onHover { hovering = $0 }
    }
}

/// `FileSheet`, with the extension's mark fetched from its pack when the file has no picture to show.
struct FileSheetLoading: View {
    var frost: FileFrost
    var mark: String?
    var extensionId: String?
    var side: CGFloat
    var packPicture: (String, String) async -> NSImage?
    @State private var image: NSImage?

    var body: some View {
        FileSheet(frost: frost, mark: image, side: side)
            .task(id: mark) {
                guard let mark, let extensionId else { return }
                image = await packPicture(mark, extensionId)
            }
    }
}

/// A contact sheet shows the card as it is once it takes clicks, not during its first moment.
enum FileOfferGuard {
    static var skipped = false
}
