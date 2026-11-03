import AppKit
import SidefolkCore
import SwiftUI

/// While an extension works on the person's file (D150): the file, a plain white bar for every kind of file, and Sidefolk's own words.
struct FileWorkingCard: View {
    var file: WorkingFile
    var look: ExtensionLook?
    var packPicture: (String, String) async -> NSImage?
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var moving = false

    var body: some View {
        FrostLoader(path: file.showsPicture ? file.path : nil, mark: file.mark.map { mark in { await packPicture(mark, file.extensionId) } },
                    markKey: file.mark.map { file.extensionId + "|" + $0 }) { frost in
            HStack(spacing: Theme.Space.m) {
                FileSheetLoading(frost: frost, mark: file.mark, extensionId: file.extensionId, side: 32, packPicture: packPicture)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    // Who's working on it, since the mark is its picture.
                    if let look {
                        HStack(spacing: Theme.Space.xs) {
                            ExtensionBadge(look: look, size: 14)
                            Text(verbatim: look.name).font(Theme.Font.caption).foregroundStyle(FrostInk.muted).lineLimit(1)
                        }
                    }
                    Text("Working on \(file.name)", comment: "The working card: an extension is making something from this file")
                        .font(Theme.Font.bodyStrong).foregroundStyle(FrostInk.text).lineLimit(1).truncationMode(.middle)
                    bar
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FrostGround(frost: frost, radius: Theme.Radius.panel))
        }
        .accessibilityElement(children: .combine)
    }

    /// How far along isn't known, so it moves without saying.
    private var bar: some View {
        GeometryReader { space in
            Capsule().fill(.white.opacity(0.18))
                .overlay(alignment: .leading) {
                    // Still, it fills the whole track, so it can't read as how far along this is.
                    Capsule().fill(.white.opacity(still ? 0.5 : 0.9)).frame(width: space.size.width * (still ? 1 : 0.35))
                        .offset(x: moving && !still ? space.size.width * 0.65 : 0)
                }
                .clipShape(Capsule())
        }
        .frame(height: 4)
        .onAppear {
            guard !still else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { moving = true }
        }
    }
}

/// A saved file's card (D150): one sheet with the new file, resting on an empty one, what changed in one line, and Sidefolk's own
/// actions on the file. It names the extension, so it can't pass for Sidefolk's own.
struct FileReceiptCard: View {
    var card: ResultCard
    var activityId: String?
    var look: ExtensionLook?
    var model: AskModel

    private var files: [PlacedFile] { card.files ?? [] }

    private var packMark: (() async -> NSImage?)? {
        guard let mark = card.mark, let id = card.refId else { return nil }
        return { await model.actions?.packPicture(mark, extensionId: id) }
    }

    var body: some View {
        FrostLoader(path: files.first?.path, mark: packMark, markKey: card.mark.map { (card.refId ?? "") + "|" + $0 }) { frost in
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    sheets(frost)
                    words
                    Spacer(minLength: 0)
                }
                // What the answer held, if it had a tree (up to 280 points), as on any card.
                if let tree = card.tree.flatMap(ExtensionPage.tree(from:)) {
                    TreeCompact(tree: tree).environment(\.colorScheme, .dark)
                }
                actions
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FrostGround(frost: frost, radius: Theme.Radius.panel))
        }
        .accessibilityElement(children: .contain)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.Space.xs) {
                if let look { ExtensionBadge(look: look, size: 14) }
                if let name = card.subtitle { Text(verbatim: name).font(Theme.Font.caption).foregroundStyle(FrostInk.muted).lineLimit(1) }
            }
            Text(verbatim: card.title).font(Theme.Font.headline).foregroundStyle(FrostInk.text).lineLimit(2).truncationMode(.middle).fixedSize(horizontal: false, vertical: true)
            if let detail = card.detail {
                Text(verbatim: detail).font(Theme.Font.caption.weight(.semibold)).foregroundStyle(FrostInk.text).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: beside).font(Theme.Font.caption).foregroundStyle(FrostInk.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var beside: String {
        let folders = Set(files.map { ($0.source as NSString).deletingLastPathComponent })
        guard folders.count == 1, let folder = folders.first else { return String(localized: "Beside the originals.", comment: "On a saved file's card") }
        let name = FileManager.default.displayName(atPath: folder)
        return files.count == 1 ? String(localized: "Beside the original in \(name).", comment: "On a saved file's card: the folder's name")
            : String(localized: "Beside the originals in \(name).", comment: "On a saved files' card: the folder's name")
    }

    /// An empty sheet behind the new file. One file can be dragged from here to wherever it's wanted.
    private func sheets(_ frost: FileFrost) -> some View {
        ZStack(alignment: .topLeading) {
            SheetShape().fill(.white.opacity(0.12)).frame(width: 56, height: 72)
                .overlay { SheetShape().stroke(.white.opacity(0.28), lineWidth: 0.5) }
            FileSheetLoading(frost: frost, mark: card.mark, extensionId: card.refId, side: 56,
                             packPicture: { await model.actions?.packPicture($0, extensionId: $1) })
                .frame(width: 56, height: 72)
                .offset(x: 12, y: 8)
                .onDrag {
                    guard files.count == 1, let file = files.first, file.isStillThere else { return NSItemProvider() }
                    return NSItemProvider(object: URL(fileURLWithPath: file.path) as NSURL)
                }
        }
        .frame(width: 68, height: 80, alignment: .topLeading)
    }

    /// Sidefolk's own buttons, on any frost.
    private var actions: some View {
        HStack(spacing: Theme.Space.s) {
            if files.count == 1, let file = files.first, file.canOpen {
                Button("Open") { model.actions?.open(file: file) }.buttonStyle(.sf(.primary, size: .sidecard)).frostEdge()
            }
            Button { model.actions?.show(files: files) } label: { Text("Show in Finder", comment: "On a saved file's card") }
                .buttonStyle(.sf(files.count == 1 && files[0].canOpen ? .secondary : .primary, size: .sidecard)).frostEdge()
            Spacer(minLength: 0)
            if let activityId {
                FrostPlainButton(title: "Undo") { model.actions?.undo(activityId: activityId, in: model) }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// A button's own fill can match a frost, so on one it gets an edge of its own.
private extension View {
    func frostEdge() -> some View {
        overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1).allowsHitTesting(false))
    }
}

/// White on any frost, with an edge on hover: the plain style's colours are for Sidefolk's own grounds.
private struct FrostPlainButton: View {
    var title: LocalizedStringKey
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.Font.bodyStrong).foregroundStyle(FrostInk.text)
                .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(.white.opacity(hovering ? 0.5 : 0), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.sfBare)
        .onHover { hovering = $0 }
    }
}
