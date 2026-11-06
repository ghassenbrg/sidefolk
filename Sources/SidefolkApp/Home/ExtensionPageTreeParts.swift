import SidefolkCore
import SwiftUI

/// Picks a card up, and takes one dropped on it to stand right after it. The system's own drag: the words carried are only the card's id, and only a card of this tree lands.
/// Esc puts it back, as any drag on a Mac.
struct TreeCardDrag: ViewModifier {
    var node: ExtensionPage.Tree.Node
    var tree: ExtensionPage.Tree
    var model: ExtensionPageModel
    var carried: String?
    var carry: (String?) -> Void
    @Binding var dropping: Bool

    /// Marks a drag as a card's, so words dragged in from elsewhere land nowhere.
    static let carrying = "sidefolk.tree.card:"
    static func card(in dragged: [String]) -> String? { dragged.first?.hasPrefix(carrying) == true ? dragged.first.map { String($0.dropFirst(carrying.count)) } : nil }

    /// What letting a card go at a spot does: the tree's own move to right after `target`, through the extension's tool, as Move to does.
    /// Only the card this board picked up itself moves: the same words typed, pasted or dragged in from another app or window name a
    /// card, but this board isn't carrying it, so they land nowhere.
    static func drop(_ dragged: [String], after target: String, carried: String?, tree: ExtensionPage.Tree, model: ExtensionPageModel) -> Bool {
        guard let reorder = tree.reorder, let id = card(in: dragged), id == carried, let place = tree.place(id, after: target) else { return false }
        Task { await model.run(tool: reorder.tool, input: reorder.input(place)) }
        return true
    }

    func body(content: Content) -> some View {
        if tree.reorder != nil {
            content
                .treeDraggable(node.fixed ? nil : node, carry: carry)
                .dropDestination(for: String.self) { ids, _ in
                    carry(nil)
                    return Self.drop(ids, after: node.id, carried: carried, tree: tree, model: model)
                } isTargeted: { dropping = $0 }
        } else {
            content
        }
    }
}

private extension View {
    /// The board learns which card is carried as the drag starts, so it can show where that card can go.
    @ViewBuilder func treeDraggable(_ node: ExtensionPage.Tree.Node?, carry: @escaping (String?) -> Void) -> some View {
        if let node {
            onDrag {
                carry(node.id)
                return NSItemProvider(object: (TreeCardDrag.carrying + node.id) as NSString)
            } preview: {
                TreeDragPreview(node: node)
            }
        } else {
            self
        }
    }
}

/// What follows the pointer while a card is carried: its tile and its words, on a card of its own.
struct TreeDragPreview: View {
    var node: ExtensionPage.Tree.Node

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            TreeTile(symbol: node.symbol, color: node.color, side: 28, tone: nil)
            Text(ext: node.kind ?? node.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(maxWidth: 260, minHeight: 44)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
    }
}

/// A symbol on its soft tile: the colour says what kind of thing it is, never how it went.
struct TreeTile: View {
    var symbol: String?
    var color: String?
    var side: CGFloat
    var tone: ExtensionPage.Tone?

