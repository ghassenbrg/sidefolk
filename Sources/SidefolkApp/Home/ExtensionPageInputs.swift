import SidefolkCore
import SwiftUI

/// An extension page's choices, text fields and lists (D68): what lets a page hold an extension's settings (how many
/// copies to keep, what to ignore) and show things with their pictures. Like switches and buttons, each runs one of the
/// extension's own tools as the person, through Guard, then the page is read again. Every text is the extension's.
struct ExtensionPageInputs: View {
    var blocks: [ExtensionPage.Block]
    var model: ExtensionPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                switch run {
                case .rows(let rows):
                    RowsCard {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .choice(let c): PageChoiceRow(choice: c, model: model)
                            case .field(let f): PageFieldRow(field: f, model: model)
                            default: EmptyView()
                            }
                        }
                    }
                case .list(let list):
                    PageListCard(list: list, model: model)
                case .styled(let choice):
                    PageChoiceView(choice: choice, model: model)
                }
            }
        }
    }

    private enum Run {
        case rows([ExtensionPage.Block]), list(ExtensionPage.List), styled(ExtensionPage.Choice)
    }

    /// Choices and fields next to each other share a card, as switches do; a list, and a choice drawn as cards, tiles
    /// or rows (D73), stand on their own.
    private var runs: [Run] {
        var out: [Run] = []
        for block in blocks {
            if case .list(let l) = block {
                out.append(.list(l))
            } else if case .choice(let c) = block, c.style != .segmented {
                out.append(.styled(c))
            } else if case .rows(let r) = out.last {
                out[out.count - 1] = .rows(r + [block])
            } else {
                out.append(.rows([block]))
            }
        }
        return out
    }
}

private struct PageRowLabel: View {
    var label: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            if let detail {
                Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A few options: side by side when they fit (four or fewer), a menu otherwise. The pick shows at once; the next read
/// of the page confirms it.
private struct PageChoiceRow: View {
    var choice: ExtensionPage.Choice
    var model: ExtensionPageModel
    @State private var pending: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.m) {
                PageRowLabel(label: choice.label, detail: choice.detail)
                Spacer(minLength: Theme.Space.m)
                picker
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                PageRowLabel(label: choice.label, detail: choice.detail)
                picker
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    @ViewBuilder private var picker: some View {
        let binding = Binding(get: { pending ?? choice.selected }, set: { value in
            guard value != choice.selected else { return }
            pending = value
            Task {
                await model.run(tool: choice.tool, input: choice.input(picking: value))
                pending = nil
            }
        })
        let options = ForEach(choice.options, id: \.value) { Text(verbatim: $0.label).tag($0.value) }
        Group {
            if choice.options.count <= 4 {
                Picker(selection: binding) { options } label: { Text(verbatim: choice.label) }.pickerStyle(.segmented)
            } else {
                Picker(selection: binding) { options } label: { Text(verbatim: choice.label) }.pickerStyle(.menu)
            }
        }
        .labelsHidden()
        .fixedSize()
        .disabled(pending != nil || choice.disabled)
    }
}

/// A line to type and a button that sends it; it empties once the tool ran without a problem.
private struct PageFieldRow: View {
    var field: ExtensionPage.Field
    var model: ExtensionPageModel
    @State private var text = ""
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PageRowLabel(label: field.label, detail: field.detail)
            HStack(spacing: Theme.Space.s) {
                TextField(text: $text) { Text(verbatim: field.placeholder ?? field.label) }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(action: send) { Text(verbatim: field.button) }
                    .buttonStyle(.sf(.secondary))
                    .disabled(running || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private func send() {
        guard !running, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        running = true
        Task {
            if await model.run(tool: field.tool, input: field.input(typing: text)) { text = "" }
            running = false
        }
    }
}

/// Rows with a picture, a swatch or a symbol, and a button each.
private struct PageListCard: View {
    var list: ExtensionPage.List
    var model: ExtensionPageModel
    @Environment(\.pixelLength) private var pixel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if list.title != nil || list.caption != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = list.title { Text(verbatim: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink) }
                    if let caption = list.caption {
                        Text(verbatim: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if list.rows.isEmpty {
                Text("Nothing to show right now.", comment: "An extension page's list of bars is empty")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            }
            VStack(spacing: 0) {
                ForEach(Array(list.rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: pixel * 2) }
                    PageListRow(row: row, model: model).padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .cardSurface()
    }
}

private struct PageListRow: View {
    var row: ExtensionPage.Row
    var model: ExtensionPageModel
    @State private var running = false

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if let image = row.image, let folder = model.folder {
                ExtensionPictureView(name: image, folder: folder, pixels: 128)
                    .frame(width: 56, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line))
            } else if let color = row.color.flatMap(Color.init(extensionHex:)) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color).frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.line))
            } else if let symbol = row.symbol {
                Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(2).truncationMode(.middle)
                if let detail = row.detail { Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1) }
            }
            Spacer(minLength: Theme.Space.s)
            if let button = row.button {
                Button {
                    running = true
                    Task {
                        await model.run(tool: button.tool, input: button.input)
                        running = false
                    }
                } label: {
                    if let symbol = button.symbol {
                        Label { Text(verbatim: button.label) } icon: { Image(systemName: symbol) }
                    } else {
                        Text(verbatim: button.label)
                    }
                }
                .buttonStyle(.sf(.secondary))
                .disabled(running)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
