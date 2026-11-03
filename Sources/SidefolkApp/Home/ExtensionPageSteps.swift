import SidefolkCore
import SwiftUI

/// A rail of things in order (D113): a line threading through tiles, each row a sentence with its state and what came of it. Native rows, so it
/// is reached with the keyboard and read by VoiceOver like any list; a row moves by dragging, by its menu, or by VoiceOver's actions.
struct PageStepsView: View {
    var steps: ExtensionPage.Steps
    var model: ExtensionPageModel
    @State private var hovered: String?
    @State private var dropping: String?
    @State private var folded: Set<String> = []
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if steps.title != nil || steps.caption != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = steps.title { Text(ext: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink) }
                    if let caption = steps.caption { Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(.bottom, Theme.Space.s)
            }
            ForEach(Array(steps.items.enumerated()), id: \.element.id) { index, item in
                row(item, index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .cardSurface()
    }

    // MARK: A row

    private static let tile: CGFloat = 26
    private static let indent: CGFloat = 22

    private func row(_ item: ExtensionPage.Steps.Item, index: Int) -> some View {
        let selected = steps.selected == item.id
        return HStack(alignment: .top, spacing: Theme.Space.s) {
            lane(item, index: index)
            VStack(alignment: .leading, spacing: 0) {
                content(item, selected: selected)
                if let output = item.output { outputFold(output, id: item.id) }
                if let insert = steps.insert, hovered == item.id || selected {
                    addButton(insert, after: item)
                } else {
                    // Room for the line to breathe, the same with or without the button.
                    Color.clear.frame(height: Theme.Space.s)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let moved = ids.first, moved != item.id, let hook = steps.reorder else { return false }
            guard steps.siblings(of: moved).contains(where: { $0.id == item.id }) else { return false }
            Task { await model.run(tool: hook.tool, input: hook.input(["id": .string(moved), "before": .string(item.id)])) }
            return true
        } isTargeted: { over in
            dropping = over ? item.id : (dropping == item.id ? nil : dropping)
        }
        .overlay(alignment: .top) {
            if dropping == item.id { Rectangle().fill(Theme.accent).frame(height: 2) }
        }
    }

    /// The line and the tile. A row on a branch draws the line it hangs from too, while there is more of it below.
    private func lane(_ item: ExtensionPage.Steps.Item, index: Int) -> some View {
        let colour = lineColour(at: index)
        return ZStack(alignment: .topLeading) {
            if lineContinues(depth: 0, from: index) {
                colour.frame(width: 2).padding(.leading, Self.tile / 2 - 1)
            }
            if item.depth > 0 {
                Group {
                    if lineContinues(depth: item.depth, from: index) { colour.frame(width: 2) }
                }
                .padding(.leading, CGFloat(item.depth) * Self.indent + Self.tile / 2 - 1)
            }
            tile(item)
                .padding(.leading, CGFloat(item.depth) * Self.indent)
        }
        .frame(width: CGFloat(item.depth) * Self.indent + Self.tile, alignment: .topLeading)
    }

    /// Whether anything at this depth comes after this row, before the line it hangs from ends.
    private func lineContinues(depth: Int, from index: Int) -> Bool {
        for later in steps.items[(index + 1)...] {
            if later.depth == depth { return true }
            if later.depth < depth { return false }
        }
        return false
    }

    private func lineColour(at index: Int) -> Color {
        let colours = steps.line.compactMap(Color.init(extensionHex:))
        guard let first = colours.first else { return Theme.line }
        guard colours.count > 1 else { return first }
        let t = Double(index) / Double(max(steps.items.count - 1, 1))
        return first.mix(with: colours[1], by: t)
    }

    private func tile(_ item: ExtensionPage.Steps.Item) -> some View {
        let fill = item.color.flatMap(Color.init(extensionHex:)) ?? Theme.well
        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(item.state == .skipped ? Theme.well : fill)
            if let symbol = item.symbol {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(item.color == nil || item.state == .skipped ? Theme.inkMuted : .white)
            }
        }
        .frame(width: Self.tile, height: Self.tile)
        .overlay(alignment: .bottomTrailing) { stateMark(item.state).offset(x: 4, y: 4) }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func stateMark(_ state: ExtensionPage.Steps.Item.State) -> some View {
        switch state {
        case .done: mark("checkmark.circle.fill", Theme.success)
        case .failed: mark("xmark.circle.fill", Theme.danger)
        case .waiting: mark("exclamationmark.circle.fill", Theme.warning)
        case .running: ProgressView().controlSize(.mini).background(Circle().fill(Theme.surfaceRaised))
        case .pending: mark("ellipsis.circle.fill", Theme.inkMuted)
        case .skipped, .none: EmptyView()
        }
    }

    private func mark(_ symbol: String, _ colour: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 12)).symbolRenderingMode(.palette).foregroundStyle(.white, colour)
            .background(Circle().fill(Theme.surfaceRaised).padding(1))
    }

    @ViewBuilder private func content(_ item: ExtensionPage.Steps.Item, selected: Bool) -> some View {
        let words = VStack(alignment: .leading, spacing: 2) {
            if let label = item.label { Text(ext: label).font(Theme.Font.eyebrow).foregroundStyle(Theme.inkFaint) }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(ext: item.title)
                    .font(selected ? Theme.Font.bodyStrong : Theme.Font.body)
                    .foregroundStyle(item.state == .skipped ? Theme.inkFaint : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.xs)
                if let result = item.result { Text(ext: result).font(Theme.Font.caption).foregroundStyle(resultInk(item)).lineLimit(1) }
            }
            if let detail = item.detail {
                Text(ext: detail).font(Theme.Font.caption).foregroundStyle(item.tone == .neutral ? Theme.inkMuted : item.tone.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let badge = item.badge {
                BadgeView(badge: badge).padding(.top, 2)
            }
            if !item.actions.isEmpty {
                HStack(spacing: Theme.Space.xs) { ForEach(Array(item.actions.enumerated()), id: \.offset) { _, c in PageButton(control: c, model: model) } }.padding(.top, 2)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: Self.tile, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(selected ? Theme.accentSoft : (hovered == item.id && steps.select != nil ? Theme.well : Color.clear)))

        Group {
            if let select = steps.select {
                Button { Task { await model.run(tool: select.tool, input: select.input(.string(item.id))) } } label: { words.contentShape(Rectangle()) }
                    .buttonStyle(.sfBare)
            } else {
                words
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(stateWords(item.state))
        .modifier(MovesWith(steps: steps, item: item, model: model))
    }

    private func resultInk(_ item: ExtensionPage.Steps.Item) -> Color {
        switch item.state {
        case .done: Theme.success
        case .failed: Theme.danger
        case .waiting: Theme.warning
        default: Theme.inkMuted
        }
    }

    private func stateWords(_ state: ExtensionPage.Steps.Item.State) -> Text {
        switch state {
        case .done: Text("Done", comment: "A step rail row's state, for VoiceOver")
        case .failed: Text("Failed", comment: "A step rail row's state, for VoiceOver")
        case .waiting: Text("Waiting", comment: "A step rail row's state, for VoiceOver")
        case .running: Text("Running", comment: "A step rail row's state, for VoiceOver")
        case .pending: Text("Not run", comment: "A step rail row's state, for VoiceOver")
        case .skipped: Text("Skipped", comment: "A step rail row's state, for VoiceOver")
        case .none: Text(verbatim: "")
        }
    }

    private func addButton(_ hook: ExtensionPage.Steps.Hook, after item: ExtensionPage.Steps.Item) -> some View {
        Button { Task { await model.run(tool: hook.tool, input: hook.input(.string(item.id))) } } label: {
            Label { Text(ext: hook.label ?? String(localized: "Add", comment: "A step rail's add button")) } icon: { Image(systemName: "plus") }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.link)
        }
        .buttonStyle(.sfBare)
        .padding(.leading, Theme.Space.s)
        .padding(.vertical, 3)
    }

    private func outputFold(_ output: String, id: String) -> some View {
        let open = folded.contains(id)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Button {
                if open { folded.remove(id) } else { folded.insert(id) }
            } label: {
                Label { Text(open ? "Hide what it gave" : "See what it gave", comment: "A step rail: the text a step produced, folded") } icon: { Image(systemName: open ? "chevron.down" : "chevron.right") }
                    .font(Theme.Font.caption).foregroundStyle(Theme.link)
            }
            .buttonStyle(.sfBare)
            if open {
                Text(ext: output).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous).fill(Theme.well))
            }
        }
        .padding(.leading, Theme.Space.s)
        .padding(.top, 2)
    }
}

/// Dragging, the row's menu and VoiceOver's actions: three ways to one move.
private struct MovesWith: ViewModifier {
    var steps: ExtensionPage.Steps
    var item: ExtensionPage.Steps.Item
    var model: ExtensionPageModel

