import SidefolkCore
import SwiftUI

/// The palette (D63): a search field over the extension's list, driven from the keyboard (`PaletteKeys`, read by the
/// controller), and, when the extension offers it, the picked row in full beside the list (D68). Its rows are the
/// extension's text, shown verbatim, with its pictures from its own data folder.
struct PaletteView: View {
    var model: PaletteModel
    @FocusState private var focused: Bool

    static let height: CGFloat = 460
    static func width(preview: Bool) -> CGFloat { preview ? 880 : 600 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkFaint)
                TextField(text: Binding(get: { model.query }, set: { model.query = $0 })) {
                    Text(ext: model.info.placeholder ?? model.info.title)
                }
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focused)
                .onSubmit { Task { await model.act("choose") } }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                Text(ext: model.info.title).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 0) {
                list.frame(width: model.hasPreview ? 400 : nil)
                if model.hasPreview {
                    Rectangle().fill(Theme.line).frame(width: 1)
                    PalettePreviewPane(preview: model.preview, item: model.picked, folder: model.folder)
                }
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .frame(width: Self.width(preview: model.hasPreview), height: Self.height)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.line))
        .onAppear { focused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                        if let section = item.section, i == 0 || model.items[i - 1].section != section {
                            Text(ext: section).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkFaint)
                                .padding(.horizontal, Theme.Space.m).padding(.top, i == 0 ? 2 : Theme.Space.s).padding(.bottom, 2)
                        }
                        PaletteRow(item: item, number: i < 9 ? i + 1 : nil, picked: i == model.selected, folder: model.folder)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                Task { await model.act(NSEvent.modifierFlags.contains(.option) ? "alternate" : "choose", on: i) }
                            }
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
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            if let message = model.message ?? model.note {
                Text(ext: message).font(Theme.Font.caption).foregroundStyle(model.message == nil ? Theme.inkFaint : Theme.ink).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Text("⌘1–9 Choose  ⇧↩ Plain text  ⌥P Pin  ⌥⌫ Delete", comment: "Keys in an extension's palette")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
        .background(Theme.surfaceSunken.opacity(0.6))
    }
}

private struct PaletteRow: View {
    var item: ExtensionPaletteList.Item
    var number: Int?
    var picked: Bool
    var folder: URL

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s + 2) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(ext: item.title).font(item.kind == .code ? .system(size: 13, design: .monospaced) : Theme.Font.body)
                    .foregroundStyle(picked ? Theme.onAccent : Theme.ink).lineLimit(item.image == nil ? 2 : 1)
                if let detail = item.detail {
                    Text(ext: detail).font(Theme.Font.caption).foregroundStyle(picked ? Theme.onAccent.opacity(0.8) : Theme.inkFaint).lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if item.pinned { Image(systemName: "pin.fill").foregroundStyle(picked ? Theme.onAccent : Theme.sun).imageScale(.small) }
            if let number {
                Text(ext: "⌘\(number)").font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(picked ? Theme.onAccent.opacity(0.85) : Theme.inkFaint)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, item.image == nil ? Theme.Space.s : 5)
        .background(picked ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    @ViewBuilder private var leading: some View {
        if let image = item.image {
            ExtensionPictureView(name: image, folder: folder, pixels: 112)
                .frame(width: 52, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.line))
        } else if let color = item.color.flatMap(Color.init(extensionHex:)) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color).frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.line))
        } else {
            Image(systemName: Self.symbol(item.kind)).foregroundStyle(picked ? Theme.onAccent : Theme.inkMuted).frame(width: 18)
        }
    }

    static func symbol(_ kind: ExtensionPaletteList.Item.Kind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// The picked row in full: its picture at size, its text to read and select, and its facts (where it came from, when).
private struct PalettePreviewPane: View {
    var preview: ExtensionPalettePreview?
    var item: ExtensionPaletteList.Item?
    var folder: URL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let preview {
                if let image = preview.image {
                    ExtensionPictureView(name: image, folder: folder, pixels: 1000, limit: ExtensionDataFile.previewLimit, fill: false)
                        .frame(maxWidth: .infinity, maxHeight: preview.text == nil ? .infinity : 200)
                }
                if let title = preview.title {
                    Text(ext: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).lineLimit(2)
                }
                if let text = preview.text {
                    ScrollView {
                        Text(ext: text).font(preview.code ? .system(size: 12, design: .monospaced) : Theme.Font.body)
                            .foregroundStyle(Theme.ink).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                } else if preview.image == nil {
                    Spacer(minLength: 0)
                }
                if !preview.facts.isEmpty {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Theme.Space.m, verticalSpacing: 3) {
                        ForEach(Array(preview.facts.enumerated()), id: \.offset) { _, fact in
                            GridRow {
                                Text(ext: fact.label).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                                Text(ext: fact.value).font(Theme.Font.caption).foregroundStyle(Theme.ink).lineLimit(3).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, Theme.Space.xs)
                }
            } else if let item {
                Text(ext: item.title).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
