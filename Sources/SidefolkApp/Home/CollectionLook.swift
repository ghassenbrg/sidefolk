import SidefolkCore
import SwiftUI

/// How a collection looks in the sidebar and its header (D53): the person's emoji or symbol and colour, else
/// the kind's own. Colours are stored by name, so the palette can be retuned without touching anyone's data.
enum CollectionLook {
    static let colors: [(name: String, color: Color)] = [
        ("red", Color(hex: 0xF0605D)), ("orange", Color(hex: 0xF5913E)), ("yellow", Color(hex: 0xF2C230)),
        ("green", Color(hex: 0x4CC26E)), ("mint", Color(hex: 0x3CCFB4)), ("teal", Theme.aqua),
        ("blue", Color(hex: 0x3E8BF0)), ("indigo", Color(hex: 0x6366E8)), ("purple", Color(hex: 0xA25DDC)),
        ("pink", Color(hex: 0xEE6BA8)), ("brown", Color(hex: 0xA77B58)), ("gray", Color(hex: 0x8A97AD)),
    ]

    static let symbols = CollectionLooks.symbols

    static func color(_ c: NotebookCollection) -> Color {
        if let name = c.color, let found = colors.first(where: { $0.name == name }) { return found.color }
        // The person's own colour, moved only in lightness until it reads on this theme's cards in light and dark
        // (`CalendarPalette`). Identity, never status (D78): it's used for this collection's icon and nothing else.
        if let name = c.color, let hex = CollectionLooks.hex(name) { return CalendarTint.of(hex).text }
        return c.kind == .profile ? Theme.aqua : Theme.folkColor("pip")
    }

    /// A colour as it's stored: "#rrggbb".
    static func stored(_ color: Color) -> String? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func part(_ v: CGFloat) -> Int { min(255, max(0, Int((v * 255).rounded()))) } // the panel picks in a wider gamut
        return String(format: "#%02x%02x%02x", part(c.redComponent), part(c.greenComponent), part(c.blueComponent))
    }

    static func symbol(_ c: NotebookCollection) -> String {
        if let symbol = c.symbol, !symbol.isEmpty { return symbol }
        switch c.kind {
        case .inbox: return "tray.fill"
        case .profile: return "person.crop.circle.fill"
        case .project: return "folder.fill"
        case .topic: return "number"
        case .list: return "checklist"
        }
    }
}

/// A collection's emoji, or its symbol in its colour.
struct CollectionIcon: View {
    var collection: NotebookCollection
    var size: CGFloat = 13
    /// In Home's navigation, where colorful icons are tiles (D67); an emoji is colourful already.
    var nav = false

    var body: some View {
        if let emoji = collection.emoji, !emoji.isEmpty {
            Text(verbatim: emoji).font(.system(size: size + 1))
        } else if nav {
            NavIcon(symbol: CollectionLook.symbol(collection), color: CollectionLook.color(collection))
        } else {
            Image(systemName: CollectionLook.symbol(collection)).foregroundStyle(CollectionLook.color(collection))
        }
    }
}

/// The same on a tinted tile, for a collection's header.
struct CollectionTile: View {
    var collection: NotebookCollection
    var size: CGFloat = 34
    /// In the sidebar with simple icons: the glyph alone (D130). Its pastel is too faint alone on a light sidebar, so it's
    /// mixed with the ink there to reach 3:1, and takes the row's own colour on the selected row.
    var bare = false
    var selected = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(bare ? .clear : CollectionLook.color(collection).opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                if let emoji = collection.emoji, !emoji.isEmpty {
                    Text(verbatim: emoji).font(.system(size: size * 0.55))
                } else {
                    Image(systemName: CollectionLook.symbol(collection))
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(glyph)
                }
            }
            .accessibilityHidden(true)
    }

    private var glyph: Color {
        let color = CollectionLook.color(collection)
        if selected { return Theme.onSidebarSelected }
        return bare && scheme == .light ? color.mix(with: Theme.ink, by: 0.45) : color
    }
}

/// Picking an icon and a colour, in the collection sheet: a colour row, then symbols, and an emoji instead.
struct CollectionLookPicker: View {
    @Binding var symbol: String?
    @Binding var color: String?
    @Binding var emoji: String
    var kind: NotebookCollection.Kind

    private var preview: NotebookCollection {
        var c = NotebookCollection(name: "", kind: kind)
        c.symbol = symbol
        c.color = color
        c.emoji = emoji.isEmpty ? nil : emoji
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: 6) {
                ForEach(CollectionLook.colors, id: \.name) { option in
                    Button { color = option.name } label: {
                        Circle().fill(option.color).frame(width: 20, height: 20)
                            .overlay { if color == option.name { Circle().strokeBorder(Theme.ink.opacity(0.7), lineWidth: 2).padding(-3) } }
                    }
                    .buttonStyle(.sfBare)
                    .accessibilityLabel(Text(verbatim: option.name))
                    .accessibilityAddTraits(color == option.name ? .isSelected : [])
                }
                // Any other colour; chosen, it stays readable (`CollectionLook.color`).
                ColorPicker(selection: Binding(get: { color.flatMap(CollectionLooks.hex).map { Color(hex: $0) } ?? Color(hex: 0x3E8BF0) },
                                               set: { color = CollectionLook.stored($0) }), supportsOpacity: false) {
                    Text("Another colour", comment: "A collection's sheet: pick any colour")
                }
                .labelsHidden()
                .help(Text("Another colour", comment: "A collection's sheet: pick any colour"))
                .overlay { if color.flatMap(CollectionLooks.hex) != nil { RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink.opacity(0.7), lineWidth: 2).padding(-3).allowsHitTesting(false) } }
            }
            ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 10), spacing: 6) {
                ForEach(CollectionLook.symbols, id: \.self) { name in
                    Button { symbol = name; emoji = "" } label: {
                        Image(systemName: name).font(.system(size: 13, weight: .medium)).frame(width: 30, height: 30)
                            .foregroundStyle(chosen(name) ? CollectionLook.color(preview) : Theme.inkMuted)
                            .background(chosen(name) ? CollectionLook.color(preview).opacity(0.18) : Theme.surfaceSunken,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.sfBare)
                    .accessibilityLabel(Text(verbatim: name))
                    .accessibilityAddTraits(chosen(name) ? .isSelected : [])
                }
            }
            }
            .frame(height: 180)
            HStack(spacing: Theme.Space.s) {
                CollectionTile(collection: preview, size: 30)
                TextField("Emoji", text: Binding(get: { emoji }, set: { emoji = String($0.trimmingCharacters(in: .whitespaces).prefix(2)) }),
                          prompt: Text(verbatim: ""))
                    .fieldHint(Text("Or an emoji"), showing: emoji.isEmpty)
                        .accessibilityLabel("Emoji")
                    .lanternField()
                    .frame(width: 120)
                Spacer()
                if symbol != nil || color != nil || !emoji.isEmpty {
                    Button("Reset") { symbol = nil; color = nil; emoji = "" }.buttonStyle(.sfPlain)
                }
            }
        }
    }

    private func chosen(_ name: String) -> Bool { emoji.isEmpty && CollectionLook.symbol(preview) == name }
}