    func body(content: Content) -> some View {
        if let hook = steps.reorder, !item.locked {
            content
                .draggable(item.id)
                .contextMenu {
                    Button { move(hook, -1) } label: { Text("Move up", comment: "A step rail row's menu") }.disabled(steps.move(item.id, by: -1) == nil)
                    Button { move(hook, 1) } label: { Text("Move down", comment: "A step rail row's menu") }.disabled(steps.move(item.id, by: 1) == nil)
                }
                .accessibilityAction(named: Text("Move up", comment: "A step rail row's menu")) { move(hook, -1) }
                .accessibilityAction(named: Text("Move down", comment: "A step rail row's menu")) { move(hook, 1) }
        } else {
            content
        }
    }

    private func move(_ hook: ExtensionPage.Steps.Hook, _ delta: Int) {
        guard let moved = steps.move(item.id, by: delta) else { return }
        Task { await model.run(tool: hook.tool, input: hook.input(moved)) }
    }
}

/// A value edited in place (D113): what is saved shows, and leaving the field or pressing Return runs the tool. A chip puts a value at the caret.
struct PageEditFieldRow: View {
    var field: ExtensionPage.Field
    var model: ExtensionPageModel
    @State private var text = ""
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @State private var problem = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(ext: field.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            if let detail = field.detail {
                Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            editor
            if !field.tokens.isEmpty {
                FlowRow(spacing: Theme.Space.xs) {
                    ForEach(field.tokens, id: \.value) { token in
                        Button { insert(token.value) } label: {
                            Label { Text(ext: token.label) } icon: { token.symbol.map { Image(systemName: $0) } }
                                .font(Theme.Font.caption)
                                .padding(.horizontal, Theme.Space.s)
                                .frame(height: Theme.Size.chip)
                                .background(Capsule().fill(Theme.well))
                        }
                        .buttonStyle(.sfBare)
                        .accessibilityHint(Text("Puts this value in the field", comment: "VoiceOver: a chip beside a field"))
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
        .onAppear { text = shown }
        .onChange(of: shown) { _, new in if !focused { text = new } }
        .onChange(of: focused) { _, now in if !now { commit() } }
    }

    private var shown: String { field.value ?? "" }

    @ViewBuilder private var editor: some View {
        switch field.kind {
        case .multiline:
            TextEditor(text: $text, selection: $selection)
                .font(Theme.Font.body)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: 72, maxHeight: 180)
                .padding(Theme.Space.xs)
                .fieldChrome(focused: focused, problem: problem)
                .accessibilityLabel(Text(ext: field.label))
        default:
            TextField(text: $text, selection: $selection) { Text(ext: field.placeholder ?? field.label) }
                .lanternField()
                .focused($focused)
                .font(field.kind == .text ? Theme.Font.body : Theme.Font.mono)
                .onSubmit(commit)
        }
    }

    private func insert(_ value: String) {
        let range = selection.flatMap { s -> Range<String.Index>? in
            if case .selection(let r) = s.indices { return r }
            return nil
        }
        if let range, range.lowerBound <= text.endIndex, range.upperBound <= text.endIndex {
            text.replaceSubrange(range, with: value)
        } else {
            text += value
        }
        focused = true
        // A chip is a whole change: it needn't wait for the person to leave the field.
        if selection == nil { commit() }
    }

    private func commit() {
        guard text != shown else { return }
        Task {
            let ok = await model.run(tool: field.tool, input: field.input(typing: text))
            problem = !ok
            if !ok, !focused { text = shown }
        }
    }
}

/// Several of a few options (D113): each a chip that stays lit. The tool gets the whole set.
struct PageMultiChoiceRow: View {
    var choice: ExtensionPage.Choice
    var model: ExtensionPageModel
    @State private var pending: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(ext: choice.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            if let detail = choice.detail { Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true) }
            FlowRow(spacing: Theme.Space.xs) {
                ForEach(choice.options, id: \.value) { option in
                    let on = (pending ?? choice.selectedAll).contains(option.value)
                    Button { toggle(option.value) } label: {
                        Text(ext: option.label)
                            .font(Theme.Font.callout)
                            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                            .padding(.horizontal, Theme.Space.m)
                            .frame(minWidth: Theme.Size.button, minHeight: Theme.Size.button)
                            .background(Capsule().fill(on ? Theme.accent : Theme.well))
                            .contrastEdge(radius: Theme.Size.button / 2)
                    }
                    .buttonStyle(.sfBare)
                    .disabled(choice.disabled)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private func toggle(_ value: String) {
        var set = pending ?? choice.selectedAll
        if let at = set.firstIndex(of: value) { set.remove(at: at) } else { set.append(value) }
        pending = set
        Task {
            await model.run(tool: choice.tool, input: choice.input(pickingAll: set))
            pending = nil
        }
    }
}
