import AppKit
import SidefolkCore
import SwiftUI

/// A dressed page's ground (D108): its colour for this appearance and, over it, a picture from its pack, whole or repeated. What
/// it is made of is decoration, so nothing here is read aloud. Without a dress, the app's own.
struct PageGround: View {
    var dress: PageDress?
    var model: ExtensionPageModel
    @Environment(\.colorScheme) private var scheme
    @State private var image: NSImage?

    var body: some View {
        if let dress, let color = Color(extensionHex: scheme == .dark ? dress.ground.dark : dress.ground.light) {
            ZStack(alignment: .top) {
                color
                if let image {
                    if dress.tile {
                        Image(nsImage: image).resizable(resizingMode: .tile)
                    } else {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
                    }
                }
            }
            .accessibilityHidden(true)
            .task(id: "\(String(describing: dress.picture))\(scheme == .dark)") {
                guard let picture = dress.picture else { image = nil; return }
                image = await model.image(picture, dark: scheme == .dark, side: 1024)
            }
        } else {
            PageBackground()
        }
    }
}

extension EnvironmentValues {
    /// Filled buttons and switches on a dressed page (D108).
    @Entry var pageAccent: Color?
    /// A page's own accent as it runs from one colour to the other, on what's filled (D126).
    @Entry var pageAccentEnd: Color?
}

/// What's selected on a page: its own accent where it has one, the theme's otherwise. As text it lightens in the dark, where a deep colour wouldn't read.
struct PageSelection {
    var accent: Color?
    var dark: Bool

    var fill: Color { accent ?? Theme.accent }
    var soft: Color { accent?.opacity(dark ? 0.26 : 0.13) ?? Theme.accentSoft }
    /// Mixed so it holds 4.5:1 on `soft` in either appearance.
    var ink: Color { accent.map { dark ? $0.mix(with: .white, by: 0.45) : $0.mix(with: .black, by: 0.2) } ?? Theme.link }
}

extension View {
    /// Sidefolk's own question when a page asks for something the person must agree to (D106, D107): its words, never the extension's,
    /// beyond the purpose the install preview showed, labelled as that.
    func pageConsent(model: ExtensionPageModel) -> some View { modifier(PageConsentAsk(model: model)) }
}

private struct PageConsentAsk: ViewModifier {
    var model: ExtensionPageModel

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { model.asking != nil }, set: { if !$0 { model.asking = nil } }), presenting: model.asking) { consent in
            Button(String(localized: "Allow", comment: "Letting an extension have the person's place or schedule reminders: the button")) {
                Task { await model.answer(consent, allow: true) }
            }
            Button(String(localized: "Not Now", comment: "Letting an extension have the person's place or schedule reminders: the button"), role: .cancel) {}
        } message: { consent in
            Text(verbatim: model.consentWords(consent))
        }
    }

    private var title: String {
        switch model.asking {
        case .place: String(localized: "Share your place with \(model.info.extensionName)?", comment: "Asked before an extension may read the person's place")
        case .schedule: String(localized: "Let \(model.info.extensionName) schedule reminders?", comment: "Asked before an extension may schedule reminders")
        case nil: ""
        }
    }
}

/// A filled button in a dressed page's own colour: the size and press of the app's, only the fill is the page's.
struct PageAccentButtonStyle: ButtonStyle {
    var accent: Color
    /// Runs to this, left to right.
    var end: Color?
    var large: Bool
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        configuration.label
            .font(Theme.Font.bodyStrong)
            .foregroundStyle(Color.white)
            .padding(.horizontal, large ? Theme.Space.xl : Theme.Space.l)
            .frame(minHeight: large ? 44 : Theme.Size.button)
            .background(LinearGradient(colors: [accent, end ?? accent], startPoint: .leading, endPoint: .trailing), in: shape)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && enabled ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.45)
    }
}

/// Rows of controls under named columns (D108): one line for each thing that has several settings. It lines up when there is room, and stacks when there isn't.
struct PageTableView: View {
    var table: PageTable
    var model: ExtensionPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let title = table.title { Text(ext: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink) }
            ViewThatFits(in: .horizontal) {
                lined.frame(minWidth: 560).frame(maxWidth: .infinity, alignment: .leading)
                stacked
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private var lined: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: 0) {
            GridRow {
                Text(ext: table.first ?? "").gridColumnAlignment(.leading)
                ForEach(table.columns.indices, id: \.self) { Text(ext: table.columns[$0]).gridColumnAlignment(.leading) }
            }
            .font(Theme.Font.caption.weight(.medium)).foregroundStyle(Theme.inkMuted)
            .padding(.vertical, Theme.Space.s)
            .accessibilityHidden(true)
            ForEach(table.rows.indices, id: \.self) { r in
                let row = table.rows[r]
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    label(row).frame(minWidth: 120, alignment: .leading)
                    ForEach(table.columns.indices, id: \.self) { c in
                        if c < row.cells.count { PageTableCell(cell: row.cells[c], spoken: "\(row.label), \(table.columns[c])", model: model) } else { Color.clear.frame(width: 1, height: 1) }
                    }
                }
                .padding(.vertical, Theme.Space.xs + 2)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.xs)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(table.rows.indices, id: \.self) { r in
                let row = table.rows[r]
                if r > 0 { Divider() }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    label(row)
                    ForEach(table.columns.indices, id: \.self) { c in
                        if c < row.cells.count {
                            HStack {
                                Text(ext: table.columns[c]).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                                Spacer(minLength: Theme.Space.s)
                                PageTableCell(cell: row.cells[c], spoken: "\(row.label), \(table.columns[c])", model: model)
                            }
                        }
                    }
                }
                .padding(Theme.Space.m)
            }
        }
    }

    private func label(_ row: PageTable.Row) -> some View {
        HStack(spacing: Theme.Space.s) {
            if let symbol = row.symbol { Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 20).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 1) {
                Text(ext: row.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                if let detail = row.detail { Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted) }
            }
        }
    }
}

struct PageTableCell: View {
    var cell: PageTable.Cell
    /// Row and column: a control on its own in a grid says neither.
    var spoken: String
    var model: ExtensionPageModel
    @State private var pendingOn: Bool?
    @State private var pendingPick: String?

    var body: some View {
        switch cell {
        case .text(let words):
            Text(ext: words).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
        case .empty:
            Color.clear.frame(width: 1, height: 1)
        case .control(let control):
            if case .toggle(let on) = control.kind {
                Toggle(isOn: Binding(get: { pendingOn ?? on }, set: { new in
                    pendingOn = new
                    Task {
                        await model.run(control, on: new)
                        pendingOn = nil
                    }
                })) { Text(ext: spoken) }
                    .toggleStyle(.switch).labelsHidden().accessibilityLabel(Text(ext: spoken))
            } else {
                PageButton(control: control, model: model)
            }
        case .choice(let choice):
            Picker(selection: Binding(get: { pendingPick ?? choice.selected }, set: { value in
                guard value != choice.selected else { return }
                pendingPick = value
                Task {
                    if let go = choice.go(picking: value) { await model.go(go) } else { await model.run(tool: choice.tool, input: choice.input(picking: value)) }
                    pendingPick = nil
                }
            })) {
                ForEach(choice.options, id: \.value) { Text(ext: $0.label).tag($0.value) }
            } label: {
                Text(ext: spoken)
            }
            .pickerStyle(.menu).labelsHidden().fixedSize().disabled(choice.disabled).accessibilityLabel(Text(ext: spoken))
        }
    }
}
