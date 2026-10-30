import SidefolkCore
import SwiftUI

/// The palette (D63): a search field over the extension's list, driven from the keyboard. Its rows are the extension's
/// text, shown verbatim.
struct PaletteView: View {
    var model: PaletteModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkFaint)
                TextField(text: Binding(get: { model.query }, set: { model.query = $0 })) {
                    Text(verbatim: model.info.placeholder ?? model.info.title)
                }
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focused)
                .onSubmit { Task { await model.act("choose") } }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    Task { await model.act("plain") }
                    return .handled
                }
                Text(verbatim: model.info.title).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            Rectangle().fill(Theme.line).frame(height: 1)
            list
            footer
        }
        .frame(width: 600, height: 440)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.line))
        .background {
            // ⌘P and ⌘⌫ on the picked row, as hidden buttons so the field keeps the typing.
            Group {
                Button { Task { await model.act("pin") } } label: { EmptyView() }.keyboardShortcut("p", modifiers: .command)
                Button { Task { await model.act("delete") } } label: { EmptyView() }.keyboardShortcut(.delete, modifiers: .command)
            }
            .opacity(0)
        }
        .onAppear { focused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                        PaletteRow(item: item, picked: i == model.selected)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { Task { await model.act("choose", on: i) } }
                            .onTapGesture { model.selected = i }
                    }
                    if model.items.isEmpty {
                        Text(model.query.isEmpty ? "Nothing here yet." : "Nothing matches.", comment: "An empty palette list")
                            .font(Theme.Font.body).foregroundStyle(Theme.inkMuted).padding(Theme.Space.xl)
                    }
                }
                .padding(Theme.Space.s)
            }
            .onChange(of: model.selected) { _, i in
                if model.items.indices.contains(i) { proxy.scrollTo(model.items[i].id) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            if let message = model.message ?? model.note {
                Text(verbatim: message).font(Theme.Font.caption).foregroundStyle(model.message == nil ? Theme.inkFaint : Theme.ink).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Text("↩ Paste  ⇧↩ Plain text  ⌘P Pin  ⌘⌫ Delete", comment: "Keys in an extension's palette")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
        .background(Theme.surfaceSunken.opacity(0.6))
    }
}

private struct PaletteRow: View {
    var item: ExtensionPaletteList.Item
    var picked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s + 2) {
            Image(systemName: symbol).foregroundStyle(picked ? Theme.onAccent : Theme.inkMuted).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title).font(item.kind == .code ? .system(size: 13, design: .monospaced) : Theme.Font.body)
                    .foregroundStyle(picked ? Theme.onAccent : Theme.ink).lineLimit(2)
                if let detail = item.detail {
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(picked ? Theme.onAccent.opacity(0.8) : Theme.inkFaint).lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if item.pinned { Image(systemName: "pin.fill").foregroundStyle(picked ? Theme.onAccent : Theme.sun).imageScale(.small) }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(picked ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private var symbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}
