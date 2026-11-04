import SwiftUI

/// Lantern's row (D84): 44 tall (32 compact), 16 at the sides, a 24 pt icon, a title and one meta line, then a value
/// or a control at the trailing edge. Up to two actions appear in the trailing value's place while the pointer is on
/// the row, and are always in the ⋯ menu beside it, so neither the keyboard nor VoiceOver has to hover (D220). Chosen: the
/// accent's soft fill with the title in the link colour. Put rows in a `RowsCard` for the hairlines between them.
struct ListRow<Leading: View, Trailing: View, Actions: View>: View {
    var title: Text
    var meta: Text?
    var selected = false
    var compact = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var actions: Actions
    @State private var hovered = false

    init(title: Text, meta: Text? = nil, selected: Bool = false, compact: Bool = false, @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.meta = meta
        self.selected = selected
        self.compact = compact
        self.leading = leading()
        self.trailing = trailing()
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                title.font(compact ? Theme.Font.body : Theme.Font.bodyStrong).foregroundStyle(selected ? Theme.link : Theme.ink)
                    .lineLimit(2)
                if let meta, !compact {
                    meta.font(Theme.Font.callout).foregroundStyle(Theme.inkFaint).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .trailing) {
                trailing.opacity(hovered && Actions.self != EmptyView.self ? 0 : 1)
                if hovered {
                    HStack(spacing: Theme.Space.xs) { actions }.buttonStyle(.sf(.quiet))
                }
            }
            if Actions.self != EmptyView.self {
                Menu { actions } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                        .frame(width: Theme.Size.hitTarget - 4, height: Theme.Size.hitTarget)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.sfBare)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("More", comment: "A row's menu of what can be done with it"))
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, compact ? Theme.Space.xs : Theme.Space.s)
        .frame(minHeight: compact ? Theme.Size.compactRow : Theme.Size.row)
        .overlay(alignment: .leading) { if selected { SelectedRail() } }
        .background(selected ? Theme.accentSoft : hovered ? Theme.ink.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(Theme.Motion.micro, value: hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension ListRow where Actions == EmptyView {
    init(title: Text, meta: Text? = nil, selected: Bool = false, compact: Bool = false, @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, meta: meta, selected: selected, compact: compact, leading: leading, trailing: trailing) { EmptyView() }
    }
}

extension ListRow where Leading == EmptyView, Actions == EmptyView {
    init(title: Text, meta: Text? = nil, selected: Bool = false, compact: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, meta: meta, selected: selected, compact: compact, leading: { EmptyView() }, trailing: trailing) { EmptyView() }
    }
}

/// A row's trailing chevron: the row opens something.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            .accessibilityHidden(true)
    }
}

/// The edge of a selected row in a list: its tint alone is about 1.2:1 from the card (D130).
struct SelectedRail: View {
    var body: some View {
        Capsule().fill(Theme.accent).frame(width: 3).padding(.vertical, 8)
            .accessibilityHidden(true)
    }
}
