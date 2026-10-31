import SwiftUI

/// Lantern's row (D84): 44 tall (32 compact), 16 at the sides, a 24 pt icon, a title and one meta line, then a value
/// or a control at the trailing edge. Up to two actions appear in the trailing value's place while the pointer is on
/// the row or the keyboard is in it, and stay for VoiceOver as actions. Chosen: the accent's soft fill with the title
/// in the link colour. Put rows in a `RowsCard` for the hairlines between them.
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
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, compact ? Theme.Space.xs : Theme.Space.s)
        .frame(minHeight: compact ? Theme.Size.compactRow : Theme.Size.row)
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
