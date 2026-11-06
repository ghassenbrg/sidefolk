import AppKit
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
                            case .choice(let c) where c.multiple: PageMultiChoiceRow(choice: c, model: model)
                            case .choice(let c): PageChoiceRow(choice: c, model: model)
                            case .field(let f) where f.search: PageFieldRow(field: f, model: model)
                            // What it saves to is part of what it is: a field called the same on another flow's page doesn't take over this one's typing or its saves.
                            case .field(let f) where f.id != nil: PageEditFieldRow(field: f, model: model).id("\(f.id ?? "")|\(f.input.hashValue)")
                            case .field(let f): PageFieldRow(field: f, model: model)
                            default: EmptyView()
                            }
                        }
                    }
                case .list(let list):
                    PageListCard(list: list, model: model)
                case .styled(let choice):
                    PageChoiceView(choice: choice, model: model)
                case .search(let field):
                    PageFieldRow(field: field, model: model)
                }
            }
        }
    }

    private enum Run {
        case rows([ExtensionPage.Block]), list(ExtensionPage.List), styled(ExtensionPage.Choice), search(ExtensionPage.Field)
    }

    /// Choices and fields next to each other share a card, as switches do; a list, and a choice drawn as cards, tiles
    /// or rows (D74), stand on their own.
    private var runs: [Run] {
        var out: [Run] = []
        for block in blocks {
            if case .list(let l) = block {
                out.append(.list(l))
            } else if case .choice(let c) = block, c.style != .segmented {
                out.append(.styled(c))
            } else if case .field(let f) = block, f.search {
                out.append(.search(f))
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
            Text(ext: label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            if let detail {
                Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
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
    @Environment(\.pageFlat) private var flat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.m) {
                PageRowLabel(label: choice.label, detail: choice.detail)
                Spacer(minLength: Theme.Space.m)
                picker
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                PageRowLabel(label: choice.label, detail: choice.detail)
                // Even stacked, a row of choices can be wider than a narrow panel, and it doesn't shrink: that pushes all the panel holds off both sides. A menu always fits.
                ViewThatFits(in: .horizontal) {
                    picker
                    menu
                }
            }
        }
        .padding(.horizontal, flat ? 0 : Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private var binding: Binding<String> {
        Binding(get: { pending ?? choice.selected }, set: { value in
            guard value != choice.selected else { return }
            pending = value
            Task {
                if let go = choice.go(picking: value) { await model.go(go) } else { await model.run(tool: choice.tool, input: choice.input(picking: value)) }
                pending = nil
            }
        })
    }

    private var menu: some View {
        Picker(selection: binding) { ForEach(choice.options, id: \.value) { Text(ext: $0.label).tag($0.value) } } label: { Text(ext: choice.label) }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(pending != nil || choice.disabled)
    }

    @ViewBuilder private var picker: some View {
        let options = ForEach(choice.options, id: \.value) { Text(ext: $0.label).tag($0.value) }
        Group {
            if choice.options.count <= 4 {
                SegmentedPicker(Text(ext: choice.label), selection: binding, segments: choice.options.map { .init($0.value, Text(ext: $0.label)) })
            } else {
                Picker(selection: binding) { options } label: { Text(ext: choice.label) }.pickerStyle(.menu)
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
    @State private var began = false
    @Environment(\.pageFlat) private var flat

    var body: some View {
        if field.search { searchBox } else { row }
    }

    /// A magnifying glass, the words, and a way to clear them.
    private var searchBox: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
            TextField(text: $text) { Text(ext: field.placeholder ?? field.label) }
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .onSubmit(send)
                .accessibilityLabel(Text(ext: field.label))
                .task(id: text) { await follow() }
                .onChange(of: field.value) { old, new in
                    if field.live, new == nil, old != nil, !text.isEmpty { text = "" }
                }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkFaint) }
                    .buttonStyle(.sfBare)
                    .accessibilityLabel(Text(ext: field.button))
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(minHeight: 36)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous).strokeBorder(Theme.line))
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PageRowLabel(label: field.label, detail: field.detail)
            HStack(spacing: Theme.Space.s) {
                TextField(text: $text, prompt: Text(verbatim: "")) { Text(ext: field.label) }
                    .fieldHint(Text(ext: field.placeholder ?? field.label), showing: text.isEmpty, spoken: field.placeholder != nil)
                    .lanternField()
                    .onSubmit(send)
                    .task(id: text) { await follow() }
                    .onChange(of: field.value) { old, new in
                        // Its state was taken away (a draft cancelled): the words go with it. Otherwise it follows what is typed, not the other way round.
                        if field.live, new == nil, old != nil, !text.isEmpty { text = "" }
                    }
                // A live field has no need of a button to send, only one to clear (D105).
                if !field.live {
                    Button(action: send) { Text(ext: field.button) }
                        .buttonStyle(.sf(.secondary))
                        .disabled(running || text.trimmingCharacters(in: .whitespaces).isEmpty)
                } else if !text.isEmpty {
                    Button { text = "" } label: { Text(ext: field.button) }.buttonStyle(.sf(.quiet))
                }
            }
        }
        .padding(.horizontal, flat ? 0 : Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private func send() {
        guard !running, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        running = true
        Task {
            if let go = field.go(typing: text) {
                await model.go(go)
            } else if await model.run(tool: field.tool, input: field.input(typing: text)) {
                text = ""
            }
            running = false
        }
    }

    /// A live field tells the page a moment after typing stops, and starts from what the page's state holds.
    private func follow() async {
        guard field.live else { return }
        if !began {
            began = true
            if let value = field.value, text.isEmpty { text = value }
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, text != (field.value ?? ""), let go = field.go(typing: text) else { return }
        await model.go(go)
    }
}

/// Rows with a picture, a swatch or a symbol, and a button each.
private struct PageListCard: View {
    var list: ExtensionPage.List
    var model: ExtensionPageModel
    @Environment(\.pixelLength) private var pixel
    @Environment(\.pageFlat) private var flat
    @State private var keys = PageListKeys()

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(list.rows.enumerated()), id: \.offset) { i, row in
                if i > 0, !row.selected, !list.rows[i - 1].selected { Rectangle().fill(Theme.line).frame(height: pixel * 2) }
                PageListRow(row: row, model: model, pressed: { keys.arm() }).padding(.vertical, row.press == nil ? 6 : 0).id(i)
            }
        }
    }

    @ViewBuilder private var scrolling: some View {
        if let height = list.maxHeight {
            ScrollViewReader { proxy in
                ScrollView { rows }
                    .frame(maxHeight: CGFloat(height))
                    .onChange(of: list.rows.firstIndex(where: \.selected)) { _, at in
                        if let at { withAnimation(Theme.Motion.ease(0.12)) { proxy.scrollTo(at) } }
                    }
            }
        } else {
            rows
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if list.title != nil || list.caption != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = list.title { Text(ext: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink) }
                    if let caption = list.caption {
                        Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if list.rows.isEmpty {
                Group {
                    if let empty = list.empty {
                        Text(ext: empty)
                    } else {
                        Text("Nothing to show right now.", comment: "An extension page's list of bars is empty")
                    }
                }
                .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            }
            scrolling
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(flat ? 0 : Theme.Space.m)
        .cardSurface()
        .onChange(of: list, initial: true) { _, new in keys.list = new }
        .onAppear { keys.start(model) }
        .onDisappear { keys.stop() }
    }
}

/// Up and down press the row beside the selected one, as clicking it would, once a row has been clicked and until a click anywhere else. Not SwiftUI's focus: a list of
/// buttons in a scroll view never holds it. The same local monitor a palette uses for its keys, and a field that has the keyboard keeps its arrows.
@MainActor
private final class PageListKeys {
    var list: ExtensionPage.List?
    /// The window the row was clicked in: a key pressed anywhere else, such as a panel that opened since, isn't for this list.
    private weak var armed: NSWindow?
    private var monitor: Any?

    func arm() { armed = NSApp.keyWindow }

    func start(_ model: ExtensionPageModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak model] event in
            guard let self else { return event }
            if event.type != .keyDown {
                // The row's own click arms it again when it lands, after this.
                self.armed = nil
                return event
            }
            let delta = event.keyCode == 125 ? 1 : event.keyCode == 126 ? -1 : 0
            guard delta != 0, let window = event.window, window === self.armed, !(window.firstResponder is NSText),
                  event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
                  let rows = self.list?.rows, let at = rows.firstIndex(where: \.selected), rows.indices.contains(at + delta), let press = rows[at + delta].press else { return event }
            Task { await model?.run(press, on: nil) }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        armed = nil
    }
}

private struct PageListRow: View {
    var row: ExtensionPage.Row
    var model: ExtensionPageModel
    /// The list takes the keyboard from here, so the arrow keys carry on from the row just clicked.
    var pressed: () -> Void = {}
    @State private var running = false
    @Environment(\.pageSelected) private var accent
    @Environment(\.colorScheme) private var scheme
    private var selection: PageSelection { PageSelection(accent: accent, dark: scheme == .dark) }

    var body: some View {
        if let press = row.press {
            Button {
                pressed()
                Task { await model.run(press, on: nil) }
            } label: {
                content
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.s)
                    .background(row.selected ? selection.soft : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.sfBare)
            .accessibilityLabel(Text(ext: [row.title, row.detail, row.markLabel].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityAddTraits(row.selected ? .isSelected : [])
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Theme.Space.m) {
            if let image = row.image, let folder = model.folder {
                ExtensionPictureView(name: image, folder: folder, pixels: 128)
                    .frame(width: row.press == nil ? 56 : 46, height: row.press == nil ? 40 : 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line))
            } else if let color = row.color.flatMap(Color.init(extensionHex:)) {
                if row.press != nil {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color).frame(width: 34, height: 34).frame(width: 46)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.line).frame(width: 34, height: 34))
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color).frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.line))
                }
            } else if let symbol = row.symbol {
                if row.press != nil {
                    Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Theme.inkMuted).frame(width: 46, height: 36)
                        .background(row.selected ? Theme.surfaceRaised : Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 22)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ext: row.title).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(row.press == nil ? 2 : 1).truncationMode(.middle)
                if let detail = row.detail { Text(ext: detail).font(Theme.Font.caption).foregroundStyle(row.press == nil ? Theme.inkFaint : Theme.inkMuted).lineLimit(1) }
            }
            Spacer(minLength: Theme.Space.s)
            if let mark = row.mark {
                Image(systemName: mark).font(.system(size: 13)).foregroundStyle(selection.fill)
                    .help(row.markLabel.map { Text(ext: $0) } ?? Text(verbatim: ""))
            }
            if let button = row.button {
                Button {
                    running = true
                    Task {
                        await model.run(button, on: nil)
                        running = false
                    }
                } label: {
                    if let symbol = button.symbol {
                        Label { Text(ext: button.label) } icon: { Image(systemName: symbol) }
                    } else {
                        Text(ext: button.label)
                    }
                }
                .buttonStyle(.sf(.secondary))
                .disabled(running)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