    var body: some View {
        let tint = tone?.color ?? color.flatMap { Color(extensionHex: $0) } ?? Theme.accent
        Image(systemName: symbol ?? "circle").font(.system(size: side * 0.42, weight: .medium)).foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: side * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A word and its colour, soft (D78).
struct TreePill: View {
    var badge: ExtensionPage.Badge
    @Environment(\.pageSelected) private var accent
    @Environment(\.colorScheme) private var scheme

    /// "Info" says nothing good or bad: on a page with its own accent, it's in that, not a second brand colour beside it.
    private var selection: PageSelection? { badge.tone == .info && accent != nil ? PageSelection(accent: accent, dark: scheme == .dark) : nil }

    var body: some View {
        Text(ext: badge.text).font(Theme.Font.caption.weight(.medium)).lineLimit(1)
            .foregroundStyle(selection?.ink ?? (badge.tone == .neutral ? Theme.inkMuted : badge.tone.color))
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
            .background(selection?.soft ?? (badge.tone == .neutral ? Theme.well : badge.tone.soft), in: Capsule())
            .fixedSize()
    }
}

struct TreeBranchLabel: View {
    var branch: ExtensionPage.Tree.Branch

    var body: some View {
        Text(ext: branch.label).font(Theme.Font.caption.weight(.semibold)).lineLimit(1)
            .foregroundStyle(branch.taken == false ? Theme.inkMuted : (branch.tone == .neutral ? Theme.ink : branch.tone.color))
            .padding(.horizontal, Theme.Space.s + 2).padding(.vertical, 3)
            .background(branch.taken == false ? Theme.well : (branch.tone == .neutral ? Theme.surfaceRaised : branch.tone.soft), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))
    }
}

/// The person's own companion in its light, standing by what's happening now.
struct TreeCompanion: View {
    var model: ExtensionPageModel

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.glow.opacity(0.55), Theme.glow.opacity(0)], center: .center, startRadius: 2, endRadius: 30)).frame(width: 60, height: 60)
            PagePictureView(picture: .companion(.full), model: model, side: 96, fill: false).frame(width: 44, height: 44)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct TreeAddButton: View {
    var add: TreeLayout.Add
    var hook: ExtensionPage.Steps.Hook
    var picker: ExtensionPage.Tree.Picker?
    var tree: ExtensionPage.Tree
    var line: TreeLine
    var model: ExtensionPageModel
    var carried: String?
    var carry: (String?) -> Void
    @State private var hovering = false
    @State private var picking = false
    @State private var dropping = false
    /// While a card is carried: whether it can land here. Every such spot shows, quiet ones too; the others step out of the way.
    private var takes: Bool? { carried.map { tree.place($0, after: add.target) != nil } }
    private var lit: Bool { hovering || dropping || takes == true }
    @FocusState private var focused: Bool
    // A popover has an environment of its own.
    @Environment(\.pageSelected) private var accent

    var body: some View {
        Button {
            if picker == nil {
                Task { await model.run(tool: hook.tool, input: hook.input(.string(add.target))) }
            } else {
                picking = true
            }
        } label: {
            if let hint = add.hint {
                Label { Text(ext: hint).lineLimit(1) } icon: { Image(systemName: "plus") }
                    .font(Theme.Font.callout).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Space.m)
                    .frame(height: 30)
                    .background(Theme.surfaceRaised, in: Capsule())
                    .overlay(Capsule().strokeBorder(lit ? line.to : Theme.line, style: StrokeStyle(lineWidth: dropping ? 2 : 1, dash: [4, 3])))
                    .contentShape(Capsule())
            } else {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 22, height: 22)
                    .background(Theme.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(lit ? line.to : Theme.line, lineWidth: dropping || takes == true ? 2 : 1))
                    .background(Circle().fill(line.to.opacity(takes == true ? 0.18 : 0)).padding(-6))
                    .scaleEffect(dropping ? 1.5 : (takes == true ? 1.2 : 1))
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.sfBare)
        .focused($focused)
        .onHover { hovering = $0 }
        .opacity(takes.map { $0 ? 1 : 0 } ?? (add.quiet && !hovering && !focused && !picking && !dropping ? 0 : 1))
        .allowsHitTesting(takes != false)
        .help(Text(ext: hook.label ?? ""))
        .accessibilityLabel(Text(ext: hook.label ?? ""))
        // A card dragged here lands at this spot: on either side of the +, so it needn't be hit exactly.
        .frame(minWidth: 36, minHeight: 36)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            carry(nil)
            return TreeCardDrag.drop(ids, after: add.target, carried: carried, tree: tree, model: model)
        } isTargeted: { dropping = $0 }
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            if let picker {
                TreePicker(picker: picker, accent: accent) { id in
                    picking = false
                    Task { await model.run(tool: hook.tool, input: hook.input(.string(add.target)).setting(picker.key, .string(id))) }
                }
            }
        }
    }
}
